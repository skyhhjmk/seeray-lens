package io.seeray.lens.domain.goal;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import io.seeray.lens.domain.site.Site;
import jakarta.persistence.*;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "goal_definition")
public class GoalDefinition extends PanacheEntityBase {
    @Id
    public UUID id;

    @ManyToOne
    @JoinColumn(name = "site_id", nullable = false)
    public Site site;

    @Column(nullable = false)
    public String name;

    @Column(nullable = false)
    public boolean enabled;

    @Column(name = "trigger_type", nullable = false)
    public String triggerType;

    @Column(name = "event_type")
    public String eventType;

    @Column(name = "event_name")
    public String eventName;

    @Column(name = "path_pattern")
    public String pathPattern;

    @Column(name = "path_match_mode", nullable = false)
    public String pathMatchMode;

    @Column(name = "fixed_value", nullable = false)
    public BigDecimal fixedValue;

    @Column(name = "created_at", nullable = false)
    public Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    public Instant updatedAt;
}
