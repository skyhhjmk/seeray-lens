package io.seeray.lens.domain.auth;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "app_user")
public class AppUser extends PanacheEntityBase {
    @Id
    public UUID id;

    @Column(nullable = false, unique = true)
    public String email;

    @Column(name = "password_hash", nullable = false)
    public String passwordHash;

    @Column(name = "display_name", nullable = false)
    public String displayName;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    public UserStatus status;

    @Column(name = "is_system_admin", nullable = false)
    public boolean systemAdmin;

    @Column(name = "auth_version", nullable = false)
    public long authVersion;

    @Column(name = "must_change_password", nullable = false)
    public boolean mustChangePassword;

    @Column(name = "created_at", nullable = false)
    public Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    public Instant updatedAt;
}
