package io.seeray.lens.domain.tag;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

@Entity
@Table(name = "tag_container_security_policy")
public class TagContainerSecurityPolicy extends PanacheEntityBase {
    @Id
    @Column(name = "container_id")
    public UUID containerId;

    @Column(name = "allow_custom_code", nullable = false)
    public boolean allowCustomCode;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "allowed_script_origins_json", nullable = false, columnDefinition = "jsonb")
    public String allowedScriptOriginsJson;

    @Column(name = "updated_by", nullable = false)
    public UUID updatedBy;

    @Column(name = "updated_at", nullable = false)
    public Instant updatedAt;
}
