package io.seeray.lens.domain.event;

import io.seeray.lens.domain.site.Site;
import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

@Entity
@Table(name = "raw_event", uniqueConstraints = @UniqueConstraint(columnNames = {"site_id", "client_event_id"}))
public class RawEvent {
    @Id
    @Column(name = "ingest_id", nullable = false)
    public UUID ingestId;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "site_id", nullable = false)
    public Site site;

    @Column(name = "client_event_id", nullable = false)
    public UUID clientEventId;

    @Column(name = "client_visitor_id", length = 64)
    public String clientVisitorId;

    @Column(name = "client_session_id", length = 64)
    public String clientSessionId;

    @Column(name = "received_at", nullable = false)
    public Instant receivedAt;

    @Column(name = "occurred_at", nullable = false)
    public Instant occurredAt;

    @Column(name = "event_type", nullable = false)
    public String eventType;

    @Column(name = "page_scheme")
    public String pageScheme;

    @Column(name = "page_host")
    public String pageHost;

    @Column(name = "page_path")
    public String pagePath;

    @Column(name = "page_title")
    public String pageTitle;

    @Column(name = "referrer_scheme")
    public String referrerScheme;

    @Column(name = "referrer_host")
    public String referrerHost;

    @Column(name = "referrer_path")
    public String referrerPath;

    @Column(name = "utm_source")
    public String utmSource;

    @Column(name = "utm_medium")
    public String utmMedium;

    @Column(name = "utm_campaign")
    public String utmCampaign;

    @Column(name = "utm_term")
    public String utmTerm;

    @Column(name = "utm_content")
    public String utmContent;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "event_data", nullable = false, columnDefinition = "jsonb")
    public String eventData;

    @Column(name = "duration_ms")
    public Integer durationMs;

    @Column(name = "user_id_hash", length = 64)
    public String userIdHash;

    @Column(name = "ingest_version", nullable = false)
    public int ingestVersion;

    @Column(name = "created_at", nullable = false)
    public Instant createdAt;
}
