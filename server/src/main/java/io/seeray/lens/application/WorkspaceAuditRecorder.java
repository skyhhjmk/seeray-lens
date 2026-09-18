package io.seeray.lens.application;

import io.seeray.lens.domain.auth.AppUser;
import io.seeray.lens.domain.common.UuidV7;
import io.seeray.lens.domain.workspace.Organization;
import io.seeray.lens.domain.workspace.WorkspaceAuditLog;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.transaction.Transactional;
import java.time.Instant;
import java.util.UUID;

/** Persists metadata-only workspace administrative activity in the caller's transaction. */
@ApplicationScoped
public class WorkspaceAuditRecorder {
    @Transactional
    public void record(UUID workspaceId, UUID actorId, String action, String resource, UUID resourceId) {
        WorkspaceAuditLog entry = new WorkspaceAuditLog();
        entry.id = UuidV7.next();
        entry.organization = Organization.findById(workspaceId);
        entry.actor = actorId == null ? null : AppUser.findById(actorId);
        entry.action = action;
        entry.resource = resource;
        entry.resourceId = resourceId;
        entry.createdAt = Instant.now();
        entry.persist();
    }
}
