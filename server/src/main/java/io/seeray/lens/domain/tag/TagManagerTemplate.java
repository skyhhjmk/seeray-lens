package io.seeray.lens.domain.tag;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import io.seeray.lens.domain.workspace.Organization;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

@Entity
@Table(name = "tag_manager_template")
public class TagManagerTemplate extends PanacheEntityBase {
    @jakarta.persistence.Id
    public UUID id;

    @ManyToOne
    @JoinColumn(name = "organization_id", nullable = false)
    public Organization organization;

    @Column(nullable = false)
    public String name;

    @Column(length = 500)
    public String description;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "tags_json", nullable = false, columnDefinition = "jsonb")
    public String tagsJson;

    @Column(name = "created_at", nullable = false)
    public Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    public Instant updatedAt;
}
