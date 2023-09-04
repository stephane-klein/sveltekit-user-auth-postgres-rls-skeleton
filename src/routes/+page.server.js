import sql from "$lib/server/db.js";

export async function load() {
    return {
        users: (
            await sql`
                SELECT
                    users.id AS id,
                    users.username AS username,
                    users.email AS email
                FROM auth.users
            `
        )
    };
}
