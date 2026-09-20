package io.seeray.lens.application;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.UUID;

/** Creates a site-scoped, non-reversible key for a client fingerprint signal. */
public final class TrackingFingerprintHasher {
    private TrackingFingerprintHasher() {}

    public static String hash(UUID siteId, TrackingPayload.Fingerprint fingerprint) {
        if (siteId == null || fingerprint == null || fingerprint.signalHash() == null) return null;
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            digest.update(siteId.toString().getBytes(StandardCharsets.UTF_8));
            digest.update((byte) 0);
            digest.update(String.valueOf(fingerprint.algorithmVersion()).getBytes(StandardCharsets.UTF_8));
            digest.update((byte) 0);
            return HexFormat.of().formatHex(digest.digest(fingerprint.signalHash().toLowerCase().getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException impossible) {
            throw new IllegalStateException("SHA-256 is not available", impossible);
        }
    }
}
