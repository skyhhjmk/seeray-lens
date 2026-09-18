package io.seeray.lens.ingestion;

import static org.junit.jupiter.api.Assertions.*;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.seeray.lens.application.TrackingIdentityHasher;
import io.seeray.lens.application.TrackingSanitizer;
import io.seeray.lens.domain.common.ControlPlaneException;
import java.util.Map;
import java.util.UUID;
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
    void detectsAndHashesGoogleClickIdsWithoutChangingStoredUrlDimensions() {
        UUID siteId = UUID.randomUUID();
        var url = TrackingSanitizer.url(
                "https://example.com/landing?gclid=click-secret-123&keep=private#top", mapper, null, siteId);

        assertEquals("/landing", url.path());
        assertEquals("google", url.source());
        assertEquals("paid_search", url.medium());
        assertEquals("google_ads", url.adClickPlatform());
        assertEquals(TrackingIdentityHasher.hash(siteId, "ad-click:click-secret-123"), url.adClickIdHash());
        assertFalse(url.adClickIdHash().contains("click-secret-123"));
    }

    @Test
    void explicitUtmDimensionsWinWhileClickIdIsRetainedOnlyAsSiteScopedHash() {
        UUID siteId = UUID.randomUUID();
        var url = TrackingSanitizer.url(
                "https://example.com/?utm_source=partner&utm_medium=email&fbclid=opaque-meta-id", mapper, null, siteId);

        assertEquals("partner", url.source());
        assertEquals("email", url.medium());
        assertEquals("meta_ads", url.adClickPlatform());
        assertEquals(TrackingIdentityHasher.hash(siteId, "ad-click:opaque-meta-id"), url.adClickIdHash());
    }

    @Test
    void recognizesOtherMajorPaidPlatforms() {
        assertEquals(
                "microsoft_ads",
                TrackingSanitizer.url("https://example.com/?msclkid=opaque", mapper)
                        .adClickPlatform());
        assertEquals(
                "tiktok_ads",
                TrackingSanitizer.url("https://example.com/?ttclid=opaque", mapper)
                        .adClickPlatform());
        assertEquals(
                null,
                TrackingSanitizer.url("https://example.com/?unknown_click=opaque", mapper)
                        .adClickPlatform());
    }

    @Test
    void rejectsDeepOrOversizedProperties() {
        Map<String, Object> value = Map.of("a", Map.of("b", Map.of("c", Map.of("d", Map.of("e", Map.of("f", 1))))));
        assertThrows(ControlPlaneException.class, () -> TrackingSanitizer.json(value, mapper));
    }
}
