package io.seeray.lens.domain.site;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import io.seeray.lens.domain.workspace.Organization;
import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "site")
public class Site extends PanacheEntityBase {
    @Id
    public UUID id;

    @ManyToOne
    @JoinColumn(name = "organization_id", nullable = false)
    public Organization organization;

    @Column(nullable = false)
    public String name;

    @Column(name = "tracking_id", nullable = false, unique = true)
    public String trackingId;

    @Column(nullable = false)
    public String timezone;

    @Column(name = "default_language", nullable = false)
    public String defaultLanguage;

    @Column(name = "tracking_enabled", nullable = false)
    public boolean trackingEnabled;

    @Column(name = "require_consent", nullable = false)
    public boolean requireConsent;

    @Column(name = "raw_retention_days", nullable = false)
    public int rawRetentionDays;

    @Column(name = "aggregate_retention_days", nullable = false)
    public int aggregateRetentionDays;

    @Column(name = "created_at", nullable = false)
    public Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    public Instant updatedAt;
}
