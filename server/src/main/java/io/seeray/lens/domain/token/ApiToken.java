package io.seeray.lens.domain.token;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import io.seeray.lens.domain.workspace.Organization;
import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

@Entity
@Table(name = "api_token")
public class ApiToken extends PanacheEntityBase {
    @Id
    public UUID id;

    @ManyToOne
    @JoinColumn(name = "organization_id", nullable = false)
    public Organization organization;

    @Column(nullable = false)
    public String name;

    @Column(name = "token_prefix", nullable = false)
    public String tokenPrefix;

    @Column(name = "token_hash", nullable = false, unique = true, columnDefinition = "char(64)")
    public String tokenHash;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(nullable = false, columnDefinition = "jsonb")
    public String scopes;

    @Column(name = "created_at", nullable = false)
    public Instant createdAt;

    @Column(name = "expires_at")
    public Instant expiresAt;

    @Column(name = "last_used_at")
    public Instant lastUsedAt;

    @Column(name = "revoked_at")
    public Instant revokedAt;
}
