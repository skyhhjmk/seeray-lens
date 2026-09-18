package io.seeray.lens.application;

import java.util.List;
import java.util.Map;

/** Transport boundary for Microsoft's UET Conversions API. */
public interface MicrosoftAdsCapiGateway {
    Result send(String tagId, String token, Map<String, Object> payload);

    record Result(int eventsReceived, List<Map<String, Object>> validationWarnings) {}
}
