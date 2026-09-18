package io.seeray.lens.domain.workspace;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import io.seeray.lens.domain.auth.AppUser;
import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "workspace_invitation")
public class WorkspaceInvitation extends PanacheEntityBase {
    @Id
    public UUID id;

    @ManyToOne(optional = false)
    @JoinColumn(name = "organization_id", nullable = false)
    public Organization organization;

    @Column(name = "invited_email", nullable = false, length = 320)
    public String invitedEmail;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    public WorkspaceRole role;

    @Column(name = "token_hash", nullable = false, length = 64, unique = true)
    public String tokenHash;

    @ManyToOne
    @JoinColumn(name = "invited_by")
    public AppUser invitedBy;

    @Column(name = "created_at", nullable = false)
    public Instant createdAt;

    @Column(name = "expires_at", nullable = false)
    public Instant expiresAt;

    @Column(name = "accepted_at")
    public Instant acceptedAt;

    @Column(name = "revoked_at")
    public Instant revokedAt;
}
