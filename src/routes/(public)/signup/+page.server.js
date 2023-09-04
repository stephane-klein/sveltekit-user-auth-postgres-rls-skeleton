import { redirect } from "@sveltejs/kit";
import sql from "$lib/server/db.js";

export async function load({ locals, url }) {
    if (locals.user) {
        throw redirect(302, "/");
    }

    if (url.searchParams.get("token")) {
        const invitation = (await sql`SELECT email, expires, user_id FROM auth.invitations WHERE token=${url.searchParams.get("token")}`)?.[0];
        if (!invitation) {
            return {
                error: "Error: invalid invitation token"
            };
        }
        if (invitation.user_id) {
            return {
                error: "Error: invitation already used"
            };
        }
        if (invitation.expires < Date.now()) {
            return {
                error: "Error: Token expired"
            };
        }

        return {
            email: invitation.email,
            token: url.searchParams.get("token")
        };
    } else if (process.env.INVITATION_REQUIRED === "1") {
        return {
            invitation_required: true
        };
    }
}

export const actions = {
    default: async({ request }) => {
        const data = await request.formData();

        if (
            (process.env.INVITATION_REQUIRED === "1") &&
            (!data.get("token"))
        ) {
            return {
                invitation_required: true
            };
        }

        let email;
        if (data.get("token")) {
            const invitation = (await sql`SELECT email, expires FROM auth.invitations WHERE token=${data.get("token")}`)?.[0];
            if (!invitation) {
                return {
                    error: "Error: invalid invitation token"
                };
            }
            if (invitation.expires < Date.now()) {
                return {
                    error: "Error: Token expired"
                };
            }
            email = invitation.email;
        } else {
            email = data.get("email");
        }

        const userId = (await sql`
            SELECT auth.create_user(
                username   => ${email},
                first_name => ${data.get("first_name")},
                last_name  => ${data.get("last_name")},
                email      => ${data.get("email")},
                password   => ${data.get("password")},
                is_staff   => false,
                is_active  => true
            ) AS id;
        `)[0].id;
        console.log(userId);

        if (data.get("token")) {
            await sql`
                UPDATE auth.invitations
                   SET user_id=${userId}
                 WHERE token=${data.get("token")}
            `;
        }
        throw redirect(302, "/");
    }
};
