package io.seeray.lens.infrastructure.google;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.google.auth.oauth2.GoogleCredentials;
import io.seeray.lens.application.GoogleAdsDataManagerGateway;
import io.seeray.lens.domain.common.ControlPlaneException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class GoogleAdsDataManagerHttpGateway implements GoogleAdsDataManagerGateway {
    private static final String ENDPOINT = "https://datamanager.googleapis.com/v1/events:ingest";
    private static final String SCOPE = "https://www.googleapis.com/auth/datamanager";
    private static final HttpClient HTTP = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(8))
            .followRedirects(HttpClient.Redirect.NEVER)
            .build();

    private final ObjectMapper mapper;

    public GoogleAdsDataManagerHttpGateway(ObjectMapper mapper) {
        this.mapper = mapper;
    }

    @Override
    public Result ingest(Map<String, Object> request, boolean validateOnly) {
        try {
            GoogleCredentials credentials =
                    GoogleCredentials.getApplicationDefault().createScoped(List.of(SCOPE));
            credentials.refreshIfExpired();
            if (credentials.getAccessToken() == null) {
                throw unavailable("Google application-default credentials did not provide an access token.");
            }
            Map<String, Object> bodyMap = new HashMap<>(request);
            bodyMap.put("validateOnly", validateOnly);
            byte[] body = mapper.writeValueAsBytes(bodyMap);
            HttpRequest httpRequest = HttpRequest.newBuilder(URI.create(ENDPOINT))
                    .timeout(Duration.ofSeconds(30))
                    .header(
                            "Authorization",
                            "Bearer " + credentials.getAccessToken().getTokenValue())
                    .header("Content-Type", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofByteArray(body))
                    .build();
            HttpResponse<String> response = HTTP.send(httpRequest, HttpResponse.BodyHandlers.ofString());
            if (response.statusCode() < 200 || response.statusCode() >= 300) {
                throw new ControlPlaneException(
                        response.statusCode() == 401 || response.statusCode() == 403 ? 403 : 502,
                        "GOOGLE_ADS_API_REJECTED",
                        "Google Data Manager rejected the request (HTTP " + response.statusCode()
                                + "). Check API access, account permission, conversion action, and row warnings.");
            }
            Map<String, Object> result = mapper.readValue(response.body(), new TypeReference<>() {});
            List<Map<String, Object>> warnings = result.get("fieldWarnings") instanceof List<?> values
                    ? values.stream()
                            .filter(Map.class::isInstance)
                            .map(value -> mapper.convertValue(value, new TypeReference<Map<String, Object>>() {}))
                            .toList()
                    : List.of();
            return new Result((String) result.get("requestId"), warnings);
        } catch (ControlPlaneException error) {
            throw error;
        } catch (Exception error) {
            throw unavailable("Could not reach Google Data Manager. Verify server ADC credentials and network access.");
        }
    }

    private static ControlPlaneException unavailable(String message) {
        return new ControlPlaneException(503, "GOOGLE_ADS_NOT_CONFIGURED", message);
    }
}
