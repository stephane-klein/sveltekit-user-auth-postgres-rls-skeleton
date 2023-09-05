import { redirect } from "@sveltejs/kit";
import sql from "$lib/server/db.js";

export async function GET({locals, params, url}) {
    await sql`
        UPDATE auth.sessions
        SET impersonate_user_id=(
            SELECT
                id
            FROM
                auth.users
            WHERE username=${params.username}
        )
        WHERE id=${locals.session_id}
    `;
    throw redirect(
        302,
        url.searchParams.get("redirect") || "/"
    );
};
