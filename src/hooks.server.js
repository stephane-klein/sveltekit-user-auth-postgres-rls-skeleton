import sql from "$lib/server/db.js";

export async function handle({ event, resolve }) {
    console.log(event.params);
    const sessionId = event.cookies.get("session");

    if (sessionId) {
        console.log(event);
        try {
            const rows = await sql`
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
                    (SELECT ARRAY_AGG(ROW_TO_JSON(_spaces)) FROM _spaces) AS spaces,
                    (SELECT ROW_TO_JSON(_current_space) FROM _current_space) AS current_space
            `;
            if (rows?.length > 0) {
                event.locals.session_id = sessionId;
                if (rows[0].impersonate_user === null) {
                    event.locals.impersonated = false;
                    event.locals.user = rows[0].user;
                    event.locals.impersonated_by = null;
                } else {
                    event.locals.impersonated = true;
                    event.locals.user = rows[0].impersonate_user;
                    event.locals.impersonated_by = rows[0].user;
                }
                event.locals.spaces = rows[0].spaces;
                event.locals.current_space = rows[0].current_space;
                console.log(event.locals);
            }
        } catch (e) {
            console.log(e);
        }
    }
    if (!event.locals.user) event.cookies.delete("session");

    const response = await resolve(event);
    return response;
}
