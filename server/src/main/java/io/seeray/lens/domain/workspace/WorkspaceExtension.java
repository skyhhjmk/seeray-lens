package io.seeray.lens.domain.workspace;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import io.seeray.lens.domain.auth.AppUser;
import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

@Entity
@Table(name = "workspace_extension")
public class WorkspaceExtension extends PanacheEntityBase {
    @Id
    public UUID id;

    @ManyToOne
    @JoinColumn(name = "organization_id", nullable = false)
    public Organization organization;

    @Column(name = "extension_key", nullable = false, length = 80)
    public String extensionKey;

    @Column(nullable = false, length = 160)
    public String name;

    @Column(nullable = false, length = 32)
    public String version;

    @Column(name = "endpoint_url", nullable = false, length = 2048)
    public String endpointUrl;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "subscriptions_json", nullable = false, columnDefinition = "jsonb")
    public String subscriptionsJson;

    @Column(name = "secret_encrypted", nullable = false)
    public byte[] secretEncrypted;

    @Column(nullable = false, length = 16)
    public String status;

    @ManyToOne
    @JoinColumn(name = "created_by", nullable = false)
    public AppUser createdBy;

    @Column(name = "created_at", nullable = false)
    public Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    public Instant updatedAt;
}
