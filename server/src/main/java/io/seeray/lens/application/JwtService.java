package io.seeray.lens.application;

import io.seeray.lens.domain.common.ControlPlaneException;
import jakarta.enterprise.context.ApplicationScoped;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Instant;
import java.util.*;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
public class JwtService {
    @ConfigProperty(name = "seeray.auth.jwt-secret")
    String secret;

    @ConfigProperty(name = "seeray.auth.access-token-seconds")
    long lifetime;

    @ConfigProperty(name = "seeray.auth.jwt-issuer")
    String issuer;

    public String issue(UUID id, String email) {
        long iat = Instant.now().getEpochSecond();
        long exp = iat + lifetime;
        String head = b64("{\"alg\":\"HS256\",\"typ\":\"JWT\"}");
        String payload =
                b64("{\"sub\":\"" + id + "\",\"iss\":\"" + issuer + "\",\"iat\":" + iat + ",\"exp\":" + exp + "}");
        return head + "." + payload + "." + sign(head + "." + payload);
    }

    public UUID verify(String token) {
        try {
            String[] p = token.split("\\.");
            if (p.length != 3
                    || !MessageDigest.isEqual(
                            sign(p[0] + "." + p[1]).getBytes(StandardCharsets.US_ASCII),
                            p[2].getBytes(StandardCharsets.US_ASCII))) throw bad();
            String json = new String(Base64.getUrlDecoder().decode(p[1]), StandardCharsets.UTF_8);
            long exp = Long.parseLong(json.replaceAll(".*\\\"exp\\\":(\\d+).*", "$1"));
            String sub = json.replaceAll(".*\\\"sub\\\":\\\"([^\\\"]+)\\\".*", "$1");
            String tokenIssuer = json.replaceAll(".*\\\"iss\\\":\\\"([^\\\"]+)\\\".*", "$1");
            if (exp < Instant.now().getEpochSecond() || !issuer.equals(tokenIssuer)) throw bad();
            return UUID.fromString(sub);
        } catch (Exception e) {
            throw bad();
        }
    }

    private String sign(String text) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            return Base64.getUrlEncoder()
                    .withoutPadding()
                    .encodeToString(mac.doFinal(text.getBytes(StandardCharsets.UTF_8)));
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    private static String b64(String s) {
        return Base64.getUrlEncoder().withoutPadding().encodeToString(s.getBytes(StandardCharsets.UTF_8));
    }

    private static ControlPlaneException bad() {
        return new ControlPlaneException(401, "INVALID_ACCESS_TOKEN", "Access token is invalid or expired");
    }
}
