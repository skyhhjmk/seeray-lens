package io.seeray.lens.domain.common;

import java.security.SecureRandom;
import java.util.UUID;

public final class UuidV7 {
    private static final SecureRandom RANDOM = new SecureRandom();

    private UuidV7() {}

    public static UUID next() {
        long timestamp = System.currentTimeMillis();
        long most = (timestamp << 16) | 0x7000L | RANDOM.nextInt(0x1000);
        long least = RANDOM.nextLong() & 0x3fff_ffff_ffff_ffffL;
        return new UUID(most, least | 0x8000_0000_0000_0000L);
    }
}
