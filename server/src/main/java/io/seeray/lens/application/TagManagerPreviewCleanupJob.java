package io.seeray.lens.application;

import io.quarkus.scheduler.Scheduled;
import io.seeray.lens.domain.tag.TagManagerPreviewSession;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.transaction.Transactional;
import java.time.Instant;

@ApplicationScoped
public class TagManagerPreviewCleanupJob {
    @Scheduled(every = "5m", identity = "tag-manager-preview-cleanup")
    @Transactional
    void expireSessions() {
        TagManagerPreviewSession.delete("expiresAt <= ?1", Instant.now());
    }
}
