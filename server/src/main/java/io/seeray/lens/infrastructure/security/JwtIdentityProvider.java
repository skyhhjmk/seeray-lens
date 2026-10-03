package io.seeray.lens.infrastructure.security;

import io.quarkus.security.credential.TokenCredential;
import io.quarkus.security.identity.*;
import io.quarkus.security.identity.request.TokenAuthenticationRequest;
import io.quarkus.security.runtime.QuarkusSecurityIdentity;
import io.seeray.lens.application.ApiTokenAuthenticator;
import io.seeray.lens.application.JwtService;
import io.seeray.lens.domain.common.ControlPlaneException;
import io.seeray.lens.domain.auth.AppUser;
import io.seeray.lens.domain.auth.UserStatus;
import io.smallrye.mutiny.Uni;
import jakarta.enterprise.context.ApplicationScoped;
import java.security.Principal;

@ApplicationScoped
public class JwtIdentityProvider implements IdentityProvider<TokenAuthenticationRequest> {
    private final JwtService jwt;
    private final ApiTokenAuthenticator apiTokens;

    public JwtIdentityProvider(JwtService jwt, ApiTokenAuthenticator apiTokens) {
        this.jwt = jwt;
        this.apiTokens = apiTokens;
    }

    @Override
    public Class<TokenAuthenticationRequest> getRequestType() {
        return TokenAuthenticationRequest.class;
    }

    @Override
    public Uni<SecurityIdentity> authenticate(
            TokenAuthenticationRequest request, AuthenticationRequestContext context) {
        TokenCredential credential = request.getToken();
        String value = credential.getToken();
        if (value.startsWith("srlat_")) {
            return context.runBlocking(() -> {
                ApiTokenAuthenticator.AuthenticatedToken token = apiTokens.authenticate(value);
                return QuarkusSecurityIdentity.builder()
                        .setPrincipal((Principal) () -> token.actorId().toString())
                        .addCredential(credential)
                        .addAttribute(ApiTokenAuthenticator.ATTRIBUTE_TYPE, ApiTokenAuthenticator.TYPE)
                        .addAttribute(ApiTokenAuthenticator.ATTRIBUTE_ID, token.id())
                        .addAttribute(ApiTokenAuthenticator.ATTRIBUTE_WORKSPACE_ID, token.workspaceId())
                        .addAttribute(ApiTokenAuthenticator.ATTRIBUTE_NAME, token.name())
                        .addAttribute(ApiTokenAuthenticator.ATTRIBUTE_CAN_READ, token.canRead())
                        .addAttribute(ApiTokenAuthenticator.ATTRIBUTE_CAN_WRITE, token.canWrite())
                        .build();
            });
        }
        return context.runBlocking(() -> {
            JwtService.Claims claims = jwt.verifyClaims(value);
            AppUser user = AppUser.findById(claims.userId());
            if (user == null || user.status == UserStatus.DISABLED || user.authVersion != claims.authVersion())
                throw new ControlPlaneException(401, "INVALID_ACCESS_TOKEN", "Access token is invalid or revoked");
            return QuarkusSecurityIdentity.builder()
                    .setPrincipal((Principal) () -> user.id.toString())
                    .addCredential(credential)
                    .addAttribute("systemAdmin", user.systemAdmin)
                    .addAttribute("mustChangePassword", user.mustChangePassword)
                    .build();
        });
    }
}
