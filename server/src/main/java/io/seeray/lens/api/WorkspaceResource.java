package io.seeray.lens.api;

import io.quarkus.security.Authenticated;
import io.seeray.lens.application.WorkspaceAccess;
import io.seeray.lens.application.WorkspaceAuditRecorder;
import io.seeray.lens.domain.common.*;
import io.seeray.lens.domain.workspace.*;
import jakarta.transaction.Transactional;
import jakarta.validation.constraints.*;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.*;
import java.net.URI;
import java.net.URISyntaxException;
import java.time.Instant;
import java.util.*;

@Authenticated
@Path("/api/v1/workspaces")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
public class WorkspaceResource {
    private final WorkspaceAccess access;
    private final WorkspaceAuditRecorder audit;

    public WorkspaceResource(WorkspaceAccess a, WorkspaceAuditRecorder audit) {
        access = a;
        this.audit = audit;
    }

    @GET
    public List<WorkspaceDto> list() {
        if (access.isApiToken()) {
            OrganizationMember member = access.member(access.apiTokenWorkspaceId());
            return List.of(dto(member.organization, member.role));
        }
        return OrganizationMember.<OrganizationMember>list("id.userId", access.userId()).stream()
                .map(m -> dto(m.organization, m.role))
                .toList();
    }

    @POST
    @Transactional
    public Response create(CreateWorkspace request) {
        access.requireInteractiveUser();
        Instant now = Instant.now();
        Organization organization = new Organization();
        organization.id = UuidV7.next();
        organization.name = request.name.trim();
        organization.createdAt = now;
        organization.updatedAt = now;
        organization.persist();
        OrganizationMember member = new OrganizationMember();
        member.id = new OrganizationMemberId(organization.id, access.userId());
        member.organization = organization;
        member.user = io.seeray.lens.domain.auth.AppUser.findById(access.userId());
        member.role = WorkspaceRole.OWNER;
        member.createdAt = now;
        member.persist();
        audit.record(organization.id, member.user.id, "CREATE_WORKSPACE", "workspace", organization.id);
        return Response.status(Response.Status.CREATED)
                .entity(dto(organization, member.role))
                .build();
    }

    @GET
    @Path("/{id}")
    public WorkspaceDto get(@PathParam("id") UUID id) {
        OrganizationMember m = access.member(id);
        return dto(m.organization, m.role);
    }

    @GET
    @Path("/{id}/branding")
    public BrandingDto branding(@PathParam("id") UUID id) {
        OrganizationMember m = access.member(id);
        return brandingDto(m.organization, m.role);
    }

    @PATCH
    @Path("/{id}/branding")
    @Transactional
    public BrandingDto updateBranding(@PathParam("id") UUID id, BrandingUpdate request) {
        OrganizationMember m = access.require(id, WorkspaceRole.OWNER);
        if (request == null) throw invalidBranding();
        String brandName = optionalText(request.brandName, 120, "INVALID_WORKSPACE_BRANDING", "Brand name is too long");
        String accentColor = optionalText(
                request.brandAccentColor, 7, "INVALID_WORKSPACE_BRANDING", "Accent color must be a 6-digit hex color");
        if (accentColor != null && !accentColor.matches("^#[0-9A-Fa-f]{6}$")) throw invalidBranding();
        String logoUrl = optionalText(request.brandLogoUrl, 2048, "INVALID_WORKSPACE_BRANDING", "Logo URL is too long");
        if (logoUrl != null && !isHttpsUrl(logoUrl)) {
            throw new ControlPlaneException(
                    400, "INVALID_WORKSPACE_BRANDING", "Logo URL must be an HTTPS URL with a hostname");
        }
        m.organization.brandName = brandName;
        m.organization.brandAccentColor = accentColor == null ? null : accentColor.toUpperCase(Locale.ROOT);
        m.organization.brandLogoUrl = logoUrl;
        m.organization.updatedAt = Instant.now();
        audit.record(id, access.userId(), "UPDATE_WORKSPACE_BRANDING", "workspace", id);
        return brandingDto(m.organization, m.role);
    }

    @PATCH
    @Path("/{id}")
    @Transactional
    public WorkspaceDto update(@PathParam("id") UUID id, UpdateWorkspace r) {
        OrganizationMember m = access.require(id, WorkspaceRole.OWNER);
        if (r.name == null || r.name.isBlank())
            throw new ControlPlaneException(400, "INVALID_WORKSPACE", "Name is required");
        m.organization.name = r.name.trim();
        m.organization.updatedAt = Instant.now();
        audit.record(id, access.userId(), "UPDATE_WORKSPACE", "workspace", id);
        return dto(m.organization, m.role);
    }

    static WorkspaceDto dto(Organization o, WorkspaceRole role) {
        return new WorkspaceDto(
                o.id, o.name, role.name().toLowerCase(Locale.ROOT), o.brandName, o.brandAccentColor, o.brandLogoUrl);
    }

    private static BrandingDto brandingDto(Organization o, WorkspaceRole role) {
        return new BrandingDto(role == WorkspaceRole.OWNER, o.brandName, o.brandAccentColor, o.brandLogoUrl);
    }

    private static String optionalText(String value, int maxLength, String code, String message) {
        if (value == null || value.isBlank()) return null;
        String normalized = value.trim();
        if (normalized.length() > maxLength) throw new ControlPlaneException(400, code, message);
        return normalized;
    }

    private static boolean isHttpsUrl(String value) {
        try {
            URI uri = new URI(value);
            return "https".equalsIgnoreCase(uri.getScheme())
                    && uri.getHost() != null
                    && uri.getUserInfo() == null
                    && uri.getFragment() == null;
        } catch (URISyntaxException error) {
            return false;
        }
    }

    private static ControlPlaneException invalidBranding() {
        return new ControlPlaneException(400, "INVALID_WORKSPACE_BRANDING", "Check the workspace branding fields");
    }

    public record UpdateWorkspace(@NotBlank @Size(max = 120) String name) {}

    public record CreateWorkspace(@NotBlank @Size(max = 120) String name) {}

    public record WorkspaceDto(
            UUID id, String name, String role, String brandName, String brandAccentColor, String brandLogoUrl) {}

    public record BrandingDto(boolean canManage, String brandName, String brandAccentColor, String brandLogoUrl) {}

    public record BrandingUpdate(String brandName, String brandAccentColor, String brandLogoUrl) {}
}
