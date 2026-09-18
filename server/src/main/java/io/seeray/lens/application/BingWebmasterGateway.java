package io.seeray.lens.application;

import java.time.LocalDate;
import java.util.List;

/** Read-only boundary around Bing Webmaster Tools' JSON API. */
public interface BingWebmasterGateway {
    List<PropertyAccess> accessibleProperties(String apiKey);

    List<TrafficStat> dailyTraffic(String apiKey, String siteUrl);

    List<BreakdownStat> queryStats(String apiKey, String siteUrl);

    List<BreakdownStat> pageStats(String apiKey, String siteUrl);

    record PropertyAccess(String siteUrl, boolean verified) {}

    record TrafficStat(LocalDate date, double clicks, double impressions) {}

    record BreakdownStat(LocalDate date, String key, double clicks, double impressions, double averagePosition) {}
}
