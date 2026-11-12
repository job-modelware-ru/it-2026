-- «Подъезд Онлайн», команда 14. Выполнять в пустой базе PostgreSQL.
BEGIN;

CREATE TABLE houses (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    address text NOT NULL CHECK (btrim(address) <> ''),
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX houses_address_uq ON houses (lower(btrim(address)));

CREATE TABLE apartments (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    house_id bigint NOT NULL REFERENCES houses ON DELETE RESTRICT,
    number text NOT NULL CHECK (number = btrim(number) AND number <> ''),
    code_fingerprint bytea NOT NULL UNIQUE,
    code_encrypted bytea NOT NULL,
    UNIQUE (house_id, number)
);

CREATE TABLE accounts (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    apartment_id bigint REFERENCES apartments ON DELETE RESTRICT,
    name text NOT NULL CHECK (btrim(name) <> ''),
    phone varchar(11) NOT NULL UNIQUE CHECK (phone ~ '^[0-9]{11}$'),
    password_hash text NOT NULL CHECK (password_hash <> ''),
    role text NOT NULL CHECK (role IN ('resident', 'dispatcher', 'admin')),
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK ((role = 'resident' AND apartment_id IS NOT NULL)
        OR (role IN ('dispatcher', 'admin') AND apartment_id IS NULL))
);

CREATE TABLE max_chat_links (
    account_id bigint PRIMARY KEY REFERENCES accounts ON DELETE RESTRICT,
    chat_id bigint NOT NULL UNIQUE,
    linked_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE max_link_tokens (
    token_hash bytea PRIMARY KEY,
    account_id bigint NOT NULL REFERENCES accounts ON DELETE RESTRICT,
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    consumed_at timestamptz,
    CHECK (expires_at > created_at),
    CHECK (consumed_at IS NULL OR
        (consumed_at >= created_at AND consumed_at < expires_at))
);

CREATE TABLE tickets (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    author_id bigint NOT NULL REFERENCES accounts ON DELETE RESTRICT,
    apartment_id bigint NOT NULL REFERENCES apartments ON DELETE RESTRICT,
    entrance text,
    description text NOT NULL CHECK (btrim(description) <> ''),
    photo_mime text,
    photo_data bytea,
    status text NOT NULL DEFAULT 'new'
        CHECK (status IN ('new', 'in_progress', 'closed')),
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK ((photo_mime IS NULL AND photo_data IS NULL) OR
        (photo_mime IS NOT NULL AND photo_data IS NOT NULL
         AND photo_mime IN ('image/jpeg', 'image/png')
         AND octet_length(photo_data) BETWEEN 1 AND 5242880))
);

CREATE TABLE ticket_events (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ticket_id bigint NOT NULL REFERENCES tickets ON DELETE RESTRICT,
    actor_id bigint NOT NULL REFERENCES accounts ON DELETE RESTRICT,
    status text NOT NULL CHECK (status IN ('new', 'in_progress', 'closed')),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE outages (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    house_id bigint NOT NULL REFERENCES houses ON DELETE RESTRICT,
    kind text NOT NULL CHECK (kind IN ('water', 'electricity', 'heating', 'elevator', 'other')),
    description text NOT NULL CHECK (btrim(description) <> ''),
    expected_fix_at timestamptz NOT NULL,
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'resolved')),
    created_at timestamptz NOT NULL DEFAULT now(),
    resolved_at timestamptz,
    CHECK ((status = 'active' AND resolved_at IS NULL)
        OR (status = 'resolved' AND resolved_at IS NOT NULL)),
    CHECK (resolved_at IS NULL OR resolved_at >= created_at)
);

CREATE TABLE outage_events (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    outage_id bigint NOT NULL REFERENCES outages ON DELETE RESTRICT,
    actor_id bigint NOT NULL REFERENCES accounts ON DELETE RESTRICT,
    kind text NOT NULL CHECK (kind IN ('published', 'rescheduled', 'resolved')),
    expected_fix_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE house_notices (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    house_id bigint NOT NULL REFERENCES houses ON DELETE RESTRICT,
    author_id bigint NOT NULL REFERENCES accounts ON DELETE RESTRICT,
    body text NOT NULL CHECK (btrim(body) <> ''),
    published_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE notifications (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    recipient_id bigint NOT NULL REFERENCES accounts ON DELETE RESTRICT,
    ticket_event_id bigint REFERENCES ticket_events ON DELETE RESTRICT,
    outage_event_id bigint REFERENCES outage_events ON DELETE RESTRICT,
    house_notice_id bigint REFERENCES house_notices ON DELETE RESTRICT,
    body text NOT NULL CHECK (btrim(body) <> ''),
    delivery_status text NOT NULL
        CHECK (delivery_status IN ('unlinked', 'pending', 'processing', 'sent', 'failed')),
    attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
    next_attempt_at timestamptz,
    lease_until timestamptz,
    sent_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (num_nonnulls(ticket_event_id, outage_event_id, house_notice_id) = 1),
    CHECK ((delivery_status = 'pending') = (next_attempt_at IS NOT NULL)),
    CHECK ((delivery_status = 'processing') = (lease_until IS NOT NULL)),
    CHECK ((delivery_status = 'sent') = (sent_at IS NOT NULL))
);

CREATE UNIQUE INDEX notifications_ticket_uq ON notifications (ticket_event_id)
    WHERE ticket_event_id IS NOT NULL;
CREATE UNIQUE INDEX notifications_outage_uq ON notifications (outage_event_id, recipient_id)
    WHERE outage_event_id IS NOT NULL;
CREATE UNIQUE INDEX notifications_notice_uq ON notifications (house_notice_id, recipient_id)
    WHERE house_notice_id IS NOT NULL;

CREATE INDEX accounts_apartment_idx ON accounts (apartment_id) WHERE role = 'resident';
CREATE INDEX tickets_author_idx ON tickets (author_id, created_at DESC);
CREATE INDEX tickets_status_idx ON tickets (status, created_at DESC);
CREATE INDEX ticket_events_ticket_idx ON ticket_events (ticket_id, id);
CREATE INDEX outages_house_idx ON outages (house_id, status, created_at DESC);
CREATE INDEX outage_events_outage_idx ON outage_events (outage_id, id);
CREATE INDEX house_notices_house_idx ON house_notices (house_id, published_at DESC);
CREATE INDEX notifications_recipient_idx ON notifications (recipient_id, created_at DESC);
CREATE INDEX notifications_pending_idx ON notifications (next_attempt_at, id)
    WHERE delivery_status = 'pending';
CREATE INDEX notifications_processing_idx ON notifications (lease_until, id)
    WHERE delivery_status = 'processing';

COMMIT;
