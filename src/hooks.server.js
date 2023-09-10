import sql from "$lib/server/db.js";

export async function handle({ event, resolve }) {
    // See https://github.com/porsager/postgres/pull/667/files
    event.locals.sql = await sql.reserve();

    // Data transferred to the browser
    event.locals.client = {};

    const sessionId = event.cookies.get("session");

    if (sessionId) {
        await event.locals.sql`
            SET SESSION ROLE TO application_user;
        `;
        await event.locals.sql`
            SELECT auth.open_session(${sessionId});
        `;
        try {
            const rows = await event.locals.sql`
                WITH _user AS (
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
                        ON sessions.user_id = users.id
                    WHERE
                        sessions.id=${sessionId}
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
                        sessions.id=${sessionId}
                    LIMIT 1
                ),
                _spaces AS (
                    SELECT
                        spaces.id        AS id,
                        spaces.slug      AS slug,
                        spaces.title     AS title,
                        space_users.role AS role
                    FROM _user
                    LEFT JOIN auth.space_users
                           ON space_users.user_id=_user.id
                    LEFT JOIN auth.spaces
                           ON space_users.space_id=spaces.id
                ),
                _current_space AS (
                    SELECT *
                    FROM _spaces
                    WHERE _spaces.slug=${event.params?.space_slug || null}
                    LIMIT 1
                )
                SELECT
                    (SELECT ROW_TO_JSON(_user) FROM _user) AS user,
                    (SELECT ROW_TO_JSON(_impersonate_user) FROM _impersonate_user) AS impersonate_user,
                    (SELECT ARRAY_AGG(ROW_TO_JSON(_spaces)) FROM _spaces)::JSONB[] AS spaces,
                    (SELECT ROW_TO_JSON(_current_space) FROM _current_space) AS current_space
            `;
            if (rows?.length > 0) {
                event.locals.session_id = sessionId;
                if (rows[0].impersonate_user === null) {
                    event.locals.client.impersonated = false;
                    event.locals.client.user = rows[0].user;
                    event.locals.client.impersonated_by = null;
                } else {
                    event.locals.client.impersonated = true;
                    event.locals.client.user = rows[0].impersonate_user;
                    event.locals.client.impersonated_by = rows[0].user;
                }
                event.locals.client.spaces = rows[0].spaces;
                event.locals.client.current_space = rows[0].current_space;
            }
        } catch (e) {
            console.log(e);
        }
    }
    if (!event.locals.client.user) event.cookies.delete("session");

    const response = await resolve(event);
    await event.locals.sql`
        SELECT auth.close_session();
    `;
    event.locals.sql.release();
    return response;
}
