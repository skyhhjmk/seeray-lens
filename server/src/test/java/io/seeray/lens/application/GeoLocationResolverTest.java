package io.seeray.lens.application;

import static org.junit.jupiter.api.Assertions.*;

import io.vertx.core.MultiMap;
import org.junit.jupiter.api.Test;

class GeoLocationResolverTest {
    @Test
    void resolvesOnlyTrustedProxyHeadersAndNormalizesValues() {
        GeoLocationResolver resolver = new GeoLocationResolver(true, "192.0.2.0/24");
        MultiMap headers = MultiMap.caseInsensitiveMultiMap()
                .add("CF-IPCountry", "us")
                .add("cf-ipcontinent", "na")
                .add("cf-region-code", "ca")
                .add("cf-region", "California")
                .add("cf-ipcity", "San Francisco")
                .add("cf-timezone", "America/Los_Angeles");

        GeoLocationResolver.Location location = resolver.resolve("192.0.2.18", headers);
        assertEquals("US", location.countryCode());
        assertEquals("NA", location.continentCode());
        assertEquals("CA", location.regionCode());
        assertEquals("California", location.region());
        assertEquals("San Francisco", location.city());
        assertEquals("America/Los_Angeles", location.timezone());
    }

    @Test
    void ignoresSpoofedHeadersFromUntrustedPeersAndUnknownCountryCodes() {
        GeoLocationResolver resolver = new GeoLocationResolver(true, "192.0.2.0/24");
        MultiMap headers = MultiMap.caseInsensitiveMultiMap().add("cf-ipcountry", "US");

        assertTrue(resolver.resolve("198.51.100.7", headers).isEmpty());
        assertTrue(
                resolver.resolve("192.0.2.7", MultiMap.caseInsensitiveMultiMap().add("cf-ipcountry", "T1"))
                        .isEmpty());
    }

    @Test
    void trustedProxyConfigurationMustUseNumericAddresses() {
        assertThrows(IllegalArgumentException.class, () -> new GeoLocationResolver(true, "proxy.example"));
    }
}
