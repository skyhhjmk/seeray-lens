package io.seeray.lens.domain.workspace;

import jakarta.persistence.Embeddable;
import java.io.Serializable;
import java.util.Objects;
import java.util.UUID;

@Embeddable
public class OrganizationMemberId implements Serializable {
    public UUID organizationId;
    public UUID userId;

    public OrganizationMemberId() {}

    public OrganizationMemberId(UUID o, UUID u) {
        organizationId = o;
        userId = u;
    }

    @Override
    public boolean equals(Object other) {
        return other instanceof OrganizationMemberId that
                && Objects.equals(organizationId, that.organizationId)
                && Objects.equals(userId, that.userId);
    }

    @Override
    public int hashCode() {
        return Objects.hash(organizationId, userId);
    }
}
