package io.seeray.lens.application;

import io.vertx.core.MultiMap;
import io.vertx.core.http.HttpServerRequest;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import java.net.InetAddress;
import java.time.ZoneId;
import java.util.*;
import org.eclipse.microprofile.config.inject.ConfigProperty;

/** Resolves coarse location only from headers on requests sent by explicitly trusted proxies. */
@ApplicationScoped
public class GeoLocationResolver {
    private static final Set<String> CONTINENTS = Set.of("AF", "AN", "AS", "EU", "NA", "OC", "SA");
    private final boolean enabled;
    private final List<Network> trustedProxies;

    @Inject
    public GeoLocationResolver(
            @ConfigProperty(name = "seeray.geo.location.enabled", defaultValue = "false") boolean enabled,
            @ConfigProperty(name = "seeray.geo.trusted-proxy-cidrs", defaultValue = "") String trustedProxyCidrs) {
        this.enabled = enabled;
        this.trustedProxies = parseNetworks(trustedProxyCidrs);
    }

    public boolean configured() {
        return enabled && !trustedProxies.isEmpty();
    }

    public Location resolve(HttpServerRequest request) {
        return resolve(request.remoteAddress().host(), request.headers());
    }

    Location resolve(String peerAddress, MultiMap headers) {
        if (!configured() || peerAddress == null || peerAddress.isBlank()) return Location.empty();
        InetAddress peer = address(peerAddress);
        if (peer == null || trustedProxies.stream().noneMatch(network -> network.contains(peer)))
            return Location.empty();

        String country = code(headers.get("cf-ipcountry"), Locale.getISOCountries());
        if (country == null) return Location.empty();
        String continent = code(headers.get("cf-ipcontinent"), CONTINENTS.toArray(String[]::new));
        String regionCode = token(headers.get("cf-region-code"), 16);
        String region = text(headers.get("cf-region"), 120);
        String city = text(headers.get("cf-ipcity"), 120);
        String timezone = timezone(headers.get("cf-timezone"));
        return new Location(country, continent, regionCode, region, city, timezone);
    }

    private static List<Network> parseNetworks(String specification) {
        if (specification == null || specification.isBlank()) return List.of();
        List<Network> result = new ArrayList<>();
        for (String configured : specification.split(",")) {
            String value = configured.trim();
            if (value.isEmpty()) continue;
            String[] parts = value.split("/", -1);
            InetAddress address = address(parts[0]);
            if (address == null) throw new IllegalArgumentException("Invalid trusted proxy address: " + parts[0]);
            int maximum = address.getAddress().length * 8;
            int prefix;
            try {
                prefix = parts.length == 1 ? maximum : Integer.parseInt(parts[1]);
            } catch (NumberFormatException invalidPrefix) {
                throw new IllegalArgumentException("Invalid trusted proxy CIDR: " + value, invalidPrefix);
            }
            if (parts.length > 2 || prefix < 0 || prefix > maximum)
                throw new IllegalArgumentException("Invalid trusted proxy CIDR: " + value);
            result.add(new Network(address.getAddress(), prefix));
        }
        return List.copyOf(result);
    }

    private static InetAddress address(String value) {
        if (value == null || value.isBlank()) return null;
        // Socket peers and CIDRs must be numeric; never trigger DNS while parsing request/config data.
        if (value.indexOf(':') < 0 && !value.matches("[0-9.]+")) return null;
        if (value.indexOf(':') >= 0 && !value.matches("[0-9A-Fa-f:.%A-Za-z0-9_-]+")) return null;
        try {
            return InetAddress.getByName(value);
        } catch (Exception invalidAddress) {
            return null;
        }
    }

    private static String code(String value, String[] validCodes) {
        if (value == null) return null;
        String normalized = value.trim().toUpperCase(Locale.ROOT);
        if (Arrays.asList(validCodes).contains(normalized)) return normalized;
        return null;
    }

    private static String token(String value, int maxLength) {
        if (value == null) return null;
        String normalized = value.strip();
        return normalized.matches("[A-Za-z0-9-]{1," + maxLength + "}") ? normalized.toUpperCase(Locale.ROOT) : null;
    }

    private static String text(String value, int maxLength) {
        if (value == null || value.isBlank()) return null;
        String cleaned = value.strip().replaceAll("[\\p{Cc}]", "");
        return !cleaned.isBlank() && cleaned.length() <= maxLength ? cleaned : null;
    }

    private static String timezone(String value) {
        String cleaned = text(value, 64);
        if (cleaned == null) return null;
        try {
            return ZoneId.of(cleaned).getId();
        } catch (Exception invalidTimezone) {
            return null;
        }
    }

    public record Location(
            String countryCode, String continentCode, String regionCode, String region, String city, String timezone) {
        static Location empty() {
            return new Location(null, null, null, null, null, null);
        }

        public boolean isEmpty() {
            return countryCode == null;
        }
    }

    private record Network(byte[] bytes, int prefix) {
        boolean contains(InetAddress candidate) {
            byte[] address = candidate.getAddress();
            if (address.length != bytes.length) return false;
            int fullBytes = prefix / 8;
            int remainingBits = prefix % 8;
            for (int i = 0; i < fullBytes; i++) if (bytes[i] != address[i]) return false;
            if (remainingBits == 0) return true;
            int mask = 0xff << (8 - remainingBits);
            return (bytes[fullBytes] & mask) == (address[fullBytes] & mask);
        }
    }
}
