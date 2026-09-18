package io.seeray.lens.application;

import java.util.List;
import java.util.Map;

/** Narrow boundary around Google's Data Manager API, replaceable in controlled integration tests. */
public interface GoogleAdsDataManagerGateway {
    Result ingest(Map<String, Object> request, boolean validateOnly);

    record Result(String requestId, List<Map<String, Object>> fieldWarnings) {}
}
