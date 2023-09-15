import { redirect, fail } from "@sveltejs/kit";

export const actions = {
    default: async({ locals, request, cookies }) => {
        const data = await request.formData();
        const authenticateResult = (await locals.sql`
            SELECT auth.authenticate(
                input_username=>'',
                input_email=>${data.get("email")},
                input_password=>${data.get("password")}
            )
        `)[0]?.authenticate;
        if (authenticateResult.status_code === 200) {
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
