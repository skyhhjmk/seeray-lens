package io.seeray.lens.infrastructure.meta;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.seeray.lens.application.MetaAdsCapiGateway;
import io.seeray.lens.domain.common.ControlPlaneException;
import jakarta.inject.Inject;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.Map;

/** Pinned Graph API endpoint; tokens are sent in the authorization header, never the URL. */
public class MetaAdsCapiHttpGateway implements MetaAdsCapiGateway {
    private static final String API_ROOT = "https://graph.facebook.com/v26.0";
    private static final HttpClient HTTP = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(8))
            .followRedirects(HttpClient.Redirect.NEVER)
            .build();

    private final ObjectMapper mapper;

    @Inject
    public MetaAdsCapiHttpGateway(ObjectMapper mapper) {
        this.mapper = mapper;
    }

    @Override
    public Result send(String datasetId, String token, Map<String, Object> payload) {
        HttpRequest request;
        try {
            request = HttpRequest.newBuilder(URI.create(API_ROOT + "/" + datasetId + "/events"))
                    .timeout(Duration.ofSeconds(30))
                    .header("Authorization", "Bearer " + token)
                    .header("Content-Type", "application/json")
                    .header("Accept", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofByteArray(mapper.writeValueAsBytes(payload)))
                    .build();
        } catch (Exception error) {
            throw new ControlPlaneException(500, "META_ADS_REQUEST_INVALID", "Could not prepare the Meta Ads request.");
        }

        try {
            HttpResponse<String> response = HTTP.send(request, HttpResponse.BodyHandlers.ofString());
            if (response.statusCode() == 401 || response.statusCode() == 403) {
                throw new ControlPlaneException(
                        502, "META_ADS_ACCESS_DENIED", "Meta rejected this access token or dataset permission.");
            }
            if (response.statusCode() == 400) {
                throw new ControlPlaneException(
                        422,
                        "META_ADS_EVENT_REJECTED",
                        "Meta rejected the conversion batch. Check the dataset, event mapping and event timestamps.");
            }
            if (response.statusCode() == 429 || response.statusCode() >= 500) {
                throw new ControlPlaneException(
                        503, "META_ADS_TEMPORARILY_UNAVAILABLE", "Meta Conversions API is temporarily unavailable.");
            }
            if (response.statusCode() < 200 || response.statusCode() >= 300) {
                throw new ControlPlaneException(
                        502, "META_ADS_API_REJECTED", "Meta rejected the request. Check the dataset and try again.");
            }
            Map<String, Object> result = mapper.readValue(response.body(), new TypeReference<>() {});
            return new Result(integer(result.get("events_received")));
        } catch (ControlPlaneException error) {
            throw error;
        } catch (Exception error) {
            // Never attach provider responses, event bodies, or authorization headers to an API error.
            throw new ControlPlaneException(503, "META_ADS_UNAVAILABLE", "Could not reach Meta Conversions API.");
        }
    }

    private static int integer(Object value) {
        try {
            return value instanceof Number number ? number.intValue() : Integer.parseInt(String.valueOf(value));
        } catch (Exception ignored) {
            return 0;
        }
    }
}
