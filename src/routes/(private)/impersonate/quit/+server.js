import { redirect } from "@sveltejs/kit";

export async function GET({locals, url}) {
    await locals.sql`
        UPDATE auth.sessions
           SET impersonate_user_id=NULL
         WHERE id=${locals.session_id}
    `;
    throw redirect(
        302,
        url.searchParams.get("redirect") || "/"
    );
};
