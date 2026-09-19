package io.seeray.lens.application;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.seeray.lens.domain.common.ControlPlaneException;
import io.seeray.lens.domain.common.UuidV7;
import io.seeray.lens.domain.workspace.*;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.transaction.Transactional;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.time.Duration;
import java.time.Instant;
import java.util.*;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

@ApplicationScoped
public class WorkspaceExtensionService {
    private static final SecureRandom RANDOM = new SecureRandom();
    private static final Set<String> SUBSCRIPTIONS =
            Set.of("analytics.event", "analytics.page_view", "diagnostics.alert");
    private final WorkspaceAccess access;
    private final ObjectMapper mapper;
    private final SecretEncryptionService encryption;
    private final WorkspaceAuditRecorder audit;

    public WorkspaceExtensionService(
            WorkspaceAccess access,
            ObjectMapper mapper,
            SecretEncryptionService encryption,
            WorkspaceAuditRecorder audit) {
        this.access = access;
        this.mapper = mapper;
        this.encryption = encryption;
        this.audit = audit;
    }

    public List<ExtensionView> list(UUID workspaceId) {
        OrganizationMember member = access.member(workspaceId);
        return WorkspaceExtension.<WorkspaceExtension>list(
                        "organization.id = ?1 order by updatedAt desc", member.organization.id)
                .stream()
                .map(extension ->
                        view(extension, member.role == WorkspaceRole.OWNER || member.role == WorkspaceRole.ADMIN))
                .toList();
    }

    @Transactional
    public CreatedExtension create(UUID workspaceId, CreateRequest request) {
        OrganizationMember member = access.require(workspaceId, WorkspaceRole.OWNER, WorkspaceRole.ADMIN);
        Validated values = validate(request);
        if (WorkspaceExtension.count("organization.id = ?1 and extensionKey = ?2", workspaceId, values.key) > 0) {
            throw new ControlPlaneException(409, "EXTENSION_KEY_EXISTS", "An extension with this key already exists");
        }
        Instant now = Instant.now();
        String secret = generateSecret();
        WorkspaceExtension extension = new WorkspaceExtension();
        extension.id = UuidV7.next();
        extension.organization = member.organization;
        extension.extensionKey = values.key;
        extension.name = values.name;
        extension.version = values.version;
        extension.endpointUrl = values.endpoint;
        extension.subscriptionsJson = encode(values.subscriptions);
        extension.secretEncrypted = encryption.encrypt(secret);
        extension.status = "enabled";
        extension.createdBy = member.user;
        extension.createdAt = extension.updatedAt = now;
        extension.persist();
        audit.record(workspaceId, access.userId(), "CREATE_WORKSPACE_EXTENSION", "workspace_extension", extension.id);
        return new CreatedExtension(view(extension, true), secret);
    }

    @Transactional
    public ExtensionView update(UUID workspaceId, UUID extensionId, UpdateRequest request) {
        WorkspaceExtension extension = writable(workspaceId, extensionId);
        Validated values = validate(request);
        extension.name = values.name;
        extension.version = values.version;
        extension.endpointUrl = values.endpoint;
        extension.subscriptionsJson = encode(values.subscriptions);
        extension.status = values.status;
        extension.updatedAt = Instant.now();
        audit.record(workspaceId, access.userId(), "UPDATE_WORKSPACE_EXTENSION", "workspace_extension", extension.id);
        return view(extension, true);
    }

    @Transactional
    public ExtensionView archive(UUID workspaceId, UUID extensionId) {
        WorkspaceExtension extension = writable(workspaceId, extensionId);
        extension.status = "archived";
        extension.updatedAt = Instant.now();
        audit.record(workspaceId, access.userId(), "ARCHIVE_WORKSPACE_EXTENSION", "workspace_extension", extension.id);
        return view(extension, true);
    }

    @Transactional
    public RotatedSecret rotateSecret(UUID workspaceId, UUID extensionId) {
        WorkspaceExtension extension = writable(workspaceId, extensionId);
        if ("archived".equals(extension.status))
            throw new ControlPlaneException(409, "EXTENSION_ARCHIVED", "Archived extensions cannot rotate credentials");
        String secret = generateSecret();
        extension.secretEncrypted = encryption.encrypt(secret);
        extension.updatedAt = Instant.now();
        audit.record(workspaceId, access.userId(), "ROTATE_WORKSPACE_EXT_SECRET", "workspace_extension", extension.id);
        return new RotatedSecret(extension.id, secret);
    }

    public TestResult test(UUID workspaceId, UUID extensionId) {
        WorkspaceExtension extension = writable(workspaceId, extensionId);
        if ("archived".equals(extension.status))
            throw new ControlPlaneException(
                    409, "EXTENSION_ARCHIVED", "Archived extensions cannot receive test events");
        String payload = testPayload(extension);
        String signature = sign(encryption.decrypt(extension.secretEncrypted), payload);
        long started = System.nanoTime();
        try {
            HttpRequest request = HttpRequest.newBuilder(URI.create(extension.endpointUrl))
                    .timeout(Duration.ofSeconds(3))
                    .header("Content-Type", "application/json")
                    .header("X-SeeRay-Extension-Event", "extension.test")
                    .header("X-SeeRay-Signature", "sha256=" + signature)
                    .POST(HttpRequest.BodyPublishers.ofString(payload))
                    .build();
            HttpResponse<Void> response = HttpClient.newBuilder()
                    .connectTimeout(Duration.ofSeconds(3))
                    .build()
                    .send(request, HttpResponse.BodyHandlers.discarding());
            return new TestResult("delivered", response.statusCode(), elapsedMillis(started));
        } catch (Exception error) {
            return new TestResult("unreachable", null, elapsedMillis(started));
        }
    }

    private WorkspaceExtension writable(UUID workspaceId, UUID extensionId) {
        access.require(workspaceId, WorkspaceRole.OWNER, WorkspaceRole.ADMIN);
        WorkspaceExtension extension = WorkspaceExtension.find(
                        "id = ?1 and organization.id = ?2", extensionId, workspaceId)
                .firstResult();
        if (extension == null) throw new ControlPlaneException(404, "EXTENSION_NOT_FOUND", "Extension not found");
        return extension;
    }

    private Validated validate(CreateRequest request) {
        if (request == null) throw invalid();
        String key = text(request.extensionKey, 80);
        if (key == null || !key.matches("[a-z][a-z0-9._-]{1,79}")) throw invalid();
        return new Validated(
                key,
                requiredText(request.name, 160),
                requiredText(request.version, 32),
                endpoint(request.endpointUrl),
                subscriptions(request.subscriptions),
                "enabled");
    }

    private Validated validate(UpdateRequest request) {
        if (request == null) throw invalid();
        String status =
                request.status == null ? "disabled" : request.status.trim().toLowerCase(Locale.ROOT);
        if (!Set.of("enabled", "disabled").contains(status)) throw invalid();
        return new Validated(
                null,
                requiredText(request.name, 160),
                requiredText(request.version, 32),
                endpoint(request.endpointUrl),
                subscriptions(request.subscriptions),
                status);
    }

    private List<String> subscriptions(List<String> values) {
        if (values == null || values.size() > SUBSCRIPTIONS.size()) throw invalid();
        LinkedHashSet<String> selected = new LinkedHashSet<>();
        for (String value : values) {
            if (value == null || !SUBSCRIPTIONS.contains(value)) throw invalid();
            selected.add(value);
        }
        return List.copyOf(selected);
    }

    private String endpoint(String value) {
        String endpoint = requiredText(value, 2048);
        try {
            URI uri = URI.create(endpoint);
            String host = uri.getHost();
            if (!"https".equalsIgnoreCase(uri.getScheme())
                    || host == null
                    || uri.getUserInfo() != null
                    || uri.getFragment() != null
                    || host.equalsIgnoreCase("localhost")
                    || host.endsWith(".local")
                    || host.equals("127.0.0.1")
                    || host.equals("::1")) throw invalid();
            return endpoint;
        } catch (IllegalArgumentException error) {
            throw invalid();
        }
    }

    private static String requiredText(String value, int max) {
        String normalized = text(value, max);
        if (normalized == null) throw invalid();
        return normalized;
    }

    private static String text(String value, int max) {
        if (value == null || value.isBlank()) return null;
        String normalized = value.trim();
        return normalized.length() <= max ? normalized : null;
    }

    private String encode(List<String> values) {
        try {
            return mapper.writeValueAsString(values);
        } catch (Exception error) {
            throw new IllegalStateException("Could not encode extension subscriptions", error);
        }
    }

    private List<String> decode(String json) {
        try {
            JsonNode values = mapper.readTree(json);
            if (values == null || !values.isArray()) return List.of();
            List<String> result = new ArrayList<>();
            for (JsonNode value : values) if (value.isTextual()) result.add(value.asText());
            return List.copyOf(result);
        } catch (Exception error) {
            return List.of();
        }
    }

    private ExtensionView view(WorkspaceExtension extension, boolean canManage) {
        return new ExtensionView(
                extension.id,
                extension.extensionKey,
                extension.name,
                extension.version,
                extension.endpointUrl,
                decode(extension.subscriptionsJson),
                extension.status,
                extension.secretEncrypted != null,
                canManage,
                extension.updatedAt);
    }

    private String testPayload(WorkspaceExtension extension) {
        try {
            return mapper.writeValueAsString(Map.of(
                    "schemaVersion",
                    1,
                    "event",
                    "extension.test",
                    "extensionKey",
                    extension.extensionKey,
                    "version",
                    extension.version,
                    "sentAt",
                    Instant.now().toString()));
        } catch (Exception error) {
            throw new IllegalStateException("Could not encode extension test payload", error);
        }
    }

    private static String sign(String secret, String payload) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            return HexFormat.of().formatHex(mac.doFinal(payload.getBytes(StandardCharsets.UTF_8)));
        } catch (Exception error) {
            throw new IllegalStateException("Could not sign extension payload", error);
        }
    }

    private static long elapsedMillis(long started) {
        return Math.max(0, (System.nanoTime() - started) / 1_000_000);
    }

    private static String generateSecret() {
        byte[] bytes = new byte[32];
        RANDOM.nextBytes(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }

    private static ControlPlaneException invalid() {
        return new ControlPlaneException(400, "INVALID_WORKSPACE_EXTENSION", "Check the extension manifest fields");
    }

    private record Validated(
            String key, String name, String version, String endpoint, List<String> subscriptions, String status) {}

    public record CreateRequest(
            String extensionKey, String name, String version, String endpointUrl, List<String> subscriptions) {}

    public record UpdateRequest(
            String name, String version, String endpointUrl, List<String> subscriptions, String status) {}

    public record ExtensionView(
            UUID id,
            String extensionKey,
            String name,
            String version,
            String endpointUrl,
            List<String> subscriptions,
            String status,
            boolean secretConfigured,
            boolean canManage,
            Instant updatedAt) {}

    public record CreatedExtension(ExtensionView extension, String secret) {}

    public record RotatedSecret(UUID extensionId, String secret) {}

    public record TestResult(String status, Integer responseStatus, long latencyMs) {}
}
