package io.seeray.lens.application;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.seeray.lens.domain.common.ControlPlaneException;
import io.seeray.lens.domain.common.UuidV7;
import io.seeray.lens.domain.experiment.ExperimentDefinition;
import io.seeray.lens.domain.site.Site;
import io.seeray.lens.domain.workspace.WorkspaceRole;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import java.sql.*;
import java.time.*;
import java.util.*;
import javax.sql.DataSource;

@ApplicationScoped
public class ExperimentService {
    private static final TypeReference<List<String>> VARIANTS = new TypeReference<>() {};
    private static final Set<String> DEVICE_TYPES = Set.of("desktop", "mobile", "tablet", "other");
    private static final Set<Integer> SEGMENT_LOOKBACK_DAYS = Set.of(7, 30, 90);
    private static final Targeting DEFAULT_TARGETING = new Targeting(List.of(), List.of(), null, 30);
    private final SiteService sites;
    private final WorkspaceAccess access;
    private final SegmentService segments;
    private final ObjectMapper mapper;
    private final DataSource dataSource;

    @Inject
    public ExperimentService(
            SiteService sites,
            WorkspaceAccess access,
            SegmentService segments,
            ObjectMapper mapper,
            DataSource dataSource) {
        this.sites = sites;
        this.access = access;
        this.segments = segments;
        this.mapper = mapper;
        this.dataSource = dataSource;
    }

    public List<View> list(UUID siteId) {
        Site s = readable(siteId);
        return ExperimentDefinition.<ExperimentDefinition>list("site.id = ?1 order by name", s.id).stream()
                .map(this::view)
                .toList();
    }

    public List<PublicView> publicDefinitions(String trackingId, String clientVisitorId) {
        Map<UUID, Boolean> segmentEligibility = new HashMap<>();
        List<PublicView> result = new ArrayList<>();
        for (ExperimentDefinition experiment : ExperimentDefinition.<ExperimentDefinition>list(
                "site.trackingId = ?1 and enabled order by name", trackingId)) {
            Targeting targeting = readTargeting(experiment.targetingJson);
            if (targeting.segmentId() != null) {
                if (clientVisitorId == null) continue;
                boolean matches = segmentEligibility.computeIfAbsent(
                        targeting.segmentId(),
                        segmentId -> segments.matchesVisitor(
                                experiment.site.id, segmentId, clientVisitorId, targeting.segmentLookbackDays()));
                if (!matches) continue;
            }
            result.add(new PublicView(
                    experiment.name,
                    read(experiment.variantsJson),
                    new PublicTargeting(targeting.pathPrefixes(), targeting.deviceTypes())));
        }
        return List.copyOf(result);
    }

    @Transactional
    public View create(UUID siteId, Update u) {
        Site s = writable(siteId);
        validate(u);
        Targeting targeting = normalizeTargeting(u.targeting());
        validateSegmentTarget(siteId, targeting);
        if (ExperimentDefinition.count(
                        "site.id = ?1 and name = ?2", siteId, u.name().trim())
                > 0) throw new ControlPlaneException(409, "EXPERIMENT_NAME_EXISTS", "Experiment already exists");
        ExperimentDefinition e = new ExperimentDefinition();
        e.id = UuidV7.next();
        e.site = s;
        e.name = u.name().trim();
        e.enabled = u.enabled();
        e.variantsJson = write(u.variants());
        e.targetingJson = writeTargeting(targeting);
        e.createdAt = e.updatedAt = Instant.now();
        e.persist();
        return view(e);
    }

    @Transactional
    public View update(UUID siteId, UUID id, Update u) {
        writable(siteId);
        validate(u);
        ExperimentDefinition e = experiment(siteId, id);
        Targeting targeting =
                u.targeting() == null ? readTargeting(e.targetingJson) : normalizeTargeting(u.targeting());
        if (u.targeting() != null) validateSegmentTarget(siteId, targeting);
        e.name = u.name().trim();
        e.enabled = u.enabled();
        e.variantsJson = write(u.variants());
        e.targetingJson = writeTargeting(targeting);
        e.updatedAt = Instant.now();
        return view(e);
    }

    @Transactional
    public void delete(UUID siteId, UUID id) {
        writable(siteId);
        experiment(siteId, id).delete();
    }

    public Report report(UUID siteId, UUID id, AnalyticsQueryService.Range range) {
        readable(siteId);
        ExperimentDefinition e = experiment(siteId, id);
        List<String> variants = read(e.variantsJson);
        Map<String, Counts> counts = new LinkedHashMap<>();
        variants.forEach(v -> counts.put(v, new Counts()));
        String sql =
                """
            select client_session_id,event_type,event_data,occurred_at from raw_event where site_id=? and client_session_id is not null and (occurred_at at time zone (select timezone from site where id=?))::date between ? and ? order by client_session_id,occurred_at,received_at,ingest_id
        """;
        Map<String, String> assigned = new HashMap<>();
        Map<String, Instant> exposureAt = new HashMap<>();
        Set<String> converted = new HashSet<>();
        try (Connection c = dataSource.getConnection();
                PreparedStatement p = c.prepareStatement(sql)) {
            p.setObject(1, siteId);
            p.setObject(2, siteId);
            p.setObject(3, range.from());
            p.setObject(4, range.to());
            try (ResultSet r = p.executeQuery()) {
                while (r.next()) {
                    String session = r.getString(1), type = r.getString(2), data = r.getString(3);
                    String exp = field(data, "action");
                    String variant = field(data, "name");
                    if ("experiment_exposure".equals(type)
                            && e.name.equals(exp)
                            && counts.containsKey(variant)
                            && !assigned.containsKey(session)) {
                        assigned.put(session, variant);
                        exposureAt.put(session, r.getTimestamp(4).toInstant());
                        counts.get(variant).exposures++;
                    } else if ("goal".equals(type)
                            && assigned.containsKey(session)
                            && !r.getTimestamp(4).toInstant().isBefore(exposureAt.get(session))
                            && converted.add(session)) counts.get(assigned.get(session)).conversions++;
                }
            }
        } catch (SQLException x) {
            throw new IllegalStateException("Could not query experiment report", x);
        }
        List<VariantReport> reports = new ArrayList<>();
        Counts control =
                counts.isEmpty() ? new Counts() : counts.values().iterator().next();
        double controlRate = control.exposures == 0 ? 0 : (double) control.conversions / control.exposures;
        int index = 0;
        for (Map.Entry<String, Counts> entry : counts.entrySet()) {
            Counts value = entry.getValue();
            double rate = value.exposures == 0 ? 0 : (double) value.conversions / value.exposures;
            Interval rateInterval = wilsonInterval(value);
            Comparison comparison =
                    index++ == 0
                            ? new Comparison(null, null, false, null, null, null)
                            : compare(controlRate, control, rate, value);
            reports.add(new VariantReport(
                    entry.getKey(),
                    value.exposures,
                    value.conversions,
                    rate,
                    comparison.relativeLift(),
                    comparison.pValue(),
                    comparison.significant(),
                    rateInterval == null ? null : rateInterval.lower(),
                    rateInterval == null ? null : rateInterval.upper(),
                    comparison.conversionRateDifference(),
                    comparison.conversionRateDifferenceCiLower(),
                    comparison.conversionRateDifferenceCiUpper()));
        }
        return new Report(e.id, e.name, range.from(), range.to(), reports);
    }

    private String field(String json, String key) {
        try {
            var n = mapper.readTree(json == null ? "{}" : json);
            return n.path(key).asText(n.path("data").path(key).asText(null));
        } catch (Exception ignored) {
            return null;
        }
    }

    private String write(List<String> v) {
        try {
            return mapper.writeValueAsString(v);
        } catch (Exception x) {
            throw new ControlPlaneException(400, "INVALID_EXPERIMENT", "Variants are invalid");
        }
    }

    private List<String> read(String json) {
        try {
            return mapper.readValue(json, VARIANTS);
        } catch (Exception x) {
            throw new IllegalStateException("Stored experiment variants are invalid", x);
        }
    }

    private String writeTargeting(Targeting targeting) {
        try {
            return mapper.writeValueAsString(targeting);
        } catch (Exception x) {
            throw new ControlPlaneException(400, "INVALID_EXPERIMENT_TARGETING", "Experiment targeting is invalid");
        }
    }

    private Targeting readTargeting(String json) {
        try {
            return normalizeTargeting(mapper.readValue(json, Targeting.class));
        } catch (Exception x) {
            throw new IllegalStateException("Stored experiment targeting is invalid", x);
        }
    }

    private View view(ExperimentDefinition e) {
        return new View(e.id, e.name, e.enabled, read(e.variantsJson), readTargeting(e.targetingJson));
    }

    private Site readable(UUID id) {
        Site s = sites.site(id);
        access.member(s.organization.id);
        return s;
    }

    private Site writable(UUID id) {
        Site s = sites.site(id);
        access.require(s.organization.id, WorkspaceRole.OWNER, WorkspaceRole.ADMIN);
        return s;
    }

    private ExperimentDefinition experiment(UUID siteId, UUID id) {
        ExperimentDefinition e = ExperimentDefinition.find("id = ?1 and site.id = ?2", id, siteId)
                .firstResult();
        if (e == null) throw new ControlPlaneException(404, "EXPERIMENT_NOT_FOUND", "Experiment was not found");
        return e;
    }

    private void validateSegmentTarget(UUID siteId, Targeting targeting) {
        if (targeting.segmentId() == null) return;
        SegmentService.View segment = segments.get(siteId, targeting.segmentId());
        if (!segment.enabled())
            throw new ControlPlaneException(
                    409, "SEGMENT_DISABLED", "Enable the saved segment before targeting it in an experiment");
    }

    private static void validate(Update u) {
        if (u.name() == null
                || u.name().isBlank()
                || u.name().length() > 256
                || u.variants() == null
                || u.variants().size() < 2
                || u.variants().size() > 10
                || u.variants().stream().anyMatch(v -> v == null || v.isBlank() || v.length() > 120)
                || new HashSet<>(u.variants()).size() != u.variants().size())
            throw new ControlPlaneException(400, "INVALID_EXPERIMENT", "Experiment needs 2 to 10 unique variants");
    }

    private static Targeting normalizeTargeting(Targeting targeting) {
        if (targeting == null) return DEFAULT_TARGETING;
        List<String> paths = targeting.pathPrefixes() == null
                ? List.of()
                : targeting.pathPrefixes().stream()
                        .filter(Objects::nonNull)
                        .map(String::trim)
                        .filter(value -> !value.isEmpty())
                        .toList();
        List<String> devices = targeting.deviceTypes() == null
                ? List.of()
                : targeting.deviceTypes().stream()
                        .filter(Objects::nonNull)
                        .map(String::trim)
                        .filter(value -> !value.isEmpty())
                        .toList();
        UUID segmentId = targeting.segmentId();
        int lookbackDays = targeting.segmentLookbackDays() == 0 ? 30 : targeting.segmentLookbackDays();
        boolean validPaths = paths.size() <= 20
                && paths.stream()
                        .allMatch(value -> value.length() <= 512
                                && value.startsWith("/")
                                && !value.contains("?")
                                && !value.contains("#"))
                && new HashSet<>(paths).size() == paths.size();
        boolean validDevices = devices.size() <= DEVICE_TYPES.size()
                && devices.stream().allMatch(DEVICE_TYPES::contains)
                && new HashSet<>(devices).size() == devices.size();
        boolean validLookback = SEGMENT_LOOKBACK_DAYS.contains(lookbackDays);
        if (!validPaths || !validDevices || !validLookback)
            throw new ControlPlaneException(
                    400,
                    "INVALID_EXPERIMENT_TARGETING",
                    "Targeting supports up to 20 unique path prefixes, known device types, and 7, 30, or 90 day segment windows");
        return new Targeting(paths, devices, segmentId, lookbackDays);
    }

    private static Comparison compare(double controlRate, Counts control, double variantRate, Counts variant) {
        Interval difference = newcombeDifferenceInterval(control, variant);
        Double rateDifference = variant.exposures == 0 || control.exposures == 0
                ? null
                : variantRate - controlRate;
        if (control.exposures == 0 || variant.exposures == 0)
            return new Comparison(
                    controlRate == 0 ? null : (variantRate - controlRate) / controlRate,
                    null,
                    false,
                    rateDifference,
                    difference == null ? null : difference.lower(),
                    difference == null ? null : difference.upper());
        Double lift = controlRate == 0 ? null : (variantRate - controlRate) / controlRate;
        double pooled = (control.conversions + variant.conversions) / (double) (control.exposures + variant.exposures);
        double variance = pooled * (1 - pooled) * (1.0 / control.exposures + 1.0 / variant.exposures);
        if (variance <= 0)
            return new Comparison(
                    lift,
                    null,
                    false,
                    rateDifference,
                    difference == null ? null : difference.lower(),
                    difference == null ? null : difference.upper());
        double z = (variantRate - controlRate) / Math.sqrt(variance);
        double pValue = Math.min(1, 2 * (1 - normalCdf(Math.abs(z))));
        return new Comparison(
                lift,
                pValue,
                pValue < 0.05,
                rateDifference,
                difference == null ? null : difference.lower(),
                difference == null ? null : difference.upper());
    }

    private static Interval newcombeDifferenceInterval(Counts control, Counts variant) {
        Interval controlInterval = wilsonInterval(control);
        Interval variantInterval = wilsonInterval(variant);
        if (controlInterval == null || variantInterval == null) return null;
        double controlRate = (double) control.conversions / control.exposures;
        double variantRate = (double) variant.conversions / variant.exposures;
        double difference = variantRate - controlRate;
        double lower = difference
                - Math.sqrt(Math.pow(variantRate - variantInterval.lower(), 2)
                        + Math.pow(controlInterval.upper() - controlRate, 2));
        double upper = difference
                + Math.sqrt(Math.pow(variantInterval.upper() - variantRate, 2)
                        + Math.pow(controlRate - controlInterval.lower(), 2));
        return new Interval(Math.max(-1, lower), Math.min(1, upper));
    }

    private static Interval wilsonInterval(Counts counts) {
        if (counts.exposures <= 0) return null;
        final double z = 1.959963984540054;
        double n = counts.exposures;
        double p = (double) counts.conversions / n;
        double zSquared = z * z;
        double denominator = 1 + zSquared / n;
        double center = (p + zSquared / (2 * n)) / denominator;
        double halfWidth = z
                * Math.sqrt(p * (1 - p) / n + zSquared / (4 * n * n))
                / denominator;
        return new Interval(Math.max(0, center - halfWidth), Math.min(1, center + halfWidth));
    }

    private static double normalCdf(double value) {
        double t = 1 / (1 + 0.2316419 * value);
        double density = 0.3989422804014327 * Math.exp(-value * value / 2);
        double probability = 1
                - density
                        * t
                        * (0.319381530 + t * (-0.356563782 + t * (1.781477937 + t * (-1.821255978 + t * 1.330274429))));
        return probability;
    }

    public record Update(boolean enabled, String name, List<String> variants, Targeting targeting) {}

    public record Targeting(
            List<String> pathPrefixes, List<String> deviceTypes, UUID segmentId, int segmentLookbackDays) {}

    public record PublicTargeting(List<String> pathPrefixes, List<String> deviceTypes) {}

    public record View(UUID id, String name, boolean enabled, List<String> variants, Targeting targeting) {}

    public record PublicView(String name, List<String> variants, PublicTargeting targeting) {}

    public record VariantReport(
            String variant,
            long exposures,
            long conversions,
            double conversionRate,
            Double relativeLift,
            Double pValue,
            boolean statisticallySignificant,
            Double conversionRateCiLower,
            Double conversionRateCiUpper,
            Double conversionRateDifference,
            Double conversionRateDifferenceCiLower,
            Double conversionRateDifferenceCiUpper) {}

    public record Report(UUID id, String name, LocalDate from, LocalDate to, List<VariantReport> variants) {}

    private static final class Counts {
        long exposures;
        long conversions;
    }

    private record Comparison(
            Double relativeLift,
            Double pValue,
            boolean significant,
            Double conversionRateDifference,
            Double conversionRateDifferenceCiLower,
            Double conversionRateDifferenceCiUpper) {}

    private record Interval(double lower, double upper) {}
}
