package io.seeray.lens.infrastructure.linkedin;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.seeray.lens.application.LinkedInConversionsGateway;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;

@ApplicationScoped
public class LinkedInConversionsGatewayProducer {
    @Produces
    @ApplicationScoped
    LinkedInConversionsGateway linkedInConversionsGateway(ObjectMapper mapper) {
        return new LinkedInConversionsHttpGateway(mapper);
    }
}
