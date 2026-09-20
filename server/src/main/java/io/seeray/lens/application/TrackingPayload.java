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
            @Size(max = 120) String category,
            @Size(max = 120) String action,
            @Size(max = 256) String name,
            Map<String, Object> data,
            JsonNode properties,
            @Valid ClientContext context,
            @Size(max = 256) @Pattern(regexp = "^[^\\p{Cc}]{1,256}$") String userId,
            @Valid Fingerprint fingerprint) {}

    public record Fingerprint(
            @Min(1) @Max(1) Integer algorithmVersion,
            @Pattern(regexp = "^[0-9a-fA-F]{16,128}$") String signalHash,
            @Pattern(regexp = "^(high|medium|low)$") String stability) {}

    public record ClientContext(
            @Pattern(regexp = "^(Chrome|Safari|Firefox|Edge|Opera|Samsung Internet|Other)$") String browser,
            @Pattern(regexp = "^[A-Za-z0-9._-]{1,24}$") String browserVersion,
            @Pattern(regexp = "^(Android|iOS|Windows|macOS|Linux|ChromeOS|Other)$") String operatingSystem,
            @Pattern(regexp = "^[A-Za-z0-9._-]{1,24}$") String operatingSystemVersion,
            @Pattern(regexp = "^(mobile|tablet|desktop|other)$") String deviceType,
            @Pattern(regexp = "^[A-Za-z0-9-]{1,35}$") String language,
            @Min(1) @Max(10000) Integer screenWidth,
            @Min(1) @Max(10000) Integer screenHeight,
            @Min(1) @Max(10000) Integer viewportWidth,
            @Min(1) @Max(10000) Integer viewportHeight,
            @DecimalMin("0.25") @DecimalMax("8.0") Double pixelRatio) {}
}
