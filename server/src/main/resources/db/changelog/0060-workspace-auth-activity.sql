create table workspace_auth_activity (
    id uuid primary key,
    organization_id uuid not null references organization(id) on delete cascade,
    actor_user_id uuid references app_user(id) on delete set null,
    event_type varchar(32) not null check (event_type in ('LOGIN_SUCCEEDED','LOGIN_FAILED','SESSION_REFRESHED','LOGOUT','REFRESH_REJECTED')),
    created_at timestamptz not null default now()
);

create index workspace_auth_activity_org_time_idx
    on workspace_auth_activity (organization_id, created_at desc, id desc);
