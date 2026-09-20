package io.seeray.lens.application;

import java.time.Instant;
import java.util.UUID;

public record TrackingMessage(
        int messageSchemaVersion,
        UUID ingestId,
        UUID clientEventId,
        UUID siteId,
        Instant receivedAt,
        Instant occurredAt,
        String eventType,
        TrackingSanitizer.CleanUrl page,
        TrackingSanitizer.CleanUrl referrer,
        String eventData,
        Integer durationMs,
        String visitorId,
        String sessionId,
        String userIdHash,
        String fingerprintKey,
        Integer fingerprintAlgorithmVersion,
        String fingerprintStability) {}
