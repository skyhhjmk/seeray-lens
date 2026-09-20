package io.seeray.lens.application;

import io.seeray.lens.domain.common.*;
import io.seeray.lens.domain.site.*;
import io.seeray.lens.domain.workspace.*;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.transaction.Transactional;
import java.net.*;
import java.security.SecureRandom;
import java.time.*;
import java.time.ZoneId;
import java.util.*;

@ApplicationScoped
public class SiteService {
    private final WorkspaceAccess access;
    private final HeatmapFileCleanupService heatmapFileCleanup;

    public SiteService(WorkspaceAccess access, HeatmapFileCleanupService heatmapFileCleanup) {
        this.access = access;
        this.heatmapFileCleanup = heatmapFileCleanup;
    }

    @Transactional
    public Site create(
            UUID workspace,
            String name,
            String timezone,
            String language,
            Integer raw,
            Integer aggregate,
            Boolean requireConsent,
            Boolean fingerprintRiskEnabled,
            Integer fingerprintRetentionDays) {
        OrganizationMember m = access.require(workspace, WorkspaceRole.OWNER, WorkspaceRole.ADMIN);
        return save(null, m.organization, name, timezone, language, true, requireConsent, raw, aggregate,
                fingerprintRiskEnabled, fingerprintRetentionDays);
    }

    @Transactional
    public Site update(
            UUID id,
            String name,
            String timezone,
            String language,
            Boolean enabled,
            Boolean requireConsent,
            Integer raw,
            Integer aggregate,
            Boolean fingerprintRiskEnabled,
            Integer fingerprintRetentionDays) {
        Site s = site(id);
        access.require(s.organization.id, WorkspaceRole.OWNER, WorkspaceRole.ADMIN);
        return save(s, s.organization, name, timezone, language, enabled, requireConsent, raw, aggregate,
                fingerprintRiskEnabled, fingerprintRetentionDays);
    }

    public Site site(UUID id) {
        Site s = Site.findById(id);
        if (s == null) throw new ControlPlaneException(404, "SITE_NOT_FOUND", "Site not found");
        return s;
    }

    public List<Site> list(UUID workspace) {
        access.member(workspace);
        return Site.list("organization.id", workspace);
    }

    @Transactional
    public void delete(UUID id) {
        Site s = site(id);
        access.require(s.organization.id, WorkspaceRole.OWNER, WorkspaceRole.ADMIN);
        heatmapFileCleanup.queueSite(id);
        s.delete();
    }

    @Transactional
    public SiteAllowedDomain addDomain(UUID site, String host, boolean subs, boolean enabled) {
        Site s = site(site);
        access.require(s.organization.id, WorkspaceRole.OWNER, WorkspaceRole.ADMIN);
        String normalized = normalize(host);
        if (SiteAllowedDomain.count("site.id=?1 and host=?2", site, normalized) > 0)
            throw new ControlPlaneException(409, "DOMAIN_EXISTS", "Domain already exists");
        SiteAllowedDomain d = new SiteAllowedDomain();
        d.id = UuidV7.next();
        d.site = s;
        d.host = normalized;
        d.allowSubdomains = subs;
        d.enabled = enabled;
        d.createdAt = Instant.now();
        d.persist();
        return d;
    }

    public List<SiteAllowedDomain> domains(UUID site) {
        Site s = site(site);
        access.member(s.organization.id);
        return SiteAllowedDomain.list("site.id", site);
    }

    /** Read-only domain lookup for the public collector; it performs no admin authorization. */
    public List<SiteAllowedDomain> trackingDomains(UUID site) {
        return SiteAllowedDomain.list("site.id", site);
    }

    @Transactional
    public SiteAllowedDomain updateDomain(UUID site, UUID id, boolean subs, boolean enabled) {
        Site s = site(site);
        access.require(s.organization.id, WorkspaceRole.OWNER, WorkspaceRole.ADMIN);
        SiteAllowedDomain d =
                SiteAllowedDomain.find("id=?1 and site.id=?2", id, site).firstResult();
        if (d == null) throw new ControlPlaneException(404, "DOMAIN_NOT_FOUND", "Domain not found");
        d.allowSubdomains = subs;
        d.enabled = enabled;
        return d;
    }

    @Transactional
    public void deleteDomain(UUID site, UUID id) {
        Site s = site(site);
        access.require(s.organization.id, WorkspaceRole.OWNER, WorkspaceRole.ADMIN);
        if (SiteAllowedDomain.delete("id=?1 and site.id=?2", id, site) == 0)
            throw new ControlPlaneException(404, "DOMAIN_NOT_FOUND", "Domain not found");
    }

    private Site save(
            Site s,
            Organization org,
            String name,
            String timezone,
            String language,
            Boolean enabled,
            Boolean requireConsent,
            Integer raw,
            Integer aggregate,
            Boolean fingerprintRiskEnabled,
            Integer fingerprintRetentionDays) {
        if (name == null || name.isBlank()) throw new ControlPlaneException(400, "INVALID_SITE", "Name is required");
        try {
            ZoneId.of(timezone);
        } catch (Exception e) {
            throw new ControlPlaneException(400, "INVALID_TIMEZONE", "Timezone must be an IANA timezone");
        }
        int r = raw == null ? (s == null ? 30 : s.rawRetentionDays) : raw;
        int a = aggregate == null ? (s == null ? 730 : s.aggregateRetentionDays) : aggregate;
        if (r < 1 || r > 3650 || a < 1 || a > 3650 || r > a)
            throw new ControlPlaneException(
                    400, "INVALID_RETENTION", "Retention must be 1..3650 and raw cannot exceed aggregate");
        Instant now = Instant.now();
        boolean newSite = s == null;
        if (newSite) {
            s = new Site();
            s.id = UuidV7.next();
            s.organization = org;
            s.trackingId = trackingId();
            s.createdAt = now;
        }
        s.name = name.trim();
        s.timezone = timezone;
        s.defaultLanguage = language == null || language.isBlank() ? "en" : language;
        s.trackingEnabled = enabled == null ? (s == null || s.trackingEnabled) : enabled;
        s.requireConsent = requireConsent == null ? (newSite ? false : s.requireConsent) : requireConsent;
        s.fingerprintRiskEnabled = fingerprintRiskEnabled == null
                ? (newSite ? false : s.fingerprintRiskEnabled)
                : fingerprintRiskEnabled;
        int fingerprintRetention = fingerprintRetentionDays == null
                ? (newSite ? 30 : s.fingerprintRetentionDays)
                : fingerprintRetentionDays;
        if (fingerprintRetention < 1 || fingerprintRetention > 365)
            throw new ControlPlaneException(400, "INVALID_FINGERPRINT_RETENTION", "Fingerprint retention must be between 1 and 365 days");
        s.fingerprintRetentionDays = fingerprintRetention;
        s.rawRetentionDays = r;
        s.aggregateRetentionDays = a;
        s.updatedAt = now;
        if (newSite) s.persist();
        return s;
    }

    static String normalize(String input) {
        try {
            String x = input.trim();
            URI uri = x.contains("://") ? URI.create(x) : URI.create("https://" + x);
            // Scheme, port, path, query, and fragment are presentation input;
            // only the validated host is persisted. User-info is never accepted.
            if (uri.getUserInfo() != null) throw new IllegalArgumentException();
            String host = uri.getHost();
            if (host == null) throw new IllegalArgumentException();
            host = IDN.toASCII(host, IDN.USE_STD3_ASCII_RULES).toLowerCase(Locale.ROOT);
            while (host.endsWith(".")) host = host.substring(0, host.length() - 1);
            if (host.isBlank() || host.length() > 253) throw new IllegalArgumentException();
            return host;
        } catch (Exception e) {
            throw new ControlPlaneException(
                    400, "INVALID_DOMAIN", "A hostname without port, path, query, or fragment is required");
        }
    }

    private static String trackingId() {
        byte[] bytes = new byte[24];
        new SecureRandom().nextBytes(bytes);
        return "srl_" + Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }
}
