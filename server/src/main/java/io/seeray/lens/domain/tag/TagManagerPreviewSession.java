package io.seeray.lens.domain.tag;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
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
@Table(name = "tag_manager_preview_session")
public class TagManagerPreviewSession extends PanacheEntityBase {
    @jakarta.persistence.Id
    public UUID id;

    @ManyToOne
    @JoinColumn(name = "container_id", nullable = false)
    public TagContainer container;

    @Column(name = "token_hash", nullable = false, length = 64)
    public String tokenHash;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "tags_json", nullable = false, columnDefinition = "jsonb")
    public String tagsJson;

    @Column(name = "execute_custom_code", nullable = false)
    public boolean executeCustomCode;

    @Column(name = "created_at", nullable = false)
    public Instant createdAt;

    @Column(name = "expires_at", nullable = false)
    public Instant expiresAt;
}
