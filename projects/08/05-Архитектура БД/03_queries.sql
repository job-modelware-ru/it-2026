-- ============================================================
-- Основные запросы Scamseeker
-- ============================================================

-- ============================================================
-- АВТОРИЗАЦИЯ И РЕГИСТРАЦИЯ
-- ============================================================

-- Регистрация нового пользователя (создаётся со статусом 'inactive')
INSERT INTO users (name, email, password_hash, role, status)
VALUES ('Новый Пользователь', 'new@example.com', 'hashed_password', 'user', 'inactive');

-- Создание токена активации для нового пользователя
INSERT INTO account_activation_tokens (token, user_id, expires_at)
SELECT 'activation-token-' || gen_random_uuid(), user_id, NOW() + INTERVAL '24 hours'
FROM users
WHERE email = 'new@example.com';

-- Проверка токена активации
SELECT u.user_id, u.email
FROM account_activation_tokens t
JOIN users u ON t.user_id = u.user_id
WHERE t.token = 'activation-token-alexey-123'
  AND t.expires_at > NOW();

-- Активация аккаунта по токену
UPDATE users
SET status = 'active'
WHERE user_id = (
    SELECT user_id FROM account_activation_tokens
    WHERE token = 'activation-token-alexey-123' AND expires_at > NOW()
);

-- Удаление использованного токена
DELETE FROM account_activation_tokens WHERE token = 'activation-token-alexey-123';

-- Авторизация (проверка данных)
SELECT user_id, name, email, role, status
FROM users
WHERE email = 'ivan@example.com' AND status = 'active';

-- Изменение личных данных
UPDATE users
SET name = 'Иван П.', updated_at = NOW()
WHERE user_id = 2;

-- Изменение пароля
UPDATE users
SET password_hash = 'new_hashed_password'
WHERE user_id = 2;

-- Отключение email-уведомлений
UPDATE users SET notify_email = FALSE WHERE user_id = 3;

-- ============================================================
-- ПРОВЕРКА ТЕКСТА
-- ============================================================

-- Сохранить результат проверки (авторизованный пользователь)
INSERT INTO checks (user_id, input_text, verdict, risk_score, model_version, highlight_mode, message_type)
VALUES (2, 'Проверяемый текст...', 'high', 87.30, 'spam_lr_char3-5_tfidf_v1', 'combined', 'email');

-- Сохранить результат проверки (гость)
INSERT INTO checks (user_id, input_text, verdict, risk_score, model_version, highlight_mode)
VALUES (NULL, 'Текст от гостя...', 'low', 12.00, 'spam_lr_char3-5_tfidf_v1', 'combined');

-- Добавить найденный признак к проверке
INSERT INTO check_findings (check_id, source, rule_code, fragment, start_pos, end_pos, explanation, weight)
VALUES (6, 'rule', 'suspicious_url', 'http://fake-site.xyz', 10, 32, 'Подозрительный домен', 40.00);

-- Получить результат проверки с подсветкой
SELECT c.check_id, c.verdict, c.risk_score, c.highlight_mode, c.created_at,
       cf.source, cf.fragment, cf.explanation, cf.weight
FROM checks c
LEFT JOIN check_findings cf ON c.check_id = cf.check_id
WHERE c.check_id = 1
ORDER BY cf.weight DESC NULLS LAST;

-- Переключение режима подсветки (обновление результата)
UPDATE checks SET highlight_mode = 'rules' WHERE check_id = 1;

-- ============================================================
-- ИСТОРИЯ ПРОВЕРОК
-- ============================================================

-- История проверок пользователя
SELECT check_id, verdict, risk_score, LEFT(input_text, 80) AS snippet, created_at
FROM checks
WHERE user_id = 2
ORDER BY created_at DESC;

-- Открыть подробный результат из истории
SELECT c.*, cf.fragment, cf.explanation, cf.weight
FROM checks c
LEFT JOIN check_findings cf ON c.check_id = cf.check_id
WHERE c.check_id = 1 AND c.user_id = 2;

-- Статистика проверок пользователя по вердиктам
SELECT verdict, COUNT(*) AS count, ROUND(AVG(risk_score), 2) AS avg_score
FROM checks
WHERE user_id = 2
GROUP BY verdict
ORDER BY count DESC;

-- ============================================================
-- БАЗА ЗНАНИЙ
-- ============================================================

-- Все категории
SELECT category_id, name, description FROM article_categories;

-- Опубликованные статьи категории
SELECT a.article_id, a.title, u.name AS author, a.created_at
FROM articles a
JOIN users u ON a.author_id = u.user_id
WHERE a.category_id = 1 AND a.status = 'published';

-- Поиск статей по ключевому слову
SELECT article_id, title
FROM articles
WHERE status = 'published'
  AND (title ILIKE '%фишинг%' OR content ILIKE '%фишинг%');

-- Статья с автором и категорией
SELECT a.title, a.content, u.name AS author, c.name AS category
FROM articles a
JOIN users u ON a.author_id = u.user_id
JOIN article_categories c ON a.category_id = c.category_id
WHERE a.article_id = 1;

-- Комментарии к статье
SELECT cm.content, u.name AS author, cm.created_at
FROM comments cm
JOIN users u ON cm.user_id = u.user_id
WHERE cm.article_id = 1
ORDER BY cm.created_at;

-- Добавить комментарий
INSERT INTO comments (article_id, user_id, content)
VALUES (1, 2, 'Спасибо за статью!');

-- ============================================================
-- СТАТИСТИКА И ОТЧЁТЫ (для администратора)
-- ============================================================

-- Общая статистика по проверкам
SELECT verdict, COUNT(*) AS count
FROM checks
GROUP BY verdict;

-- Топ пользователей по количеству проверок
SELECT u.name, COUNT(c.check_id) AS checks_count
FROM users u
LEFT JOIN checks c ON u.user_id = c.user_id
GROUP BY u.name
ORDER BY checks_count DESC;

-- Самые частые правила срабатывания
SELECT rule_code, COUNT(*) AS hits
FROM check_findings
WHERE source = 'rule'
GROUP BY rule_code
ORDER BY hits DESC;

-- Количество гостевых проверок
SELECT COUNT(*) AS guest_checks
FROM checks
WHERE user_id IS NULL;

-- Средний риск по типу сообщения
SELECT message_type, COUNT(*) AS count, ROUND(AVG(risk_score), 2) AS avg_risk
FROM checks
WHERE message_type IS NOT NULL
GROUP BY message_type
ORDER BY avg_risk DESC;