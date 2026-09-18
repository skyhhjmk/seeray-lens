package io.seeray.lens.application;

import java.util.Map;

/** Transport boundary for LinkedIn Marketing API Conversions API. */
public interface LinkedInConversionsGateway {
    Result send(String token, Map<String, Object> payload);

    record Result(int eventsReceived) {}
}
