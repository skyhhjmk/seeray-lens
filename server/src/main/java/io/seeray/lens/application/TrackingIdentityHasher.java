package io.seeray.lens.application;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.UUID;

/** Converts an application-provided opaque user identifier into a site-scoped non-reversible key. */
public final class TrackingIdentityHasher {
    private TrackingIdentityHasher() {}

    public static String hash(UUID siteId, String userId) {
        if (siteId == null || userId == null || userId.isBlank()) return null;
        String normalizedUserId = userId.trim().replaceAll("\\s+", " ");
        if (normalizedUserId.isEmpty()) return null;
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            digest.update(siteId.toString().getBytes(StandardCharsets.UTF_8));
            digest.update((byte) 0);
            return HexFormat.of().formatHex(digest.digest(normalizedUserId.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException impossible) {
            throw new IllegalStateException("SHA-256 is not available", impossible);
        }
    }
}
