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
@Table(name = "tag_manager_preview_event")
public class TagManagerPreviewEvent extends PanacheEntityBase {
    @jakarta.persistence.Id
    public UUID id;

    @ManyToOne
    @JoinColumn(name = "session_id", nullable = false)
    public TagManagerPreviewSession session;

    @Column(name = "tag_index", nullable = false)
    public int tagIndex;

    @Column(name = "tag_name", nullable = false, length = 256)
    public String tagName;

    @Column(name = "trigger_event", nullable = false, length = 64)
    public String triggerEvent;

    @Column(nullable = false, length = 16)
    public String outcome;

    @Column(name = "page_path", nullable = false, length = 512)
    public String pagePath;

    @Column(name = "occurred_at", nullable = false)
    public Instant occurredAt;
}
