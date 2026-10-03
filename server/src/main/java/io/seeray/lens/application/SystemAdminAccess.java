package io.seeray.lens.application;

import io.quarkus.security.identity.SecurityIdentity;
import io.seeray.lens.domain.auth.AppUser;
import io.seeray.lens.domain.auth.UserStatus;
import io.seeray.lens.domain.common.ControlPlaneException;
import jakarta.enterprise.context.ApplicationScoped;
import java.util.UUID;

@ApplicationScoped
public class SystemAdminAccess {
    private final SecurityIdentity identity;

    public SystemAdminAccess(SecurityIdentity identity) {
        this.identity = identity;
    }

    public UUID require() {
        if (identity.isAnonymous() || identity.getAttribute(ApiTokenAuthenticator.ATTRIBUTE_TYPE) != null)
            throw forbidden();
        UUID userId;
        try {
            userId = UUID.fromString(identity.getPrincipal().getName());
        } catch (RuntimeException failure) {
            throw forbidden();
        }
        AppUser user = AppUser.findById(userId);
        if (user == null || user.status != UserStatus.ACTIVE || !user.systemAdmin) throw forbidden();
        return userId;
    }

    public boolean isSystemAdmin() {
        if (identity.isAnonymous() || identity.getAttribute(ApiTokenAuthenticator.ATTRIBUTE_TYPE) != null)
            return false;
        try {
            AppUser user = AppUser.findById(UUID.fromString(identity.getPrincipal().getName()));
            return user != null && user.status == UserStatus.ACTIVE && user.systemAdmin;
        } catch (RuntimeException ignored) {
            return false;
        }
    }

    private static ControlPlaneException forbidden() {
        return new ControlPlaneException(403, "SYSTEM_ADMIN_REQUIRED", "System administrator permission required");
    }
}
