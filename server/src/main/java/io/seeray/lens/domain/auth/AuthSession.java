package io.seeray.lens.domain.auth;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "auth_session")
public class AuthSession extends PanacheEntityBase {
    @Id
    public UUID id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id", nullable = false)
    public AppUser user;

    @Column(name = "refresh_token_hash", nullable = false, unique = true, columnDefinition = "char(64)")
    public String refreshTokenHash;

    @Column(name = "expires_at", nullable = false)
    public Instant expiresAt;

    @Column(name = "revoked_at")
    public Instant revokedAt;

    @Column(name = "created_at", nullable = false)
    public Instant createdAt;

    @Column(name = "last_used_at")
    public Instant lastUsedAt;
}
