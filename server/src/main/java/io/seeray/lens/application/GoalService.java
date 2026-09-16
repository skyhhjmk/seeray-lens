package io.seeray.lens.application;

import io.seeray.lens.domain.common.ControlPlaneException;
import io.seeray.lens.domain.common.UuidV7;
import io.seeray.lens.domain.goal.GoalDefinition;
import io.seeray.lens.domain.site.Site;
import io.seeray.lens.domain.workspace.WorkspaceRole;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.transaction.Transactional;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

@ApplicationScoped
public class GoalService {
    private final SiteService sites;
    private final WorkspaceAccess access;

    public GoalService(SiteService sites, WorkspaceAccess access) {
        this.sites = sites;
        this.access = access;
    }

    public List<View> list(UUID siteId) {
        Site site = sites.site(siteId);
        access.member(site.organization.id);
        return GoalDefinition.<GoalDefinition>list("site.id = ?1 order by name", siteId).stream()
                .map(GoalService::view)
                .toList();
    }

    @Transactional
    public View create(UUID siteId, Update update) {
        Site site = writableSite(siteId);
        validate(update);
        if (GoalDefinition.count(
                        "site.id = ?1 and name = ?2", siteId, update.name().trim())
                > 0) throw new ControlPlaneException(409, "GOAL_NAME_EXISTS", "A goal with this name already exists");
        GoalDefinition goal = new GoalDefinition();
        goal.id = UuidV7.next();
        goal.site = site;
        apply(goal, update);
        goal.createdAt = goal.updatedAt = Instant.now();
        goal.persist();
        return view(goal);
    }

    @Transactional
    public View update(UUID siteId, UUID goalId, Update update) {
        writableSite(siteId);
        validate(update);
        GoalDefinition goal = goal(siteId, goalId);
        if (GoalDefinition.count(
                        "site.id = ?1 and name = ?2 and id <> ?3",
                        siteId,
                        update.name().trim(),
                        goalId)
                > 0) throw new ControlPlaneException(409, "GOAL_NAME_EXISTS", "A goal with this name already exists");
        apply(goal, update);
        goal.updatedAt = Instant.now();
        return view(goal);
    }

    @Transactional
    public void delete(UUID siteId, UUID goalId) {
        writableSite(siteId);
        goal(siteId, goalId).delete();
    }

    private Site writableSite(UUID siteId) {
        Site site = sites.site(siteId);
        access.require(site.organization.id, WorkspaceRole.OWNER, WorkspaceRole.ADMIN);
        return site;
    }

    private static GoalDefinition goal(UUID siteId, UUID goalId) {
        GoalDefinition goal =
                GoalDefinition.find("id = ?1 and site.id = ?2", goalId, siteId).firstResult();
        if (goal == null) throw new ControlPlaneException(404, "GOAL_NOT_FOUND", "Goal was not found");
        return goal;
    }

    private static void validate(Update update) {
        String type = update.triggerType() == null ? "" : update.triggerType();
        String mode = update.pathMatchMode() == null ? "exact" : update.pathMatchMode();
        if (update.name() == null
                || update.name().isBlank()
                || update.name().trim().length() > 256
                || !(type.equals("event") || type.equals("page_view"))
                || !(mode.equals("exact") || mode.equals("contains"))
                || update.fixedValue() == null
                || update.fixedValue().signum() < 0
                || update.fixedValue().scale() > 4)
            throw new ControlPlaneException(400, "INVALID_GOAL", "Goal configuration is invalid");
        if (type.equals("event")
                && (update.eventType() == null
                        || update.eventType().isBlank()
                        || update.eventType().length() > 64))
            throw new ControlPlaneException(400, "INVALID_GOAL", "Event goals require an event type");
        if (type.equals("page_view")
                && (update.pathPattern() == null
                        || update.pathPattern().isBlank()
                        || update.pathPattern().length() > 2048
                        || !update.pathPattern().startsWith("/")))
            throw new ControlPlaneException(400, "INVALID_GOAL", "Page-view goals require a path pattern");
    }

    private static void apply(GoalDefinition goal, Update update) {
        boolean event = update.triggerType().equals("event");
        goal.name = update.name().trim();
        goal.enabled = update.enabled();
        goal.triggerType = update.triggerType();
        goal.eventType = event ? update.eventType().trim() : null;
        goal.eventName =
                event && update.eventName() != null && !update.eventName().isBlank()
                        ? update.eventName().trim()
                        : null;
        goal.pathPattern = event ? null : update.pathPattern().trim();
        goal.pathMatchMode = update.pathMatchMode() == null ? "exact" : update.pathMatchMode();
        goal.fixedValue = update.fixedValue();
    }

    private static View view(GoalDefinition goal) {
        return new View(
                goal.id,
                goal.name,
                goal.enabled,
                goal.triggerType,
                goal.eventType,
                goal.eventName,
                goal.pathPattern,
                goal.pathMatchMode,
                goal.fixedValue);
    }

    public record Update(
            boolean enabled,
            String name,
            String triggerType,
            String eventType,
            String eventName,
            String pathPattern,
            String pathMatchMode,
            BigDecimal fixedValue) {}

    public record View(
            UUID id,
            String name,
            boolean enabled,
            String triggerType,
            String eventType,
            String eventName,
            String pathPattern,
            String pathMatchMode,
            BigDecimal fixedValue) {}
}
