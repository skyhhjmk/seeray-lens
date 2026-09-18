package io.seeray.lens.infrastructure.meta;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.seeray.lens.application.MetaAdsCapiGateway;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;

@ApplicationScoped
public class MetaAdsCapiGatewayProducer {
    @Produces
    @ApplicationScoped
    MetaAdsCapiGateway metaAdsCapiGateway(ObjectMapper mapper) {
        return new MetaAdsCapiHttpGateway(mapper);
    }
}
