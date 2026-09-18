package io.seeray.lens.infrastructure.google;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.seeray.lens.application.SearchConsoleGateway;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;

@ApplicationScoped
public class GoogleSearchConsoleGatewayProducer {
    @Produces
    @ApplicationScoped
    SearchConsoleGateway searchConsoleGateway(ObjectMapper mapper) {
        return new GoogleSearchConsoleHttpGateway(mapper);
    }
}
