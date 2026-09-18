package io.seeray.lens.domain.analytics;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import io.seeray.lens.domain.site.Site;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

@Entity
@Table(name = "page_overlay_session")
public class PageOverlaySession extends PanacheEntityBase {
    @jakarta.persistence.Id
    public UUID id;

    @ManyToOne
    @JoinColumn(name = "site_id", nullable = false)
    public Site site;

    @Column(name = "token_hash", nullable = false, length = 64)
    public String tokenHash;

    @Column(name = "source_path", nullable = false, length = 2048)
    public String sourcePath;

    @Column(name = "from_date", nullable = false)
    public LocalDate fromDate;

    @Column(name = "to_date", nullable = false)
    public LocalDate toDate;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "targets_json", nullable = false, columnDefinition = "jsonb")
    public String targetsJson;

    @Column(name = "created_at", nullable = false)
    public Instant createdAt;

    @Column(name = "expires_at", nullable = false)
    public Instant expiresAt;
}
