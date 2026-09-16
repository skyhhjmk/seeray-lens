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
    private final SiteService sites;
    private final WorkspaceAccess access;
    private final ObjectMapper mapper;
    private final DataSource dataSource;

    @Inject
    public ExperimentService(SiteService sites, WorkspaceAccess access, ObjectMapper mapper, DataSource dataSource) {
        this.sites = sites;
        this.access = access;
        this.mapper = mapper;
        this.dataSource = dataSource;
    }

    public List<View> list(UUID siteId) {
        Site s = readable(siteId);
        return ExperimentDefinition.<ExperimentDefinition>list("site.id = ?1 order by name", s.id).stream()
                .map(this::view)
                .toList();
    }

    @Transactional
    public View create(UUID siteId, Update u) {
        Site s = writable(siteId);
        validate(u);
        if (ExperimentDefinition.count(
                        "site.id = ?1 and name = ?2", siteId, u.name().trim())
                > 0) throw new ControlPlaneException(409, "EXPERIMENT_NAME_EXISTS", "Experiment already exists");
        ExperimentDefinition e = new ExperimentDefinition();
        e.id = UuidV7.next();
        e.site = s;
        e.name = u.name().trim();
        e.enabled = u.enabled();
        e.variantsJson = write(u.variants());
        e.createdAt = e.updatedAt = Instant.now();
        e.persist();
        return view(e);
    }

    @Transactional
    public View update(UUID siteId, UUID id, Update u) {
        writable(siteId);
        validate(u);
        ExperimentDefinition e = experiment(siteId, id);
        e.name = u.name().trim();
        e.enabled = u.enabled();
        e.variantsJson = write(u.variants());
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
        return new Report(
                e.id,
                e.name,
                range.from(),
                range.to(),
                counts.entrySet().stream()
                        .map(x -> new VariantReport(
                                x.getKey(),
                                x.getValue().exposures,
                                x.getValue().conversions,
                                x.getValue().exposures == 0
                                        ? 0
                                        : (double) x.getValue().conversions / x.getValue().exposures))
                        .toList());
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

    private View view(ExperimentDefinition e) {
        return new View(e.id, e.name, e.enabled, read(e.variantsJson));
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

    public record Update(boolean enabled, String name, List<String> variants) {}

    public record View(UUID id, String name, boolean enabled, List<String> variants) {}

    public record VariantReport(String variant, long exposures, long conversions, double conversionRate) {}

    public record Report(UUID id, String name, LocalDate from, LocalDate to, List<VariantReport> variants) {}

    private static final class Counts {
        long exposures;
        long conversions;
    }
}
