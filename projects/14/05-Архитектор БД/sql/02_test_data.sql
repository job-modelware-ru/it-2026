-- Учебные данные. Запускать один раз после 01_create_database.sql.
-- Телефоны и chat_id вымышлены. Значения хешей и шифротекста — заглушки,
-- для входа и подключения реального MAX они не подходят.
BEGIN;

INSERT INTO houses (address) VALUES ('ул. Садовая, д. 10'), ('ул. Садовая, д. 12');

INSERT INTO apartments (house_id, number, code_fingerprint, code_encrypted)
SELECT h.id, v.number, convert_to(v.code, 'UTF8'), convert_to('demo:' || v.code, 'UTF8')
FROM (VALUES
    ('ул. Садовая, д. 10', '1', 'demo-code-10-1'),
    ('ул. Садовая, д. 10', '2', 'demo-code-10-2'),
    ('ул. Садовая, д. 12', '1', 'demo-code-12-1')
) AS v(address, number, code)
JOIN houses h ON h.address = v.address;

INSERT INTO accounts (apartment_id, name, phone, password_hash, role)
SELECT a.id, v.name, v.phone, 'demo-hash-no-login', 'resident'
FROM (VALUES
    ('ул. Садовая, д. 10', '1', 'Анна', '70000000001'),
    ('ул. Садовая, д. 10', '1', 'Иван', '70000000002'),
    ('ул. Садовая, д. 12', '1', 'Мария', '70000000003')
) AS v(address, number, name, phone)
JOIN houses h ON h.address = v.address
JOIN apartments a ON a.house_id = h.id AND a.number = v.number;

INSERT INTO accounts (name, phone, password_hash, role) VALUES
    ('Диспетчер', '70000000004', 'demo-hash-no-login', 'dispatcher'),
    ('Администратор', '70000000005', 'demo-hash-no-login', 'admin');

INSERT INTO max_chat_links (account_id, chat_id)
SELECT id, 900001 FROM accounts WHERE phone = '70000000001';
INSERT INTO max_link_tokens (token_hash, account_id, expires_at)
SELECT convert_to('demo-token', 'UTF8'), id, now() + interval '15 minutes'
FROM accounts WHERE phone = '70000000002';

INSERT INTO tickets (author_id, apartment_id, entrance, description)
SELECT id, apartment_id, '1', 'Не работает домофон'
FROM accounts WHERE phone = '70000000001';
INSERT INTO ticket_events (ticket_id, actor_id, status)
SELECT id, author_id, status FROM tickets;

INSERT INTO outages (house_id, kind, description, expected_fix_at)
SELECT id, 'water', 'Нет холодной воды', now() + interval '3 hours'
FROM houses WHERE address = 'ул. Садовая, д. 10';
INSERT INTO outage_events (outage_id, actor_id, kind, expected_fix_at)
SELECT o.id, a.id, 'published', o.expected_fix_at
FROM outages o CROSS JOIN accounts a WHERE a.role = 'dispatcher';

INSERT INTO house_notices (house_id, author_id, body)
SELECT h.id, a.id, 'В пятницу с 10:00 до 12:00 будут ремонтировать входную дверь.'
FROM houses h CROSS JOIN accounts a
WHERE h.address = 'ул. Садовая, д. 10' AND a.role = 'dispatcher';

-- В рассылку входят оба жителя дома 10. Мария из дома 12 её не получает.
INSERT INTO notifications (recipient_id, outage_event_id, body, delivery_status, next_attempt_at)
SELECT a.id, e.id, o.description,
    CASE WHEN l.account_id IS NULL THEN 'unlinked' ELSE 'pending' END,
    CASE WHEN l.account_id IS NOT NULL THEN now() END
FROM outage_events e
JOIN outages o ON o.id = e.outage_id
JOIN apartments ap ON ap.house_id = o.house_id
JOIN accounts a ON a.apartment_id = ap.id AND a.role = 'resident'
LEFT JOIN max_chat_links l ON l.account_id = a.id;

INSERT INTO notifications (recipient_id, house_notice_id, body, delivery_status, next_attempt_at)
SELECT a.id, n.id, n.body,
    CASE WHEN l.account_id IS NULL THEN 'unlinked' ELSE 'pending' END,
    CASE WHEN l.account_id IS NOT NULL THEN now() END
FROM house_notices n
JOIN apartments ap ON ap.house_id = n.house_id
JOIN accounts a ON a.apartment_id = ap.id AND a.role = 'resident'
LEFT JOIN max_chat_links l ON l.account_id = a.id;

INSERT INTO notifications (recipient_id, ticket_event_id, body, delivery_status, next_attempt_at)
SELECT t.author_id, e.id, 'Заявка принята', 'pending', now()
FROM ticket_events e JOIN tickets t ON t.id = e.ticket_id;

COMMIT;
