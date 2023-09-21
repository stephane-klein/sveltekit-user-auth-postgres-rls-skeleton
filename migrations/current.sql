-- Enter migration here
DROP SCHEMA IF EXISTS public CASCADE;
DROP SCHEMA IF EXISTS auth CASCADE;
DROP SCHEMA IF EXISTS main CASCADE;

CREATE SCHEMA IF NOT EXISTS utils;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA utils;
CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA utils;
CREATE EXTENSION IF NOT EXISTS "intarray" WITH SCHEMA utils;

-- Helper section

CREATE OR REPLACE FUNCTION utils.create_role_if_not_exists(rolename NAME) RETURNS TEXT AS
$$
BEGIN
    IF NOT EXISTS (SELECT * FROM pg_roles WHERE rolname = rolename) THEN
        EXECUTE format('CREATE ROLE %I', rolename);
        RETURN 'CREATE ROLE';
    ELSE
        RETURN format('ROLE ''%I'' ALREADY EXISTS', rolename);
    END IF;
END;
$$
LANGUAGE plpgsql;

-- Auth section

CREATE SCHEMA IF NOT EXISTS auth;

DROP TABLE IF EXISTS auth.users CASCADE;
CREATE TABLE auth.users (
    id                     SERIAL PRIMARY KEY,
    username               VARCHAR(100) NOT NULL UNIQUE,
    first_name             VARCHAR(150) DEFAULT NULL,
    last_name              VARCHAR(150) DEFAULT NULL,
    email                  VARCHAR(360) NOT NULL UNIQUE,
    password               VARCHAR(255) NOT NULL,
    is_active              BOOLEAN DEFAULT FALSE,
    is_superuser           BOOLEAN DEFAULT FALSE,
    is_serviceuser         BOOLEAN DEFAULT FALSE,
    last_login             TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    last_seen              TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    date_joined            TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    created_at             TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    created_by INTEGER
        DEFAULT (NULLIF(CURRENT_SETTING('auth.user_id', TRUE), ''))::INTEGER,

    updated_at             TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
ALTER TABLE auth.users ADD CONSTRAINT users_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users (id) ON DELETE SET NULL;
CREATE INDEX users_username_index    ON auth.users (username);
CREATE INDEX users_first_name_index  ON auth.users (first_name);
CREATE INDEX users_last_name_index   ON auth.users (last_name);
CREATE INDEX users_email_index       ON auth.users (email);
CREATE INDEX users_is_active_index   ON auth.users (is_active);
CREATE INDEX users_last_login_index  ON auth.users (last_login);
CREATE INDEX users_last_seen_index   ON auth.users (last_seen);
CREATE INDEX users_date_joined_index ON auth.users (date_joined);
CREATE INDEX users_created_at_index  ON auth.users (created_at);
CREATE INDEX users_updated_at_index  ON auth.users (updated_at);

INSERT INTO auth.users (
    id,
    username,
    email,
    password,
    is_active,
    is_superuser,
    is_serviceuser,
    date_joined
)
VALUES (
    0,                   -- id,
    'root',              -- username,
    'noreply@localhost', -- email,
    '',                  -- password,
    TRUE,                -- is_active,
    TRUE,                -- is_superuser,
    TRUE,                -- is_serviceuser,
    NOW()                -- date_joined
);

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

DROP FUNCTION IF EXISTS auth.create_session;
CREATE OR REPLACE FUNCTION auth.create_session(
    input_user_id INTEGER
) RETURNS UUID
LANGUAGE SQL
AS $$
    DELETE FROM auth.sessions WHERE user_id = input_user_id;
    INSERT INTO auth.sessions (user_id) VALUES (input_user_id) RETURNING sessions.id;
$$;

DROP FUNCTION IF EXISTS auth.authenticate;
CREATE FUNCTION auth.authenticate(
    input_username VARCHAR(100),
    input_email    VARCHAR(360),
    input_password VARCHAR(255)
) RETURNS JSON
LANGUAGE 'plpgsql' SECURITY DEFINER
AS $$
DECLARE
    _user auth.users;
    _response JSON;
BEGIN
    SELECT
        * INTO _user
    FROM
        auth.users
    WHERE
        (username = input_username) OR
        (email = input_email);

    IF (_user IS NULL) THEN
        SELECT
            JSON_BUILD_OBJECT(
                'status_code', 404,
                'status', 'Login failed user not found'
            ) INTO _response;

        INSERT INTO auth.audit_events
            (
                entity_type,
                entity_id,
                space_ids,
                event_type,
                details
            )
            VALUES(
                'auth.users',
                NULL,
                NULL,
                'user.LOGIN_FAILED_USER_NOT_FOUND',
                JSONB_BUILD_OBJECT(
                    'username', input_username,
                    'email', input_email
                )
            );

        RETURN _response;
    END IF;

    IF (_user.is_active IS FALSE) THEN
        SELECT
            JSON_BUILD_OBJECT(
                'status_code', 403,
                'status', 'Login failed, user ' || _user.username || 'deactivate'
            ) INTO _response;

        INSERT INTO auth.audit_events
            (
                entity_type,
                entity_id,
                event_type
            )
            VALUES(
                'auth.users',
                _user.id,
                'user.LOGIN_FAILED_USER_DEACTIVATE'
            );

        RETURN _response;
    END IF;

    IF (_user.password != utils.CRYPT(input_password, _user.password)) THEN
        SELECT
            JSON_BUILD_OBJECT(
                'status_code', 403,
                'status', 'Login failed, bad password'
            ) INTO _response;

        INSERT INTO auth.audit_events
            (
                entity_type,
                entity_id,
                event_type
            )
            VALUES(
                'auth.users',
                _user.id,
                'user.LOGIN_FAILED_BAD_PASSWORD'
            );

        RETURN _response;
    END IF;

    WITH _audit_events AS (
        INSERT INTO auth.audit_events (
            entity_type,
            entity_id,
            event_type,
            space_ids
        )
        VALUES(
            'auth.users',
            _user.id,
            'user.LOGIN_SUCCESS',
            (
                SELECT ARRAY_AGG(space_id)
                FROM auth.space_users
                WHERE user_id = _user.id
            )
        )
    ),
    _update AS (
        UPDATE auth.users
           SET last_login = NOW()
         WHERE id=_user.id
    )
    SELECT json_build_object(
        'status_code', 200,
        'status', 'Login successful',
        'user', json_build_object(
            'id',         _user.id,
            'username',   _user.username,
            'first_name', _user.first_name,
            'last_name',  _user.last_name,
            'email',      _user.email
        ),
	    'session_id', (SELECT auth.create_session(_user.id))
    ) INTO _response;

    RETURN _response;
END;
$$;

DROP TABLE IF EXISTS auth.spaces CASCADE;
CREATE TABLE auth.spaces (
    id                     SERIAL PRIMARY KEY,
    parent_space_id        INTEGER DEFAULT NULL,
    slug                   VARCHAR(100) NOT NULL,
    title                  VARCHAR(100) NOT NULL,
    is_publicly_browsable  BOOLEAN DEFAULT FALSE,
    invitation_required    BOOLEAN DEFAULT TRUE,

    created_by
        INTEGER
        DEFAULT (NULLIF(CURRENT_SETTING('auth.user_id', TRUE), ''))::INTEGER
        REFERENCES auth.users(id) ON DELETE SET NULL,

    created_at  TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    updated_by  INTEGER DEFAULT NULL REFERENCES auth.users(id) ON DELETE SET NULL,
    updated_at  TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    deleted_by  INTEGER DEFAULT NULL REFERENCES auth.users(id) ON DELETE SET NULL,
    deleted_at  TIMESTAMP WITH TIME ZONE DEFAULT NULL
);
ALTER TABLE auth.spaces ADD CONSTRAINT spaces_parent_space_id_fkey FOREIGN KEY (parent_space_id) REFERENCES auth.spaces (id) ON DELETE CASCADE;

CREATE INDEX spaces_parent_space_id_index          ON auth.spaces (parent_space_id);
CREATE INDEX spaces_slug_index                     ON auth.spaces (slug);
CREATE INDEX spaces_is_publicly_browsable_index    ON auth.spaces (is_publicly_browsable);
CREATE INDEX spaces_created_by_index               ON auth.spaces (created_by);
CREATE INDEX spaces_created_at_index               ON auth.spaces (created_at);
CREATE INDEX spaces_updated_by_index               ON auth.spaces (updated_by);
CREATE INDEX spaces_updated_at_index               ON auth.spaces (updated_at);
CREATE INDEX spaces_deleted_by_index               ON auth.spaces (deleted_by);
CREATE INDEX spaces_deleted_at_index               ON auth.spaces (deleted_at);

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

    created_by INTEGER
        DEFAULT (NULLIF(CURRENT_SETTING('auth.user_id', TRUE), ''))::INTEGER
        REFERENCES auth.users(id) ON DELETE SET NULL,

    created_at  TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
CREATE INDEX space_users_user_id_index ON auth.space_users (user_id);
CREATE INDEX space_users_space_id_index ON auth.space_users (space_id);
CREATE INDEX space_users_role_index ON auth.space_users (role);
CREATE INDEX space_users_created_by_index ON auth.space_users (created_by);
CREATE INDEX space_users_created_at_index ON auth.space_users (created_at);

DROP FUNCTION IF EXISTS auth.create_user;
CREATE FUNCTION auth.create_user(
    _id                    INTEGER,
    _username              VARCHAR(100),
    _first_name            VARCHAR(150),
    _last_name             VARCHAR(150),
    _email                 VARCHAR(360),
    _password              VARCHAR(255),
    _is_active             BOOLEAN,
    _is_superuser          BOOLEAN,
    _spaces                JSONB
) RETURNS JSON
LANGUAGE 'plpgsql' SECURITY DEFINER
AS $$
DECLARE
    _response JSON;
BEGIN
    IF (
        (SESSION_USER = 'webapp') AND
        (_spaces IS NULL)
    ) THEN
        SELECT json_build_object(
            'status_code', 401,
            'status', 'space parameter must not be empty'
        ) INTO _response;

        RETURN _response;
    END IF;
    IF (
        (SESSION_USER = 'webapp') AND  -- TODO webapp is a bad hack, must be refactored
        (
            (
                SELECT
                    COUNT(*)
                FROM
                    JSONB_TO_RECORDSET(_spaces) AS _space_records(slug VARCHAR, role auth.roles)
                INNER JOIN auth.spaces
                        ON _space_records.slug = spaces.slug
                WHERE
                    spaces.invitation_required = FALSE
            ) = 0
        )
    ) THEN
        SELECT json_build_object(
            'status_code', 401,
            'status', 'Spaces do not exists or invitation required'
        ) INTO _response;

        RETURN _response;
    END IF;

    WITH _user AS (
        INSERT INTO auth.users
        (
            id,
            username,
            first_name,
            last_name,
            email,
            password,
            is_active,
            is_superuser
        )
        VALUES(
            COALESCE(_id, NEXTVAL('auth.users_id_seq')),
            TRIM(_username),
            TRIM(_first_name),
            TRIM(_last_name),
            LOWER(TRIM(_email)),
            utils.CRYPT(TRIM(_password), utils.GEN_SALT('bf', 8)),
            _is_active,
            FALSE
        ) RETURNING id
    ),
    _space_users AS (
        INSERT INTO auth.space_users
        (
            user_id,
            space_id,
            role
        )
        SELECT
            (SELECT id FROM _user LIMIT 1) AS user_id,
            spaces.id AS space_id,
            _space_records.role AS role
        FROM
            JSONB_TO_RECORDSET(_spaces) AS _space_records(slug VARCHAR, role auth.roles)
        INNER JOIN auth.spaces
                ON _space_records.slug = spaces.slug
        WHERE
            (SESSION_USER != 'webapp') OR -- TODO webapp is a bad hack, must be refactored
            (spaces.invitation_required = FALSE)
    ),
    _audit_events AS (
        INSERT INTO auth.audit_events (
            entity_type,
            entity_id,
            event_type,
            space_ids
        )
        VALUES(
            'auth.users',                   -- entity_type
            (SELECT id FROM _user LIMIT 1), -- entity_id
            'user.SIGNUP',                  -- event_type
            (
                SELECT
                    ARRAY_AGG(spaces.id)
                FROM
                    JSONB_TO_RECORDSET(_spaces) AS _space_records(slug VARCHAR, role auth.roles)
                INNER JOIN auth.spaces
                        ON _space_records.slug = spaces.slug
            )
        )
    )
    SELECT json_build_object(
        'status_code', 200,
        'status', 'User created with success',
        'user_id', (SELECT id FROM _user LIMIT 1)
    ) INTO _response;

    IF ((_response->>'user_id')::INTEGER > (SELECT COALESCE(pg_sequence_last_value('auth.users_id_seq'), 0))) THEN
        PERFORM SETVAL('auth.users_id_seq', (_response->>'user_id')::INTEGER, TRUE);
    END IF;

    RETURN _response;
END;
$$;

DROP TABLE IF EXISTS auth.invitations CASCADE;
CREATE TABLE auth.invitations (
    id          SERIAL PRIMARY KEY,
    invited_by  INTEGER DEFAULT NULL,
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

DROP FUNCTION IF EXISTS auth.fetch_invitation_by_token;
CREATE FUNCTION auth.fetch_invitation_by_token(
    _token TEXT
) RETURNS auth.invitations
LANGUAGE SQL SECURITY DEFINER
AS $$
    SELECT * FROM auth.invitations WHERE token=_token;
$$;


DROP TABLE IF EXISTS auth.space_invitations CASCADE;
CREATE TABLE auth.space_invitations (
    invitation_id  INTEGER NOT NULL REFERENCES auth.invitations(id),
    space_id       INTEGER NOT NULL REFERENCES auth.spaces(id),
    role           auth.roles NOT NULL
);
CREATE INDEX space_invitations_invitation_id_index ON auth.space_invitations (invitation_id);
CREATE INDEX space_invitations_space_id_index ON auth.space_invitations (space_id);
CREATE INDEX space_invitations_role_index ON auth.space_invitations (role);

DROP FUNCTION IF EXISTS auth.create_user_from_invitation;
CREATE FUNCTION auth.create_user_from_invitation(
    _id              INTEGER,
    _invitation_id   INTEGER,
    _username        VARCHAR(100),
    _first_name      VARCHAR(150),
    _last_name       VARCHAR(150),
    _email           VARCHAR(360),
    _password        VARCHAR(255),
    _is_active       BOOLEAN
) RETURNS JSON
LANGUAGE 'plpgsql' SECURITY DEFINER
AS $$
DECLARE
    _response JSON;
    _invitation auth.invitations;
BEGIN
    SELECT * INTO _invitation FROM auth.invitations WHERE id=_invitation_id;

    IF (_invitation IS NULL) THEN
        SELECT
            JSON_BUILD_OBJECT(
                'status_code', 404,
                'status', 'Invitation not found'
            ) INTO _response;

        RETURN _response;
    END IF;

    IF (_invitation.expires < NOW()) THEN
        SELECT
            JSON_BUILD_OBJECT(
                'status_code', 401,
                'status', 'Invitation expired'
            ) INTO _response;

        RETURN _response;
    END IF;

    IF (_invitation.user_id IS NOT NULL) THEN
        SELECT
            JSON_BUILD_OBJECT(
                'status_code', 401,
                'status', 'Invitation already used'
            ) INTO _response;

        RETURN _response;
    END IF;

    WITH _user AS (
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
            COALESCE(_id, NEXTVAL('auth.users_id_seq')),
            TRIM(_username),
            TRIM(_first_name),
            TRIM(_last_name),
            LOWER(TRIM(_email)),
            utils.CRYPT(TRIM(_password), utils.GEN_SALT('bf', 8)),
            _is_active
        ) RETURNING id
    ),
    _space_users AS (
        INSERT INTO auth.space_users
        (
            user_id,
            space_id,
            role
        )
        SELECT
            (SELECT id FROM _user LIMIT 1) AS user_id,
            space_invitations.space_id     AS space_id,
            space_invitations.role          AS role
        FROM
            auth.space_invitations
        WHERE
            space_invitations.invitation_id=_invitation_id
    ),
    _update_invitation AS (
        UPDATE auth.invitations
           SET user_id=(SELECT id FROM _user LIMIT 1)
         WHERE id=_invitation_id
    ),
    _audit_events AS (
        INSERT INTO auth.audit_events (
            entity_type,
            entity_id,
            event_type,
            space_ids
        )
        VALUES(
            'auth.users',                   -- entity_type
            (SELECT id FROM _user LIMIT 1), -- entity_id
            'user.INVITATION_SIGNUP',       -- event_type
            (
                SELECT
                    ARRAY_AGG(space_invitations.space_id)
                FROM
                    auth.space_invitations
                WHERE
                    space_invitations.invitation_id=_invitation_id
            )
        )
    )
    SELECT
        JSON_BUILD_OBJECT(
            'status_code', 200,
            'status', 'Use created',
            'user_id', (SELECT id FROM _user LIMIT 1)
        ) INTO _response;

    IF ((_response->>'user_id')::INTEGER > (SELECT COALESCE(pg_sequence_last_value('auth.users_id_seq'), 0))) THEN
        PERFORM SETVAL('auth.users_id_seq', (_response->>'user_id')::INTEGER, TRUE);
    END IF;

    RETURN _response;
END;
$$;


DROP FUNCTION IF EXISTS auth.open_session;
CREATE FUNCTION auth.open_session(_session_id UUID) RETURNS JSONB
LANGUAGE 'plpgsql' SECURITY DEFINER
AS $$
DECLARE
    _response JSONB;
BEGIN
    WITH _user AS (
        SELECT
            users.id,
            users.username,
            users.first_name,
            users.last_name,
            users.email,
            users.is_active,
            users.last_login,
            users.last_seen,
            users.date_joined,
            users.created_at,
            users.updated_at
        FROM
            auth.sessions
        INNER JOIN auth.users
            ON sessions.user_id = users.id
        WHERE
            sessions.id=_session_id
        LIMIT 1
    ),
    _impersonate_user AS (
        SELECT
            users.id,
            users.username,
            users.first_name,
            users.last_name,
            users.email,
            users.is_active,
            users.last_login,
            users.date_joined,
            users.created_at,
            users.updated_at
        FROM
            auth.sessions
        INNER JOIN auth.users
            ON sessions.impersonate_user_id = users.id
        WHERE
            sessions.id=_session_id
        LIMIT 1
    )
    SELECT
        JSON_BUILD_OBJECT(
            'user', (
                CASE
                    WHEN ((SELECT COUNT(*) FROM _impersonate_user) > 0) THEN
                        (SELECT ROW_TO_JSON(_impersonate_user) FROM _impersonate_user)
                    WHEN ((SELECT COUNT(*) FROM _user) > 0) THEN
                        (SELECT ROW_TO_JSON(_user) FROM _user)
                    ELSE
                        NULL
                END
            ),
            'impersonated_by', (
                CASE
                    WHEN ((SELECT COUNT(*) FROM _impersonate_user) > 0) THEN
                        (SELECT ROW_TO_JSON(_user) FROM _user)
                    ELSE
                        NULL
                END
            ),
            'spaces', (
                CASE
                    WHEN ((SELECT COUNT(*) FROM _impersonate_user) > 0) THEN
                        (SELECT ARRAY_AGG(space_id) FROM auth.space_users WHERE user_id = (SELECT id FROM _impersonate_user LIMIT 1))
                    WHEN ((SELECT COUNT(*) FROM _user) > 0) THEN
                        (SELECT ARRAY_AGG(space_id) FROM auth.space_users WHERE user_id = (SELECT id FROM _user LIMIT 1))
                    ELSE
                        NULL
                END
            ),
            'spaces_admin', (
                CASE
                    WHEN ((SELECT COUNT(*) FROM _impersonate_user) > 0) THEN
                        (
                            SELECT ARRAY_AGG(space_id)
                            FROM auth.space_users
                            WHERE (
                                (user_id = (SELECT id FROM _impersonate_user LIMIT 1)) AND
                                (role = ANY(ARRAY['space.ADMIN'::auth.roles, 'space.OWNER'::auth.roles]))
                            )
                        )
                    WHEN ((SELECT COUNT(*) FROM _user) > 0) THEN
                        (
                            SELECT ARRAY_AGG(space_id)
                            FROM auth.space_users
                            WHERE (
                                (user_id = (SELECT id FROM _user LIMIT 1)) AND
                                (role = ANY(ARRAY['space.ADMIN'::auth.roles, 'space.OWNER'::auth.roles]))
                            )
                        )
                    ELSE
                        NULL
                END
            )
        ) INTO _response
    ;

    IF (
        (_response->>'impersonated_by' IS NOT NULL) AND
        (
            COALESCE(
                (_response->'impersonated_by'->>'last_seen')::TIMESTAMP,
                DATE('1900-01-01')
            )
            < (NOW() - INTERVAL '2' MINUTE)
        )
    ) THEN
        UPDATE auth.users
        SET last_seen = NOW()
        WHERE
            (users.id = (_response->'impersonated_by'->>'id')::INTEGER);

        INSERT INTO auth.audit_events
            (
                author_id,
                entity_type,
                entity_id,
                event_type,
                space_ids
            )
            VALUES (
                (_response->'impersonated_by'->>'id')::INTEGER,
                'auth.users',
                (_response->'impersonated_by'->>'id')::INTEGER,
                'user.SEEN',
                (
                    SELECT ARRAY_AGG(space_id)
                    FROM auth.space_users
                    WHERE user_id = (_response->'impersonated_by'->>'id')::INTEGER
                )
            );
    ELSIF (
        (_response->>'user' IS NOT NULL) AND
        (
            COALESCE(
                (_response->'user'->>'last_seen')::TIMESTAMP,
                DATE('1900-01-01')
            )
            < (NOW() - INTERVAL '2' MINUTE)
        )
    ) THEN
        UPDATE auth.users
        SET last_seen = NOW()
        WHERE
            (users.id = (_response->'user'->>'id')::INTEGER);

        INSERT INTO auth.audit_events
            (
                author_id,
                entity_type,
                entity_id,
                event_type,
                space_ids
            )
            VALUES (
                (_response->'user'->>'id')::INTEGER,
                'auth.users',
                (_response->'user'->>'id')::INTEGER,
                'user.SEEN',
                (
                    SELECT ARRAY_AGG(space_id)
                    FROM auth.space_users
                    WHERE user_id = (_response->'user'->>'id')::INTEGER
                )
            );
    END IF;

    PERFORM
        SET_CONFIG(
            'auth.session_id',
            _session_id::VARCHAR,
            FALSE
        ),
        SET_CONFIG(
            'auth.user_id',
            _response->'user'->>'id'::VARCHAR,
            FALSE
        ),
        SET_CONFIG(
            'auth.impersonated_by_id',
            _response->'impersonated_by'->>'id'::VARCHAR,
            FALSE
        ),
        SET_CONFIG(
            'auth.spaces',
            (
                CASE
                    WHEN _response->>'spaces' IS NULL THEN
                        ''
                    ELSE
                        ARRAY_TO_STRING(
                            ARRAY(
                                SELECT JSONB_ARRAY_ELEMENTS(_response->'spaces')
                            ),
                            ','
                        )
                END
            ),
            FALSE
        ),
        SET_CONFIG(
            'auth.spaces_admin',
            (
                CASE
                    WHEN _response->>'spaces_admin' IS NULL THEN
                        ''
                    ELSE
                        ARRAY_TO_STRING(
                            ARRAY(
                                SELECT JSONB_ARRAY_ELEMENTS(_response->'spaces_admin')
                            ),
                            ','
                        )
                END
            ),
            FALSE
        );

    RETURN _response;
END;
$$;

DROP FUNCTION IF EXISTS auth.close_session;
CREATE FUNCTION auth.close_session() RETURNS VOID
LANGUAGE sql SECURITY DEFINER
AS $$
    SELECT
        SET_CONFIG(
            'auth.session_id',
            NULL,
            FALSE
        ),
        SET_CONFIG(
            'auth.user_id',
            NULL,
            FALSE
        ),
        SET_CONFIG(
            'auth.spaces',
            NULL,
            FALSE
        );
$$;

DROP TYPE IF EXISTS auth.entity_types;
CREATE TYPE auth.entity_types AS ENUM (
    'auth.users',
    'auth.spaces',
    'auth.space_users',
    'auth.invitations',
    'auth.space_invitations',
    'main.resource_a',
    'main.resource_b'
);

DROP TYPE IF EXISTS auth.audit_event_types;
CREATE TYPE auth.audit_event_types AS ENUM (
    'user.SEEN',
    'user.LOGIN_SUCCESS',
    'user.LOGIN_FAILED_USER_DEACTIVATE',
    'user.LOGIN_FAILED_USER_NOT_FOUND',
    'user.LOGIN_FAILED_BAD_PASSWORD',
    'user.SIGNUP',
    'user.INVITATION_SIGNUP',
    'user.LOGOUT',
    'user.ENTER_IMPERSONATE',
    'user.EXIT_IMPERSONATE',
    'user.RESET_PASSWORD_ASKED',
    'user.PASSWORD_CHANGED',
    'CREATED',
    'DESTROYED',
    'UPDATED',
    'CLOSED'
);


DROP TABLE IF EXISTS auth.audit_events CASCADE;
CREATE TABLE auth.audit_events (
    id                     SERIAL PRIMARY KEY,

    author_id INTEGER
        DEFAULT (NULLIF(CURRENT_SETTING('auth.user_id', TRUE), ''))::INTEGER
        REFERENCES auth.users(id) ON DELETE SET NULL,

    created_at             TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    entity_type            auth.entity_types DEFAULT NULL,
    entity_id              INTEGER DEFAULT NULL,
    space_ids              INTEGER[] DEFAULT NULL,

    ipv4_address VARCHAR
        DEFAULT (NULLIF(CURRENT_SETTING('auth.ipv4_address', TRUE), '')),

    ipv6_address VARCHAR
        DEFAULT (NULLIF(CURRENT_SETTING('auth.ipv6_address', TRUE), '')),

    event_type             auth.audit_event_types,
    details                JSONB DEFAULT NULL
);
CREATE INDEX audit_events_author_id_index    ON auth.audit_events (author_id);
CREATE INDEX audit_events_created_at_index   ON auth.audit_events (created_at);
CREATE INDEX audit_events_entity_type_index  ON auth.audit_events (entity_type);
CREATE INDEX audit_events_entity_id_index    ON auth.audit_events (entity_id);
CREATE INDEX audit_events_space_ids_index    ON auth.audit_events USING GIST (space_ids utils.gist__int_ops);
CREATE INDEX audit_events_ipv4_address_index ON auth.audit_events (ipv4_address);
CREATE INDEX audit_events_ipv6_address_index ON auth.audit_events (ipv6_address);
CREATE INDEX audit_events_event_type_index   ON auth.audit_events (event_type);

DROP FUNCTION IF EXISTS auth.space_after_insert_row;
CREATE FUNCTION auth.space_after_insert_row() RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO auth.audit_events
    (
        entity_type,
        entity_id,
        event_type,
        space_ids
    )
    VALUES (
        'auth.spaces',
        NEW.id,
        'CREATED',
        ARRAY[NEW.id]
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


DROP FUNCTION IF EXISTS auth.impersonate;
CREATE FUNCTION auth.impersonate(_username VARCHAR) RETURNS JSON
LANGUAGE 'plpgsql' SECURITY DEFINER
AS $$
DECLARE
    _user_id INTEGER;
BEGIN
    WITH _my_admin_or_owner_spaces AS (
        SELECT space_id
        FROM auth.space_users
        WHERE
            (user_id = CURRENT_SETTING('auth.user_id', TRUE)::INTEGER) AND
            (role = ANY(ARRAY['space.ADMIN', 'space.OWNER']::auth.roles[]))
    )
    SELECT
        user_id INTO _user_id
    FROM
        auth.space_users
    INNER JOIN auth.users
            ON space_users.user_id = users.id
    INNER JOIN _my_admin_or_owner_spaces
            ON _my_admin_or_owner_spaces.space_id = space_users.space_id
         WHERE users.username = _username;

    IF (_user_id IS NULL) THEN
        RETURN (
            SELECT json_build_object(
                'status_code', 401,
                'status', 'Either the user ' || _username || 'does not exist, or you are not authorized to impersonate him.'
            )
        );
    ELSE
        UPDATE auth.sessions
        SET impersonate_user_id=_user_id
        WHERE id=CURRENT_SETTING('auth.session_id', TRUE)::UUID;

        INSERT INTO auth.audit_events
            (
                entity_type,
                entity_id,
                event_type,
                space_ids
            )
            VALUES(
                'auth.users',
                _user_id,
                'user.ENTER_IMPERSONATE',
                (
                    SELECT ARRAY_AGG(space_id)
                    FROM auth.space_users
                    WHERE user_id = (NULLIF(CURRENT_SETTING('auth.user_id', TRUE), ''))::INTEGER
                )
            );

        RETURN (
            SELECT json_build_object(
                'status_code', 200,
                'status', 'You impersonate ' || _username || ' with success'
            )
        );
    END IF;
END;
$$;

DROP FUNCTION IF EXISTS auth.exit_impersonate;
CREATE FUNCTION auth.exit_impersonate() RETURNS VOID
LANGUAGE sql SECURITY DEFINER
AS $$
    UPDATE auth.sessions
       SET impersonate_user_id=NULL
     WHERE id=CURRENT_SETTING('auth.session_id', TRUE)::UUID;

    INSERT INTO auth.audit_events
        (
            author_id,
            entity_type,
            entity_id,
            event_type,
            space_ids
        )
        VALUES(
            (NULLIF(CURRENT_SETTING('auth.impersonated_by_id', TRUE), ''))::INTEGER,
            'auth.users',
            (NULLIF(CURRENT_SETTING('auth.user_id', TRUE), ''))::INTEGER,
            'user.EXIT_IMPERSONATE',
            (
                SELECT ARRAY_AGG(space_id)
                FROM auth.space_users
                WHERE user_id = (NULLIF(CURRENT_SETTING('auth.user_id', TRUE), ''))::INTEGER
            )
        );
$$;

DROP FUNCTION IF EXISTS auth.logout;
CREATE FUNCTION auth.logout() RETURNS VOID
LANGUAGE SQL
AS $$
    INSERT INTO auth.audit_events
    (
        entity_type,
        entity_id,
        event_type,
        space_ids
    )
    VALUES(
        'auth.users',
        (NULLIF(CURRENT_SETTING('auth.user_id', TRUE), ''))::INTEGER,
        'user.LOGOUT',
        (
            SELECT ARRAY_AGG(space_id)
            FROM auth.space_users
            WHERE user_id = (NULLIF(CURRENT_SETTING('auth.user_id', TRUE), ''))::INTEGER
        )
    );
$$;

DROP FUNCTION IF EXISTS auth.anonymous_user_ask_reset_password;
CREATE FUNCTION auth.anonymous_user_ask_reset_password(_email VARCHAR) RETURNS JSON
LANGUAGE 'plpgsql' SECURITY DEFINER
AS $$
DECLARE
    _result JSON;
BEGIN
    SELECT
        JSONB_BUILD_OBJECT(
            'id', users.id,
            'email', users.email
        ) INTO _result
    FROM auth.users
    WHERE email=_email;

    IF (_result->'id' IS NOT NULL) THEN
        INSERT INTO auth.audit_events
            (
                entity_type,
                entity_id,
                event_type,
                space_ids
            )
            VALUES(
                'auth.users',
                (_result->>'id')::INTEGER,
                'user.RESET_PASSWORD_ASKED',
                (
                    SELECT ARRAY_AGG(space_id)
                    FROM auth.space_users
                    WHERE user_id = (_result->>'id')::INTEGER
                )
            );
    END IF;

    RETURN _result;
END;
$$;

DROP FUNCTION IF EXISTS auth.anonymous_user_change_password;
CREATE FUNCTION auth.anonymous_user_change_password(_email VARCHAR, _password VARCHAR) RETURNS JSON
LANGUAGE 'plpgsql' SECURITY DEFINER
AS $$
DECLARE
    _user_id INTEGER;
BEGIN
    UPDATE auth.users
        SET password=utils.CRYPT(TRIM(_password), utils.GEN_SALT('bf', 8))
        WHERE email=_email
        RETURNING id INTO _user_id;

    IF (_user_id IS NOT NULL) THEN
        INSERT INTO auth.audit_events
            (
                entity_type,
                entity_id,
                event_type,
                space_ids
            )
            VALUES(
                'auth.users',
                _user_id,
                'user.PASSWORD_CHANGED',
                (
                    SELECT ARRAY_AGG(space_id)
                    FROM auth.space_users
                    WHERE user_id = _user_id
                )
            );

            RETURN (
                SELECT json_build_object(
                    'status_code', 200,
                    'status', 'Password changed'
                )
            );
    END IF;

    RETURN (
        SELECT json_build_object(
            'status_code', 404,
            'status', 'User not found'
        )
    );
END;
$$;


CREATE TRIGGER space_after_insert
    AFTER INSERT ON auth.spaces
    FOR EACH ROW
    EXECUTE FUNCTION auth.space_after_insert_row();

-- Main section

CREATE SCHEMA IF NOT EXISTS main;

DROP TABLE IF EXISTS main.resource_a CASCADE;
CREATE TABLE main.resource_a (
    id                     SERIAL PRIMARY KEY,
    space_id               INTEGER NOT NULL,
    slug                   VARCHAR(12) NOT NULL, -- contains nanoid
    title                  VARCHAR(100) NOT NULL,
    content                TEXT NOT NULL,

    created_at             TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    created_by INTEGER
        DEFAULT (NULLIF(CURRENT_SETTING('auth.user_id', TRUE), ''))::INTEGER
        REFERENCES auth.users(id) ON DELETE SET NULL,

    updated_at             TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_by             INTEGER DEFAULT NULL REFERENCES auth.users(id) ON DELETE SET NULL,

    deleted_at             TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    deleted_by             INTEGER DEFAULT NULL REFERENCES auth.users(id) ON DELETE SET NULL,

    CONSTRAINT fk_space_id FOREIGN KEY (space_id) REFERENCES auth.spaces (id) ON DELETE CASCADE
);
CREATE INDEX resource_a_space_id_index   ON main.resource_a (space_id);
CREATE INDEX resource_a_slug_index       ON main.resource_a (slug);
CREATE INDEX resource_a_created_at_index ON main.resource_a (created_at);
CREATE INDEX resource_a_created_by_index ON main.resource_a (created_by);
CREATE INDEX resource_a_updated_at_index ON main.resource_a (updated_at);
CREATE INDEX resource_a_updated_by_index ON main.resource_a (updated_by);
CREATE INDEX resource_a_deleted_at_index ON main.resource_a (deleted_at);
CREATE INDEX resource_a_deleted_by_index ON main.resource_a (deleted_by);

DROP FUNCTION IF EXISTS main.resource_a_after_insert_row;
CREATE FUNCTION main.resource_a_after_insert_row() RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO auth.audit_events
    (
        entity_type,
        entity_id,
        event_type,
        space_ids
    )
    VALUES (
        'main.resource_a',
        NEW.id,
        'CREATED',
        ARRAY[NEW.space_id]
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER resource_a_after_insert
    AFTER INSERT ON main.resource_a
    FOR EACH ROW
    EXECUTE FUNCTION main.resource_a_after_insert_row();

DROP TABLE IF EXISTS main.resource_b CASCADE;
CREATE TABLE main.resource_b (
    id                     SERIAL PRIMARY KEY,
    space_id               INTEGER NOT NULL,
    slug                   VARCHAR(12) NOT NULL, -- contains nanoid
    title                  VARCHAR(100) NOT NULL,
    content                TEXT NOT NULL,

    created_at             TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    created_by INTEGER
        DEFAULT (NULLIF(CURRENT_SETTING('auth.user_id', TRUE), ''))::INTEGER
        REFERENCES auth.users(id) ON DELETE SET NULL,

    updated_at             TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_by             INTEGER DEFAULT NULL REFERENCES auth.users(id) ON DELETE SET NULL,

    deleted_at             TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    deleted_by             INTEGER DEFAULT NULL REFERENCES auth.users(id) ON DELETE SET NULL,

    CONSTRAINT fk_space_id FOREIGN KEY (space_id) REFERENCES auth.spaces (id) ON DELETE CASCADE
);
CREATE INDEX resource_b_space_id_index  ON main.resource_b (space_id);
CREATE INDEX resource_b_slug_index       ON main.resource_b (slug);
CREATE INDEX resource_b_created_at_index ON main.resource_b (created_at);
CREATE INDEX resource_b_created_by_index ON main.resource_b (created_by);
CREATE INDEX resource_b_updated_at_index ON main.resource_b (updated_at);
CREATE INDEX resource_b_updated_by_index ON main.resource_b (updated_by);
CREATE INDEX resource_b_deleted_at_index ON main.resource_b (deleted_at);
CREATE INDEX resource_b_deleted_by_index ON main.resource_b (deleted_by);

DROP FUNCTION IF EXISTS main.resource_b_after_insert_row;
CREATE FUNCTION main.resource_b_after_insert_row() RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO auth.audit_events
    (
        entity_type,
        entity_id,
        event_type,
        space_ids
    )
    VALUES (
        'main.resource_b',
        NEW.id,
        'CREATED',
        ARRAY[NEW.space_id]
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER resource_b_after_insert
    AFTER INSERT ON main.resource_b
    FOR EACH ROW
    EXECUTE FUNCTION main.resource_b_after_insert_row();


-- Setup Row-Level Security (https://www.postgresql.org/docs/15/ddl-rowsecurity.html)

SELECT utils.create_role_if_not_exists('application_user');
COMMENT ON ROLE application_user IS
    'The "application_user" role is to be used by the web application,'
    'because it enables communication with PostgreSQL in a session that'
    'applies user permissions rules to resources (POLICY, RLS features)';

DO $$ BEGIN
    IF NOT EXISTS (SELECT * FROM pg_roles WHERE rolname = 'webapp') THEN
        CREATE ROLE webapp LOGIN PASSWORD 'password' IN ROLE application_user;
        GRANT CONNECT ON DATABASE myapp TO webapp;
    END IF;
END $$;

DROP FUNCTION IF EXISTS auth.get_entity_details;
CREATE OR REPLACE FUNCTION auth.get_entity_details(
    entity_type auth.entity_types,
    entity_id INTEGER
) RETURNS JSONB
LANGUAGE SQL
AS $$
    SELECT
        CASE
            WHEN entity_type = 'auth.users' THEN
                (
                    SELECT
                        JSONB_BUILD_OBJECT(
                            'caption', username,
                            'space_title', spaces.title,
                            'space_id', spaces.id
                        )
                    FROM auth.users
                    LEFT JOIN auth.space_users
                           ON users.id = space_users.user_id
                    LEFT JOIN auth.spaces
                           ON space_users.space_id = spaces.id
                    WHERE users.id=entity_id
                    LIMIT 1
                )
            WHEN entity_type = 'auth.invitations' THEN
                (
                    SELECT
                        JSONB_BUILD_OBJECT(
                            'caption', invitations.email,
                            'space_title', spaces.title,
                            'space_id', spaces.id
                        )
                    FROM auth.invitations
                    LEFT JOIN auth.space_invitations
                           ON invitations.id = space_invitations.invitation_id
                    LEFT JOIN auth.spaces
                           ON space_invitations.space_id = spaces.id
                    WHERE invitations.id=entity_id
                    LIMIT 1
                )
            WHEN entity_type = 'main.resource_a' THEN
                (
                    SELECT
                        JSONB_BUILD_OBJECT(
                            'caption', resource_a.title,
                            'space_title', spaces.title,
                            'space_id', spaces.id
                        )
                    FROM main.resource_a
                    LEFT JOIN auth.spaces
                           ON resource_a.space_id = spaces.id
                    WHERE resource_a.id=entity_id
                    LIMIT 1
                )
            WHEN entity_type = 'main.resource_b' THEN
                (
                    SELECT
                        JSONB_BUILD_OBJECT(
                            'caption', resource_b.title,
                            'space_title', spaces.title,
                            'space_id', spaces.id
                        )
                    FROM main.resource_b
                    LEFT JOIN auth.spaces
                           ON resource_b.space_id = spaces.id
                    WHERE resource_b.id=entity_id
                    LIMIT 1
                )
        END
    ;
$$;

CREATE VIEW auth.view_audit_events
    WITH (security_invoker=TRUE)
    AS SELECT
        TO_CHAR(audit_events.created_at, 'YYYY-MM-dd HH24:MI:SS') AS created_at,
        (
            CASE
                WHEN users.username IS NULL THEN
                    'Anonymous'
                ELSE
                    users.username
            END
        ) AS author_username,
        audit_events.author_id AS author_id,
        audit_events.event_type,
        audit_events.entity_type,
        audit_events.entity_id,
        (
            auth.get_entity_details(
                audit_events.entity_type,
                audit_events.entity_id
            )
        ) AS entity_details,

        audit_events.ipv4_address,
        audit_events.ipv6_address
    FROM
        auth.audit_events
    LEFT JOIN auth.users
           ON audit_events.author_id=users.id
    ORDER BY created_at DESC;

GRANT ALL ON SCHEMA utils TO application_user;
GRANT ALL ON SCHEMA auth TO application_user;
GRANT ALL ON SCHEMA main TO application_user;
GRANT ALL ON ALL TABLES IN SCHEMA auth TO application_user;
GRANT ALL ON ALL SEQUENCES IN SCHEMA auth TO application_user;
GRANT ALL ON ALL TABLES IN SCHEMA main TO application_user;

ALTER TABLE auth.users             ENABLE ROW LEVEL SECURITY;
ALTER TABLE auth.sessions          ENABLE ROW LEVEL SECURITY;
ALTER TABLE auth.invitations       ENABLE ROW LEVEL SECURITY;
ALTER TABLE auth.space_invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE auth.spaces            ENABLE ROW LEVEL SECURITY;
ALTER TABLE auth.space_users       ENABLE ROW LEVEL SECURITY;
ALTER TABLE auth.audit_events      ENABLE ROW LEVEL SECURITY;

ALTER TABLE main.resource_a ENABLE ROW LEVEL SECURITY;
ALTER TABLE main.resource_b ENABLE ROW LEVEL SECURITY;


CREATE POLICY session_read
    ON auth.sessions
    AS PERMISSIVE
    FOR SELECT
    TO application_user
    USING(
        user_id = NULLIF(CURRENT_SETTING('auth.user_id', TRUE), '')::INTEGER
    );

CREATE POLICY space_read
    ON auth.spaces
    AS PERMISSIVE
    FOR SELECT
    TO application_user
    USING(
        (is_publicly_browsable IS TRUE) OR
        (
            id = ANY(
                REGEXP_SPLIT_TO_ARRAY(
                    NULLIF(CURRENT_SETTING('auth.spaces', TRUE), ''),
                    ','
                )::INTEGER[]
            )
        )
    );

CREATE POLICY space_users_read
    ON auth.space_users
    AS PERMISSIVE
    FOR SELECT
    TO application_user
    USING(
        space_id = ANY(
            REGEXP_SPLIT_TO_ARRAY(
                NULLIF(CURRENT_SETTING('auth.spaces', TRUE), ''),
                ','
            )::INTEGER[]
        )
    );

CREATE POLICY user_read
    ON auth.users
    AS PERMISSIVE
    FOR SELECT
    TO application_user
    USING(
        id = ANY(
            SELECT user_id
            FROM auth.space_users
            WHERE
                space_id = ANY(
                    REGEXP_SPLIT_TO_ARRAY(
                        NULLIF(CURRENT_SETTING('auth.spaces', TRUE), ''),
                        ','
                    )::INTEGER[]
                )
        )
    );

CREATE POLICY space_invitation_read
    ON auth.space_invitations
    AS PERMISSIVE
    FOR SELECT
    TO application_user
    USING(
        space_id = ANY(
            REGEXP_SPLIT_TO_ARRAY(
                NULLIF(CURRENT_SETTING('auth.spaces', TRUE), ''),
                ','
            )::INTEGER[]
        )
    );

CREATE POLICY space_invitation_write
    ON auth.space_invitations
    AS PERMISSIVE
    FOR INSERT
    TO application_user
    WITH CHECK (
        space_invitations.space_id=ANY(
            SELECT
                space_id
            FROM
                auth.space_users
            WHERE
                (user_id=NULLIF(CURRENT_SETTING('auth.user_id', TRUE), '')::INTEGER) AND
                (role IN ('space.ADMIN', 'space.OWNER'))
        )
    );

CREATE POLICY invitation_read
    ON auth.invitations
    AS PERMISSIVE
    FOR ALL
    TO application_user
    USING(
        (invitations.invited_by = (NULLIF(CURRENT_SETTING('auth.user_id', TRUE), ''))::INTEGER) OR
        exists(
            SELECT *
            FROM auth.space_invitations
            WHERE
                (
                    space_id = ANY(
                        REGEXP_SPLIT_TO_ARRAY(
                            NULLIF(CURRENT_SETTING('auth.spaces', TRUE), ''),
                            ','
                        )::INTEGER[]
                    )
                ) AND (
                    space_invitations.invitation_id = invitations.id
                )
        )
    );

CREATE POLICY invitation_write
    ON auth.invitations
    AS PERMISSIVE
    FOR INSERT
    TO application_user
    WITH CHECK (
        invitations.invited_by=(NULLIF(CURRENT_SETTING('auth.user_id', TRUE), ''))::INTEGER
    );

CREATE POLICY audit_events_read
    ON auth.audit_events
    AS PERMISSIVE
    FOR SELECT
    TO application_user
    USING(
        (
            REGEXP_SPLIT_TO_ARRAY(
                NULLIF(CURRENT_SETTING('auth.spaces_admin', TRUE), ''),
                ','
            )::INTEGER[]
        ) && space_ids
    );

CREATE POLICY audit_events_write
    ON auth.audit_events
    AS PERMISSIVE
    FOR INSERT
    TO application_user
    WITH CHECK (
        (audit_events.author_id IS NULL) OR
        (audit_events.author_id = (NULLIF(CURRENT_SETTING('auth.user_id', TRUE), ''))::INTEGER)
    );

CREATE POLICY resource_a_read
    ON main.resource_a
    AS PERMISSIVE
    FOR SELECT
    TO application_user
    USING(
        space_id = ANY(
            REGEXP_SPLIT_TO_ARRAY(
                NULLIF(CURRENT_SETTING('auth.spaces', TRUE), ''),
                ','
            )::INTEGER[]
        )
    );
