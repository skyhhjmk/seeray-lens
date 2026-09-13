package io.seeray.lens.application;

import io.quarkus.elytron.security.common.BcryptUtil;
import io.seeray.lens.domain.auth.*;
import io.seeray.lens.domain.common.*;
import io.seeray.lens.domain.workspace.*;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.transaction.Transactional;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.time.*;
import java.util.*;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
public class AuthService {
    @ConfigProperty(name = "seeray.auth.refresh-token-days")
    long refreshDays;

    private final JwtService jwt;

    public AuthService(JwtService jwt) {
        this.jwt = jwt;
    }

    @Transactional
    public Tokens register(String email, String password, String displayName) {
        String normalized = email.trim().toLowerCase(Locale.ROOT);
        if (AppUser.count("email", normalized) > 0)
            throw new ControlPlaneException(409, "EMAIL_EXISTS", "Email already registered");
        Instant now = Instant.now();
        AppUser user = new AppUser();
        user.id = UuidV7.next();
        user.email = normalized;
        user.passwordHash = BcryptUtil.bcryptHash(password);
        String safeDisplayName = displayName == null ? "" : displayName.trim();
        user.displayName = safeDisplayName.isBlank() ? "User" : safeDisplayName;
        user.status = UserStatus.ACTIVE;
        user.createdAt = now;
        user.updatedAt = now;
        user.persist();
        Organization org = new Organization();
        org.id = UuidV7.next();
        org.name = safeDisplayName.isBlank() ? "My Workspace" : safeDisplayName + " Workspace";
        org.createdAt = now;
        org.updatedAt = now;
        org.persist();
        OrganizationMember member = new OrganizationMember();
        member.id = new OrganizationMemberId(org.id, user.id);
        member.organization = org;
        member.user = user;
        member.role = WorkspaceRole.OWNER;
        member.createdAt = now;
        member.persist();
        return issue(user, now);
    }

    @Transactional
    public Tokens login(String email, String password) {
        AppUser user =
                AppUser.find("email", email.trim().toLowerCase(Locale.ROOT)).firstResult();
        if (user == null || !BcryptUtil.matches(password, user.passwordHash))
            throw new ControlPlaneException(401, "INVALID_CREDENTIALS", "Invalid email or password");
        if (user.status == UserStatus.DISABLED)
            throw new ControlPlaneException(403, "USER_DISABLED", "User is disabled");
        return issue(user, Instant.now());
    }

    @Transactional
    public Tokens refresh(String refresh) {
        AuthSession old = AuthSession.find("refreshTokenHash", hash(refresh)).firstResult();
        Instant now = Instant.now();
        if (old == null || old.revokedAt != null || old.expiresAt.isBefore(now))
            throw new ControlPlaneException(401, "INVALID_REFRESH_TOKEN", "Refresh token is invalid");
        if (old.user.status == UserStatus.DISABLED)
            throw new ControlPlaneException(403, "USER_DISABLED", "User is disabled");
        old.revokedAt = now;
        old.lastUsedAt = now;
        return issue(old.user, now);
    }

    @Transactional
    public void logout(String refresh) {
        AuthSession s = AuthSession.find("refreshTokenHash", hash(refresh)).firstResult();
        if (s != null && s.revokedAt == null) s.revokedAt = Instant.now();
    }

    private Tokens issue(AppUser user, Instant now) {
        String refresh = randomToken();
        AuthSession s = new AuthSession();
        s.id = UuidV7.next();
        s.user = user;
        s.refreshTokenHash = hash(refresh);
        s.createdAt = now;
        s.expiresAt = now.plus(Duration.ofDays(refreshDays));
        s.persist();
        return new Tokens(jwt.issue(user.id, user.email), refresh);
    }

    static String hash(String value) {
        try {
            return HexFormat.of()
                    .formatHex(MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    private static String randomToken() {
        byte[] b = new byte[32];
        new SecureRandom().nextBytes(b);
        return "srlr_" + Base64.getUrlEncoder().withoutPadding().encodeToString(b);
    }

    public record Tokens(String accessToken, String refreshToken) {}
}
