package io.seeray.lens.domain.heatmap;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import io.seeray.lens.domain.site.Site;
import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "heatmap_site_config")
public class HeatmapSiteConfig extends PanacheEntityBase {
    @Id
    @Column(name = "site_id")
    public UUID siteId;

    @OneToOne
    @MapsId
    @JoinColumn(name = "site_id")
    public Site site;

    @Column(nullable = false)
    public boolean enabled;

    @Column(name = "sample_rate", nullable = false)
    public int sampleRate;

    @Column(name = "raw_retention_days", nullable = false)
    public int rawRetentionDays;

    @Column(name = "aggregate_retention_days", nullable = false)
    public int aggregateRetentionDays;

    @Column(name = "config_version", nullable = false)
    public long configVersion;

    @Column(name = "updated_at", nullable = false)
    public Instant updatedAt;
}
