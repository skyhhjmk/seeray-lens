package io.seeray.lens.domain.workspace;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "organization")
public class Organization extends PanacheEntityBase {
    @Id
    public UUID id;

    @Column(nullable = false)
    public String name;

    @Column(name = "created_at", nullable = false)
    public Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    public Instant updatedAt;
}
