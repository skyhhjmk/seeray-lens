package io.seeray.lens.api;

import io.quarkus.security.Authenticated;
import io.seeray.lens.application.ApiTokenService;
import io.seeray.lens.application.ApiTokenUsageService;
import io.seeray.lens.domain.token.ApiToken;
import jakarta.validation.constraints.*;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.*;
import java.time.Instant;
import java.util.*;

@Authenticated
@Path("/api/v1/workspaces/{workspaceId}/api-tokens")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
public class ApiTokenResource {
    private final ApiTokenService tokens;
    private final ApiTokenUsageService usage;

    public ApiTokenResource(ApiTokenService tokens, ApiTokenUsageService usage) {
        this.tokens = tokens;
        this.usage = usage;
    }

    @GET
    public List<TokenDto> list(@PathParam("workspaceId") UUID workspace) {
        return tokens.list(workspace).stream().map(ApiTokenResource::dto).toList();
    }

    @POST
    public Response create(@PathParam("workspaceId") UUID workspace, CreateToken r) {
        var c = tokens.create(workspace, r.name, r.scopes, r.expiresAt);
        return Response.status(201)
                .entity(new CreatedToken(dto(c.token()), c.plainToken()))
                .build();
    }

    @POST
    @Path("/{tokenId}/revoke")
    public Response revoke(@PathParam("workspaceId") UUID workspace, @PathParam("tokenId") UUID token) {
        tokens.revoke(workspace, token);
        return Response.noContent().build();
    }

    @GET
    @Path("/{tokenId}/usage")
    public ApiTokenUsageService.Page usage(
            @PathParam("workspaceId") UUID workspace,
            @PathParam("tokenId") UUID token,
            @QueryParam("cursor") String cursor,
            @DefaultValue("25") @QueryParam("limit") int limit) {
        return usage.list(workspace, token, cursor, limit);
    }

    static TokenDto dto(ApiToken t) {
        return new TokenDto(t.id, t.name, t.tokenPrefix, t.scopes, t.createdAt, t.expiresAt, t.lastUsedAt, t.revokedAt);
    }

    public record CreateToken(
            @NotBlank @Size(max = 120) String name, @NotEmpty List<String> scopes, Instant expiresAt) {}

    public record TokenDto(
            UUID id,
            String name,
            String tokenPrefix,
            String scopes,
            Instant createdAt,
            Instant expiresAt,
            Instant lastUsedAt,
            Instant revokedAt) {}

    public record CreatedToken(TokenDto token, String plainToken) {}
}
