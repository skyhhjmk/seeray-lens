package io.seeray.lens.application;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.seeray.lens.domain.common.ControlPlaneException;
import io.seeray.lens.domain.common.UuidV7;
import io.seeray.lens.domain.funnel.FunnelDefinition;
import io.seeray.lens.domain.site.Site;
import io.seeray.lens.domain.workspace.WorkspaceRole;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import java.sql.*;
import java.time.Instant;
import java.util.*;
import javax.sql.DataSource;

@ApplicationScoped
public class FunnelService {
    private static final TypeReference<List<Step>> STEPS = new TypeReference<>() {};
    private final SiteService sites;
    private final WorkspaceAccess access;
    private final ObjectMapper mapper;
    private final DataSource dataSource;

    @Inject
    public FunnelService(SiteService sites, WorkspaceAccess access, ObjectMapper mapper, DataSource dataSource) {
        this.sites = sites;
        this.access = access;
        this.mapper = mapper;
        this.dataSource = dataSource;
    }

    public List<View> list(UUID siteId) {
        Site site = readable(siteId);
        return FunnelDefinition.<FunnelDefinition>list("site.id = ?1 order by name", site.id).stream()
                .map(this::view)
                .toList();
    }

    @Transactional
    public View create(UUID siteId, Update update) {
        Site site = writable(siteId);
        validate(update);
        if (FunnelDefinition.count(
                        "site.id = ?1 and name = ?2", siteId, update.name().trim())
                > 0)
            throw new ControlPlaneException(409, "FUNNEL_NAME_EXISTS", "A funnel with this name already exists");
        FunnelDefinition funnel = new FunnelDefinition();
        funnel.id = UuidV7.next();
        funnel.site = site;
        funnel.name = update.name().trim();
        funnel.enabled = update.enabled();
        funnel.stepsJson = write(update.steps());
        funnel.createdAt = funnel.updatedAt = Instant.now();
        funnel.persist();
        return view(funnel);
    }

    @Transactional
    public View update(UUID siteId, UUID funnelId, Update update) {
        writable(siteId);
        validate(update);
        FunnelDefinition funnel = funnel(siteId, funnelId);
        if (FunnelDefinition.count(
                        "site.id = ?1 and name = ?2 and id <> ?3",
                        siteId,
                        update.name().trim(),
                        funnelId)
                > 0)
            throw new ControlPlaneException(409, "FUNNEL_NAME_EXISTS", "A funnel with this name already exists");
        funnel.name = update.name().trim();
        funnel.enabled = update.enabled();
        funnel.stepsJson = write(update.steps());
        funnel.updatedAt = Instant.now();
        return view(funnel);
    }

    @Transactional
    public void delete(UUID siteId, UUID funnelId) {
        writable(siteId);
        funnel(siteId, funnelId).delete();
    }

    public Report report(UUID siteId, UUID funnelId, AnalyticsQueryService.Range range) {
        readable(siteId);
        FunnelDefinition funnel = funnel(siteId, funnelId);
        List<Step> steps = read(funnel.stepsJson);
        List<Session> sessions = sessions(siteId, range);
        long[] reached = new long[steps.size()];
        for (Session session : sessions) {
            int next = 0;
            for (Event event : session.events) {
                if (next < steps.size() && matches(steps.get(next), event)) {
                    reached[next++]++;
                }
            }
        }
        List<StepResult> results = new ArrayList<>();
        for (int i = 0; i < steps.size(); i++)
            results.add(new StepResult(
                    i,
                    steps.get(i).name(),
                    reached[i],
                    reached.length == 0 || reached[0] == 0 ? 0 : (double) reached[i] / reached[0]));
        return new Report(funnel.id, funnel.name, range.from(), range.to(), results);
    }

    private List<Session> sessions(UUID siteId, AnalyticsQueryService.Range range) {
        String sql =
                """
                select client_session_id,event_type,page_path, event_data, occurred_at
                from raw_event where site_id=? and client_session_id is not null
                  and (occurred_at at time zone (select timezone from site where id=?))::date between ? and ?
                order by client_session_id,occurred_at,received_at,ingest_id
                """;
        Map<String, Session> grouped = new LinkedHashMap<>();
        try (Connection c = dataSource.getConnection();
                PreparedStatement p = c.prepareStatement(sql)) {
            p.setObject(1, siteId);
            p.setObject(2, siteId);
            p.setObject(3, range.from());
            p.setObject(4, range.to());
            try (ResultSet r = p.executeQuery()) {
                while (r.next())
                    grouped.computeIfAbsent(r.getString(1), Session::new)
                            .events
                            .add(new Event(
                                    r.getString(2),
                                    r.getString(3),
                                    r.getString(4),
                                    r.getTimestamp(5).toInstant()));
            }
        } catch (SQLException e) {
            throw new IllegalStateException("Could not query funnel sessions", e);
        }
        return new ArrayList<>(grouped.values());
    }

    private boolean matches(Step step, Event event) {
        if ("event".equals(step.type()))
            return event.type().equals(step.eventType())
                    && (step.eventName() == null || step.eventName().equals(name(event.data())));
        if (!"page_view".equals(step.type()) || !"page_view".equals(event.type()) || event.path() == null) return false;
        return "contains".equals(step.matchMode())
                ? event.path().contains(step.path())
                : event.path().equals(step.path());
    }

    private String name(String json) {
        try {
            var node = mapper.readTree(json == null ? "{}" : json);
            return node.path("name").asText(node.path("data").path("name").asText(null));
        } catch (Exception ignored) {
            return null;
        }
    }

    private String write(List<Step> steps) {
        try {
            return mapper.writeValueAsString(steps);
        } catch (Exception e) {
            throw new ControlPlaneException(400, "INVALID_FUNNEL", "Funnel steps are invalid");
        }
    }

    private List<Step> read(String json) {
        try {
            return mapper.readValue(json, STEPS);
        } catch (Exception e) {
            throw new IllegalStateException("Stored funnel steps are invalid", e);
        }
    }

    private View view(FunnelDefinition f) {
        return new View(f.id, f.name, f.enabled, read(f.stepsJson));
    }

    private Site readable(UUID id) {
        Site site = sites.site(id);
        access.member(site.organization.id);
        return site;
    }

    private Site writable(UUID id) {
        Site site = sites.site(id);
        access.require(site.organization.id, WorkspaceRole.OWNER, WorkspaceRole.ADMIN);
        return site;
    }

    private FunnelDefinition funnel(UUID siteId, UUID id) {
        FunnelDefinition f =
                FunnelDefinition.find("id = ?1 and site.id = ?2", id, siteId).firstResult();
        if (f == null) throw new ControlPlaneException(404, "FUNNEL_NOT_FOUND", "Funnel was not found");
        return f;
    }

    private static void validate(Update u) {
        if (u.name() == null
                || u.name().isBlank()
                || u.name().length() > 256
                || u.steps() == null
                || u.steps().size() < 2
                || u.steps().size() > 10)
            throw new ControlPlaneException(400, "INVALID_FUNNEL", "A funnel needs between 2 and 10 steps");
        for (Step s : u.steps()) {
            if (s == null
                    || s.name() == null
                    || s.name().isBlank()
                    || !("event".equals(s.type()) || "page_view".equals(s.type())))
                throw new ControlPlaneException(400, "INVALID_FUNNEL", "Funnel step is invalid");
            if ("event".equals(s.type())
                    && (s.eventType() == null || s.eventType().isBlank()))
                throw new ControlPlaneException(400, "INVALID_FUNNEL", "Event steps require eventType");
            if ("page_view".equals(s.type()) && (s.path() == null || !s.path().startsWith("/")))
                throw new ControlPlaneException(400, "INVALID_FUNNEL", "Page steps require a path");
        }
    }

    public record Step(String name, String type, String eventType, String eventName, String path, String matchMode) {}

    public record Update(boolean enabled, String name, List<Step> steps) {}

    public record View(UUID id, String name, boolean enabled, List<Step> steps) {}

    public record StepResult(int index, String name, long sessions, double rate) {}

    public record Report(
            UUID id, String name, java.time.LocalDate from, java.time.LocalDate to, List<StepResult> steps) {}

    private record Event(String type, String path, String data, Instant at) {}

    private static final class Session {
        final String id;
        final List<Event> events = new ArrayList<>();

        Session(String id) {
            this.id = id;
        }
    }
}
