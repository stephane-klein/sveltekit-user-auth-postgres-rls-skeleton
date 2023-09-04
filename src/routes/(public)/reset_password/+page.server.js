import logger from "$lib/server/logger.js";
import jwt from "jsonwebtoken";
import sql from "$lib/server/db.js";
import mail from "$lib/server/mail.js";

export const actions = {
    default: async({ request }) => {
        const data = await request.formData();
        const user = await sql`SELECT * FROM auth.users WHERE email=${data.get("email")}`;

        if (user.length === 1) {
            const token = jwt.sign(
                {subject: user[0].id},
                process.env.SECRET || "secret",
                { expiresIn: "30m" }
            );

            const resetUrl = new URL(request.url);
            resetUrl.pathname = "/change_password/";
            resetUrl.searchParams.set("token", token);

            const info = await mail.sendMail({
                from: "noreply@example.com",
                to: data.get("email"),
                subject: "[MyApp] Please reset your password",
                text: `
We heard that you lost your MyApp password. Sorry about that!

But don’t worry! You can use the following link to reset your password:

${resetUrl}

If you don’t use this link within 3 hours, it will expire. To get a new password reset link, visit ${request.url}

Thanks,
MyApp Team`,
                html: `
<p>We heard that you lost your MyApp password. Sorry about that!<p>

<p>But don’t worry! You can use the following link to reset your password: <a href="${resetUrl}">${resetUrl}</a></p>

<p>If you don’t use this link within 3 hours, it will expire. To get a new password reset link, visit <a href="request.url">${request.url}</a>.</p>

<p>Thanks,<br />
MyApp Team</p>`
            });

            logger.info(
                {messageId: info.messageId},
                "Mail sent"
            );
        } else {
            // Don't tell the user which e-mail addresses are registered with the service.
        }

        return {
            success: true
        };
    }
};
