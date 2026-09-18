package io.seeray.lens.application;

import io.seeray.lens.domain.common.ControlPlaneException;
import jakarta.enterprise.context.ApplicationScoped;
import java.nio.ByteBuffer;
import java.security.SecureRandom;
import java.util.Base64;
import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import org.eclipse.microprofile.config.inject.ConfigProperty;

/** Encrypts integration credentials at rest using an operator-managed AES-256 key. */
@ApplicationScoped
public class SecretEncryptionService {
    private static final int NONCE_BYTES = 12;
    private static final int TAG_BITS = 128;
    private static final SecureRandom RANDOM = new SecureRandom();

    @ConfigProperty(name = "seeray.security.encryption-key", defaultValue = "")
    String configuredKey;

    public byte[] encrypt(String secret) {
        if (secret == null || secret.isBlank()) {
            throw new IllegalArgumentException("A non-empty secret is required");
        }
        byte[] nonce = new byte[NONCE_BYTES];
        RANDOM.nextBytes(nonce);
        try {
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, key(), new GCMParameterSpec(TAG_BITS, nonce));
            byte[] ciphertext = cipher.doFinal(secret.getBytes(java.nio.charset.StandardCharsets.UTF_8));
            return ByteBuffer.allocate(nonce.length + ciphertext.length)
                    .put(nonce)
                    .put(ciphertext)
                    .array();
        } catch (ControlPlaneException error) {
            throw error;
        } catch (Exception error) {
            throw new ControlPlaneException(
                    500, "SECRET_ENCRYPTION_FAILED", "Could not protect integration credentials.");
        }
    }

    public String decrypt(byte[] encrypted) {
        if (encrypted == null || encrypted.length <= NONCE_BYTES) {
            throw new ControlPlaneException(
                    500, "SECRET_DECRYPTION_FAILED", "Stored integration credentials are invalid.");
        }
        try {
            ByteBuffer value = ByteBuffer.wrap(encrypted);
            byte[] nonce = new byte[NONCE_BYTES];
            value.get(nonce);
            byte[] ciphertext = new byte[value.remaining()];
            value.get(ciphertext);
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, key(), new GCMParameterSpec(TAG_BITS, nonce));
            return new String(cipher.doFinal(ciphertext), java.nio.charset.StandardCharsets.UTF_8);
        } catch (ControlPlaneException error) {
            throw error;
        } catch (Exception error) {
            throw new ControlPlaneException(
                    500, "SECRET_DECRYPTION_FAILED", "Could not read stored integration credentials.");
        }
    }

    private SecretKeySpec key() {
        try {
            byte[] bytes = Base64.getDecoder().decode(configuredKey == null ? "" : configuredKey.strip());
            if (bytes.length != 32) throw new IllegalArgumentException();
            return new SecretKeySpec(bytes, "AES");
        } catch (IllegalArgumentException error) {
            throw new ControlPlaneException(
                    503,
                    "SECRET_ENCRYPTION_NOT_CONFIGURED",
                    "Configure SEERAY_SECRET_ENCRYPTION_KEY as a stable base64-encoded 32-byte key before saving external credentials.");
        }
    }
}
