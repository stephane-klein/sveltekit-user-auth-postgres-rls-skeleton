import { redirect } from "@sveltejs/kit";
import jwt from "jsonwebtoken";
import logger from "$lib/server/logger.js";
import sql from "$lib/server/db.js";
import mail from "$lib/server/mail.js";

export const actions = {
    default: async({ locals, request }) => {
        const data = await request.formData();

        const token = jwt.sign(
            {
                user_id: locals.user.id,
                email: data.get("email")
            },
            process.env.SECRET || "secret",
            {
                expiresIn: "7d"
            }
        );

        await sql`
            INSERT INTO auth.invitations ${
                sql({
                    invited_by: locals.user.id,
                    email: data.get("email"),
                    token: token
                })
            }
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
                invited_by: locals.user.id,
                email: data.get("email"),
                token: token,
                messageId: messageId
            },
            "Send invitation"
        );

        throw redirect(302, "./../");
    }
};
