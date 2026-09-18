package io.seeray.lens.domain.tag;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "tag_container_environment_release")
public class TagContainerEnvironmentRelease extends PanacheEntityBase {
    @jakarta.persistence.Id
    public UUID id;

    @ManyToOne
    @JoinColumn(name = "container_id", nullable = false)
    public TagContainer container;

    @Column(nullable = false)
    public String environment;

    @Column(nullable = false)
    public int version;

    @Column(name = "released_at", nullable = false)
    public Instant releasedAt;
}
