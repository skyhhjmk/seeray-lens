package io.seeray.lens.application;

import java.util.Map;

/** Transport boundary for X Ads Conversion API. */
public interface XAdsConversionsGateway {
    Result send(String pixelId, String accessToken, Map<String, Object> payload);

    record Result(int eventsReceived) {}
}
