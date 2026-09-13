package io.seeray.lens.domain.workspace;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import io.seeray.lens.domain.auth.AppUser;
import jakarta.persistence.*;
import java.time.Instant;

@Entity
@Table(name = "organization_member")
public class OrganizationMember extends PanacheEntityBase {
    @EmbeddedId
    public OrganizationMemberId id;

    @ManyToOne
    @MapsId("organizationId")
    @JoinColumn(name = "organization_id")
    public Organization organization;

    @ManyToOne
    @MapsId("userId")
    @JoinColumn(name = "user_id")
    public AppUser user;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    public WorkspaceRole role;

    @Column(name = "created_at", nullable = false)
    public Instant createdAt;
}
