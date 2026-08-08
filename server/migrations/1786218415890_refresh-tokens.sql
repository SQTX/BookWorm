-- Refresh tokens, stored so they can be revoked.
--
-- Access tokens are stateless JWTs and cannot be withdrawn before they expire —
-- which is fine at a 15-minute lifetime. Refresh tokens live for weeks, so a
-- stolen one is worth something, and that means it has to be revocable. It
-- cannot be if it exists only as a signature.
--
-- Only a SHA-256 of the token is stored, never the token itself: a database
-- leak then hands over nothing usable. SHA-256 rather than Argon2id is correct
-- here precisely because it is fast — the token is 256 bits of CSPRNG output,
-- so there is no low-entropy guess to slow down, unlike a human-chosen
-- password.

-- Up Migration

CREATE TABLE refresh_tokens (
    id          SERIAL PRIMARY KEY,
    user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash  TEXT NOT NULL UNIQUE,
    expires_at  TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at  TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    -- Set on rotation, on logout, and on every token of a user when a
    -- already-used token is replayed. A NULL here means live.
    revoked_at  TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_refresh_tokens_user ON refresh_tokens(user_id);
-- Expired rows are deleted on a schedule; without this the sweep is a seq scan
-- over every token ever issued.
CREATE INDEX idx_refresh_tokens_expires ON refresh_tokens(expires_at);

-- Down Migration

DROP TABLE refresh_tokens;
