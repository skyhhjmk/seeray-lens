package io.seeray.lens.application;

import java.util.UUID;

/** Broker payload for the isolated heatmap ingestion route. */
public record HeatmapMessage(UUID siteId, int effectiveSampleRate, HeatmapPayload payload) {}
