package io.seeray.lens.domain.site;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "site_allowed_domain")
public class SiteAllowedDomain extends PanacheEntityBase {
    @Id
    public UUID id;

    @ManyToOne
    @JoinColumn(name = "site_id", nullable = false)
    public Site site;

    @Column(nullable = false)
    public String host;

    @Column(name = "allow_subdomains", nullable = false)
    public boolean allowSubdomains;

    @Column(nullable = false)
    public boolean enabled;

    @Column(name = "created_at", nullable = false)
    public Instant createdAt;
}
