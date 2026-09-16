package io.seeray.lens.domain.tag;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

@Entity
@Table(name = "tag_container_version")
public class TagContainerVersion extends PanacheEntityBase {
    @Id
    public UUID id;

    @ManyToOne
    @JoinColumn(name = "container_id", nullable = false)
    public TagContainer container;

    @Column(nullable = false)
    public int version;

    @Column(nullable = false)
    public String status;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "tags_json", nullable = false, columnDefinition = "jsonb")
    public String tagsJson;

    @Column(name = "created_at", nullable = false)
    public Instant createdAt;
}
