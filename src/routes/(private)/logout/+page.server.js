import { redirect } from "@sveltejs/kit";

export async function load({ cookies }) {
    cookies.set("session", "", { path: "/" });
    throw redirect(302, "/");
}
