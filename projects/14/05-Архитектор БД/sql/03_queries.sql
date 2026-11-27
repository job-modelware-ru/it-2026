-- Примеры для данных из 02_test_data.sql.
-- В приложении значения из примеров передаются параметрами запроса,
-- а id жителя берётся из проверенной сессии. Роль сотрудника проверяет сервис.

-- 1. Квартира и дом жителя.
SELECT a.name, h.address, ap.number
FROM accounts a
JOIN apartments ap ON ap.id = a.apartment_id
JOIN houses h ON h.id = ap.house_id
WHERE a.phone = '70000000001';

-- 2. Заявки жителя. Фото не загружается в список.
SELECT t.id, t.description, t.status, t.created_at
FROM tickets t JOIN accounts a ON a.id = t.author_id
WHERE a.phone = '70000000001'
ORDER BY t.created_at DESC, t.id DESC;

-- 3. Открытые заявки для диспетчера.
SELECT t.id, h.address, ap.number, t.entrance, t.description, t.status
FROM tickets t
JOIN apartments ap ON ap.id = t.apartment_id
JOIN houses h ON h.id = ap.house_id
WHERE t.status IN ('new', 'in_progress')
ORDER BY t.created_at, t.id;

-- 4. Аварии только по дому текущего жителя.
SELECT o.id, o.kind, o.description, o.expected_fix_at
FROM outages o
JOIN apartments ap ON ap.house_id = o.house_id
JOIN accounts a ON a.apartment_id = ap.id
WHERE a.phone = '70000000001' AND o.status = 'active'
ORDER BY o.created_at DESC, o.id DESC;

-- 5. Сообщения по дому жителя.
SELECT n.body, n.published_at
FROM house_notices n
JOIN apartments ap ON ap.house_id = n.house_id
JOIN accounts a ON a.apartment_id = ap.id
WHERE a.phone = '70000000001'
ORDER BY n.published_at DESC, n.id DESC;

-- 6. Уведомления в личном кабинете, включая ещё не отправленные в MAX.
SELECT n.body, n.delivery_status, n.created_at
FROM notifications n JOIN accounts a ON a.id = n.recipient_id
WHERE a.phone = '70000000002'
ORDER BY n.created_at DESC, n.id DESC;

-- 7. История заявки её автора.
SELECT e.status, actor.name, e.created_at
FROM ticket_events e
JOIN accounts actor ON actor.id = e.actor_id
JOIN tickets t ON t.id = e.ticket_id
JOIN accounts owner ON owner.id = t.author_id
WHERE owner.phone = '70000000001'
ORDER BY e.id;

-- 8. Взять учебную заявку в работу вместе с историей и уведомлением.
-- В приложении ID заявки приходит из маршрута, а ID диспетчера — из сессии.
BEGIN;
SELECT id, status FROM tickets
WHERE id = 1
FOR UPDATE;

WITH dispatcher AS (
    SELECT id FROM accounts
    WHERE phone = '70000000004' AND role = 'dispatcher'
), changed AS (
    UPDATE tickets t SET status = 'in_progress'
    FROM dispatcher d
    WHERE t.id = 1 AND t.status = 'new'
    RETURNING t.id, t.author_id, d.id AS dispatcher_id
), event AS (
    INSERT INTO ticket_events (ticket_id, actor_id, status)
    SELECT id, dispatcher_id, 'in_progress' FROM changed
    RETURNING id, ticket_id
)
INSERT INTO notifications (recipient_id, ticket_event_id, body, delivery_status, next_attempt_at)
SELECT c.author_id, e.id, 'Заявка взята в работу',
    CASE WHEN l.account_id IS NULL THEN 'unlinked' ELSE 'pending' END,
    CASE WHEN l.account_id IS NOT NULL THEN now() END
FROM changed c JOIN event e ON e.ticket_id = c.id
LEFT JOIN max_chat_links l ON l.account_id = c.author_id;
ROLLBACK; -- Демонстрация: в приложении после успешной операции используется COMMIT.

-- 9. Резервирование пачки уведомлений фоновым обработчиком.
BEGIN;
WITH batch AS (
    SELECT id FROM notifications
    WHERE delivery_status = 'pending' AND next_attempt_at <= now()
    ORDER BY next_attempt_at, id
    LIMIT 20 FOR UPDATE SKIP LOCKED
)
UPDATE notifications n
SET delivery_status = 'processing', next_attempt_at = NULL,
    lease_until = clock_timestamp() + interval '1 minute',
    attempt_count = attempt_count + 1
FROM batch WHERE n.id = batch.id
RETURNING n.id, n.recipient_id, n.body, n.lease_until;
ROLLBACK; -- При работе сервиса резерв фиксируется до обращения к MAX.

-- 10. Возврат заданий, обработчик которых остановился.
-- Для примера задан предел в три попытки, включая истёкшие резервы.
BEGIN;
UPDATE notifications
SET delivery_status = CASE WHEN attempt_count < 3 THEN 'pending' ELSE 'failed' END,
    lease_until = NULL,
    next_attempt_at = CASE WHEN attempt_count < 3 THEN now() END
WHERE delivery_status = 'processing' AND lease_until <= now()
RETURNING id, delivery_status;
ROLLBACK;
