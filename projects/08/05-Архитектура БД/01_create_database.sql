-- ============================================================
-- Веб-сервис анализа текста на фишинг/скам "Scamseeker"
-- Создание базы данных (PostgreSQL)
-- ============================================================

-- ============================================================
-- ОБЩАЯ ЧАСТЬ: функция для автообновления updated_at
-- ============================================================

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- МОДУЛЬ "ПОЛЬЗОВАТЕЛИ И АВТОРИЗАЦИЯ"
-- ============================================================

-- Пользователи
CREATE TABLE users (
    user_id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    role VARCHAR(20) NOT NULL DEFAULT 'user',        -- 'user' или 'admin'
    status VARCHAR(20) NOT NULL DEFAULT 'inactive',  -- 'inactive' или 'active'
    notify_email BOOLEAN NOT NULL DEFAULT TRUE,      -- настройка email-уведомлений
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_users_role CHECK (role IN ('user', 'admin')),
    CONSTRAINT chk_users_status CHECK (status IN ('inactive', 'active'))
);

CREATE TRIGGER trg_users_updated_at
BEFORE UPDATE ON users
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Токены активации аккаунта
CREATE TABLE account_activation_tokens (
    token VARCHAR(255) PRIMARY KEY,
    user_id INT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    expires_at TIMESTAMP NOT NULL
);

CREATE INDEX idx_activation_tokens_user ON account_activation_tokens(user_id);

-- Токены сброса пароля
CREATE TABLE password_reset_tokens (
    token VARCHAR(255) PRIMARY KEY,
    user_id INT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    expires_at TIMESTAMP NOT NULL
);

CREATE INDEX idx_reset_tokens_user ON password_reset_tokens(user_id);

-- ============================================================
-- МОДУЛЬ "ПРОВЕРКА ТЕКСТА"
-- ============================================================

-- Проверки текста (история)
CREATE TABLE checks (
    check_id BIGSERIAL PRIMARY KEY,
    user_id INT REFERENCES users(user_id) ON DELETE CASCADE,  -- NULL для гостя
    input_text TEXT NOT NULL,
    verdict VARCHAR(20) NOT NULL,            -- 'high', 'medium', 'low'
    risk_score NUMERIC(5, 2) NOT NULL,       -- 0.00 .. 100.00
    model_version VARCHAR(100),              -- например, spam_lr_char3-5_tfidf_v1
    highlight_mode VARCHAR(20) NOT NULL DEFAULT 'combined', -- 'model', 'rules', 'combined'
    message_type VARCHAR(50),                -- опциональный тип сообщения
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_checks_verdict CHECK (verdict IN ('high', 'medium', 'low')),
    CONSTRAINT chk_checks_risk_score CHECK (risk_score >= 0 AND risk_score <= 100),
    CONSTRAINT chk_checks_highlight_mode CHECK (highlight_mode IN ('model', 'rules', 'combined'))
);

-- Индекс для быстрого доступа к истории пользователя
CREATE INDEX idx_checks_user_time ON checks(user_id, created_at DESC);

-- Найденные признаки (подсветка + "почему так")
CREATE TABLE check_findings (
    finding_id BIGSERIAL PRIMARY KEY,
    check_id BIGINT NOT NULL REFERENCES checks(check_id) ON DELETE CASCADE,
    source VARCHAR(20) NOT NULL,             -- 'model' или 'rule'
    rule_code VARCHAR(100),                  -- код regex-правила (если source='rule')
    fragment TEXT NOT NULL,                  -- подсвеченный фрагмент текста
    start_pos INT,                           -- позиция начала в тексте
    end_pos INT,                             -- позиция конца
    explanation TEXT,                        -- пояснение для пользователя
    weight NUMERIC(5, 2),                    -- вклад в оценку риска
    CONSTRAINT chk_findings_source CHECK (source IN ('model', 'rule')),
    CONSTRAINT chk_findings_positions CHECK (
        start_pos IS NULL OR end_pos IS NULL OR start_pos <= end_pos
    )
);

CREATE INDEX idx_findings_check ON check_findings(check_id);

-- ============================================================
-- МОДУЛЬ "БАЗА ЗНАНИЙ"
-- ============================================================

-- Категории информационных страниц
CREATE TABLE article_categories (
    category_id SERIAL PRIMARY KEY,
    parent_category_id INT REFERENCES article_categories(category_id),
    name VARCHAR(255) NOT NULL UNIQUE,
    description TEXT
);

-- Информационные страницы
CREATE TABLE articles (
    article_id SERIAL PRIMARY KEY,
    category_id INT NOT NULL REFERENCES article_categories(category_id),
    author_id INT NOT NULL REFERENCES users(user_id),
    title VARCHAR(255) NOT NULL,
    content TEXT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'draft',     -- 'draft', 'published', 'archived'
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_articles_status CHECK (status IN ('draft', 'published', 'archived'))
);

CREATE INDEX idx_articles_category ON articles(category_id);
CREATE INDEX idx_articles_status ON articles(status);

CREATE TRIGGER trg_articles_updated_at
BEFORE UPDATE ON articles
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Комментарии к статьям
CREATE TABLE comments (
    comment_id SERIAL PRIMARY KEY,
    article_id INT NOT NULL REFERENCES articles(article_id) ON DELETE CASCADE,
    user_id INT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    parent_comment_id INT REFERENCES comments(comment_id),
    content TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_comments_article ON comments(article_id);