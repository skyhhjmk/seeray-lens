package io.seeray.lens.infrastructure.security;

import io.quarkus.security.credential.TokenCredential;
import io.quarkus.security.identity.*;
import io.quarkus.security.identity.request.TokenAuthenticationRequest;
import io.quarkus.security.runtime.QuarkusSecurityIdentity;
import io.seeray.lens.application.JwtService;
import io.smallrye.mutiny.Uni;
import jakarta.enterprise.context.ApplicationScoped;
import java.security.Principal;

@ApplicationScoped
public class JwtIdentityProvider implements IdentityProvider<TokenAuthenticationRequest> {
    private final JwtService jwt;

    public JwtIdentityProvider(JwtService jwt) {
        this.jwt = jwt;
    }

    @Override
    public Class<TokenAuthenticationRequest> getRequestType() {
        return TokenAuthenticationRequest.class;
    }

    @Override
    public Uni<SecurityIdentity> authenticate(
            TokenAuthenticationRequest request, AuthenticationRequestContext context) {
        TokenCredential credential = request.getToken();
        try {
            String subject = jwt.verify(credential.getToken()).toString();
            return Uni.createFrom()
                    .item(QuarkusSecurityIdentity.builder()
                            .setPrincipal((Principal) () -> subject)
                            .addCredential(credential)
                            .build());
        } catch (RuntimeException failure) {
            return Uni.createFrom().failure(failure);
        }
    }
}
