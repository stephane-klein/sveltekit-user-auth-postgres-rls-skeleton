import nodemailer from "nodemailer";

const transporter = nodemailer.createTransport({
    host: process.env.SMTP_HOST || "127.0.0.1",
    port: process.env.SMTP_POST || 1025,
    secure: false
});

export default transporter;
