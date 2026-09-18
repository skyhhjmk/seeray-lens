package io.seeray.lens.infrastructure.bing;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.seeray.lens.application.BingWebmasterGateway;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;

@ApplicationScoped
public class BingWebmasterGatewayProducer {
    @Produces
    @ApplicationScoped
    BingWebmasterGateway bingWebmasterGateway(ObjectMapper mapper) {
        return new BingWebmasterHttpGateway(mapper);
    }
}
