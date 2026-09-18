package io.seeray.lens.application;

import io.quarkus.mailer.Mail;
import io.quarkus.mailer.Mailer;
import io.quarkus.panache.common.Page;
import io.seeray.lens.domain.auth.AppUser;
import io.seeray.lens.domain.auth.UserStatus;
import io.seeray.lens.domain.common.ControlPlaneException;
import io.seeray.lens.domain.common.UuidV7;
import io.seeray.lens.domain.workspace.Organization;
import io.seeray.lens.domain.workspace.OrganizationMember;
import io.seeray.lens.domain.workspace.OrganizationMemberId;
import io.seeray.lens.domain.workspace.WorkspaceInvitation;
import io.seeray.lens.domain.workspace.WorkspaceRole;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.persistence.EntityManager;
import jakarta.persistence.LockModeType;
import jakarta.transaction.Transactional;
import java.net.URI;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.HexFormat;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import org.eclipse.microprofile.config.inject.ConfigProperty;

/** Secure, expiring workspace invitations with one-time acceptance links delivered by email. */
@ApplicationScoped
public class WorkspaceInvitationService {
    private static final Duration INVITATION_LIFETIME = Duration.ofDays(7);
    private static final SecureRandom RANDOM = new SecureRandom();

    private final WorkspaceAccess access;
    private final EntityManager entityManager;
    private final WorkspaceAuditRecorder audit;

    @Inject
    Mailer mailer;

    @ConfigProperty(name = "seeray.app.admin-url", defaultValue = "http://localhost:3000")
    String adminUrl;

    @Inject
    public WorkspaceInvitationService(
            WorkspaceAccess access, EntityManager entityManager, WorkspaceAuditRecorder audit) {
        this.access = access;
        this.entityManager = entityManager;
        this.audit = audit;
    }

    public ListResponse list(UUID workspaceId) {
        var member = access.member(workspaceId);
        if (member.role != WorkspaceRole.OWNER && member.role != WorkspaceRole.ADMIN) {
            throw forbidden();
        }
        List<InvitationView> invitations = WorkspaceInvitation.<WorkspaceInvitation>find(
                        "organization.id=?1 order by createdAt desc", workspaceId)
                .page(Page.ofSize(100))
                .list()
                .stream()
                .map(WorkspaceInvitationService::view)
                .toList();
        return new ListResponse(
                member.role == WorkspaceRole.OWNER, INVITATION_LIFETIME.toDays(), List.copyOf(invitations));
    }

    @Transactional
    public InvitationView create(UUID workspaceId, String emailValue, String roleValue) {
        Organization organization = lockWorkspaceAndRequireOwner(workspaceId);
        String email = normalizeEmail(emailValue);
        WorkspaceRole role = assignableRole(roleValue);
        Instant now = Instant.now();

        AppUser existingUser = AppUser.find("email", email).firstResult();
        if (existingUser != null && existingUser.status != UserStatus.ACTIVE) {
            throw new ControlPlaneException(409, "INVITEE_INACTIVE", "Disabled accounts cannot be invited.");
        }
        if (existingUser != null
                && OrganizationMember.findById(new OrganizationMemberId(workspaceId, existingUser.id)) != null) {
            throw new ControlPlaneException(
                    409, "INVITEE_ALREADY_MEMBER", "This account already belongs to the workspace.");
        }

        WorkspaceInvitation prior = WorkspaceInvitation.find(
                        "organization.id=?1 and invitedEmail=?2 and acceptedAt is null and revokedAt is null",
                        workspaceId,
                        email)
                .firstResult();
        if (prior != null && prior.expiresAt.isAfter(now)) {
            throw new ControlPlaneException(
                    409, "INVITATION_EXISTS", "An active invitation already exists for this email.");
        }
        if (prior != null) prior.revokedAt = now;

        String token = randomToken();
        WorkspaceInvitation invitation = new WorkspaceInvitation();
        invitation.id = UuidV7.next();
        invitation.organization = organization;
        invitation.invitedEmail = email;
        invitation.role = role;
        invitation.tokenHash = hash(token);
        invitation.invitedBy = AppUser.findById(access.userId());
        invitation.createdAt = now;
        invitation.expiresAt = now.plus(INVITATION_LIFETIME);
        invitation.persist();

        String acceptUrl = invitationUrl(token);
        String inviter = invitation.invitedBy.displayName == null || invitation.invitedBy.displayName.isBlank()
                ? invitation.invitedBy.email
                : invitation.invitedBy.displayName;
        String body = "Hello,\n\n"
                + inviter + " invited you to join " + organization.name + " as a "
                + role.name().toLowerCase(Locale.ROOT) + ".\n\n"
                + "Accept this invitation within 7 days:\n" + acceptUrl + "\n\n"
                + "If you were not expecting this invitation, you can ignore this message.";
        try {
            mailer.send(Mail.withText(email, "Workspace invitation: " + organization.name, body));
        } catch (Exception error) {
            throw new ControlPlaneException(
                    503,
                    "INVITATION_EMAIL_FAILED",
                    "The invitation was not saved because email delivery failed. Check server SMTP settings and retry.");
        }
        audit.record(workspaceId, access.userId(), "CREATE_INVITATION", "invitation", invitation.id);
        return view(invitation);
    }

    @Transactional
    public void revoke(UUID workspaceId, UUID invitationId) {
        lockWorkspaceAndRequireOwner(workspaceId);
        WorkspaceInvitation invitation = WorkspaceInvitation.find(
                        "id=?1 and organization.id=?2", invitationId, workspaceId)
                .firstResult();
        if (invitation == null) throw new ControlPlaneException(404, "INVITATION_NOT_FOUND", "Invitation not found.");
        if (invitation.acceptedAt != null) {
            throw new ControlPlaneException(
                    409, "INVITATION_ALREADY_ACCEPTED", "Accepted invitations cannot be revoked.");
        }
        if (invitation.revokedAt == null) {
            invitation.revokedAt = Instant.now();
            audit.record(workspaceId, access.userId(), "REVOKE_INVITATION", "invitation", invitation.id);
        }
    }

    public InvitationSummary preview(String rawToken) {
        WorkspaceInvitation invitation = findByToken(rawToken);
        ensurePending(invitation);
        return new InvitationSummary(
                invitation.invitedEmail,
                invitation.organization.name,
                invitation.role.name().toLowerCase(Locale.ROOT),
                invitation.expiresAt,
                AppUser.count("email", invitation.invitedEmail) > 0);
    }

    @Transactional
    public AcceptResult acceptForCurrentUser(String rawToken) {
        UUID userId = access.userId();
        WorkspaceInvitation invitation = findByToken(rawToken);
        Organization organization = lockWorkspace(invitation.organization.id);
        invitation = findByToken(rawToken);
        ensurePending(invitation);
        AppUser user = AppUser.findById(userId);
        if (user == null || user.status != UserStatus.ACTIVE) {
            throw new ControlPlaneException(
                    403, "INVITATION_ACCOUNT_INACTIVE", "This account cannot accept invitations.");
        }
        if (!user.email.equalsIgnoreCase(invitation.invitedEmail)) {
            throw new ControlPlaneException(
                    403, "INVITATION_EMAIL_MISMATCH", "Sign in with the email address this invitation was sent to.");
        }
        return accept(invitation, organization, user);
    }

    @Transactional
    public OrganizationMember acceptForNewAccount(String rawToken, String email, AppUser user) {
        WorkspaceInvitation invitation = findByToken(rawToken);
        Organization organization = lockWorkspace(invitation.organization.id);
        invitation = findByToken(rawToken);
        ensurePending(invitation);
        if (!normalizeEmail(email).equals(invitation.invitedEmail)) {
            throw new ControlPlaneException(
                    403, "INVITATION_EMAIL_MISMATCH", "Use the email address this invitation was sent to.");
        }
        accept(invitation, organization, user);
        return OrganizationMember.findById(new OrganizationMemberId(organization.id, user.id));
    }

    private AcceptResult accept(WorkspaceInvitation invitation, Organization organization, AppUser user) {
        OrganizationMemberId id = new OrganizationMemberId(organization.id, user.id);
        if (OrganizationMember.findById(id) != null) {
            throw new ControlPlaneException(
                    409, "INVITATION_ALREADY_MEMBER", "This account already belongs to the workspace.");
        }
        OrganizationMember member = new OrganizationMember();
        member.id = id;
        member.organization = organization;
        member.user = user;
        member.role = invitation.role;
        member.createdAt = Instant.now();
        member.persist();
        invitation.acceptedAt = Instant.now();
        audit.record(organization.id, user.id, "ACCEPT_INVITATION", "invitation", invitation.id);
        return new AcceptResult(
                organization.id, organization.name, member.role.name().toLowerCase(Locale.ROOT));
    }

    private Organization lockWorkspaceAndRequireOwner(UUID workspaceId) {
        Organization organization = lockWorkspace(workspaceId);
        access.require(workspaceId, WorkspaceRole.OWNER);
        return organization;
    }

    private Organization lockWorkspace(UUID workspaceId) {
        Organization organization = Organization.findById(workspaceId);
        if (organization == null) throw new ControlPlaneException(404, "WORKSPACE_NOT_FOUND", "Workspace not found.");
        entityManager.lock(organization, LockModeType.PESSIMISTIC_WRITE);
        return organization;
    }

    private static WorkspaceInvitation findByToken(String rawToken) {
        if (rawToken == null || rawToken.isBlank() || rawToken.length() > 128) {
            throw invalidToken();
        }
        WorkspaceInvitation invitation =
                WorkspaceInvitation.find("tokenHash", hash(rawToken)).firstResult();
        if (invitation == null) throw invalidToken();
        return invitation;
    }

    private static void ensurePending(WorkspaceInvitation invitation) {
        if (invitation.revokedAt != null || invitation.acceptedAt != null) {
            throw new ControlPlaneException(
                    410, "INVITATION_NO_LONGER_VALID", "This invitation has already been used or revoked.");
        }
        if (!invitation.expiresAt.isAfter(Instant.now())) {
            throw new ControlPlaneException(
                    410, "INVITATION_EXPIRED", "This invitation has expired. Ask the workspace owner to send another.");
        }
    }

    private static InvitationView view(WorkspaceInvitation invitation) {
        String status = invitation.acceptedAt != null
                ? "accepted"
                : invitation.revokedAt != null
                        ? "revoked"
                        : invitation.expiresAt.isAfter(Instant.now()) ? "pending" : "expired";
        return new InvitationView(
                invitation.id,
                invitation.invitedEmail,
                invitation.role.name().toLowerCase(Locale.ROOT),
                invitation.createdAt,
                invitation.expiresAt,
                invitation.acceptedAt,
                invitation.revokedAt,
                status,
                "pending".equals(status));
    }

    private String invitationUrl(String token) {
        URI base = URI.create(adminUrl.strip().endsWith("/") ? adminUrl.strip() : adminUrl.strip() + "/");
        return base.resolve("#/accept-invitation?token=" + URLEncoder.encode(token, StandardCharsets.UTF_8))
                .toString();
    }

    private static String normalizeEmail(String value) {
        String email = value == null ? "" : value.strip().toLowerCase(Locale.ROOT);
        if (email.length() > 320 || !email.matches("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$")) {
            throw new ControlPlaneException(400, "INVITATION_EMAIL_INVALID", "Enter a valid email address.");
        }
        return email;
    }

    private static WorkspaceRole assignableRole(String value) {
        try {
            WorkspaceRole role =
                    WorkspaceRole.valueOf(value == null ? "" : value.strip().toUpperCase(Locale.ROOT));
            if (role == WorkspaceRole.ADMIN || role == WorkspaceRole.VIEWER) return role;
        } catch (IllegalArgumentException ignored) {
            // Keep one stable validation message for unknown and non-assignable roles.
        }
        throw new ControlPlaneException(400, "INVITATION_ROLE_INVALID", "Invitation role must be admin or viewer.");
    }

    private static String randomToken() {
        byte[] bytes = new byte[32];
        RANDOM.nextBytes(bytes);
        return "srlw_" + Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }

    private static String hash(String value) {
        try {
            return HexFormat.of()
                    .formatHex(MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException error) {
            throw new IllegalStateException(error);
        }
    }

    private static ControlPlaneException invalidToken() {
        return new ControlPlaneException(404, "INVITATION_NOT_FOUND", "Invitation not found or no longer available.");
    }

    private static ControlPlaneException forbidden() {
        return new ControlPlaneException(403, "FORBIDDEN", "Insufficient workspace permission.");
    }

    public record InvitationView(
            UUID id,
            String email,
            String role,
            Instant createdAt,
            Instant expiresAt,
            Instant acceptedAt,
            Instant revokedAt,
            String status,
            boolean canRevoke) {}

    public record ListResponse(boolean canManage, long lifetimeDays, List<InvitationView> invitations) {}

    public record InvitationSummary(
            String email, String workspaceName, String role, Instant expiresAt, boolean accountExists) {}

    public record AcceptResult(UUID workspaceId, String workspaceName, String role) {}
}
