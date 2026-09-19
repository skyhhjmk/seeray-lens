package io.seeray.lens.domain.workspace;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "organization")
public class Organization extends PanacheEntityBase {
    @Id
    public UUID id;

    @Column(nullable = false)
    public String name;

    @Column(name = "brand_name")
    public String brandName;

    @Column(name = "brand_accent_color", length = 7)
    public String brandAccentColor;

    @Column(name = "brand_logo_url", length = 2048)
    public String brandLogoUrl;

    @Column(name = "created_at", nullable = false)
    public Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    public Instant updatedAt;
}
