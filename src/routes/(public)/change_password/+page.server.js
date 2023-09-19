import logger from "$lib/server/logger.js";
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
        email: decoded.user.email
    };
}

export const actions = {
    default: async({ locals, request, url }) => {
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

        const anonymousUserChangePasswordResult = (await locals.sql`
            SELECT auth.anonymous_user_change_password(${decoded.user.email}, ${data.get("password")}) AS result
        `)[0].result;

        if (anonymousUserChangePasswordResult.status === 200) {
            logger.info(
                {
                    id: decoded.user.email
                },
                "Password updated"
            );
        }

        const info = await mail.sendMail({
            from: "noreply@example.com",
            to: decoded.user.email,
            subject: "[MyApp] Password changed",
            text: `${decoded.user.email} account password changed.`,
            html: `<p>${decoded.user.email} account password changed.<p>`
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
