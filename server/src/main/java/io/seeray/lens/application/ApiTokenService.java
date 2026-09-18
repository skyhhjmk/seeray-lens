package io.seeray.lens.application;

import io.seeray.lens.domain.common.ControlPlaneException;
import io.seeray.lens.domain.common.UuidV7;
import io.seeray.lens.domain.token.ApiToken;
import io.seeray.lens.domain.workspace.WorkspaceRole;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.transaction.Transactional;
import java.security.SecureRandom;
import java.time.Instant;
import java.util.*;

@ApplicationScoped
public class ApiTokenService {
    private static final Set<String> VALID_SCOPES = Set.of("sites:read", "sites:write");
    private final WorkspaceAccess access;
    private final WorkspaceAuditRecorder audit;

    public ApiTokenService(WorkspaceAccess access, WorkspaceAuditRecorder audit) {
        this.access = access;
        this.audit = audit;
    }

    @Transactional
    public Created create(UUID workspaceId, String name, List<String> scopes, Instant expiresAt) {
        var member = access.require(workspaceId, WorkspaceRole.OWNER);
        if (scopes == null || scopes.isEmpty() || !VALID_SCOPES.containsAll(scopes))
            throw new ControlPlaneException(400, "INVALID_SCOPE", "Scopes must be sites:read or sites:write");
        if (expiresAt != null && !expiresAt.isAfter(Instant.now()))
            throw new ControlPlaneException(400, "INVALID_EXPIRY", "Expiry must be in the future");
        String plain = random();
        ApiToken token = new ApiToken();
        token.id = UuidV7.next();
        token.organization = member.organization;
        token.name = name.trim();
        token.tokenPrefix = plain.substring(0, 12);
        token.tokenHash = AuthService.hash(plain);
        token.scopes = "[\"" + String.join("\",\"", scopes) + "\"]";
        token.createdAt = Instant.now();
        token.expiresAt = expiresAt;
        token.persist();
        audit.record(workspaceId, access.userId(), "CREATE_API_TOKEN", "api-token", token.id);
        return new Created(token, plain);
    }

    public List<ApiToken> list(UUID workspaceId) {
        access.member(workspaceId);
        return ApiToken.list("organization.id", workspaceId);
    }

    @Transactional
    public void revoke(UUID workspaceId, UUID id) {
        access.require(workspaceId, WorkspaceRole.OWNER);
        ApiToken t =
                ApiToken.find("id=?1 and organization.id=?2", id, workspaceId).firstResult();
        if (t == null) throw new ControlPlaneException(404, "API_TOKEN_NOT_FOUND", "API token not found");
        if (t.revokedAt == null) {
            t.revokedAt = Instant.now();
            audit.record(workspaceId, access.userId(), "REVOKE_API_TOKEN", "api-token", t.id);
        }
    }

    private static String random() {
        byte[] b = new byte[32];
        new SecureRandom().nextBytes(b);
        return "srlat_" + Base64.getUrlEncoder().withoutPadding().encodeToString(b);
    }

    public record Created(ApiToken token, String plainToken) {}
}
