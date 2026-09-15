package io.seeray.lens.application;

import io.seeray.lens.domain.common.ControlPlaneException;
import io.seeray.lens.domain.heatmap.HeatmapSiteConfig;
import io.seeray.lens.domain.site.Site;
import io.seeray.lens.domain.workspace.WorkspaceRole;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.transaction.Transactional;
import java.time.Instant;
import java.util.UUID;

@ApplicationScoped
public class HeatmapConfigService {
    private final SiteService sites;
    private final WorkspaceAccess access;

    public HeatmapConfigService(SiteService sites, WorkspaceAccess access) {
        this.sites = sites;
        this.access = access;
    }

    public Config get(UUID siteId) {
        Site site = sites.site(siteId);
        access.member(site.organization.id);
        return view(config(site));
    }

    public Config publicConfig(String trackingId) {
        Site site = Site.find("trackingId", trackingId).firstResult();
        if (site == null || !site.trackingEnabled) return new Config(false, 0, 0, 30, 180);
        return view(config(site));
    }

    @Transactional
    public Config update(UUID siteId, Update update) {
        Site site = sites.site(siteId);
        access.require(site.organization.id, WorkspaceRole.OWNER, WorkspaceRole.ADMIN);
        if (update.sampleRate() < 0
                || update.sampleRate() > 100
                || update.rawRetentionDays() < 1
                || update.aggregateRetentionDays() < update.rawRetentionDays())
            throw new ControlPlaneException(400, "INVALID_HEATMAP_CONFIG", "Heatmap configuration is invalid");
        HeatmapSiteConfig config = config(site);
        if (!config.isPersistent()) config.persist();
        config.enabled = update.enabled();
        config.sampleRate = update.sampleRate();
        config.rawRetentionDays = update.rawRetentionDays();
        config.aggregateRetentionDays = update.aggregateRetentionDays();
        config.configVersion++;
        config.updatedAt = Instant.now();
        return view(config);
    }

    private HeatmapSiteConfig config(Site site) {
        HeatmapSiteConfig config = HeatmapSiteConfig.findById(site.id);
        if (config != null) return config;
        config = new HeatmapSiteConfig();
        config.site = site;
        config.siteId = site.id;
        config.enabled = false;
        config.sampleRate = 10;
        config.rawRetentionDays = 30;
        config.aggregateRetentionDays = 180;
        config.configVersion = 1;
        config.updatedAt = Instant.now();
        return config;
    }

    private static Config view(HeatmapSiteConfig config) {
        return new Config(
                config.enabled,
                config.sampleRate,
                config.configVersion,
                config.rawRetentionDays,
                config.aggregateRetentionDays);
    }

    public record Config(
            boolean enabled, int sampleRate, long version, int rawRetentionDays, int aggregateRetentionDays) {}

    public record Update(boolean enabled, int sampleRate, int rawRetentionDays, int aggregateRetentionDays) {}
}
