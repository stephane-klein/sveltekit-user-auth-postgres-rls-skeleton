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
            SELECT * FROM auth.view_audit_events
        `
    );
    return {
        audit_events: await locals.sql`
            SELECT * FROM auth.view_audit_events
        `
    };
}
