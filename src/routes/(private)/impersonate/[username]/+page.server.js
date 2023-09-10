import { redirect } from "@sveltejs/kit";

export async function GET({locals, params, url}) {
    const result = await locals.sql`
        SELECT auth.impersonate(${params.username})
    `;
    if (result[0].impersonate.status_code === 200) {
        throw redirect(
            302,
            url.searchParams.get("redirect") || "/"
        );
    } else {
        return result[0].impersonate;
    }
};
