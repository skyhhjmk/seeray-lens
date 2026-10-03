package io.seeray.lens.application;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.persistence.EntityManager;
import jakarta.transaction.Transactional;
import java.util.UUID;

@ApplicationScoped
public class SystemAdminAuditRecorder {
    private final EntityManager entityManager;

    public SystemAdminAuditRecorder(EntityManager entityManager) {
        this.entityManager = entityManager;
    }

    @Transactional
    public void record(UUID actorId, UUID targetUserId, UUID siteId, String action) {
        boolean userAction = targetUserId != null;
        String sql = userAction
                ? "INSERT INTO system_admin_audit (id, actor_user_id, target_user_id, site_id, action) VALUES (:id, :actor, :target, NULL, :action)"
                : "INSERT INTO system_admin_audit (id, actor_user_id, target_user_id, site_id, action) VALUES (:id, :actor, NULL, :site, :action)";
        var query = entityManager.createNativeQuery(sql)
                .setParameter("id", UUID.randomUUID())
                .setParameter("actor", actorId)
                .setParameter("action", action);
        if (userAction) query.setParameter("target", targetUserId);
        else query.setParameter("site", siteId);
        query.executeUpdate();
    }
}
