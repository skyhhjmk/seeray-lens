package io.seeray.lens.application;

import io.quarkus.elytron.security.common.BcryptUtil;
import io.seeray.lens.api.SiteResource;
import io.seeray.lens.domain.auth.*;
import io.seeray.lens.domain.common.ControlPlaneException;
import io.seeray.lens.domain.site.Site;
import io.seeray.lens.domain.workspace.Organization;
import io.seeray.lens.domain.workspace.OrganizationMember;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.persistence.EntityManager;
import jakarta.transaction.Transactional;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.security.SecureRandom;
import java.time.Instant;
import java.util.*;

@ApplicationScoped
public class SystemAdminService {
    private static final String TEMP_PASSWORD_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%";
    private final SystemAdminAccess access;
    private final SystemAdminAuditRecorder audit;
    private final SiteService sites;
    private final EntityManager entityManager;

    public SystemAdminService(
            SystemAdminAccess access, SystemAdminAuditRecorder audit, SiteService sites, EntityManager entityManager) {
        this.access = access;
        this.audit = audit;
        this.sites = sites;
        this.entityManager = entityManager;
    }

    public Page<UserDto> users(int page, int size) {
        access.require();
        List<AppUser> rows = AppUser.<AppUser>find("order by createdAt desc, id desc").page(page, size).list();
        return new Page<>(rows.stream().map(this::userDto).toList(), page, size, AppUser.count());
    }

    @Transactional
    public UserDto updateUser(UUID targetId, UpdateUser request) {
        if (request == null) throw invalid("User changes are required");
        UUID actorId = access.require();
        lockAdministration();
        actorId = access.require();
        AppUser target = user(targetId);
        boolean changed = false;
        boolean securityChanged = false;
        boolean profileChanged = false;
        boolean statusChanged = false;
        boolean administratorChanged = false;
        if (request.email() != null) {
            String email = request.email().strip().toLowerCase(Locale.ROOT);
            if (email.isBlank() || email.length() > 320 || !email.matches("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$"))
                throw invalid("A valid email address is required");
            AppUser duplicate = AppUser.find("email", email).firstResult();
            if (duplicate != null && !duplicate.id.equals(target.id))
                throw new ControlPlaneException(409, "EMAIL_EXISTS", "Email already registered");
            if (!target.email.equals(email)) {
                target.email = email;
                changed = true;
                profileChanged = true;
            }
        }
        if (request.displayName() != null) {
            String name = request.displayName().strip();
            if (name.isBlank() || name.length() > 120) throw invalid("Display name must contain 1 to 120 characters");
            if (!target.displayName.equals(name)) {
                target.displayName = name;
                changed = true;
                profileChanged = true;
            }
        }
        if (request.status() != null) {
            UserStatus status;
            try {
                status = UserStatus.valueOf(request.status().strip().toUpperCase(Locale.ROOT));
            } catch (RuntimeException failure) {
                throw invalid("Status must be active or disabled");
            }
            if (target.status != status) {
                target.status = status;
                securityChanged = true;
                changed = true;
                statusChanged = true;
            }
        }
        if (request.systemAdmin() != null && target.systemAdmin != request.systemAdmin()) {
            target.systemAdmin = request.systemAdmin();
            securityChanged = true;
            changed = true;
            administratorChanged = true;
        }
        if (securityChanged) invalidateSessions(target);
        if (changed) {
            target.updatedAt = Instant.now();
            if (profileChanged) audit.record(actorId, target.id, null, "UPDATE_USER_PROFILE");
            if (statusChanged) audit.record(actorId, target.id, null, "CHANGE_USER_STATUS");
            if (administratorChanged) audit.record(actorId, target.id, null, "CHANGE_SYSTEM_ADMIN");
        }
        ensureActiveAdministratorExists();
        return userDto(target);
    }

    @Transactional
    public ResetPasswordResult resetPassword(UUID targetId) {
        UUID actorId = access.require();
        lockAdministration();
        actorId = access.require();
        AppUser target = user(targetId);
        String temporaryPassword = temporaryPassword();
        target.passwordHash = BcryptUtil.bcryptHash(temporaryPassword);
        target.mustChangePassword = true;
        target.updatedAt = Instant.now();
        invalidateSessions(target);
        audit.record(actorId, target.id, null, "RESET_USER_PASSWORD");
        return new ResetPasswordResult(temporaryPassword);
    }

    public Page<SiteResource.SiteDto> sites(int page, int size) {
        access.require();
        List<Site> rows = Site.<Site>find("order by createdAt desc, id desc").page(page, size).list();
        return new Page<>(rows.stream().map(SiteResource::dto).toList(), page, size, Site.count());
    }

    @Transactional
    public SiteResource.SiteDto createSite(CreateSite request) {
        if (request == null) throw new ControlPlaneException(400, "INVALID_SITE", "Site details are required");
        UUID actorId = access.require();
        Site site = sites.createForSystemAdmin(request.workspaceId(), request.name(), request.timezone(),
                request.defaultLanguage(), request.rawRetentionDays(), request.aggregateRetentionDays(),
                request.requireConsent(), request.fingerprintRiskEnabled(), request.fingerprintRetentionDays());
        audit.record(actorId, null, site.id, "CREATE_SITE");
        return SiteResource.dto(site);
    }

    @Transactional
    public SiteResource.SiteDto updateSite(UUID siteId, UpdateSite request) {
        if (request == null) throw new ControlPlaneException(400, "INVALID_SITE", "Site changes are required");
        UUID actorId = access.require();
        Site site = sites.updateForSystemAdmin(siteId, request.name(), request.timezone(), request.defaultLanguage(),
                request.trackingEnabled(), request.requireConsent(), request.rawRetentionDays(),
                request.aggregateRetentionDays(), request.fingerprintRiskEnabled(), request.fingerprintRetentionDays());
        audit.record(actorId, null, site.id, "UPDATE_SITE");
        return SiteResource.dto(site);
    }

    @Transactional
    public void deleteSite(UUID siteId, String trackingIdConfirmation) {
        UUID actorId = access.require();
        Site site = sites.site(siteId);
        if (trackingIdConfirmation == null || !site.trackingId.equals(trackingIdConfirmation.strip()))
            throw new ControlPlaneException(409, "SITE_DELETE_CONFIRMATION_REQUIRED", "Enter the site's tracking ID to confirm deletion");
        audit.record(actorId, null, site.id, "DELETE_SITE");
        sites.deleteForSystemAdmin(siteId);
    }

    public List<WorkspaceDto> workspaces() {
        access.require();
        return Organization.<Organization>list("order by name asc, id asc").stream()
                .map(org -> new WorkspaceDto(org.id, org.name)).toList();
    }

    private UserDto userDto(AppUser user) {
        return new UserDto(user.id, user.email, user.displayName, user.status.name().toLowerCase(Locale.ROOT),
                user.systemAdmin, user.mustChangePassword, user.createdAt,
                OrganizationMember.count("id.userId", user.id));
    }

    private static AppUser user(UUID id) {
        AppUser user = AppUser.findById(id);
        if (user == null) throw new ControlPlaneException(404, "USER_NOT_FOUND", "User not found");
        return user;
    }

    private void invalidateSessions(AppUser user) {
        Instant now = Instant.now();
        user.authVersion++;
        AuthSession.update("revokedAt = ?1 where user.id = ?2 and revokedAt is null", now, user.id);
    }

    private void lockAdministration() {
        entityManager.createNativeQuery("LOCK TABLE app_user IN SHARE ROW EXCLUSIVE MODE").executeUpdate();
    }

    private void ensureActiveAdministratorExists() {
        if (AppUser.count("systemAdmin = true and status = ?1", UserStatus.ACTIVE) == 0)
            throw new ControlPlaneException(409, "LAST_SYSTEM_ADMIN_REQUIRED", "At least one active system administrator must remain");
    }

    private static String temporaryPassword() {
        SecureRandom random = new SecureRandom();
        StringBuilder value = new StringBuilder(24);
        for (int i = 0; i < 24; i++) value.append(TEMP_PASSWORD_ALPHABET.charAt(random.nextInt(TEMP_PASSWORD_ALPHABET.length())));
        return value.toString();
    }

    private static ControlPlaneException invalid(String message) {
        return new ControlPlaneException(400, "INVALID_USER", message);
    }

    public record UserDto(UUID id, String email, String displayName, String status, boolean systemAdmin,
            boolean mustChangePassword, Instant createdAt, long workspaceCount) {}
    public record UpdateUser(String email, String displayName, String status, Boolean systemAdmin) {}
    public record ResetPasswordResult(String temporaryPassword) {}
    public record CreateSite(@NotNull UUID workspaceId, @NotBlank @Size(max = 120) String name,
            @NotBlank String timezone, String defaultLanguage,
            Integer rawRetentionDays, Integer aggregateRetentionDays, Boolean requireConsent,
            Boolean fingerprintRiskEnabled, Integer fingerprintRetentionDays) {}
    public record UpdateSite(String name, String timezone, String defaultLanguage, Boolean trackingEnabled,
            Boolean requireConsent, Integer rawRetentionDays, Integer aggregateRetentionDays,
            Boolean fingerprintRiskEnabled, Integer fingerprintRetentionDays) {}
    public record WorkspaceDto(UUID id, String name) {}
    public record Page<T>(List<T> items, int page, int size, long total) {}
}
