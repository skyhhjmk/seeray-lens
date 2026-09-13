package io.seeray.lens.ingestion;

import static org.junit.jupiter.api.Assertions.*;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.seeray.lens.application.TrackingSanitizer;
import io.seeray.lens.domain.common.ControlPlaneException;
import java.util.Map;
import org.junit.jupiter.api.Test;

class TrackingSanitizerTest {
    private final ObjectMapper mapper = new ObjectMapper();

    @Test
    void removesArbitraryQueryAndFragmentButKeepsUtm() {
        var url = TrackingSanitizer.url("https://WWW.Example.com/order?id=123&utm_source=google#result", mapper);
        assertEquals("www.example.com", url.host());
        assertEquals("/order", url.path());
        assertEquals("google", url.source());
    }

    @Test
    void rejectsDeepOrOversizedProperties() {
        Map<String, Object> value = Map.of("a", Map.of("b", Map.of("c", Map.of("d", Map.of("e", Map.of("f", 1))))));
        assertThrows(ControlPlaneException.class, () -> TrackingSanitizer.json(value, mapper));
    }
}
