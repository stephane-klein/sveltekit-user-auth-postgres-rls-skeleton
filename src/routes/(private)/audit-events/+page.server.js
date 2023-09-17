export async function load({ locals }) {
    console.log(
        await locals.sql`
            SELECT
                *
            FROM
                auth.users
        `
    );
    console.log(
        await locals.sql`
            SELECT
                TO_CHAR(audit_events.created_at, 'YYYY-MM-dd') AS created_at,
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
                audit_events.entity_id
            FROM
                auth.audit_events
            LEFT JOIN auth.users
                   ON audit_events.author_id=users.id
            ORDER BY created_at DESC
        `
    );
    return {
        audit_events: await locals.sql`
            SELECT
                TO_CHAR(audit_events.created_at, 'YYYY-MM-dd') AS created_at,
                (
                    CASE
                        WHEN users.username IS NULL THEN
                            'Anonymous'
                        ELSE
                            users.username
                    END
                ) AS author_username,
                audit_events.event_type,
                audit_events.entity_type,
                audit_events.entity_id
            FROM
                auth.audit_events
            LEFT JOIN auth.users
                   ON audit_events.author_id=users.id
            ORDER BY created_at DESC
        `
    };
}
