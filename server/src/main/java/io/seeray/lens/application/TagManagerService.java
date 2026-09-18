package io.seeray.lens.application;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.seeray.lens.domain.common.ControlPlaneException;
import io.seeray.lens.domain.common.UuidV7;
import io.seeray.lens.domain.site.Site;
import io.seeray.lens.domain.tag.*;
import io.seeray.lens.domain.workspace.WorkspaceRole;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.time.Duration;
import java.time.Instant;
import java.util.*;

@ApplicationScoped
public class TagManagerService {
    private static final Set<String> ENVIRONMENTS = Set.of("development", "staging", "production");
    private static final SecureRandom PREVIEW_RANDOM = new SecureRandom();
    private static final Duration PREVIEW_TTL = Duration.ofMinutes(15);
    private final SiteService sites;
    private final WorkspaceAccess access;
    private final ObjectMapper mapper;

    @Inject
    public TagManagerService(SiteService sites, WorkspaceAccess access, ObjectMapper mapper) {
        this.sites = sites;
        this.access = access;
        this.mapper = mapper;
    }

    public List<ContainerView> list(UUID siteId) {
        Site s = readable(siteId);
        return TagContainer.<TagContainer>list("site.id = ?1 order by name", s.id).stream()
                .map(this::view)
                .toList();
    }

    @Transactional
    public ContainerView create(UUID siteId, String name) {
        Site s = writable(siteId);
        if (name == null || name.isBlank() || name.length() > 256) throw invalid();
        if (TagContainer.count("site.id = ?1 and name = ?2", siteId, name.trim()) > 0)
            throw new ControlPlaneException(409, "CONTAINER_NAME_EXISTS", "Tag container already exists");
        TagContainer c = new TagContainer();
        c.id = UuidV7.next();
        c.site = s;
        c.name = name.trim();
        c.enabled = true;
        c.createdAt = c.updatedAt = Instant.now();
        c.persist();
        return view(c);
    }

    @Transactional
    public ContainerView update(UUID siteId, UUID containerId, String name, boolean enabled) {
        TagContainer c = writableContainer(siteId, containerId);
        validateName(siteId, containerId, name);
        c.name = name.trim();
        c.enabled = enabled;
        c.updatedAt = Instant.now();
        return view(c);
    }

    @Transactional
    public void delete(UUID siteId, UUID containerId) {
        writableContainer(siteId, containerId).delete();
    }

    public List<VersionView> versions(UUID siteId, UUID containerId) {
        TagContainer c = readableContainer(siteId, containerId);
        return TagContainerVersion.<TagContainerVersion>list("container.id = ?1 order by version desc", c.id).stream()
                .map(this::version)
                .toList();
    }

    public List<TemplateView> templates(UUID siteId) {
        Site s = readable(siteId);
        return TagManagerTemplate.<TagManagerTemplate>list("organization.id = ?1 order by name", s.organization.id)
                .stream()
                .map(this::template)
                .toList();
    }

    @Transactional
    public TemplateView createTemplate(UUID siteId, String name, String description, JsonNode tags) {
        Site s = writable(siteId);
        validateTemplate(s.organization.id, null, name, description, tags);
        TagManagerTemplate template = new TagManagerTemplate();
        template.id = UuidV7.next();
        template.organization = s.organization;
        template.name = name.trim();
        template.description = normalizeDescription(description);
        template.tagsJson = tags.toString();
        template.createdAt = template.updatedAt = Instant.now();
        template.persist();
        return template(template);
    }

    @Transactional
    public TemplateView updateTemplate(UUID siteId, UUID templateId, String name, String description, JsonNode tags) {
        TagManagerTemplate template = writableTemplate(siteId, templateId);
        validateTemplate(template.organization.id, templateId, name, description, tags);
        template.name = name.trim();
        template.description = normalizeDescription(description);
        template.tagsJson = tags.toString();
        template.updatedAt = Instant.now();
        return template(template);
    }

    @Transactional
    public void deleteTemplate(UUID siteId, UUID templateId) {
        writableTemplate(siteId, templateId).delete();
    }

    @Transactional
    public VersionView draft(UUID siteId, UUID containerId, JsonNode tags) {
        TagContainer c = writableContainer(siteId, containerId);
        validateTags(tags);
        TagContainerVersion latest = TagContainerVersion.<TagContainerVersion>find(
                        "container.id = ?1 order by version desc", c.id)
                .firstResult();
        Integer next = latest == null ? null : latest.version;
        TagContainerVersion v = new TagContainerVersion();
        v.id = UuidV7.next();
        v.container = c;
        v.version = next == null ? 1 : next + 1;
        v.status = "draft";
        v.tagsJson = tags.toString();
        v.createdAt = Instant.now();
        v.persist();
        return version(v);
    }

    @Transactional
    public PreviewCreated createPreviewSession(
            UUID siteId, UUID containerId, JsonNode tags, boolean executeCustomCode) {
        TagContainer container = writableContainer(siteId, containerId);
        validateTags(tags);
        Instant now = Instant.now();
        TagManagerPreviewSession.delete("expiresAt <= ?1", now);
        byte[] bytes = new byte[32];
        PREVIEW_RANDOM.nextBytes(bytes);
        String token = Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
        TagManagerPreviewSession session = new TagManagerPreviewSession();
        session.id = UuidV7.next();
        session.container = container;
        session.tokenHash = previewTokenHash(token);
        session.tagsJson = tags.toString();
        session.executeCustomCode = executeCustomCode;
        session.createdAt = now;
        session.expiresAt = now.plus(PREVIEW_TTL);
        session.persist();
        return new PreviewCreated(session.id, token, session.expiresAt, executeCustomCode);
    }

    public PreviewBundle previewBundle(String trackingId, UUID sessionId, String token) {
        TagManagerPreviewSession session = previewSession(trackingId, sessionId, token);
        try {
            return new PreviewBundle(mapper.readTree(session.tagsJson), session.executeCustomCode);
        } catch (Exception error) {
            throw new IllegalStateException(error);
        }
    }

    @Transactional
    public void recordPreviewEvents(String trackingId, UUID sessionId, String token, JsonNode events) {
        TagManagerPreviewSession session = previewSession(trackingId, sessionId, token);
        if (events == null || !events.isArray() || events.size() > 100) throw invalidPreview();
        int incoming = events.size();
        long count = TagManagerPreviewEvent.count("session.id = ?1", session.id);
        int excess = (int) Math.max(0, count + incoming - 1000);
        if (excess > 0) {
            List<TagManagerPreviewEvent> oldest = TagManagerPreviewEvent.<TagManagerPreviewEvent>list(
                    "session.id = ?1 order by occurredAt asc", session.id);
            oldest.subList(0, Math.min(excess, oldest.size())).forEach(TagManagerPreviewEvent::delete);
        }
        JsonNode configuredTags;
        try {
            configuredTags = mapper.readTree(session.tagsJson);
        } catch (Exception error) {
            throw new IllegalStateException(error);
        }
        for (JsonNode event : events) {
            if (event == null || !event.isObject()) throw invalidPreview();
            JsonNode tagIndexNode = event.get("tagIndex");
            JsonNode triggerEventNode = event.get("triggerEvent");
            JsonNode outcomeNode = event.get("outcome");
            JsonNode pagePathNode = event.get("pagePath");
            if (tagIndexNode == null || !tagIndexNode.isIntegralNumber() || !tagIndexNode.canConvertToInt())
                throw invalidPreview();
            int tagIndex = tagIndexNode.asInt();
            if (tagIndex < 0 || tagIndex >= configuredTags.size() || tagIndex >= 100) throw invalidPreview();
            String triggerEvent = previewText(triggerEventNode, 64);
            String outcome = previewText(outcomeNode, 16);
            String pagePath = sanitizePreviewPath(previewText(pagePathNode, 1024));
            if (triggerEvent == null
                    || pagePath == null
                    || outcome == null
                    || !Set.of("fired", "no_match", "blocked").contains(outcome)) throw invalidPreview();
            TagManagerPreviewEvent recorded = new TagManagerPreviewEvent();
            recorded.id = UuidV7.next();
            recorded.session = session;
            recorded.tagIndex = tagIndex;
            recorded.tagName = previewTagName(configuredTags.get(tagIndex), tagIndex);
            recorded.triggerEvent = triggerEvent;
            recorded.outcome = outcome;
            recorded.pagePath = pagePath;
            recorded.occurredAt = Instant.now();
            recorded.persist();
        }
    }

    public List<PreviewEventView> previewEvents(UUID siteId, UUID containerId, UUID sessionId) {
        TagContainer container = readableContainer(siteId, containerId);
        TagManagerPreviewSession session = TagManagerPreviewSession.find(
                        "id = ?1 and container.id = ?2", sessionId, container.id)
                .firstResult();
        if (session == null) throw previewNotFound();
        return TagManagerPreviewEvent.<TagManagerPreviewEvent>list(
                        "session.id = ?1 order by occurredAt desc", session.id)
                .stream()
                .limit(100)
                .map(event -> new PreviewEventView(
                        event.id,
                        event.tagIndex,
                        event.tagName,
                        event.triggerEvent,
                        event.outcome,
                        event.pagePath,
                        event.occurredAt))
                .toList();
    }

    @Transactional
    public void stopPreviewSession(UUID siteId, UUID containerId, UUID sessionId) {
        TagContainer container = writableContainer(siteId, containerId);
        TagManagerPreviewSession session = TagManagerPreviewSession.find(
                        "id = ?1 and container.id = ?2", sessionId, container.id)
                .firstResult();
        if (session == null) throw previewNotFound();
        session.delete();
    }

    private TagManagerPreviewSession previewSession(String trackingId, UUID sessionId, String token) {
        TagManagerPreviewSession session = TagManagerPreviewSession.find(
                        "id = ?1 and container.site.trackingId = ?2", sessionId, trackingId)
                .firstResult();
        if (session == null) throw previewNotFound();
        if (!session.expiresAt.isAfter(Instant.now()))
            throw new ControlPlaneException(410, "PREVIEW_SESSION_EXPIRED", "Tag preview session has expired");
        if (token == null
                || token.isBlank()
                || !MessageDigest.isEqual(
                        session.tokenHash.getBytes(StandardCharsets.US_ASCII),
                        previewTokenHash(token).getBytes(StandardCharsets.US_ASCII)))
            throw new ControlPlaneException(403, "INVALID_PREVIEW_TOKEN", "Tag preview token is invalid");
        return session;
    }

    private static String previewTokenHash(String token) {
        try {
            return HexFormat.of()
                    .formatHex(MessageDigest.getInstance("SHA-256").digest(token.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException impossible) {
            throw new IllegalStateException(impossible);
        }
    }

    private static String previewText(JsonNode node, int maxLength) {
        if (node == null || !node.isTextual()) return null;
        String value = node.asText().trim();
        return value.isEmpty() || value.length() > maxLength || value.indexOf('\u0000') >= 0 ? null : value;
    }

    private static String previewTagName(JsonNode tag, int index) {
        for (String key : List.of("name", "eventType")) {
            JsonNode value = tag == null ? null : tag.get(key);
            if (value != null && value.isTextual() && !value.asText().isBlank())
                return value.asText().trim();
        }
        return "Tag " + (index + 1);
    }

    private static String sanitizePreviewPath(String value) {
        if (value == null || !value.startsWith("/")) return null;
        int query = value.indexOf('?');
        int fragment = value.indexOf('#');
        int end = value.length();
        if (query >= 0) end = Math.min(end, query);
        if (fragment >= 0) end = Math.min(end, fragment);
        String path = value.substring(0, end);
        return path.length() <= 512 ? path : path.substring(0, 512);
    }

    private static void validateTags(JsonNode tags) {
        if (tags == null || !tags.isArray() || tags.size() > 100) throw invalid();
        if (tags.toString().getBytes(StandardCharsets.UTF_8).length > 64 * 1024) throw invalid();
        for (JsonNode tag : tags) validateTag(tag);
    }

    private static void validateTag(JsonNode tag) {
        if (tag == null || !tag.isObject()) throw invalid();
        String type = text(tag, "type");
        if (!"event".equals(type) && !"page_view".equals(type) && !"custom_html".equals(type)) throw invalid();

        String eventType = text(tag, "eventType");
        String name = text(tag, "name");
        String code = text(tag, "code");
        if ("custom_html".equals(type)) {
            if (name == null || code == null || code.length() > 32 * 1024 || code.indexOf('\u0000') >= 0)
                throw invalid();
            if (!hasTrigger(tag)) throw invalid();
        } else if (eventType == null && name == null) {
            throw invalid();
        }
        if (eventType != null && eventType.length() > 64) throw invalid();
        if (name != null && name.length() > 256) throw invalid();

        JsonNode trigger = tag.get("trigger");
        if ("event".equals(type) && trigger == null && !hasTriggerArray(tag.get("triggers"))) throw invalid();
        if (trigger != null && !trigger.isNull() && !validTrigger(trigger)) throw invalid();
        JsonNode triggers = tag.get("triggers");
        if (triggers != null && !triggers.isNull()) validateTriggers(triggers);

        JsonNode properties = tag.get("properties");
        if (properties != null && !properties.isNull() && !properties.isObject()) throw invalid();
    }

    private static boolean hasTrigger(JsonNode tag) {
        JsonNode trigger = tag.get("trigger");
        return validTrigger(trigger) || hasTriggerArray(tag.get("triggers"));
    }

    private static boolean hasTriggerArray(JsonNode triggers) {
        return triggers != null && triggers.isArray() && triggers.size() > 0;
    }

    private static void validateTriggers(JsonNode triggers) {
        if (!triggers.isArray() || triggers.size() > 30 || triggers.size() == 0) throw invalid();
        for (JsonNode trigger : triggers) {
            if (trigger == null || trigger.isNull()) throw invalid();
            if (trigger.isTextual()) {
                if (!validTrigger(trigger)) throw invalid();
                continue;
            }
            if (!trigger.isObject()) throw invalid();
            String kind = textOrNull(trigger, "type");
            if (kind == null || "predefined".equals(kind) || "event".equals(kind)) {
                if (!validTrigger(trigger.get("event"))) throw invalid();
                validateConditions(trigger.get("conditions"));
                continue;
            }
            if (!"custom_js".equals(kind)) throw invalid();
            if (trigger.hasNonNull("conditions")) throw invalid();
            String functionName = textOrNull(trigger, "functionName");
            String code = textOrNull(trigger, "code");
            if (functionName == null || functionName.length() > 128) throw invalid();
            if (code != null && (code.length() > 16 * 1024 || code.indexOf('\u0000') >= 0)) throw invalid();
        }
    }

    private static void validateConditions(JsonNode conditions) {
        if (conditions == null || conditions.isNull()) return;
        if (!conditions.isArray() || conditions.size() > 20) throw invalid();
        for (JsonNode condition : conditions) {
            if (condition == null || !condition.isObject()) throw invalid();
            String property = textOrNull(condition, "property");
            String operator = textOrNull(condition, "operator");
            if (property == null || property.length() > 128) throw invalid();
            if (operator == null
                    || !Set.of("equals", "not_equals", "contains", "starts_with", "ends_with", "exists")
                            .contains(operator)) throw invalid();
            if ("exists".equals(operator)) continue;
            JsonNode value = condition.get("value");
            if (value == null
                    || !value.isTextual()
                    || value.asText().length() > 512
                    || value.asText().indexOf('\u0000') >= 0) throw invalid();
        }
    }

    private static boolean validTrigger(JsonNode trigger) {
        if (trigger == null || trigger.isNull()) return false;
        if (trigger.isTextual())
            return !trigger.asText().isBlank() && trigger.asText().length() <= 128;
        return trigger.isObject()
                && trigger.get("event") != null
                && trigger.get("event").isTextual()
                && !trigger.get("event").asText().isBlank()
                && trigger.get("event").asText().length() <= 128;
    }

    private static String text(JsonNode object, String field) {
        JsonNode value = object.get(field);
        if (value == null || value.isNull()) return null;
        if (!value.isTextual() || value.asText().isBlank()) throw invalid();
        return value.asText().trim();
    }

    private static String textOrNull(JsonNode object, String field) {
        JsonNode value = object.get(field);
        if (value == null || value.isNull()) return null;
        if (!value.isTextual() || value.asText().isBlank()) throw invalid();
        return value.asText().trim();
    }

    @Transactional
    public VersionView publish(UUID siteId, UUID containerId, int version) {
        return publishToEnvironment(siteId, containerId, version, "production");
    }

    @Transactional
    public VersionView publishToEnvironment(UUID siteId, UUID containerId, int version, String environment) {
        validateEnvironment(environment);
        TagContainer c = writableContainer(siteId, containerId);
        TagContainerVersion v = TagContainerVersion.find("container.id = ?1 and version = ?2", c.id, version)
                .firstResult();
        if (v == null) throw new ControlPlaneException(404, "VERSION_NOT_FOUND", "Container version was not found");
        if ("production".equals(environment)) {
            TagContainerVersion.update("status = 'draft' where container.id = ?1 and status = 'published'", c.id);
            v.status = "published";
            c.publishedVersion = v.version;
        }
        TagContainerEnvironmentRelease release = TagContainerEnvironmentRelease.find(
                        "container.id = ?1 and environment = ?2", c.id, environment)
                .firstResult();
        if (release == null) {
            release = new TagContainerEnvironmentRelease();
            release.id = UuidV7.next();
            release.container = c;
            release.environment = environment;
        }
        release.version = v.version;
        release.releasedAt = Instant.now();
        release.persist();
        c.updatedAt = Instant.now();
        return version(v);
    }

    public JsonNode published(String trackingId, String environment) {
        validateEnvironment(environment);
        TagContainer c = TagContainer.find("site.trackingId = ?1 and enabled", trackingId)
                .firstResult();
        if (c == null) return mapper.createArrayNode();
        TagContainerEnvironmentRelease release = TagContainerEnvironmentRelease.find(
                        "container.id = ?1 and environment = ?2", c.id, environment)
                .firstResult();
        Integer version = release == null && "production".equals(environment)
                ? c.publishedVersion
                : release == null ? null : release.version;
        if (version == null) return mapper.createArrayNode();
        TagContainerVersion v = TagContainerVersion.find("container.id = ?1 and version = ?2", c.id, version)
                .firstResult();
        try {
            return v == null ? mapper.createArrayNode() : mapper.readTree(v.tagsJson);
        } catch (Exception e) {
            return mapper.createArrayNode();
        }
    }

    private ContainerView view(TagContainer c) {
        Map<String, Integer> releases = new TreeMap<>();
        TagContainerEnvironmentRelease.<TagContainerEnvironmentRelease>list("container.id = ?1", c.id)
                .forEach(release -> releases.put(release.environment, release.version));
        if (c.publishedVersion != null) releases.putIfAbsent("production", c.publishedVersion);
        return new ContainerView(c.id, c.name, c.enabled, c.publishedVersion, releases);
    }

    private VersionView version(TagContainerVersion v) {
        try {
            return new VersionView(v.id, v.version, v.status, mapper.readTree(v.tagsJson));
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    private TemplateView template(TagManagerTemplate template) {
        try {
            return new TemplateView(
                    template.id,
                    template.name,
                    template.description,
                    mapper.readTree(template.tagsJson),
                    template.createdAt,
                    template.updatedAt);
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    private Site readable(UUID id) {
        Site s = sites.site(id);
        access.member(s.organization.id);
        return s;
    }

    private Site writable(UUID id) {
        Site s = sites.site(id);
        access.require(s.organization.id, WorkspaceRole.OWNER, WorkspaceRole.ADMIN);
        return s;
    }

    private TagContainer writableContainer(UUID siteId, UUID id) {
        writable(siteId);
        TagContainer c = container(siteId, id);
        return c;
    }

    private TagContainer readableContainer(UUID siteId, UUID id) {
        readable(siteId);
        return container(siteId, id);
    }

    private TagContainer container(UUID siteId, UUID id) {
        TagContainer c =
                TagContainer.find("id = ?1 and site.id = ?2", id, siteId).firstResult();
        if (c == null) throw new ControlPlaneException(404, "CONTAINER_NOT_FOUND", "Tag container was not found");
        return c;
    }

    private TagManagerTemplate writableTemplate(UUID siteId, UUID templateId) {
        Site s = writable(siteId);
        TagManagerTemplate template = TagManagerTemplate.find(
                        "id = ?1 and organization.id = ?2", templateId, s.organization.id)
                .firstResult();
        if (template == null)
            throw new ControlPlaneException(404, "TAG_TEMPLATE_NOT_FOUND", "Tag manager template was not found");
        return template;
    }

    private static ControlPlaneException invalid() {
        return new ControlPlaneException(400, "INVALID_TAG_CONTAINER", "Tag container payload is invalid");
    }

    private static ControlPlaneException invalidTemplate() {
        return new ControlPlaneException(400, "INVALID_TAG_TEMPLATE", "Tag manager template payload is invalid");
    }

    private static ControlPlaneException invalidPreview() {
        return new ControlPlaneException(400, "INVALID_TAG_PREVIEW", "Tag manager preview event is invalid");
    }

    private static ControlPlaneException previewNotFound() {
        return new ControlPlaneException(404, "PREVIEW_SESSION_NOT_FOUND", "Tag preview session was not found");
    }

    private static void validateEnvironment(String environment) {
        if (environment == null || !ENVIRONMENTS.contains(environment)) {
            throw new ControlPlaneException(400, "INVALID_TAG_ENVIRONMENT", "Tag manager environment is invalid");
        }
    }

    private static void validateTemplate(
            UUID organizationId, UUID templateId, String name, String description, JsonNode tags) {
        if (name == null || name.isBlank() || name.length() > 120) throw invalidTemplate();
        if (description != null && description.length() > 500) throw invalidTemplate();
        String query = templateId == null
                ? "organization.id = ?1 and name = ?2"
                : "organization.id = ?1 and name = ?2 and id <> ?3";
        long matchingNames = templateId == null
                ? TagManagerTemplate.count(query, organizationId, name.trim())
                : TagManagerTemplate.count(query, organizationId, name.trim(), templateId);
        if (matchingNames > 0)
            throw new ControlPlaneException(409, "TAG_TEMPLATE_NAME_EXISTS", "Tag manager template already exists");
        if (tags == null || !tags.isArray() || tags.isEmpty() || tags.size() > 100) throw invalidTemplate();
        if (tags.toString().getBytes(StandardCharsets.UTF_8).length > 64 * 1024) throw invalidTemplate();
        try {
            for (JsonNode tag : tags) validateTag(tag);
        } catch (ControlPlaneException error) {
            if ("INVALID_TAG_CONTAINER".equals(error.code)) throw invalidTemplate();
            throw error;
        }
    }

    private static String normalizeDescription(String description) {
        return description == null || description.isBlank() ? null : description.trim();
    }

    private static void validateName(UUID siteId, UUID containerId, String name) {
        if (name == null || name.isBlank() || name.length() > 256) throw invalid();
        if (TagContainer.count("site.id = ?1 and name = ?2 and id <> ?3", siteId, name.trim(), containerId) > 0)
            throw new ControlPlaneException(409, "CONTAINER_NAME_EXISTS", "Tag container already exists");
    }

    public record ContainerView(
            UUID id,
            String name,
            boolean enabled,
            Integer publishedVersion,
            Map<String, Integer> environmentVersions) {}

    public record VersionView(UUID id, int version, String status, JsonNode tags) {}

    public record TemplateView(
            UUID id, String name, String description, JsonNode tags, Instant createdAt, Instant updatedAt) {}

    public record PreviewCreated(UUID sessionId, String token, Instant expiresAt, boolean executeCustomCode) {}

    public record PreviewBundle(JsonNode tags, boolean executeCustomCode) {}

    public record PreviewEventView(
            UUID id,
            int tagIndex,
            String tagName,
            String triggerEvent,
            String outcome,
            String pagePath,
            Instant occurredAt) {}
}
