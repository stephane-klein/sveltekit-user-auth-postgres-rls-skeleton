-- Enter migration here
DROP SCHEMA IF EXISTS public CASCADE;
DROP SCHEMA IF EXISTS auth CASCADE;

CREATE SCHEMA IF NOT EXISTS utils;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA utils;
CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA utils;

CREATE SCHEMA IF NOT EXISTS auth;

DROP TABLE IF EXISTS auth.users CASCADE;
CREATE TABLE auth.users (
    id                     SERIAL PRIMARY KEY,
    username               VARCHAR(100) NULL UNIQUE,
    first_name             VARCHAR(150) DEFAULT NULL,
    last_name              VARCHAR(150) DEFAULT NULL,
    email                  VARCHAR(360) DEFAULT NULL,
    password               VARCHAR(255) DEFAULT NULL,
    is_active              BOOLEAN DEFAULT false,
    last_login             TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    date_joined            TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    created_at             TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at             TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
CREATE INDEX users_username_index    ON auth.users (username);
CREATE INDEX users_first_name_index  ON auth.users (first_name);
CREATE INDEX users_last_name_index   ON auth.users (last_name);
CREATE INDEX users_email_index       ON auth.users (email);
CREATE INDEX users_is_active_index   ON auth.users (is_active);
CREATE INDEX users_last_login_index  ON auth.users (last_login);
CREATE INDEX users_date_joined_index ON auth.users (date_joined);
CREATE INDEX users_created_at_index  ON auth.users (created_at);
CREATE INDEX users_updated_at_index  ON auth.users (updated_at);

DROP FUNCTION IF EXISTS auth.create_user;
CREATE FUNCTION auth.create_user(
    id                     INTEGER,
    username               VARCHAR(100),
    first_name             VARCHAR(150),
    last_name              VARCHAR(150),
    email                  VARCHAR(360),
    password               VARCHAR(255),
    is_active              BOOLEAN
) RETURNS INTEGER
LANGUAGE sql
AS $$
    INSERT INTO auth.users
    (
        id,
        username,
        first_name,
        last_name,
        email,
        password,
        is_active
    )
    VALUES(
        COALESCE(id, NEXTVAL('auth.users_id_seq')),
        TRIM(username),
        TRIM(first_name),
        TRIM(last_name),
        LOWER(TRIM(email)),
        utils.CRYPT(TRIM(password), utils.GEN_SALT('bf', 8)),
        is_active
    )
    RETURNING id;
$$;

DROP TABLE IF EXISTS auth.sessions CASCADE;
CREATE TABLE auth.sessions(
    id                  UUID PRIMARY KEY DEFAULT utils.uuid_generate_v4() NOT NULL,
    user_id             INTEGER NOT NULL,
    impersonate_user_id INTEGER DEFAULT NULL,
    expires             TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP + '2days'::interval),

    CONSTRAINT fk_user_id FOREIGN KEY (user_id) REFERENCES auth.users (id) ON DELETE CASCADE
);
CREATE INDEX sessions_user_id_index ON auth.sessions (user_id);
CREATE INDEX sessions_impersonate_user_id_index ON auth.sessions (impersonate_user_id);

CREATE OR REPLACE FUNCTION auth.create_session(
    input_user_id INTEGER
) RETURNS UUID
LANGUAGE SQL
AS $$
    DELETE FROM auth.sessions WHERE user_id = input_user_id;
    INSERT INTO auth.sessions (user_id) VALUES (input_user_id) RETURNING sessions.id;
$$;;

DROP FUNCTION IF EXISTS auth.authenticate;
CREATE FUNCTION auth.authenticate(
    input_username VARCHAR(100),
    input_email    VARCHAR(360),
    input_password VARCHAR(255)
) RETURNS JSON
LANGUAGE 'plpgsql'
AS $$
DECLARE
    response JSON;
BEGIN
    WITH user_authenticated AS (
        SELECT
            id,
            username,
            first_name,
            last_name,
            email,
            password,
            is_active
        FROM
            auth.users
        WHERE
            (
                (
                    (username = input_username) AND
                    (password = utils.CRYPT(input_password, password))
                ) OR
                (
                    (email = input_email) AND
                    (password = utils.CRYPT(input_password, password))
                )
            ) AND
            (is_active IS true)
        LIMIT 1
    )
    SELECT json_build_object(
        'status_code', CASE WHEN (SELECT COUNT(*) FROM user_authenticated) > 0 THEN 200 ELSE 401 END,
        'status', CASE WHEN (SELECT COUNT(*) FROM user_authenticated) > 0
            THEN 'Login successful.'
            ELSE 'Invalid username/password combination.'
        END,
        'user', CASE WHEN (SELECT COUNT(*) FROM user_authenticated) > 0
            THEN (
                SELECT
                    json_build_object(
                        'id',         user_authenticated.id,
                        'username',   user_authenticated.username,
                        'first_name', user_authenticated.first_name,
                        'last_name',  user_authenticated.last_name,
                        'email',      user_authenticated.email,
                        'password',   user_authenticated.password
                    )
                FROM
                    user_authenticated
            )
            ELSE NULL
	    END,
	    'session_id', (SELECT auth.create_session(user_authenticated.id) FROM user_authenticated)
    ) INTO response;

    IF ((response->>'status_code')::INTEGER = 200) THEN
        UPDATE auth.users
           SET last_login = NOW()
         WHERE id=(response->'user'->>'id')::INTEGER;
    END IF;
    RETURN response;
END;
$$;

DROP TABLE IF EXISTS auth.invitations CASCADE;
CREATE TABLE auth.invitations (
    id          SERIAL PRIMARY KEY,
    invited_by  INTEGER DEFAULT NULL,
    spaces      JSONB DEFAULT NULL,
                /*
                    Example:
                    [
                        {
                            "id": 1,
                            "role": "space.MEMBER"
                        },
                        {
                            "id": 2,
                            "role": "space.ADMIN"
                        }
                    ]
                */
    email       VARCHAR(360) DEFAULT NULL,
    token       TEXT,
    expires     TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP + '7days'::interval),
    user_id     INTEGER DEFAULT NULL,

    CONSTRAINT fk_invited_by FOREIGN KEY (invited_by) REFERENCES auth.users (id) ON DELETE CASCADE,
    CONSTRAINT fk_user_id FOREIGN KEY (user_id) REFERENCES auth.users (id) ON DELETE CASCADE
);
CREATE INDEX invitations_invited_by_index ON auth.invitations (invited_by);
CREATE INDEX invitations_email_index ON auth.invitations (email);
CREATE INDEX invitations_token_index ON auth.invitations (token);
CREATE INDEX invitations_user_id_index ON auth.invitations (user_id);

DROP TABLE IF EXISTS auth.spaces CASCADE;
CREATE TABLE auth.spaces (
    id                SERIAL PRIMARY KEY,
    parent_space_id   INTEGER DEFAULT NULL,
    slug              VARCHAR(100) NOT NULL,
    title             VARCHAR(100) NOT NULL,

    created_by  INTEGER DEFAULT NULL REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at  TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    updated_by  INTEGER DEFAULT NULL REFERENCES auth.users(id) ON DELETE SET NULL,
    updated_at  TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    deleted_by  INTEGER DEFAULT NULL REFERENCES auth.users(id) ON DELETE SET NULL,
    deleted_at  TIMESTAMP WITH TIME ZONE DEFAULT NULL
);
ALTER TABLE auth.spaces ADD CONSTRAINT spaces_parent_space_id_fkey FOREIGN KEY (parent_space_id) REFERENCES auth.spaces (id) ON DELETE CASCADE;

CREATE INDEX spaces_parent_space_id_index ON auth.spaces (parent_space_id);
CREATE INDEX spaces_slug_index ON auth.spaces (slug);
CREATE INDEX spaces_created_by_index ON auth.spaces (created_by);
CREATE INDEX spaces_created_at_index ON auth.spaces (created_at);
CREATE INDEX spaces_updated_by_index ON auth.spaces (updated_by);
CREATE INDEX spaces_updated_at_index ON auth.spaces (updated_at);
CREATE INDEX spaces_deleted_by_index ON auth.spaces (deleted_by);
CREATE INDEX spaces_deleted_at_index ON auth.spaces (deleted_at);

DROP TYPE IF EXISTS auth.roles;
CREATE TYPE auth.roles AS ENUM (
    'space.MEMBER',
    'space.ADMIN',
    'space.OWNER'
);

DROP TABLE IF EXISTS auth.space_users CASCADE;
CREATE TABLE auth.space_users (
    user_id     INTEGER NOT NULL REFERENCES auth.users(id),
    space_id    INTEGER NOT NULL REFERENCES auth.spaces(id),
    role        auth.roles NOT NULL,
    created_by  INTEGER DEFAULT NULL REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at  TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
CREATE INDEX space_users_user_id_index ON auth.space_users (user_id);
CREATE INDEX space_users_space_id_index ON auth.space_users (space_id);
CREATE INDEX space_users_role_index ON auth.space_users (role);
CREATE INDEX space_users_created_by_index ON auth.space_users (created_by);
CREATE INDEX space_users_created_at_index ON auth.space_users (created_at);
