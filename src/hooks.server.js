import sql from "$lib/server/db.js";

export async function handle({ event, resolve }) {
    const sessionId = event.cookies.get("session");

    if (sessionId) {
        try {
            const rows = await sql`
                WITH _user AS (
                    SELECT
                        users.id,
                        users.username,
                        users.first_name,
                        users.last_name,
                        users.email,
                        users.is_staff,
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
                        users.is_staff,
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
                )
                SELECT
                    (SELECT ROW_TO_JSON(_user) FROM _user) AS user,
                    (SELECT ROW_TO_JSON(_impersonate_user) FROM _impersonate_user) AS impersonate_user
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
            }
        } catch (e) {
            console.log(e);
        }
    }
    if (!event.locals.user) event.cookies.delete("session");

    const response = await resolve(event);
    return response;
}
