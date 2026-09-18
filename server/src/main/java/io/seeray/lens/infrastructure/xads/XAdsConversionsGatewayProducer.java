package io.seeray.lens.infrastructure.xads;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.seeray.lens.application.XAdsConversionsGateway;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;

@ApplicationScoped
public class XAdsConversionsGatewayProducer {
    @Produces
    @ApplicationScoped
    XAdsConversionsGateway xAdsConversionsGateway(ObjectMapper mapper) {
        return new XAdsConversionsHttpGateway(mapper);
    }
}
