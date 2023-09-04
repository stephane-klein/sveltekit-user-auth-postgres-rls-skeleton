import { redirect, fail } from "@sveltejs/kit";
import sql from "$lib/server/db.js";

export const actions = {
    default: async({ request, cookies }) => {
        const data = await request.formData();
        const authenticateResult = (await sql`
            SELECT auth.authenticate(
                input_username=>'',
                input_email=>${data.get("email")},
                input_password=>${data.get("password")}
            )
        `)[0]?.authenticate;
        if (authenticateResult.session_id !== null) {
            cookies.set("session", authenticateResult?.session_id, { path: "/" });
            throw redirect(302, "/");
        } else {
            cookies.delete("session");
            return fail(400, {
                email: data.get("email"),
                error: authenticateResult.status
            });
        }
    }
};
