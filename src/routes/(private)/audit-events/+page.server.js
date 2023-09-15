export async function load({ locals }) {
    return {
        audit_events: await locals.sql`
            SELECT * FROM auth.view_audit_events
        `
    };
}
