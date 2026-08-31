-- Which token replaced which, so a lost rotation can be told from a theft.
--
-- Rotation is single-use: presenting a token that has already been rotated away
-- means either a replay or a stolen copy, and the answer is to revoke every
-- session for that user. That rule is right, and it also has a failure mode the
-- desktop client hits regularly.
--
-- The new pair travels in the response to POST /auth/refresh. If that response
-- does not arrive — the process was quitting on a six-second deadline, the
-- network dropped, the machine slept — the server has rotated and the client
-- has not. Its stored token is now the revoked one, and the next launch
-- presents it. The server, unable to see the difference, treats a client that
-- lost a reply as an attacker and cuts every session. The user is asked for a
-- password they should never have needed to type.
--
-- Knowing the successor makes the two distinguishable. A revoked token whose
-- successor has *itself* been used is a genuine replay: somebody is holding a
-- token from further back in the chain than the live client. A revoked token
-- whose successor was never used, revoked moments ago, is a reply that went
-- missing — the client cannot be holding the successor, because nothing has
-- ever presented it.

-- Up Migration

ALTER TABLE refresh_tokens
    ADD COLUMN replaced_by INTEGER REFERENCES refresh_tokens(id) ON DELETE SET NULL;

-- Down Migration

ALTER TABLE refresh_tokens DROP COLUMN replaced_by;
