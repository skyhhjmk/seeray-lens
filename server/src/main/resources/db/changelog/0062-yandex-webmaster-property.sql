create table yandex_webmaster_property (
    site_id uuid primary key references site(id) on delete cascade,
    site_url varchar(2048) not null,
    yandex_user_id varchar(64) not null,
    host_id varchar(512) not null,
    oauth_token_ciphertext bytea not null,
    updated_by uuid references app_user(id) on delete set null,
    updated_at timestamptz not null default now()
);
