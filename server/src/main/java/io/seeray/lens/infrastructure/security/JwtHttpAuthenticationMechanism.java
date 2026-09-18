package io.seeray.lens.infrastructure.security;

import io.quarkus.security.credential.TokenCredential;
import io.quarkus.security.identity.*;
import io.quarkus.security.identity.request.TokenAuthenticationRequest;
import io.quarkus.vertx.http.runtime.security.ChallengeData;
import io.quarkus.vertx.http.runtime.security.HttpAuthenticationMechanism;
import io.smallrye.mutiny.Uni;
import io.vertx.ext.web.RoutingContext;
import jakarta.enterprise.context.ApplicationScoped;

@ApplicationScoped
public class JwtHttpAuthenticationMechanism implements HttpAuthenticationMechanism {
    @Override
    public Uni<ChallengeData> getChallenge(RoutingContext context) {
        return Uni.createFrom().item(new ChallengeData(401, "WWW-Authenticate", "Bearer"));
    }

    @Override
    public Uni<SecurityIdentity> authenticate(RoutingContext context, IdentityProviderManager manager) {
        String path = context.request().path();
        if (path != null && path.matches("^/api/v1/tag-manager/[^/]+/preview/[^/]+(?:/events)?$")) {
            // The Authorization bearer on this explicitly public route is a short-lived preview token,
            // validated against its hashed session secret by TagManagerService, not an application JWT.
            return Uni.createFrom().nullItem();
        }
        String authorization = context.request().getHeader("Authorization");
        if (authorization == null || !authorization.startsWith("Bearer "))
            return Uni.createFrom().nullItem();
        return manager.authenticate(
                new TokenAuthenticationRequest(new TokenCredential(authorization.substring(7), "Bearer")));
    }
}
