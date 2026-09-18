package io.seeray.lens.domain.tag;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import io.seeray.lens.domain.auth.AppUser;
import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "tag_manager_production_request")
public class TagManagerProductionRequest extends PanacheEntityBase {
    @Id
    public UUID id;

    @ManyToOne
    @JoinColumn(name = "container_id", nullable = false)
    public TagContainer container;

    @Column(name = "base_version")
    public Integer baseVersion;

    @Column(name = "target_version", nullable = false)
    public int targetVersion;

    @ManyToOne
    @JoinColumn(name = "requested_by", nullable = false)
    public AppUser requestedBy;

    @Column(name = "requested_at", nullable = false)
    public Instant requestedAt;

    @Column(name = "request_note", nullable = false, length = 1000)
    public String requestNote;

    @Column(nullable = false)
    public String status;

    @ManyToOne
    @JoinColumn(name = "reviewed_by")
    public AppUser reviewedBy;

    @Column(name = "reviewed_at")
    public Instant reviewedAt;

    @Column(name = "review_note", length = 1000)
    public String reviewNote;
}
