import sql from "$lib/server/db.js";

export async function load() {
    return {
        invitations: (
            await sql`
                SELECT
                    id,
                    email,
                    invited_by,
                    expires,
                    user_id
                FROM
                    auth.invitations
            `
        )
    };
}
