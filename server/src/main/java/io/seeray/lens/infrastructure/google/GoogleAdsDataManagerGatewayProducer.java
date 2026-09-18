package io.seeray.lens.infrastructure.google;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.seeray.lens.application.GoogleAdsDataManagerGateway;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;

@ApplicationScoped
public class GoogleAdsDataManagerGatewayProducer {
    @Produces
    @ApplicationScoped
    GoogleAdsDataManagerGateway googleAdsDataManagerGateway(ObjectMapper mapper) {
        return new GoogleAdsDataManagerHttpGateway(mapper);
    }
}
