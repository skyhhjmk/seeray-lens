package io.seeray.lens.application;

import java.util.Map;

/** Transport boundary for Meta's Conversions API. */
public interface MetaAdsCapiGateway {
    Result send(String datasetId, String token, Map<String, Object> payload);

    record Result(int eventsReceived) {}
}
