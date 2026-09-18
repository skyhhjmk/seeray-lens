package io.seeray.lens.infrastructure.linkedin;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.seeray.lens.application.LinkedInConversionsGateway;
import io.seeray.lens.domain.common.ControlPlaneException;
import jakarta.inject.Inject;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.List;
import java.util.Map;

/** Uses the current versioned LinkedIn Marketing API; credentials are never placed in the URL. */
public class LinkedInConversionsHttpGateway implements LinkedInConversionsGateway {
    private static final String ENDPOINT = "https://api.linkedin.com/rest/conversionEvents";
    private static final String LINKEDIN_VERSION = "202609";
    private static final HttpClient HTTP = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(8))
            .followRedirects(HttpClient.Redirect.NEVER)
            .build();

    private final ObjectMapper mapper;

    @Inject
    public LinkedInConversionsHttpGateway(ObjectMapper mapper) {
        this.mapper = mapper;
    }

    @Override
    public Result send(String token, Map<String, Object> payload) {
        int submitted = eventCount(payload);
        HttpRequest request;
        try {
            request = HttpRequest.newBuilder(URI.create(ENDPOINT))
                    .timeout(Duration.ofSeconds(30))
                    .header("Authorization", "Bearer " + token)
                    .header("Content-Type", "application/json")
                    .header("Accept", "application/json")
                    .header("Linkedin-Version", LINKEDIN_VERSION)
                    .header("X-Restli-Protocol-Version", "2.0.0")
                    .header("X-RestLi-Method", "BATCH_CREATE")
                    .POST(HttpRequest.BodyPublishers.ofByteArray(mapper.writeValueAsBytes(payload)))
                    .build();
        } catch (Exception error) {
            throw new ControlPlaneException(
                    500, "LINKEDIN_ADS_REQUEST_INVALID", "Could not prepare the LinkedIn conversion request.");
        }

        try {
            HttpResponse<String> response = HTTP.send(request, HttpResponse.BodyHandlers.ofString());
            if (response.statusCode() == 401 || response.statusCode() == 403) {
                throw new ControlPlaneException(
                        502,
                        "LINKEDIN_ADS_ACCESS_DENIED",
                        "LinkedIn rejected this OAuth token or conversion permission.");
            }
            if (response.statusCode() == 400 || response.statusCode() == 422) {
                throw new ControlPlaneException(
                        422,
                        "LINKEDIN_ADS_EVENT_REJECTED",
                        "LinkedIn rejected the conversion batch. Check the conversion rule and event timestamps.");
            }
            if (response.statusCode() == 429 || response.statusCode() >= 500) {
                throw new ControlPlaneException(
                        503,
                        "LINKEDIN_ADS_TEMPORARILY_UNAVAILABLE",
                        "LinkedIn Conversions API is temporarily unavailable.");
            }
            if (response.statusCode() < 200 || response.statusCode() >= 300) {
                throw new ControlPlaneException(
                        502,
                        "LINKEDIN_ADS_API_REJECTED",
                        "LinkedIn rejected the request. Check the destination and try again.");
            }
            return new Result(submitted);
        } catch (ControlPlaneException error) {
            throw error;
        } catch (Exception error) {
            // Do not expose provider response bodies, event payloads, or authorization headers.
            throw new ControlPlaneException(
                    503, "LINKEDIN_ADS_UNAVAILABLE", "Could not reach LinkedIn Conversions API.");
        }
    }

    private static int eventCount(Map<String, Object> payload) {
        Object elements = payload.get("elements");
        return elements instanceof List<?> values ? values.size() : 0;
    }
}
