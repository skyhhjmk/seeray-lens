package io.seeray.lens.application;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.quarkus.scheduler.Scheduled;
import io.seeray.lens.domain.common.UuidV7;
import io.seeray.lens.domain.site.Site;
import io.seeray.lens.domain.workspace.WorkspaceExtension;
import io.seeray.lens.domain.workspace.WorkspaceExtensionDelivery;
import io.seeray.lens.domain.workspace.WorkspaceRole;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.persistence.EntityManager;
import jakarta.persistence.LockModeType;
import jakarta.transaction.Transactional;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.*;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import org.jboss.logging.Logger;

/** Queues privacy-minimized analytics events and delivers signed extension webhooks with retries. */
@ApplicationScoped
public class WorkspaceExtensionDeliveryService {
    private static final Logger LOG = Logger.getLogger(WorkspaceExtensionDeliveryService.class);
    private static final int MAX_ATTEMPTS = 5;
    private static final int BATCH_SIZE = 20;
    private final EntityManager entityManager;
    private final ObjectMapper mapper;
    private final SecretEncryptionService encryption;
    private final WorkspaceAccess access;
    private final WorkspaceAuditRecorder audit;
    private final HttpClient httpClient;

    public WorkspaceExtensionDeliveryService(
            EntityManager entityManager,
            ObjectMapper mapper,
            SecretEncryptionService encryption,
            WorkspaceAccess access,
            WorkspaceAuditRecorder audit) {
        this.entityManager = entityManager;
        this.mapper = mapper;
        this.encryption = encryption;
        this.access = access;
        this.audit = audit;
        this.httpClient =
                HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(3)).build();
    }

    @Transactional
    public void enqueue(List<TrackingMessage> events) {
        for (TrackingMessage event : events) {
            String subscription = subscription(event.eventType());
            if (subscription == null) continue;
            Site site = Site.findById(event.siteId());
            if (site == null) continue;
            List<WorkspaceExtension> extensions =
                    WorkspaceExtension.list("organization.id = ?1 and status = 'enabled'", site.organization.id);
            for (WorkspaceExtension extension : extensions) {
                if (!subscriptions(extension).contains(subscription)) continue;
                String payload = payload(event, subscription);
                entityManager
                        .createNativeQuery(
                                """
                                INSERT INTO workspace_extension_delivery
                                  (id, extension_id, client_event_id, event_type, payload_json, status, attempts,
                                   available_at, created_at, updated_at)
                                VALUES (?, ?, ?, ?, ?::jsonb, 'pending', 0, now(), now(), now())
                                ON CONFLICT (extension_id, client_event_id, event_type) DO NOTHING
                                """)
                        .setParameter(1, UuidV7.next())
                        .setParameter(2, extension.id)
                        .setParameter(3, event.clientEventId())
                        .setParameter(4, subscription)
                        .setParameter(5, payload)
                        .executeUpdate();
            }
        }
    }

    public List<DeliveryView> list(UUID workspaceId, UUID extensionId, int limit) {
        var member = access.member(workspaceId);
        int bounded = Math.max(1, Math.min(limit, 100));
        return WorkspaceExtensionDelivery.<WorkspaceExtensionDelivery>list(
                        "extension.id = ?1 and extension.organization.id = ?2 order by createdAt desc",
                        extensionId,
                        member.organization.id)
                .stream()
                .limit(bounded)
                .map(delivery -> new DeliveryView(
                        delivery.id,
                        delivery.clientEventId,
                        delivery.eventType,
                        delivery.status,
                        delivery.attempts,
                        delivery.responseStatus,
                        delivery.lastError,
                        delivery.createdAt,
                        delivery.deliveredAt))
                .toList();
    }

    @Transactional
    public DeliveryView retry(UUID workspaceId, UUID extensionId, UUID deliveryId) {
        var member = access.require(workspaceId, WorkspaceRole.OWNER, WorkspaceRole.ADMIN);
        WorkspaceExtensionDelivery delivery = WorkspaceExtensionDelivery.find(
                        "id = ?1 and extension.id = ?2 and extension.organization.id = ?3",
                        deliveryId,
                        extensionId,
                        member.organization.id)
                .firstResult();
        if (delivery == null)
            throw new io.seeray.lens.domain.common.ControlPlaneException(
                    404, "EXTENSION_DELIVERY_NOT_FOUND", "Extension delivery not found");
        if (!"failed".equals(delivery.status))
            throw new io.seeray.lens.domain.common.ControlPlaneException(
                    409, "EXTENSION_DELIVERY_NOT_FAILED", "Only failed deliveries can be retried");
        delivery.status = "pending";
        delivery.availableAt = Instant.now();
        delivery.lastError = null;
        delivery.updatedAt = Instant.now();
        audit.record(
                workspaceId, access.userId(), "RETRY_EXTENSION_DELIVERY", "workspace_extension_delivery", delivery.id);
        return new DeliveryView(
                delivery.id,
                delivery.clientEventId,
                delivery.eventType,
                delivery.status,
                delivery.attempts,
                delivery.responseStatus,
                delivery.lastError,
                delivery.createdAt,
                delivery.deliveredAt);
    }

    @Scheduled(every = "5s", identity = "workspace-extension-delivery")
    void scheduledDeliver() {
        for (int i = 0; i < BATCH_SIZE; i++) {
            Claim claim = claim();
            if (claim == null) return;
            deliver(claim);
        }
    }

    @Transactional
    Claim claim() {
        Instant now = Instant.now();
        entityManager
                .createQuery("update WorkspaceExtensionDelivery d set d.status = 'pending', d.updatedAt = :now "
                        + "where d.status = 'sending' and d.updatedAt < :stale")
                .setParameter("now", now)
                .setParameter("stale", now.minus(Duration.ofMinutes(10)))
                .executeUpdate();
        WorkspaceExtensionDelivery delivery = WorkspaceExtensionDelivery.<WorkspaceExtensionDelivery>find(
                        "status = 'pending' and availableAt <= ?1 order by availableAt asc, createdAt asc", now)
                .withLock(LockModeType.PESSIMISTIC_WRITE)
                .firstResult();
        if (delivery == null) return null;
        delivery.status = "sending";
        delivery.attempts++;
        delivery.updatedAt = now;
        WorkspaceExtension extension = delivery.extension;
        return new Claim(
                delivery.id,
                delivery.attempts,
                extension.endpointUrl,
                extension.secretEncrypted,
                delivery.eventType,
                delivery.payloadJson);
    }

    private void deliver(Claim claim) {
        try {
            String signature = sign(encryption.decrypt(claim.secretEncrypted), claim.payload);
            HttpRequest request = HttpRequest.newBuilder(URI.create(claim.endpoint))
                    .timeout(Duration.ofSeconds(5))
                    .header("Content-Type", "application/json")
                    .header("X-SeeRay-Extension-Event", claim.eventType)
                    .header("X-SeeRay-Signature", "sha256=" + signature)
                    .POST(HttpRequest.BodyPublishers.ofString(claim.payload))
                    .build();
            HttpResponse<Void> response = httpClient.send(request, HttpResponse.BodyHandlers.discarding());
            if (response.statusCode() >= 200 && response.statusCode() < 300) {
                complete(claim.id, response.statusCode());
            } else {
                fail(claim, response.statusCode(), "Endpoint returned HTTP " + response.statusCode());
            }
        } catch (Exception error) {
            LOG.debugf(error, "Workspace extension delivery %s failed", claim.id);
            fail(claim, null, error.getClass().getSimpleName() + ": delivery failed");
        }
    }

    @Transactional
    void complete(UUID id, int responseStatus) {
        WorkspaceExtensionDelivery delivery = WorkspaceExtensionDelivery.findById(id);
        if (delivery == null) return;
        delivery.status = "delivered";
        delivery.responseStatus = responseStatus;
        delivery.lastError = null;
        delivery.deliveredAt = delivery.updatedAt = Instant.now();
    }

    @Transactional
    void fail(Claim claim, Integer responseStatus, String error) {
        WorkspaceExtensionDelivery delivery = WorkspaceExtensionDelivery.findById(claim.id);
        if (delivery == null) return;
        delivery.responseStatus = responseStatus;
        delivery.lastError = error.length() > 500 ? error.substring(0, 500) : error;
        delivery.updatedAt = Instant.now();
        if (claim.attempts >= MAX_ATTEMPTS) {
            delivery.status = "failed";
            return;
        }
        delivery.status = "pending";
        long delaySeconds = Math.min(300, 5L << Math.min(claim.attempts - 1, 6));
        delivery.availableAt = Instant.now().plusSeconds(delaySeconds);
    }

    private String payload(TrackingMessage event, String subscription) {
        Map<String, Object> value = new LinkedHashMap<>();
        value.put("schemaVersion", 1);
        value.put("event", subscription);
        value.put("eventId", event.clientEventId());
        value.put("siteId", event.siteId());
        value.put("occurredAt", event.occurredAt());
        value.put("eventType", event.eventType());
        if (event.page() != null) {
            value.put(
                    "page",
                    Map.of(
                            "scheme", Objects.toString(event.page().scheme(), ""),
                            "host", Objects.toString(event.page().host(), ""),
                            "path", Objects.toString(event.page().path(), ""),
                            "title", Objects.toString(event.page().title(), "")));
        }
        try {
            JsonNode data = mapper.readTree(event.eventData());
            if (data != null && data.isObject()) {
                ((com.fasterxml.jackson.databind.node.ObjectNode) data).remove(List.of("visitorId", "sessionId"));
            }
            value.put("data", data == null ? mapper.createObjectNode() : data);
            return mapper.writeValueAsString(value);
        } catch (Exception error) {
            throw new IllegalStateException("Could not encode extension delivery payload", error);
        }
    }

    private List<String> subscriptions(WorkspaceExtension extension) {
        try {
            JsonNode node = mapper.readTree(extension.subscriptionsJson);
            if (node == null || !node.isArray()) return List.of();
            List<String> result = new ArrayList<>();
            node.elements().forEachRemaining(value -> {
                if (value.isTextual()) result.add(value.asText());
            });
            return result;
        } catch (Exception error) {
            return List.of();
        }
    }

    private static String subscription(String eventType) {
        return switch (eventType) {
            case "page_view" -> "analytics.page_view";
            case "event" -> "analytics.event";
            default -> null;
        };
    }

    private static String sign(String secret, String payload) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            return HexFormat.of().formatHex(mac.doFinal(payload.getBytes(StandardCharsets.UTF_8)));
        } catch (Exception error) {
            throw new IllegalStateException("Could not sign extension delivery", error);
        }
    }

    private record Claim(
            UUID id, int attempts, String endpoint, byte[] secretEncrypted, String eventType, String payload) {}

    public record DeliveryView(
            UUID id,
            UUID clientEventId,
            String eventType,
            String status,
            int attempts,
            Integer responseStatus,
            String lastError,
            Instant createdAt,
            Instant deliveredAt) {}
}
