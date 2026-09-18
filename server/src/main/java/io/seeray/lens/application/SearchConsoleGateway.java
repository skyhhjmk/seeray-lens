package io.seeray.lens.application;

import java.util.List;

/** Read-only boundary around the Google Search Console API. */
public interface SearchConsoleGateway {
    List<PropertyAccess> accessibleProperties();

    SearchResult query(String propertyUrl, QueryRequest request);

    record PropertyAccess(String propertyUrl, String permissionLevel) {}

    record QueryRequest(String startDate, String endDate, List<String> dimensions, int rowLimit) {}

    record SearchRow(List<String> keys, double clicks, double impressions, double ctr, double position) {}

    record SearchResult(List<SearchRow> rows, String aggregationType) {}
}
