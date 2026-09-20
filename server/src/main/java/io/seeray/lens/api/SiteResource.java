package io.seeray.lens.api;

import io.quarkus.security.Authenticated;
import io.seeray.lens.application.*;
import io.seeray.lens.domain.site.*;
import jakarta.validation.constraints.*;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.*;
import java.util.*;

@Authenticated
@Path("/api/v1/sites")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
public class SiteResource {
    private final SiteService sites;

    public SiteResource(SiteService s) {
        sites = s;
    }

    @GET
    @Path("/{siteId}")
    public SiteDto get(@PathParam("siteId") UUID id) {
        Site s = sites.site(id);
        sites.domains(id);
        return dto(s);
    }

    @PATCH
    @Path("/{siteId}")
    public SiteDto update(@PathParam("siteId") UUID id, SitePatch r) {
        return dto(sites.update(
                id,
                r.name,
                r.timezone,
                r.defaultLanguage,
                r.trackingEnabled,
                r.requireConsent,
                r.rawRetentionDays,
                r.aggregateRetentionDays,
                r.fingerprintRiskEnabled,
                r.fingerprintRetentionDays));
    }

    @DELETE
    @Path("/{siteId}")
    public Response delete(@PathParam("siteId") UUID id) {
        sites.delete(id);
        return Response.noContent().build();
    }

    static SiteDto dto(Site s) {
        return new SiteDto(
                s.id,
                s.organization.id,
                s.name,
                s.trackingId,
                s.timezone,
                s.defaultLanguage,
                s.trackingEnabled,
                s.requireConsent,
                s.rawRetentionDays,
                s.aggregateRetentionDays,
                s.fingerprintRiskEnabled,
                s.fingerprintRetentionDays);
    }

    static DomainDto domain(SiteAllowedDomain d) {
        return new DomainDto(d.id, d.host, d.allowSubdomains, d.enabled);
    }

    public record SiteRequest(
            @NotBlank @Size(max = 120) String name,
            @NotBlank String timezone,
            String defaultLanguage,
            Boolean requireConsent,
            Integer rawRetentionDays,
            Integer aggregateRetentionDays,
            Boolean fingerprintRiskEnabled,
            Integer fingerprintRetentionDays) {}

    public record SitePatch(
            String name,
            String timezone,
            String defaultLanguage,
            Boolean trackingEnabled,
            Boolean requireConsent,
            Integer rawRetentionDays,
            Integer aggregateRetentionDays,
            Boolean fingerprintRiskEnabled,
            Integer fingerprintRetentionDays) {}

    public record SiteDto(
            UUID id,
            UUID workspaceId,
            String name,
            String trackingId,
            String timezone,
            String defaultLanguage,
            boolean trackingEnabled,
            boolean requireConsent,
            int rawRetentionDays,
            int aggregateRetentionDays,
            boolean fingerprintRiskEnabled,
            int fingerprintRetentionDays) {}

    public record DomainRequest(@NotBlank String host, boolean allowSubdomains, boolean enabled) {}

    public record DomainPatch(boolean allowSubdomains, boolean enabled) {}

    public record DomainDto(UUID id, String host, boolean allowSubdomains, boolean enabled) {}
}
