package io.seeray.lens.application;

import io.seeray.lens.domain.auth.AppUser;
import io.seeray.lens.domain.auth.UserStatus;
import io.seeray.lens.domain.common.ControlPlaneException;
import io.seeray.lens.domain.workspace.*;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.persistence.EntityManager;
import jakarta.persistence.LockModeType;
import jakarta.transaction.Transactional;
import java.time.Instant;
import java.util.*;

/** Owner-managed workspace membership and role assignment. */
@ApplicationScoped
public class WorkspaceMemberService {
    private final WorkspaceAccess access;
    private final EntityManager entityManager;
    private final WorkspaceAuditRecorder audit;

    @Inject
    public WorkspaceMemberService(WorkspaceAccess access, EntityManager entityManager, WorkspaceAuditRecorder audit) {
        this.access = access;
        this.entityManager = entityManager;
        this.audit = audit;
    }

    public List<MemberDto> list(UUID workspaceId) {
        access.require(workspaceId, WorkspaceRole.OWNER, WorkspaceRole.ADMIN);
        return OrganizationMember.<OrganizationMember>list("id.organizationId", workspaceId).stream()
                .sorted(Comparator.comparing(member -> member.user.email.toLowerCase(Locale.ROOT)))
                .map(member -> dto(member, access.userId()))
                .toList();
    }

    @Transactional
    public MemberDto add(UUID workspaceId, String email, String roleValue) {
        lockWorkspaceAndRequireOwner(workspaceId);
        String normalizedEmail = email == null ? "" : email.strip().toLowerCase(Locale.ROOT);
        if (normalizedEmail.isBlank()) throw invalid("An account email is required");
        WorkspaceRole role = assignableRole(roleValue);
        AppUser user = AppUser.<AppUser>find("lower(email)", normalizedEmail).firstResult();
        if (user == null)
            throw new ControlPlaneException(404, "ACCOUNT_NOT_FOUND", "This email does not have an account yet");
        if (user.status != UserStatus.ACTIVE)
            throw new ControlPlaneException(409, "ACCOUNT_INACTIVE", "Disabled accounts cannot join a workspace");
        OrganizationMemberId id = new OrganizationMemberId(workspaceId, user.id);
        if (OrganizationMember.findById(id) != null)
            throw new ControlPlaneException(409, "MEMBER_EXISTS", "This account is already a workspace member");

        Organization organization = Organization.findById(workspaceId);
        OrganizationMember member = new OrganizationMember();
        member.id = id;
        member.organization = organization;
        member.user = user;
        member.role = role;
        member.createdAt = Instant.now();
        member.persist();
        audit.record(workspaceId, access.userId(), "ADD_MEMBER", "member", user.id);
        return dto(member, access.userId());
    }

    @Transactional
    public MemberDto changeRole(UUID workspaceId, UUID userId, String roleValue) {
        lockWorkspaceAndRequireOwner(workspaceId);
        OrganizationMember target = member(workspaceId, userId);
        if (target.role == WorkspaceRole.OWNER)
            throw new ControlPlaneException(
                    409, "OWNER_TRANSFER_REQUIRED", "Transfer ownership before changing the owner role");
        target.role = assignableRole(roleValue);
        audit.record(workspaceId, access.userId(), "CHANGE_ROLE", "member", target.user.id);
        return dto(target, access.userId());
    }

    @Transactional
    public void remove(UUID workspaceId, UUID userId) {
        lockWorkspaceAndRequireOwner(workspaceId);
        OrganizationMember target = member(workspaceId, userId);
        if (target.role == WorkspaceRole.OWNER)
            throw new ControlPlaneException(
                    409, "OWNER_TRANSFER_REQUIRED", "Transfer ownership before removing the owner");
        UUID targetId = target.user.id;
        target.delete();
        audit.record(workspaceId, access.userId(), "REMOVE_MEMBER", "member", targetId);
    }

    @Transactional
    public MemberDto transferOwnership(UUID workspaceId, UUID userId) {
        lockWorkspaceAndRequireOwner(workspaceId);
        OrganizationMember owner = access.require(workspaceId, WorkspaceRole.OWNER);
        OrganizationMember target = member(workspaceId, userId);
        if (owner.id.userId.equals(target.id.userId)) throw invalid("Choose another member to receive ownership");
        if (target.role == WorkspaceRole.OWNER)
            throw new ControlPlaneException(409, "ALREADY_OWNER", "This member already owns the workspace");
        target.role = WorkspaceRole.OWNER;
        owner.role = WorkspaceRole.ADMIN;
        audit.record(workspaceId, access.userId(), "TRANSFER_OWNERSHIP", "member", target.user.id);
        return dto(target, access.userId());
    }

    private void lockWorkspaceAndRequireOwner(UUID workspaceId) {
        Organization organization = Organization.findById(workspaceId);
        if (organization == null) throw new ControlPlaneException(404, "WORKSPACE_NOT_FOUND", "Workspace not found");
        entityManager.lock(organization, LockModeType.PESSIMISTIC_WRITE);
        // Re-check after acquiring the organization lock so concurrent ownership transfers cannot
        // let the former owner perform a stale privileged operation.
        access.require(workspaceId, WorkspaceRole.OWNER);
    }

    private static OrganizationMember member(UUID workspaceId, UUID userId) {
        OrganizationMember member = OrganizationMember.findById(new OrganizationMemberId(workspaceId, userId));
        if (member == null) throw new ControlPlaneException(404, "MEMBER_NOT_FOUND", "Workspace member not found");
        return member;
    }

    private static WorkspaceRole assignableRole(String value) {
        try {
            WorkspaceRole role =
                    WorkspaceRole.valueOf(value == null ? "" : value.strip().toUpperCase(Locale.ROOT));
            if (role == WorkspaceRole.ADMIN || role == WorkspaceRole.VIEWER) return role;
        } catch (IllegalArgumentException ignored) {
            // Return one stable validation message for unknown and non-assignable roles.
        }
        throw invalid("Role must be admin or viewer");
    }

    private static ControlPlaneException invalid(String message) {
        return new ControlPlaneException(400, "INVALID_MEMBER", message);
    }

    private static MemberDto dto(OrganizationMember member, UUID currentUserId) {
        return new MemberDto(
                member.user.id,
                member.user.email,
                member.user.displayName,
                member.role.name().toLowerCase(Locale.ROOT),
                member.createdAt,
                member.id.userId.equals(currentUserId));
    }

    public record MemberDto(
            UUID userId, String email, String displayName, String role, Instant createdAt, boolean currentUser) {}
}
