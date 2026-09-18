package io.seeray.lens.application;

import java.time.LocalDate;
import java.util.List;

/** Read-only boundary around Yandex Webmaster API v4. */
public interface YandexWebmasterGateway {
    User user(String oauthToken);

    List<Host> hosts(String oauthToken, String userId);

    QueryPage popularQueries(
            String oauthToken,
            String userId,
            String hostId,
            LocalDate from,
            LocalDate to,
            String deviceType,
            int offset,
            int limit);

    record User(String userId) {}

    record Host(String hostId, String siteUrl, boolean verified) {}

    record SearchQuery(String query, double clicks, double impressions, double averagePosition) {}

    record QueryPage(List<SearchQuery> queries, int totalCount) {}
}
