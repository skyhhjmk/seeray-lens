package io.seeray.lens.infrastructure.xads;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.seeray.lens.application.XAdsConversionsGateway;
import io.seeray.lens.domain.common.ControlPlaneException;
import jakarta.inject.Inject;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.List;
import java.util.Map;

/** Sends first-party click-ID conversion events using X's server-side pixel-token contract. */
public class XAdsConversionsHttpGateway implements XAdsConversionsGateway {
    private static final String ENDPOINT = "https://ads-api.x.com/12/measurement/conversions/";
    private static final HttpClient HTTP = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(8))
            .followRedirects(HttpClient.Redirect.NEVER)
            .build();

    private final ObjectMapper mapper;

    @Inject
    public XAdsConversionsHttpGateway(ObjectMapper mapper) {
        this.mapper = mapper;
    }

    @Override
    public Result send(String pixelId, String accessToken, Map<String, Object> payload) {
        int submitted = eventCount(payload);
        if (submitted < 1) {
            throw new ControlPlaneException(
                    400, "X_ADS_EVENT_REQUIRED", "At least one X conversion event is required.");
        }
        HttpRequest request;
        try {
            request = HttpRequest.newBuilder(URI.create(ENDPOINT + pixelId))
                    .timeout(Duration.ofSeconds(30))
                    .header("X-Pixel-Token", accessToken)
                    .header("Content-Type", "application/json")
                    .header("Accept", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofByteArray(mapper.writeValueAsBytes(payload)))
                    .build();
        } catch (Exception error) {
            throw new ControlPlaneException(
                    500, "X_ADS_REQUEST_INVALID", "Could not prepare the X conversion request.");
        }
        try {
            HttpResponse<String> response = HTTP.send(request, HttpResponse.BodyHandlers.ofString());
            if (response.statusCode() == 401 || response.statusCode() == 403) {
                throw new ControlPlaneException(502, "X_ADS_ACCESS_DENIED", "X rejected this pixel access token.");
            }
            if (response.statusCode() == 400 || response.statusCode() == 422) {
                throw new ControlPlaneException(
                        422,
                        "X_ADS_EVENT_REJECTED",
                        "X rejected the conversion batch. Check its event IDs and timestamps.");
            }
            if (response.statusCode() == 429 || response.statusCode() >= 500) {
                throw new ControlPlaneException(
                        503, "X_ADS_TEMPORARILY_UNAVAILABLE", "X Conversion API is temporarily unavailable.");
            }
            if (response.statusCode() < 200 || response.statusCode() >= 300) {
                throw new ControlPlaneException(502, "X_ADS_API_REJECTED", "X rejected the conversion request.");
            }
            return new Result(submitted);
        } catch (ControlPlaneException error) {
            throw error;
        } catch (Exception error) {
            // Never expose provider response bodies, event payloads, or pixel credentials.
            throw new ControlPlaneException(503, "X_ADS_UNAVAILABLE", "Could not reach the X Conversion API.");
        }
    }

    private static int eventCount(Map<String, Object> payload) {
        Object conversions = payload.get("conversions");
        return conversions instanceof List<?> values ? values.size() : 0;
    }
}
