package io.seeray.lens.application;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import java.sql.Connection;
import java.sql.PreparedStatement;
import javax.sql.DataSource;

/** Deletes only processed raw batches; snapshots remain administrator-managed. */
@ApplicationScoped
public class HeatmapRetentionService {
    private final DataSource dataSource;

    @Inject
    public HeatmapRetentionService(DataSource dataSource) {
        this.dataSource = dataSource;
    }

    @Transactional
    public void clean() {
        try (Connection connection = dataSource.getConnection()) {
            delete(
                    connection,
                    "delete from heatmap_raw_batch b using heatmap_site_config c where b.site_id=c.site_id and b.processed_at is not null and b.received_at < now() - (c.raw_retention_days * interval '1 day')");
            delete(
                    connection,
                    "delete from heatmap_grid_daily d using heatmap_site_config c where d.site_id=c.site_id and d.business_date < current_date - c.aggregate_retention_days");
            delete(
                    connection,
                    "delete from heatmap_scroll_daily d using heatmap_site_config c where d.site_id=c.site_id and d.business_date < current_date - c.aggregate_retention_days");
            delete(
                    connection,
                    "delete from heatmap_instance_fact i using heatmap_site_config c where i.site_id=c.site_id and i.business_date < current_date - c.raw_retention_days");
            delete(
                    connection,
                    "delete from heatmap_instance_scroll_bin b using heatmap_site_config c where b.site_id=c.site_id and not exists (select 1 from heatmap_instance_fact i where i.site_id=b.site_id and i.page_instance_id=b.page_instance_id and i.variant_id=b.variant_id)");
        } catch (Exception error) {
            throw new IllegalStateException("Could not clean expired heatmap data", error);
        }
    }

    private static void delete(Connection connection, String sql) throws Exception {
        try (PreparedStatement statement = connection.prepareStatement(sql)) {
            statement.executeUpdate();
        }
    }
}
