import { redirect } from "@sveltejs/kit";

export async function GET({locals, url}) {
    await locals.sql`
        SELECT auth.exit_impersonate()
    `;
    throw redirect(
        302,
        url.searchParams.get("redirect") || "/"
    );
};
