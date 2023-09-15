import { redirect } from "@sveltejs/kit";
import jwt from "jsonwebtoken";
import logger from "$lib/server/logger.js";
import mail from "$lib/server/mail.js";

export const actions = {
    default: async({ locals, request }) => {
        const data = await request.formData();

        const token = jwt.sign(
            {
                user_id: locals.client.user.id,
                email: data.get("email")
            },
            process.env.SECRET || "secret",
            {
                expiresIn: "7d"
            }
        );

        await locals.sql`
            WITH _invitation AS (
                INSERT INTO auth.invitations
                ${
                    locals.sql({
                        "invited_by": locals.client.user.id,
                        "email": data.get("email"),
                        "token": token,
                    })
                }
                RETURNING id
            ),
            _space_invitations AS (
                INSERT INTO auth.space_invitations
                (
                    invitation_id,
                    space_id,
                    role
                )
                VALUES(
                    (SELECT id FROM _invitation),
                    ${locals.client.current_space.id},
                    'space.MEMBER'
                )
            )
            INSERT INTO auth.audit_events
                (
                    entity_type,
                    entity_id,
                    space_ids,
                    event_type
                )
                VALUES(
                    'auth.invitations',
                    (SELECT id FROM _invitation),
                    ${[locals.client.current_space.id]},
                    'CREATED'
                );
        `;

        const invitationUrl = new URL(request.url);
        invitationUrl.pathname = "/signup/";
        invitationUrl.searchParams.set("token", token);

        const { messageId } = await mail.sendMail({
            from: "noreply@example.com",
            to: data.get("email"),
            subject: "[MyApp] Invitation",
            text: `Invitation ${invitationUrl}`,
            html: `<a href="${invitationUrl}">Invitation</a>`
        });

        logger.info(
            {
                invited_by: locals.client.user.id,
                email: data.get("email"),
                token: token,
                messageId: messageId
            },
            "Send invitation"
        );

        throw redirect(302, "./../");
    }
};
