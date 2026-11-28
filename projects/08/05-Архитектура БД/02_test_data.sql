-- ============================================================
-- Тестовые данные для Scamseeker
-- ============================================================

-- 1. ПОЛЬЗОВАТЕЛИ
INSERT INTO users (name, email, password_hash, role, status, notify_email) VALUES
    ('Админ Системы', 'admin@scamseeker.local', 'hashed_admin', 'admin', 'active', TRUE),
    ('Иван Петров', 'ivan@example.com', 'hashed_ivan', 'user', 'active', TRUE),
    ('Мария Сидорова', 'maria@example.com', 'hashed_maria', 'user', 'active', FALSE),
    ('Алексей Козлов', 'alexey@example.com', 'hashed_alexey', 'user', 'inactive', TRUE);

-- 2. ТОКЕНЫ АКТИВАЦИИ (для неактивного пользователя)
INSERT INTO account_activation_tokens (token, user_id, expires_at) VALUES
    ('activation-token-alexey-123', 4, NOW() + INTERVAL '24 hours');

-- 3. КАТЕГОРИИ СТАТЕЙ
INSERT INTO article_categories (name, description) VALUES
    ('Что такое фишинг и скам', 'Базовые понятия и признаки угроз'),
    ('Как работает Scamseeker', 'Описание логики проверки простым языком'),
    ('Рекомендации по безопасности', 'Что делать при подозрении на мошенничество');

-- 4. ИНФОРМАЦИОННЫЕ СТАТЬИ
INSERT INTO articles (category_id, author_id, title, content, status) VALUES
    (1, 1, 'Что такое фишинг?',
     'Фишинг — это попытка мошенников выманить ваши данные, представляясь доверенной организацией. Типичные каналы — email, SMS, мессенджеры.',
     'published'),
    (1, 1, 'Типичные признаки скама',
     'Срочность, незнакомые ссылки, просьбы о переводе денег, обещания крупных выигрышей, требования предоплаты — всё это признаки скама.',
     'published'),
    (2, 1, 'Как Scamseeker оценивает риск',
     'Сервис применяет ML-модель и набор regex-правил. Модель оценивает общий тон и структуру текста, правила выявляют конкретные подозрительные элементы: ссылки, слова срочности, приманки.',
     'published'),
    (3, 1, 'Что делать при высоком риске',
     'Не переходите по ссылкам, не сообщайте личные данные, проверьте отправителя через официальные каналы, при необходимости обратитесь в поддержку организации.',
     'published'),
    (3, 1, 'Черновик: как сообщить о фишинге',
     'Инструкция по сообщению о подозрительном сообщении в банк и в правоохранительные органы.',
     'draft');

-- 5. КОММЕНТАРИИ
INSERT INTO comments (article_id, user_id, content) VALUES
    (1, 2, 'Очень понятно объяснено, спасибо!'),
    (2, 3, 'Помогло распознать подозрительное письмо.'),
    (3, 2, 'Интересно, что учитывается и модель, и правила.');

-- 6. ПРОВЕРКИ ТЕКСТА (история)
INSERT INTO checks (user_id, input_text, verdict, risk_score, model_version, highlight_mode, message_type) VALUES
    (2,
     'Уважаемый клиент! Ваш аккаунт будет заблокирован. Срочно перейдите по ссылке http://secure-bank-verify.xyz и подтвердите данные.',
     'high', 92.50, 'spam_lr_char3-5_tfidf_v1', 'combined', 'email'),
    (2,
     'Здравствуйте! Напоминаем, что завтра в 10:00 плановая встреча в офисе.',
     'low', 8.20, 'spam_lr_char3-5_tfidf_v1', 'combined', 'email'),
    (3,
     'Поздравляем! Вы выиграли 100000 рублей. Для получения приза оплатите комиссию 500 руб.',
     'high', 88.10, 'spam_lr_char3-5_tfidf_v1', 'rules', 'sms'),
    (2,
     'Ваш заказ №1234 отправлен. Ожидайте доставку курьером.',
     'medium', 45.00, 'spam_lr_char3-5_tfidf_v1', 'model', 'sms'),
    (NULL,
     'Срочно! Ваша карта заблокирована. Позвоните по номеру 8-800-...',
     'high', 85.00, 'spam_lr_char3-5_tfidf_v1', 'combined', 'sms');

-- 7. НАЙДЕННЫЕ ПРИЗНАКИ (подсветка / "почему так")
INSERT INTO check_findings (check_id, source, rule_code, fragment, start_pos, end_pos, explanation, weight) VALUES
    (1, 'rule', 'urgency', 'Срочно', 48, 54,
     'Слова срочности — типичный признак давления на получателя', 15.00),
    (1, 'rule', 'suspicious_url', 'http://secure-bank-verify.xyz', 82, 110,
     'Подозрительный домен, не похожий на официальный', 40.00),
    (1, 'model', NULL, 'Ваш аккаунт будет заблокирован', 20, 48,
     'Модель отметила угрозу блокировки как рискованную фразу', 20.00),
    (3, 'rule', 'prize_bait', 'Вы выиграли 100000 рублей', 15, 40,
     'Обещание крупного выигрыша — классическая приманка', 35.00),
    (3, 'rule', 'advance_fee', 'оплатите комиссию 500 руб.', 62, 86,
     'Требование предоплаты для получения приза', 40.00),
    (4, 'model', NULL, 'Ваш заказ №1234 отправлен', 0, 24,
     'Модель нашла нейтральную фразу умеренно рискованной в контексте SMS', 10.00),
    (5, 'rule', 'urgency', 'Срочно', 0, 6,
     'Слова срочности', 15.00),
    (5, 'rule', 'card_blocked', 'Ваша карта заблокирована', 8, 32,
     'Угроза блокировки карты — типичный приём социальной инженерии', 30.00),
    (5, 'rule', 'phone_number', '8-800-...', 60, 69,
     'Подозрительный номер телефона', 20.00);

-- 8. СБРОС ПОСЛЕДОВАТЕЛЬНОСТЕЙ (не обязательно, но полезно при повторном запуске)
-- SELECT setval('checks_check_id_seq', (SELECT MAX(check_id) FROM checks));
-- SELECT setval('check_findings_finding_id_seq', (SELECT MAX(finding_id) FROM check_findings));

-- Проверка данных
SELECT 'users' AS table_name, COUNT(*) FROM users
UNION ALL SELECT 'account_activation_tokens', COUNT(*) FROM account_activation_tokens
UNION ALL SELECT 'checks', COUNT(*) FROM checks
UNION ALL SELECT 'check_findings', COUNT(*) FROM check_findings
UNION ALL SELECT 'article_categories', COUNT(*) FROM article_categories
UNION ALL SELECT 'articles', COUNT(*) FROM articles
UNION ALL SELECT 'comments', COUNT(*) FROM comments;