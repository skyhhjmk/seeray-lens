CREATE TABLE workspace_extension_delivery (
  id UUID PRIMARY KEY,
  extension_id UUID NOT NULL REFERENCES workspace_extension(id) ON DELETE CASCADE,
  client_event_id UUID NOT NULL,
  event_type VARCHAR(48) NOT NULL,
  payload_json JSONB NOT NULL,
  status VARCHAR(16) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'sending', 'delivered', 'failed')),
  attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  available_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  response_status INTEGER,
  last_error VARCHAR(500),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  delivered_at TIMESTAMPTZ,
  UNIQUE (extension_id, client_event_id, event_type)
);

CREATE INDEX idx_workspace_extension_delivery_poll
  ON workspace_extension_delivery(status, available_at, created_at);

CREATE INDEX idx_workspace_extension_delivery_extension
  ON workspace_extension_delivery(extension_id, created_at DESC);
