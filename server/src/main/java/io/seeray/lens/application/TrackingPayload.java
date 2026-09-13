package io.seeray.lens.application;

import com.fasterxml.jackson.databind.JsonNode;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import java.time.Instant;
import java.util.List;
import java.util.Map;

public record TrackingPayload(
        @NotNull Integer schemaVersion,
        @NotBlank @Size(max = 64) String siteId,
        Instant sentAt,
        @NotEmpty @Size(max = 100) List<@Valid TrackingEvent> events) {
    public record TrackingEvent(
            @NotBlank @Size(max = 64) String eventId,
            @NotBlank @Size(max = 64) String type,
            Instant occurredAt,
            @Size(max = 4096) String url,
            @Size(max = 512) String title,
            @Size(max = 4096) String referrer,
            @Min(0) @Max(86_400_000) Integer durationMs,
            @Pattern(
                            regexp =
                                    "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$")
                    String visitorId,
            @Pattern(
                            regexp =
                                    "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$")
                    String sessionId,
            Map<String, Object> data,
            JsonNode properties) {}
}
