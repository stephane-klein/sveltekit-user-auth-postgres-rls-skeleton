import logger from "$lib/server/logger.js";
import sql from "$lib/server/db.js";
import jwt from "jsonwebtoken";
import mail from "$lib/server/mail.js";

export async function load({ url }) {
    let decoded;
    try {
        decoded = jwt.verify(
            url.searchParams.get("token"),
            process.env.SECRET || "secret"
        );
    } catch(error) {
        return {
            tokenValid: false
        };
    }

    return {
        tokenValid: true,
        email: (await sql`SELECT email FROM auth.users WHERE id=${decoded.subject}`)[0].email
    };
}

export const actions = {
    default: async({ request, url }) => {
        let decoded;
        try {
            decoded = jwt.verify(
                url.searchParams.get("token"),
                process.env.SECRET || "secret"
            );
        } catch(error) {
            return {
                tokenValid: false
            };
        }

        const data = await request.formData();

        if ((data.get("password").trim() === "") || (data.get("passwordConfirm").trim() === "")) {
            return {
                tokenValid: true,
                error: "All password fields are required"
            };
        }

        if (data.get("password").trim() !== data.get("passwordConfirm").trim()) {
            return {
                tokenValid: true,
                error: "Error: The two password fields do not contain the same values."
            };
        }

        await sql`
            UPDATE auth.users
               SET password=utils.CRYPT(TRIM(${data.get("password").trim()}), utils.GEN_SALT('bf', 8))
             WHERE id=${decoded.subject}
        `;
        logger.info(
            {
                id: decoded.subject
            },
            "Password updated"
        );
        const email = (await sql`SELECT email FROM auth.users WHERE id=${decoded.subject}`)[0].email;

        const info = await mail.sendMail({
            from: "noreply@example.com",
            to: email,
            subject: "[MyApp] Password changed",
            text: `${email} account password changed.`,
            html: `<p>${email} account password changed.<p>`
        });

        logger.info(
            {messageId: info.messageId},
            "Password changed mail sent"
        );

        return {
            tokenValid: true,
            passwordUpdated: true
        };
    }
};
