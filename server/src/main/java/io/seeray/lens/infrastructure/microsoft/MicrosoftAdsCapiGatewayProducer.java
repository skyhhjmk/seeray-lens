package io.seeray.lens.infrastructure.microsoft;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.seeray.lens.application.MicrosoftAdsCapiGateway;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;

@ApplicationScoped
public class MicrosoftAdsCapiGatewayProducer {
    @Produces
    @ApplicationScoped
    MicrosoftAdsCapiGateway microsoftAdsCapiGateway(ObjectMapper mapper) {
        return new MicrosoftAdsCapiHttpGateway(mapper);
    }
}
