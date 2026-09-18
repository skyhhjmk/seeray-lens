package io.seeray.lens.domain.workspace;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import io.seeray.lens.domain.auth.AppUser;
import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "workspace_audit_log")
public class WorkspaceAuditLog extends PanacheEntityBase {
    @Id
    public UUID id;

    @ManyToOne(optional = false)
    @JoinColumn(name = "organization_id", nullable = false)
    public Organization organization;

    @ManyToOne
    @JoinColumn(name = "actor_user_id")
    public AppUser actor;

    @Column(nullable = false, length = 32)
    public String action;

    @Column(nullable = false, length = 32)
    public String resource;

    @Column(name = "resource_id")
    public UUID resourceId;

    @Column(name = "created_at", nullable = false)
    public Instant createdAt;
}
