package io.seeray.lens.infrastructure.google;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.google.auth.oauth2.GoogleCredentials;
import io.seeray.lens.application.SearchConsoleGateway;
import io.seeray.lens.domain.common.ControlPlaneException;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class GoogleSearchConsoleHttpGateway implements SearchConsoleGateway {
    private static final String API_ROOT = "https://searchconsole.googleapis.com/webmasters/v3";
    private static final String SCOPE = "https://www.googleapis.com/auth/webmasters.readonly";
    private static final HttpClient HTTP = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(8))
            .followRedirects(HttpClient.Redirect.NEVER)
            .build();

    private final ObjectMapper mapper;

    public GoogleSearchConsoleHttpGateway(ObjectMapper mapper) {
        this.mapper = mapper;
    }

    @Override
    public List<PropertyAccess> accessibleProperties() {
        Map<String, Object> response = send(HttpRequest.newBuilder(URI.create(API_ROOT + "/sites"))
                .timeout(Duration.ofSeconds(30))
                .header("Authorization", "Bearer " + accessToken())
                .GET()
                .build());
        Object entries = response.get("siteEntry");
        if (!(entries instanceof List<?> sites)) return List.of();
        List<PropertyAccess> result = new ArrayList<>();
        for (Object value : sites) {
            if (!(value instanceof Map<?, ?> site)) continue;
            Object property = site.get("siteUrl");
            if (property instanceof String propertyUrl) {
                result.add(new PropertyAccess(propertyUrl, String.valueOf(site.get("permissionLevel"))));
            }
        }
        return List.copyOf(result);
    }

    @Override
    public SearchResult query(String propertyUrl, QueryRequest request) {
        Map<String, Object> body = new HashMap<>();
        body.put("startDate", request.startDate());
        body.put("endDate", request.endDate());
        body.put("dimensions", request.dimensions());
        body.put("type", "web");
        body.put("rowLimit", request.rowLimit());
        Map<String, Object> response = send(HttpRequest.newBuilder(URI.create(API_ROOT + "/sites/"
                        + URLEncoder.encode(propertyUrl, StandardCharsets.UTF_8).replace("+", "%20")
                        + "/searchAnalytics/query"))
                .timeout(Duration.ofSeconds(30))
                .header("Authorization", "Bearer " + accessToken())
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofByteArray(writeBody(body)))
                .build());
        List<SearchRow> rows = new ArrayList<>();
        if (response.get("rows") instanceof List<?> values) {
            for (Object value : values) {
                if (!(value instanceof Map<?, ?> row)) continue;
                List<String> keys = row.get("keys") instanceof List<?> dimensions
                        ? dimensions.stream().map(String::valueOf).toList()
                        : List.of();
                rows.add(new SearchRow(
                        keys,
                        number(row.get("clicks")),
                        number(row.get("impressions")),
                        number(row.get("ctr")),
                        number(row.get("position"))));
            }
        }
        return new SearchResult(
                List.copyOf(rows), String.valueOf(response.getOrDefault("responseAggregationType", "auto")));
    }

    private String accessToken() {
        try {
            GoogleCredentials credentials =
                    GoogleCredentials.getApplicationDefault().createScoped(List.of(SCOPE));
            credentials.refreshIfExpired();
            if (credentials.getAccessToken() == null) throw unavailable();
            return credentials.getAccessToken().getTokenValue();
        } catch (ControlPlaneException error) {
            throw error;
        } catch (Exception error) {
            throw unavailable();
        }
    }

    private Map<String, Object> send(HttpRequest request) {
        try {
            HttpResponse<String> response = HTTP.send(request, HttpResponse.BodyHandlers.ofString());
            if (response.statusCode() == 401 || response.statusCode() == 403) {
                throw new ControlPlaneException(
                        502,
                        "SEARCH_CONSOLE_ACCESS_DENIED",
                        "Google Search Console denied access. Grant the server service identity access to this property.");
            }
            if (response.statusCode() < 200 || response.statusCode() >= 300) {
                throw new ControlPlaneException(
                        502,
                        "SEARCH_CONSOLE_API_REJECTED",
                        "Google Search Console returned HTTP " + response.statusCode()
                                + ". Check the property, date range, and API quota.");
            }
            return mapper.readValue(response.body(), new TypeReference<>() {});
        } catch (ControlPlaneException error) {
            throw error;
        } catch (Exception error) {
            throw new ControlPlaneException(
                    502, "SEARCH_CONSOLE_UNAVAILABLE", "Could not reach the Google Search Console API.");
        }
    }

    private byte[] writeBody(Map<String, Object> body) {
        try {
            return mapper.writeValueAsBytes(body);
        } catch (Exception error) {
            throw new ControlPlaneException(
                    500, "SEARCH_CONSOLE_REQUEST_INVALID", "Could not encode the Search Console query.");
        }
    }

    private static double number(Object value) {
        return value instanceof Number number ? number.doubleValue() : 0;
    }

    private static ControlPlaneException unavailable() {
        return new ControlPlaneException(
                503,
                "SEARCH_CONSOLE_NOT_CONFIGURED",
                "Server Google Application Default Credentials are unavailable. Configure ADC with the webmasters.readonly scope.");
    }
}
