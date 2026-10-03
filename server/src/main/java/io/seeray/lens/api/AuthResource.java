package io.seeray.lens.api;

import io.seeray.lens.application.AuthService;
import io.seeray.lens.application.WorkspaceAccess;
import io.quarkus.security.Authenticated;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.*;

@Path("/api/v1/auth")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
public class AuthResource {
    private final AuthService auth;
    private final WorkspaceAccess access;

    public AuthResource(AuthService auth, WorkspaceAccess access) {
        this.auth = auth;
        this.access = access;
    }

    @POST
    @Path("/register")
    public TokenResponse register(RegisterRequest r) {
        return tokens(auth.register(r.email, r.password, r.displayName));
    }

    @POST
    @Path("/register-invitation")
    public TokenResponse registerInvitation(RegisterInvitationRequest r) {
        return tokens(auth.registerForInvitation(r.email, r.password, r.displayName, r.invitationToken));
    }

    @POST
    @Path("/login")
    public TokenResponse login(LoginRequest r) {
        return tokens(auth.login(r.email, r.password));
    }

    @POST
    @Path("/refresh")
    public TokenResponse refresh(RefreshRequest r) {
        return tokens(auth.refresh(r.refreshToken));
    }

    @POST
    @Path("/logout")
    public Response logout(RefreshRequest r) {
        auth.logout(r.refreshToken);
        return Response.noContent().build();
    }

    @GET
    @Path("/me")
    @Authenticated
    public AuthService.CurrentUser me() {
        return auth.currentUser(access.userId());
    }

    @POST
    @Path("/change-password")
    @Authenticated
    public TokenResponse changePassword(@Valid ChangePasswordRequest request) {
        if (request == null) throw new io.seeray.lens.domain.common.ControlPlaneException(
                400, "INVALID_PASSWORD", "A new password is required");
        return tokens(auth.changeTemporaryPassword(access.userId(), request.newPassword()));
    }

    private static TokenResponse tokens(AuthService.Tokens t) {
        return new TokenResponse(t.accessToken(), t.refreshToken());
    }

    public record RegisterRequest(
            @Email @NotBlank String email,
            @NotBlank @Size(min = 12, max = 200) String password,
            @Size(max = 120) String displayName) {}

    public record RegisterInvitationRequest(
            @Email @NotBlank String email,
            @NotBlank @Size(min = 12, max = 200) String password,
            @Size(max = 120) String displayName,
            @NotBlank @Size(max = 128) String invitationToken) {}

    public record LoginRequest(@Email @NotBlank String email, @NotBlank String password) {}

    public record RefreshRequest(@NotBlank String refreshToken) {}

    public record ChangePasswordRequest(@NotBlank @Size(min = 12, max = 200) String newPassword) {}

    public record TokenResponse(String accessToken, String refreshToken) {}
}
