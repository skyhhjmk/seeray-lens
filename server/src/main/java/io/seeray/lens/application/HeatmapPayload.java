package io.seeray.lens.application;

import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import java.util.List;

/** Deliberately excludes visitor, session, DOM, text, and selector data. */
public record HeatmapPayload(
        @NotNull Integer schemaVersion,
        @NotBlank @Size(max = 64) String siteId,
        @NotBlank @Pattern(regexp = "^[0-9a-fA-F-]{36}$") String clientBatchId,
        @NotEmpty @Size(max = 500) List<@Valid Event> events) {
    public record Event(
            @NotBlank @Pattern(regexp = "^(start|click|move|scroll)$") String type,
            @NotBlank @Pattern(regexp = "^[0-9a-fA-F-]{36}$") String instanceId,
            @NotBlank @Size(max = 4096) String url,
            @NotBlank @Size(max = 128) String layoutVersion,
            @NotBlank @Size(max = 128) String targetId,
            @Min(1) @Max(32768) int viewportWidth,
            @Min(1) @Max(32768) int viewportHeight,
            @Min(1) @Max(32768) int contentWidth,
            @Min(1) @Max(32768) int contentHeight,
            @Min(0) @Max(32768) Integer x,
            @Min(0) @Max(32768) Integer y,
            @Size(max = 100) List<@Min(0) @Max(99) Integer> scrollBins,
            boolean truncated,
            @Min(0) Integer dropped) {}
}
