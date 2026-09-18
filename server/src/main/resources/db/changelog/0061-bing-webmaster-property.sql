create table bing_webmaster_property (
    site_id uuid primary key references site(id) on delete cascade,
    site_url varchar(2048) not null,
    api_key_ciphertext bytea not null,
    updated_by uuid references app_user(id) on delete set null,
    updated_at timestamptz not null default now()
);
