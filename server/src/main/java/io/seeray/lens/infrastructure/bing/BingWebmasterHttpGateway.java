package io.seeray.lens.infrastructure.bing;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.seeray.lens.application.BingWebmasterGateway;
import io.seeray.lens.domain.common.ControlPlaneException;
import jakarta.inject.Inject;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class BingWebmasterHttpGateway implements BingWebmasterGateway {
    private static final String API_ROOT = "https://ssl.bing.com/webmaster/api.svc/json";
    private static final Pattern BING_DATE = Pattern.compile("^/Date\\((-?\\d+)([+-]\\d{4})?\\)/$");
    private static final HttpClient HTTP = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(8))
            .followRedirects(HttpClient.Redirect.NEVER)
            .build();

    private final ObjectMapper mapper;

    @Inject
    public BingWebmasterHttpGateway(ObjectMapper mapper) {
        this.mapper = mapper;
    }

    @Override
    public List<PropertyAccess> accessibleProperties(String apiKey) {
        List<PropertyAccess> properties = new ArrayList<>();
        for (Object value : entries(get(apiKey, "GetUserSites", null))) {
            if (!(value instanceof Map<?, ?> property)) continue;
            String url = string(property, "Url", "url");
            if (!url.isBlank()) properties.add(new PropertyAccess(url, bool(property, "IsVerified", "isVerified")));
        }
        return List.copyOf(properties);
    }

    @Override
    public List<TrafficStat> dailyTraffic(String apiKey, String siteUrl) {
        List<TrafficStat> result = new ArrayList<>();
        for (Object value : entries(get(apiKey, "GetRankAndTrafficStats", siteUrl))) {
            if (!(value instanceof Map<?, ?> row)) continue;
            LocalDate date = date(row.get("Date"));
            if (date != null)
                result.add(new TrafficStat(date, number(row.get("Clicks")), number(row.get("Impressions"))));
        }
        return List.copyOf(result);
    }

    @Override
    public List<BreakdownStat> queryStats(String apiKey, String siteUrl) {
        return breakdowns(get(apiKey, "GetQueryStats", siteUrl));
    }

    @Override
    public List<BreakdownStat> pageStats(String apiKey, String siteUrl) {
        return breakdowns(get(apiKey, "GetPageStats", siteUrl));
    }

    private List<BreakdownStat> breakdowns(Map<String, Object> response) {
        List<BreakdownStat> result = new ArrayList<>();
        for (Object value : entries(response)) {
            if (!(value instanceof Map<?, ?> row)) continue;
            LocalDate date = date(row.get("Date"));
            String key = string(row, "Query", "query");
            if (date != null && !key.isBlank()) {
                result.add(new BreakdownStat(
                        date,
                        key,
                        number(row.get("Clicks")),
                        number(row.get("Impressions")),
                        number(first(row, "AvgImpressionPosition", "AverageImpressionPosition"))));
            }
        }
        return List.copyOf(result);
    }

    private Map<String, Object> get(String apiKey, String method, String siteUrl) {
        StringBuilder uri = new StringBuilder(API_ROOT)
                .append('/')
                .append(method)
                .append("?apikey=")
                .append(encode(apiKey));
        if (siteUrl != null) uri.append("&siteUrl=").append(encode(siteUrl));
        HttpRequest request = HttpRequest.newBuilder(URI.create(uri.toString()))
                .timeout(Duration.ofSeconds(30))
                .header("Accept", "application/json")
                .GET()
                .build();
        try {
            HttpResponse<String> response = HTTP.send(request, HttpResponse.BodyHandlers.ofString());
            if (response.statusCode() == 401 || response.statusCode() == 403) {
                throw new ControlPlaneException(
                        502,
                        "BING_WEBMASTER_ACCESS_DENIED",
                        "Bing Webmaster Tools denied this API key. Replace it with a key for a user that can access the verified site.");
            }
            if (response.statusCode() < 200 || response.statusCode() >= 300) {
                throw new ControlPlaneException(
                        502,
                        "BING_WEBMASTER_API_REJECTED",
                        "Bing Webmaster Tools returned HTTP " + response.statusCode()
                                + ". Check the site URL and API quota.");
            }
            return mapper.readValue(response.body(), new TypeReference<>() {});
        } catch (ControlPlaneException error) {
            throw error;
        } catch (Exception error) {
            // Never include the request URI or provider response: Bing's API key is in the query string.
            throw new ControlPlaneException(502, "BING_WEBMASTER_UNAVAILABLE", "Could not reach Bing Webmaster Tools.");
        }
    }

    private static List<?> entries(Map<String, Object> response) {
        Object data = response.get("d");
        return data instanceof List<?> values ? values : List.of();
    }

    private static Object first(Map<?, ?> map, String primary, String secondary) {
        Object value = map.get(primary);
        return value == null ? map.get(secondary) : value;
    }

    private static String string(Map<?, ?> map, String primary, String secondary) {
        Object value = first(map, primary, secondary);
        return value instanceof String text ? text : "";
    }

    private static boolean bool(Map<?, ?> map, String primary, String secondary) {
        Object value = first(map, primary, secondary);
        return Boolean.TRUE.equals(value) || "true".equalsIgnoreCase(String.valueOf(value));
    }

    private static double number(Object value) {
        if (value instanceof Number number) return number.doubleValue();
        try {
            return value == null ? 0 : Double.parseDouble(String.valueOf(value));
        } catch (NumberFormatException ignored) {
            return 0;
        }
    }

    private static LocalDate date(Object value) {
        if (value instanceof String text) {
            try {
                return LocalDate.parse(text);
            } catch (RuntimeException ignored) {
                Matcher matcher = BING_DATE.matcher(text);
                if (!matcher.matches()) return null;
                try {
                    Instant instant = Instant.ofEpochMilli(Long.parseLong(matcher.group(1)));
                    String offset = matcher.group(2);
                    ZoneOffset zone = offset == null
                            ? ZoneOffset.UTC
                            : ZoneOffset.of(offset.substring(0, 3) + ":" + offset.substring(3));
                    return instant.atOffset(zone).toLocalDate();
                } catch (RuntimeException invalid) {
                    return null;
                }
            }
        }
        if (value instanceof Number number) {
            try {
                return Instant.ofEpochMilli(number.longValue())
                        .atOffset(ZoneOffset.UTC)
                        .toLocalDate();
            } catch (RuntimeException ignored) {
                return null;
            }
        }
        return null;
    }

    private static String encode(String value) {
        return URLEncoder.encode(value, StandardCharsets.UTF_8).replace("+", "%20");
    }
}
