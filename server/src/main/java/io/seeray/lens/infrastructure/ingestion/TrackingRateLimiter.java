package io.seeray.lens.infrastructure.ingestion;

import io.quarkus.redis.datasource.RedisDataSource;
import io.quarkus.redis.datasource.value.ValueCommands;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.jboss.logging.Logger;

@ApplicationScoped
public class TrackingRateLimiter {
    private static final Logger LOG = Logger.getLogger(TrackingRateLimiter.class);
    private final ValueCommands<String, Long> counters;
    private final long limit;

    @Inject
    public TrackingRateLimiter(
            RedisDataSource redis,
            @ConfigProperty(name = "seeray.collector.rate-limit-per-minute", defaultValue = "600") long limit) {
        counters = redis.value(String.class, Long.class);
        this.limit = limit;
    }

    public boolean allow(String siteId) {
        try {
            String key = "seeray:collect:rate:" + siteId + ":" + (System.currentTimeMillis() / 60000);
            long count = counters.incr(key);
            if (count == 1) counters.setex(key, 120, 1L);
            return count <= limit;
        } catch (RuntimeException failure) {
            LOG.warn("Redis rate limiter unavailable; accepting event in degraded mode");
            return true;
        }
    }
}
