package io.seeray.lens.infrastructure.microsoft;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.seeray.lens.application.MicrosoftAdsCapiGateway;
import io.seeray.lens.domain.common.ControlPlaneException;
import jakarta.inject.Inject;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.List;
import java.util.Map;

public class MicrosoftAdsCapiHttpGateway implements MicrosoftAdsCapiGateway {
    private static final String API_ROOT = "https://capi.uet.microsoft.com/v1";
    private static final HttpClient HTTP = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(8))
            .followRedirects(HttpClient.Redirect.NEVER)
            .build();

    private final ObjectMapper mapper;

    @Inject
    public MicrosoftAdsCapiHttpGateway(ObjectMapper mapper) {
        this.mapper = mapper;
    }

    @Override
    public Result send(String tagId, String token, Map<String, Object> payload) {
        HttpRequest request;
        try {
            request = HttpRequest.newBuilder(URI.create(API_ROOT + "/" + tagId + "/events"))
                    .timeout(Duration.ofSeconds(30))
                    .header("Authorization", "Bearer " + token)
                    .header("Content-Type", "application/json")
                    .header("Accept", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofByteArray(mapper.writeValueAsBytes(payload)))
                    .build();
        } catch (Exception error) {
            throw new ControlPlaneException(
                    500, "MICROSOFT_ADS_REQUEST_INVALID", "Could not prepare the Microsoft Ads request.");
        }

        try {
            HttpResponse<String> response = HTTP.send(request, HttpResponse.BodyHandlers.ofString());
            if (response.statusCode() == 401 || response.statusCode() == 403) {
                throw new ControlPlaneException(
                        502,
                        "MICROSOFT_ADS_ACCESS_DENIED",
                        "Microsoft Ads rejected this UET token or tag ID. Check the token belongs to this tag.");
            }
            if (response.statusCode() == 400) {
                throw new ControlPlaneException(
                        422,
                        "MICROSOFT_ADS_EVENT_REJECTED",
                        "Microsoft Ads rejected the event batch. Check the event mapping, consent, MSCLKID and 7-day time limit.");
            }
            if (response.statusCode() < 200 || response.statusCode() >= 300) {
                throw new ControlPlaneException(
                        502,
                        "MICROSOFT_ADS_API_REJECTED",
                        "Microsoft Ads returned HTTP " + response.statusCode()
                                + ". Check the UET tag and try again later.");
            }
            Map<String, Object> result = mapper.readValue(response.body(), new TypeReference<>() {});
            return new Result(integer(result.get("eventsReceived")), warnings(result));
        } catch (ControlPlaneException error) {
            throw error;
        } catch (Exception error) {
            // Never attach provider responses or authorization headers to an API error.
            throw new ControlPlaneException(
                    503, "MICROSOFT_ADS_UNAVAILABLE", "Could not reach Microsoft Ads Conversions API.");
        }
    }

    private List<Map<String, Object>> warnings(Map<String, Object> response) {
        Object error = response.get("error");
        if (!(error instanceof Map<?, ?> errorMap) || !(errorMap.get("details") instanceof List<?> details)) {
            return List.of();
        }
        return details.stream()
                .filter(Map.class::isInstance)
                .map(Map.class::cast)
                .filter(item -> Boolean.TRUE.equals(item.get("isWarning")))
                .map(item -> Map.<String, Object>of(
                        "index", integer(item.get("index")),
                        "propertyName", safeText(item.get("propertyName"), 120),
                        "errorCode", safeText(item.get("errorCode"), 80)))
                .toList();
    }

    private static int integer(Object value) {
        try {
            return value instanceof Number number ? number.intValue() : Integer.parseInt(String.valueOf(value));
        } catch (Exception ignored) {
            return 0;
        }
    }

    private static String safeText(Object value, int maximum) {
        if (value == null) return "";
        String text = String.valueOf(value).replaceAll("[\\p{Cntrl}]", " ").strip();
        return text.substring(0, Math.min(text.length(), maximum));
    }
}
