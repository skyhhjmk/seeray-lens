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
import java.time.Instant;
import java.util.*;

@ApplicationScoped
public class TagManagerService {
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
    public VersionView draft(UUID siteId, UUID containerId, JsonNode tags) {
        TagContainer c = writableContainer(siteId, containerId);
        if (tags == null || !tags.isArray() || tags.size() > 100) throw invalid();
        Integer next = (Integer) TagContainerVersion.find("container.id = ?1 order by version desc", c.id)
                .project(Integer.class)
                .firstResult();
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
    public VersionView publish(UUID siteId, UUID containerId, int version) {
        TagContainer c = writableContainer(siteId, containerId);
        TagContainerVersion v = TagContainerVersion.find("container.id = ?1 and version = ?2", c.id, version)
                .firstResult();
        if (v == null) throw new ControlPlaneException(404, "VERSION_NOT_FOUND", "Container version was not found");
        TagContainerVersion.update("status = 'draft' where container.id = ?1 and status = 'published'", c.id);
        v.status = "published";
        c.publishedVersion = v.version;
        c.updatedAt = Instant.now();
        return version(v);
    }

    public JsonNode published(String trackingId) {
        TagContainer c = TagContainer.find("site.trackingId = ?1 and enabled", trackingId)
                .firstResult();
        if (c == null || c.publishedVersion == null) return mapper.createArrayNode();
        TagContainerVersion v = TagContainerVersion.find(
                        "container.id = ?1 and version = ?2 and status = 'published'", c.id, c.publishedVersion)
                .firstResult();
        try {
            return v == null ? mapper.createArrayNode() : mapper.readTree(v.tagsJson);
        } catch (Exception e) {
            return mapper.createArrayNode();
        }
    }

    private ContainerView view(TagContainer c) {
        return new ContainerView(c.id, c.name, c.enabled, c.publishedVersion);
    }

    private VersionView version(TagContainerVersion v) {
        try {
            return new VersionView(v.id, v.version, v.status, mapper.readTree(v.tagsJson));
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
        TagContainer c =
                TagContainer.find("id = ?1 and site.id = ?2", id, siteId).firstResult();
        if (c == null) throw new ControlPlaneException(404, "CONTAINER_NOT_FOUND", "Tag container was not found");
        return c;
    }

    private static ControlPlaneException invalid() {
        return new ControlPlaneException(400, "INVALID_TAG_CONTAINER", "Tag container payload is invalid");
    }

    public record ContainerView(UUID id, String name, boolean enabled, Integer publishedVersion) {}

    public record VersionView(UUID id, int version, String status, JsonNode tags) {}
}
