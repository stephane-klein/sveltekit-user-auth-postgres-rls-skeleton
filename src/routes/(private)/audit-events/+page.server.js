export async function load({ locals }) {
    return {
        audit_events: await locals.sql`
            SELECT
                TO_CHAR(audit_events.created_at, 'YYYY-MM-dd') AS created_at,
                users.username AS author_username,
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
