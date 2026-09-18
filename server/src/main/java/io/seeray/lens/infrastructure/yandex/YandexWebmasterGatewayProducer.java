package io.seeray.lens.infrastructure.yandex;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.seeray.lens.application.YandexWebmasterGateway;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;

@ApplicationScoped
public class YandexWebmasterGatewayProducer {
    @Produces
    @ApplicationScoped
    YandexWebmasterGateway yandexWebmasterGateway(ObjectMapper mapper) {
        return new YandexWebmasterHttpGateway(mapper);
    }
}
