import { redirect } from "@sveltejs/kit";

export async function load({ locals, url }) {
    if (locals.client.user) {
        throw redirect(302, "/");
    }

    if (url.searchParams.get("token")) {
        const invitation = (await locals.sql`SELECT * FROM auth.fetch_invitation_by_token(${url.searchParams.get("token")})`)[0];
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
    }

    return {
        spaces: await locals.sql`
            SELECT
                slug,
                title
            FROM
                auth.spaces
            WHERE
                is_publicly_browsable IS TRUE
            ORDER BY
                created_at
        `
    };
}

export const actions = {
    default: async({ locals, request }) => {
        const data = await request.formData();

        if (
            (process.env.INVITATION_REQUIRED === "1") &&
            (!data.get("token"))
        ) {
            return {
                invitation_required: true
            };
        }

        let result;
        if (data.get("token")) {
            const invitation = (await locals.sql`SELECT * FROM auth.fetch_invitation_by_token(${data.get("token")})`)[0];
            if (!invitation) {
                return {
                    error: "Error: invalid invitation token"
                };
            }
            if (invitation.expires < Date.now()) {
                return {
                    error: "Error: Invitation expired"
                };
            }
            if (invitation.user_id !== null) {
                return {
                    error: "Error: Invitation already used"
                };
            }
            result = (await locals.sql`
                SELECT auth.create_user_from_invitation(
                    _id            => null,
                    _invitation_id => ${invitation.id},
                    _username      => ${data.get("username")},
                    _first_name    => ${data.get("first_name")},
                    _last_name     => ${data.get("last_name")},
                    _email         => ${invitation.email},
                    _password      => ${data.get("password")},
                    _is_active     => true
);
            `)[0].create_user_from_invitation;
        } else {
            result = (await locals.sql`
                SELECT auth.create_user(
                    _id           => null,
                    _username     => ${data.get("username")},
                    _first_name   => ${data.get("first_name")},
                    _last_name    => ${data.get("last_name")},
                    _email        => ${data.get("email")},
                    _password     => ${data.get("password")},
                    _is_active    => true,
                    _is_superuser => false,
                    _spaces       => ${[{
                        slug: data.get("space"),
                        role: 'space.MEMBER'
                    }]}
                );
            `)[0].create_user;
        }
        if (result.status_code !== 200) {
            return {
                error: result.status
            };
        }

        throw redirect(302, "/");
    }
};
