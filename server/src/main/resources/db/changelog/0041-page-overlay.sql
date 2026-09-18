create table page_overlay_session (
  id uuid primary key,
  site_id uuid not null references site(id) on delete cascade,
  token_hash char(64) not null,
  source_path varchar(2048) not null,
  from_date date not null,
  to_date date not null,
  targets_json jsonb not null,
  created_at timestamptz not null,
  expires_at timestamptz not null,
  constraint page_overlay_session_date_check check (from_date <= to_date)
);
create index page_overlay_session_expiry_idx on page_overlay_session(expires_at);
