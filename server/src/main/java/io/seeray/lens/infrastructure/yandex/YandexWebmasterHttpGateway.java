package io.seeray.lens.infrastructure.yandex;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.seeray.lens.application.YandexWebmasterGateway;
import io.seeray.lens.domain.common.ControlPlaneException;
import jakarta.inject.Inject;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

public class YandexWebmasterHttpGateway implements YandexWebmasterGateway {
    private static final String API_ROOT = "https://api.webmaster.yandex.net/v4";
    private static final HttpClient HTTP = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(8))
            .followRedirects(HttpClient.Redirect.NEVER)
            .build();

    private final ObjectMapper mapper;

    @Inject
    public YandexWebmasterHttpGateway(ObjectMapper mapper) {
        this.mapper = mapper;
    }

    @Override
    public User user(String oauthToken) {
        Map<String, Object> response = get(oauthToken, API_ROOT + "/user");
        Object userId = response.get("user_id");
        if (userId == null || String.valueOf(userId).isBlank()) {
            throw new ControlPlaneException(
                    502, "YANDEX_WEBMASTER_RESPONSE_INVALID", "Yandex did not return an account ID.");
        }
        return new User(String.valueOf(userId));
    }

    @Override
    public List<Host> hosts(String oauthToken, String userId) {
        Map<String, Object> response = get(oauthToken, API_ROOT + "/user/" + encodePath(userId) + "/hosts");
        List<Host> result = new ArrayList<>();
        if (response.get("hosts") instanceof List<?> values) {
            for (Object value : values) {
                if (!(value instanceof Map<?, ?> host)) continue;
                String hostId = text(host.get("host_id"));
                String siteUrl = text(host.get("ascii_host_url"));
                if (!hostId.isBlank() && !siteUrl.isBlank()) {
                    result.add(new Host(hostId, siteUrl, Boolean.TRUE.equals(host.get("verified"))));
                }
            }
        }
        return List.copyOf(result);
    }

    @Override
    public QueryPage popularQueries(
            String oauthToken,
            String userId,
            String hostId,
            LocalDate from,
            LocalDate to,
            String deviceType,
            int offset,
            int limit) {
        String url = API_ROOT + "/user/" + encodePath(userId) + "/hosts/" + encodePath(hostId)
                + "/search-queries/popular?order_by=TOTAL_SHOWS&device_type_indicator=" + encode(deviceType)
                + "&date_from=" + encode(from.toString()) + "&date_to=" + encode(to.toString())
                + "&offset=" + offset + "&limit=" + limit;
        Map<String, Object> response = get(oauthToken, url);
        List<YandexWebmasterGateway.SearchQuery> queries = new ArrayList<>();
        if (response.get("queries") instanceof List<?> values) {
            for (Object value : values) {
                if (!(value instanceof Map<?, ?> query)) continue;
                Object indicatorsValue = query.get("indicators");
                if (!(indicatorsValue instanceof Map<?, ?> indicators)) continue;
                String queryText = text(query.get("query_text"));
                if (queryText.isBlank()) continue;
                double clicks = number(indicators.get("TOTAL_CLICKS"));
                double impressions = number(indicators.get("TOTAL_SHOWS"));
                queries.add(
                        new SearchQuery(queryText, clicks, impressions, number(indicators.get("AVG_SHOW_POSITION"))));
            }
        }
        return new QueryPage(List.copyOf(queries), integer(response.get("count")));
    }

    private Map<String, Object> get(String oauthToken, String url) {
        HttpRequest request = HttpRequest.newBuilder(URI.create(url))
                .timeout(Duration.ofSeconds(30))
                .header("Authorization", "OAuth " + oauthToken)
                .header("Accept", "application/json")
                .GET()
                .build();
        try {
            HttpResponse<String> response = HTTP.send(request, HttpResponse.BodyHandlers.ofString());
            if (response.statusCode() == 401 || response.statusCode() == 403) {
                throw new ControlPlaneException(
                        502,
                        "YANDEX_WEBMASTER_ACCESS_DENIED",
                        "Yandex Webmaster rejected the OAuth token or account. Reauthorize the Yandex user and verify site ownership.");
            }
            if (response.statusCode() == 404) {
                throw new ControlPlaneException(
                        502,
                        "YANDEX_WEBMASTER_SITE_UNAVAILABLE",
                        "Yandex Webmaster could not find verified search data for this site.");
            }
            if (response.statusCode() < 200 || response.statusCode() >= 300) {
                throw new ControlPlaneException(
                        502,
                        "YANDEX_WEBMASTER_API_REJECTED",
                        "Yandex Webmaster returned HTTP " + response.statusCode()
                                + ". Check the property and date range.");
            }
            return mapper.readValue(response.body(), new TypeReference<>() {});
        } catch (ControlPlaneException error) {
            throw error;
        } catch (Exception error) {
            // The token is an Authorization header; never attach the request or response to an API error.
            throw new ControlPlaneException(502, "YANDEX_WEBMASTER_UNAVAILABLE", "Could not reach Yandex Webmaster.");
        }
    }

    private static String text(Object value) {
        return value == null ? "" : String.valueOf(value);
    }

    private static double number(Object value) {
        try {
            return value instanceof Number number ? number.doubleValue() : Double.parseDouble(text(value));
        } catch (NumberFormatException ignored) {
            return 0;
        }
    }

    private static int integer(Object value) {
        try {
            return value instanceof Number number ? number.intValue() : Integer.parseInt(text(value));
        } catch (NumberFormatException ignored) {
            return 0;
        }
    }

    private static String encodePath(String value) {
        return encode(value);
    }

    private static String encode(String value) {
        return URLEncoder.encode(value, StandardCharsets.UTF_8).replace("+", "%20");
    }
}
