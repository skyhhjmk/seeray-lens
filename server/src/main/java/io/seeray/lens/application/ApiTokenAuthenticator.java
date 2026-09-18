package io.seeray.lens.application;

import io.seeray.lens.domain.common.ControlPlaneException;
import jakarta.enterprise.context.ApplicationScoped;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.UUID;
import javax.sql.DataSource;

@ApplicationScoped
public class ApiTokenAuthenticator {
    public static final String ATTRIBUTE_TYPE = "seeray.auth.type";
    public static final String ATTRIBUTE_ID = "seeray.api-token.id";
    public static final String ATTRIBUTE_WORKSPACE_ID = "seeray.api-token.workspace";
    public static final String ATTRIBUTE_NAME = "seeray.api-token.name";
    public static final String ATTRIBUTE_CAN_READ = "seeray.api-token.read";
    public static final String ATTRIBUTE_CAN_WRITE = "seeray.api-token.write";
    public static final String TYPE = "api-token";
    private static final String TOKEN_PATTERN = "^srlat_[A-Za-z0-9_-]{43}$";
    private final DataSource dataSource;

    public ApiTokenAuthenticator(DataSource dataSource) {
        this.dataSource = dataSource;
    }

    public AuthenticatedToken authenticate(String plainToken) {
        if (plainToken == null || !plainToken.matches(TOKEN_PATTERN)) throw invalidToken();
        String hash = AuthService.hash(plainToken);
        String prefix = plainToken.substring(0, 12);
        try (Connection connection = dataSource.getConnection();
                PreparedStatement lookup =
                        connection.prepareStatement("select t.id,t.organization_id,t.name,t.created_by_user_id,"
                                + "t.scopes @> '[\"sites:read\"]'::jsonb,t.scopes @> '[\"sites:write\"]'::jsonb "
                                + "from api_token t "
                                + "join organization_member m on m.organization_id=t.organization_id "
                                + "and m.user_id=t.created_by_user_id "
                                + "join app_user u on u.id=m.user_id "
                                + "where t.token_hash=? and t.token_prefix=? and t.revoked_at is null "
                                + "and (t.expires_at is null or t.expires_at>now()) and u.status='ACTIVE'")) {
            lookup.setString(1, hash);
            lookup.setString(2, prefix);
            try (ResultSet row = lookup.executeQuery()) {
                if (!row.next()) throw invalidToken();
                UUID tokenId = row.getObject(1, UUID.class);
                UUID workspaceId = row.getObject(2, UUID.class);
                String name = row.getString(3);
                UUID actorId = row.getObject(4, UUID.class);
                boolean canRead = row.getBoolean(5);
                boolean canWrite = row.getBoolean(6);
                if (!canRead && !canWrite) throw invalidToken();
                markUsed(connection, tokenId);
                return new AuthenticatedToken(tokenId, workspaceId, name, actorId, canRead, canWrite);
            }
        } catch (ControlPlaneException error) {
            throw error;
        } catch (SQLException error) {
            throw new IllegalStateException("Could not authenticate API token", error);
        }
    }

    private static void markUsed(Connection connection, UUID tokenId) throws SQLException {
        try (PreparedStatement update =
                connection.prepareStatement("update api_token set last_used_at=now() where id=? "
                        + "and (last_used_at is null or last_used_at<now()-interval '1 minute')")) {
            update.setObject(1, tokenId);
            update.executeUpdate();
        }
    }

    private static ControlPlaneException invalidToken() {
        return new ControlPlaneException(401, "INVALID_API_TOKEN", "API token is invalid, expired, or revoked");
    }

    public record AuthenticatedToken(
            UUID id, UUID workspaceId, String name, UUID actorId, boolean canRead, boolean canWrite) {}
}
