package io.seeray.lens.domain.workspace;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

@Entity
@Table(name = "workspace_extension_delivery")
public class WorkspaceExtensionDelivery extends PanacheEntityBase {
    @Id
    public UUID id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "extension_id", nullable = false)
    public WorkspaceExtension extension;

    @Column(name = "client_event_id", nullable = false)
    public UUID clientEventId;

    @Column(name = "event_type", nullable = false, length = 48)
    public String eventType;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "payload_json", nullable = false, columnDefinition = "jsonb")
    public String payloadJson;

    @Column(nullable = false, length = 16)
    public String status;

    @Column(nullable = false)
    public int attempts;

    @Column(name = "available_at", nullable = false)
    public Instant availableAt;

    @Column(name = "response_status")
    public Integer responseStatus;

    @Column(name = "last_error", length = 500)
    public String lastError;

    @Column(name = "created_at", nullable = false)
    public Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    public Instant updatedAt;

    @Column(name = "delivered_at")
    public Instant deliveredAt;
}
