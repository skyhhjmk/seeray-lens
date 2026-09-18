package io.seeray.lens.domain.experiment;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import io.seeray.lens.domain.site.Site;
import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

@Entity
@Table(name = "experiment_definition")
public class ExperimentDefinition extends PanacheEntityBase {
    @Id
    public UUID id;

    @ManyToOne
    @JoinColumn(name = "site_id", nullable = false)
    public Site site;

    @Column(nullable = false)
    public String name;

    @Column(nullable = false)
    public boolean enabled;

    @Column(name = "lifecycle_status", nullable = false, length = 16)
    public String lifecycleStatus;

    @Column(name = "allocation_group", length = 64)
    public String allocationGroup;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "variants_json", nullable = false, columnDefinition = "jsonb")
    public String variantsJson;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "targeting_json", nullable = false, columnDefinition = "jsonb")
    public String targetingJson;

    @Column(name = "created_at", nullable = false)
    public Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    public Instant updatedAt;
}
