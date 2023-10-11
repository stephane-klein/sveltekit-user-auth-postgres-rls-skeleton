import sql from "$lib/server/db.js";

export async function handle({ event, resolve }) {
    // See https://github.com/porsager/postgres/pull/667/files
    // await sql.reserve() have a bug, it didn't execute auto fetching of array types
    // then, I call this query to force auto fetching of array types loading
    await sql`SELECT 1`;
    event.locals.sql = await sql.reserve();

    // Data transferred to the browser
    event.locals.client = {};

    const sessionId = event.cookies.get("session");

    if (sessionId) {
        const openSessionResult = (await event.locals.sql`
            SELECT auth.open_session(${sessionId});
        `)[0].open_session;

        if (openSessionResult.user) {
            event.locals.session_id = sessionId;
            event.locals.client.user = openSessionResult.user;
            event.locals.client.impersonated_by = openSessionResult.impersonated_by;

            const result = (await event.locals.sql`
                WITH _spaces AS (
                    SELECT
                        spaces.id        AS id,
                        spaces.slug      AS slug,
                        spaces.title     AS title,
                        space_users.role AS role
                    FROM auth.space_users
                    INNER JOIN auth.spaces
                           ON space_users.space_id=spaces.id
                    WHERE
                        space_users.user_id=${event.locals.client.user.id}
                ),
                _current_space AS (
                    SELECT *
                    FROM _spaces
                    WHERE _spaces.slug=${event.params?.space_slug || null}
                    LIMIT 1
                )
                SELECT
                    (SELECT ARRAY_AGG(ROW_TO_JSON(_spaces)) FROM _spaces)::JSONB[] AS spaces,
                    (SELECT ROW_TO_JSON(_current_space) FROM _current_space) AS current_space
            `)[0];

            event.locals.client.spaces = result.spaces;
            event.locals.client.current_space = result.current_space;
        } else {
            event.cookies.delete("session");
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
