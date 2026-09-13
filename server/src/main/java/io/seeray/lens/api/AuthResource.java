package io.seeray.lens.api;

import io.seeray.lens.application.AuthService;
import jakarta.validation.constraints.*;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.*;

@Path("/api/v1/auth")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
public class AuthResource {
    private final AuthService auth;

    public AuthResource(AuthService auth) {
        this.auth = auth;
    }

    @POST
    @Path("/register")
    public TokenResponse register(RegisterRequest r) {
        return tokens(auth.register(r.email, r.password, r.displayName));
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

    private static TokenResponse tokens(AuthService.Tokens t) {
        return new TokenResponse(t.accessToken(), t.refreshToken());
    }

    public record RegisterRequest(
            @Email @NotBlank String email,
            @NotBlank @Size(min = 12, max = 200) String password,
            @Size(max = 120) String displayName) {}

    public record LoginRequest(@Email @NotBlank String email, @NotBlank String password) {}

    public record RefreshRequest(@NotBlank String refreshToken) {}

    public record TokenResponse(String accessToken, String refreshToken) {}
}
