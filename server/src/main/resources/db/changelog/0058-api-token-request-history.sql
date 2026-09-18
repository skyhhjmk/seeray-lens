CREATE TABLE api_token_request_log (
  id UUID PRIMARY KEY,
  token_id UUID NOT NULL REFERENCES api_token(id) ON DELETE CASCADE,
  method VARCHAR(8) NOT NULL CHECK (method IN ('GET', 'HEAD', 'OPTIONS', 'POST', 'PUT', 'PATCH', 'DELETE')),
  route_template VARCHAR(512) NOT NULL,
  status_code INTEGER NOT NULL CHECK (status_code BETWEEN 100 AND 599),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_api_token_request_log_token_time
  ON api_token_request_log(token_id, created_at DESC, id DESC);

CREATE INDEX idx_api_token_request_log_time
  ON api_token_request_log(created_at);
