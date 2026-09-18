package io.seeray.lens.application;

import jakarta.enterprise.context.ApplicationScoped;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/** Generates explainable, volume-gated comparisons between equal adjacent reporting periods. */
@ApplicationScoped
public class AnalyticsInsightsService {
    private static final int ITEMS_PER_CATEGORY = 5;
    private static final long MIN_ABSOLUTE_CHANGE = 10;
    private static final long MIN_NEW_OR_LOST_VOLUME = 20;
    private static final double MIN_RELATIVE_CHANGE = 0.25;

    private final AnalyticsQueryService analytics;
    private final SegmentedAnalyticsQueryService segmented;

    public AnalyticsInsightsService(AnalyticsQueryService analytics, SegmentedAnalyticsQueryService segmented) {
        this.analytics = analytics;
        this.segmented = segmented;
    }

    public Report report(UUID siteId, AnalyticsQueryService.Range currentRange, UUID segmentId) {
        long days = ChronoUnit.DAYS.between(currentRange.from(), currentRange.to()) + 1;
        AnalyticsQueryService.Range previousRange = new AnalyticsQueryService.Range(
                currentRange.from().minusDays(days), currentRange.from().minusDays(1));
        var currentOverview = segmentId == null
                ? analytics.overview(siteId, currentRange)
                : segmented.overview(siteId, currentRange, segmentId);
        var previousOverview = segmentId == null
                ? analytics.overview(siteId, previousRange)
                : segmented.overview(siteId, previousRange, segmentId);
        List<Metric> metrics = List.of(
                metric("page_views", "Page views", currentOverview.pageViews(), previousOverview.pageViews()),
                metric(
                        "unique_visitors",
                        "Unique visitors",
                        currentOverview.uniqueVisitors(),
                        previousOverview.uniqueVisitors()),
                metric("sessions", "Sessions", currentOverview.sessions(), previousOverview.sessions()));

        List<Change> changes = new ArrayList<>();
        addPages(changes, pages(siteId, currentRange, segmentId), pages(siteId, previousRange, segmentId));
        addTraffic(changes, traffic(siteId, currentRange, segmentId), traffic(siteId, previousRange, segmentId));
        addEvents(changes, events(siteId, currentRange, segmentId), events(siteId, previousRange, segmentId));
        return new Report(
                currentRange.from(),
                currentRange.to(),
                previousRange.from(),
                previousRange.to(),
                metrics,
                List.copyOf(changes));
    }

    private List<AnalyticsQueryService.Page> pages(UUID siteId, AnalyticsQueryService.Range range, UUID segmentId) {
        return segmentId == null ? analytics.pages(siteId, range) : segmented.pages(siteId, range, segmentId);
    }

    private List<AnalyticsQueryService.Traffic> traffic(
            UUID siteId, AnalyticsQueryService.Range range, UUID segmentId) {
        return segmentId == null ? analytics.traffic(siteId, range) : segmented.traffic(siteId, range, segmentId);
    }

    private List<AnalyticsQueryService.Event> events(UUID siteId, AnalyticsQueryService.Range range, UUID segmentId) {
        return segmentId == null ? analytics.events(siteId, range) : segmented.events(siteId, range, segmentId);
    }

    private static void addPages(
            List<Change> changes,
            List<AnalyticsQueryService.Page> currentRows,
            List<AnalyticsQueryService.Page> previousRows) {
        Map<String, Long> current = new HashMap<>();
        for (AnalyticsQueryService.Page row : currentRows) current.put(row.path(), row.pageViews());
        Map<String, Long> previous = new HashMap<>();
        for (AnalyticsQueryService.Page row : previousRows) previous.put(row.path(), row.pageViews());
        compare(changes, "page", "Page views", current, previous);
    }

    private static void addEvents(
            List<Change> changes,
            List<AnalyticsQueryService.Event> currentRows,
            List<AnalyticsQueryService.Event> previousRows) {
        Map<String, Long> current = new HashMap<>();
        for (AnalyticsQueryService.Event row : currentRows) {
            if (!"page_view".equals(row.eventType())) current.put(row.eventType(), row.count());
        }
        Map<String, Long> previous = new HashMap<>();
        for (AnalyticsQueryService.Event row : previousRows) {
            if (!"page_view".equals(row.eventType())) previous.put(row.eventType(), row.count());
        }
        compare(changes, "event", "Events", current, previous);
    }

    private static void addTraffic(
            List<Change> changes,
            List<AnalyticsQueryService.Traffic> currentRows,
            List<AnalyticsQueryService.Traffic> previousRows) {
        Map<TrafficKey, Long> current = new HashMap<>();
        for (AnalyticsQueryService.Traffic row : currentRows) current.put(TrafficKey.of(row), row.sessions());
        Map<TrafficKey, Long> previous = new HashMap<>();
        for (AnalyticsQueryService.Traffic row : previousRows) previous.put(TrafficKey.of(row), row.sessions());
        Set<TrafficKey> keys = new HashSet<>(current.keySet());
        keys.addAll(previous.keySet());
        List<Change> ranked = new ArrayList<>();
        for (TrafficKey key : keys) {
            addIfNotable(
                    ranked,
                    "acquisition",
                    key.label(),
                    key.detail(),
                    "Sessions",
                    current.getOrDefault(key, 0L),
                    previous.getOrDefault(key, 0L));
        }
        appendTop(changes, ranked);
    }

    private static void compare(
            List<Change> changes,
            String category,
            String metric,
            Map<String, Long> current,
            Map<String, Long> previous) {
        Set<String> keys = new HashSet<>(current.keySet());
        keys.addAll(previous.keySet());
        List<Change> ranked = new ArrayList<>();
        for (String key : keys) {
            addIfNotable(
                    ranked, category, key, null, metric, current.getOrDefault(key, 0L), previous.getOrDefault(key, 0L));
        }
        appendTop(changes, ranked);
    }

    private static void addIfNotable(
            List<Change> target,
            String category,
            String label,
            String detail,
            String metric,
            long current,
            long previous) {
        long delta = current - previous;
        long absolute = Math.abs(delta);
        boolean notable = previous == 0
                ? current >= MIN_NEW_OR_LOST_VOLUME
                : current == 0
                        ? previous >= MIN_NEW_OR_LOST_VOLUME
                        : absolute >= MIN_ABSOLUTE_CHANGE && absolute / (double) previous >= MIN_RELATIVE_CHANGE;
        if (!notable) return;
        Double percent = previous == 0 ? null : delta * 100d / previous;
        String direction = previous == 0 ? "new" : current == 0 ? "disappeared" : delta > 0 ? "increase" : "decrease";
        target.add(new Change(category, label, detail, metric, current, previous, delta, absolute, percent, direction));
    }

    private static void appendTop(List<Change> target, List<Change> candidates) {
        candidates.stream()
                .sorted(Comparator.comparingLong(Change::absoluteDelta)
                        .reversed()
                        .thenComparing(Change::label))
                .limit(ITEMS_PER_CATEGORY)
                .forEach(target::add);
    }

    private static Metric metric(String key, String label, long current, long previous) {
        return new Metric(
                key,
                label,
                current,
                previous,
                current - previous,
                previous == 0 ? null : (current - previous) * 100d / previous);
    }

    private record TrafficKey(
            String channel, String source, String medium, String campaign, String term, String content) {
        static TrafficKey of(AnalyticsQueryService.Traffic row) {
            return new TrafficKey(row.channel(), row.source(), row.medium(), row.campaign(), row.term(), row.content());
        }

        String label() {
            if (campaign != null && !campaign.isBlank()) return campaign;
            if (source != null && !source.isBlank()) return source;
            return channel;
        }

        String detail() {
            String sourceDetail = source == null ? channel : channel + " · " + source;
            String mediumDetail = medium == null ? sourceDetail : sourceDetail + " / " + medium;
            String result = campaign == null || campaign.isBlank() ? mediumDetail : mediumDetail + " · " + campaign;
            if (term != null && !term.isBlank()) result += " · " + term;
            if (content != null && !content.isBlank()) result += " · " + content;
            return result;
        }
    }

    public record Report(
            LocalDate from,
            LocalDate to,
            LocalDate previousFrom,
            LocalDate previousTo,
            List<Metric> metrics,
            List<Change> changes) {}

    public record Metric(String key, String label, long current, long previous, long delta, Double percentChange) {}

    public record Change(
            String category,
            String label,
            String detail,
            String metric,
            long current,
            long previous,
            long delta,
            long absoluteDelta,
            Double percentChange,
            String direction) {}
}
