package io.seeray.lens.infrastructure.yandex;

import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.LocalDate;
import org.junit.jupiter.api.Test;

class YandexWebmasterHttpGatewayTest {
    @Test
    void requestsTheIndicatorsUsedByTheSearchReport() {
        String url = YandexWebmasterHttpGateway.popularQueriesUrl(
                "42",
                "https:example.com:443",
                LocalDate.parse("2026-09-01"),
                LocalDate.parse("2026-09-07"),
                "MOBILE_AND_TABLET",
                500,
                500);

        assertTrue(url.contains("order_by=TOTAL_SHOWS"));
        assertTrue(url.contains(
                "query_indicator=TOTAL_SHOWS&query_indicator=TOTAL_CLICKS" + "&query_indicator=AVG_SHOW_POSITION"));
        assertTrue(url.contains("device_type_indicator=MOBILE_AND_TABLET"));
        assertTrue(url.contains("offset=500&limit=500"));
    }
}
