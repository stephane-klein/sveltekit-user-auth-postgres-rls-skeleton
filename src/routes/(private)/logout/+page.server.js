import { redirect } from "@sveltejs/kit";

export async function load({ locals, cookies }) {
    await locals.sql`
        SELECT auth.logout()
    `;
    cookies.set("session", "", { path: "/" });
    throw redirect(302, "/");
}
