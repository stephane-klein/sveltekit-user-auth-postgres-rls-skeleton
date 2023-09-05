#!/usr/bin/env node
import { fileURLToPath } from "url";
import path from "path";
import fs from "fs";
import yaml from "js-yaml";
import postgres from "postgres";
import jwt from "jsonwebtoken";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

async function main(sql) {
    const data = yaml.load(fs.readFileSync(path.resolve(__dirname, "./fixtures.yaml"), "utf8"));

    await sql`TRUNCATE auth.users, auth.sessions, auth.invitations, auth.spaces, auth.space_users`;
    await sql`
        ALTER SEQUENCE auth.invitations_id_seq RESTART WITH 1;
        ALTER SEQUENCE auth.spaces_id_seq RESTART WITH 1;
        ALTER SEQUENCE auth.users_id_seq RESTART WITH 1;
    `.simple();

    async function import_spaces(spaces, parent_space_id) {
        for await (const space of spaces) {
            const space_id = (await sql`
                INSERT INTO auth.spaces
                ${
                    sql({
                        "parent_space_id": parent_space_id,
                        "slug": space.slug,
                        "title": space.title
                    })
                }
                RETURNING id
            `)[0].id;
            if (space?.spaces) {
                await import_spaces(
                    space.spaces,
                    space_id
                );
            }
        }
    }
    await import_spaces(data.spaces, null);

    for await (const user of data.users) {
        const user_id = (await sql`
            SELECT auth.create_user(
                id         => ${user?.id || undefined},
                username   => ${user.username},
                first_name => ${user.first_name},
                last_name  => ${user.last_name},
                email      => ${user.email},
                password   => ${user.password},
                is_active  => TRUE
            ) AS user_id;
        `)[0].user_id;

        for await (const space_user of user.spaces) {
            await sql`
                INSERT INTO auth.space_users
                    (
                        user_id,
                        space_id,
                        role
                    )
                    VALUES(
                        ${user_id},
                        (
                            SELECT id
                            FROM auth.spaces
                            WHERE slug=${space_user.slug}
                        ),
                        ${space_user.role}
                    )
            `;
        }
    }

    for await (const invite of data.invitations) {
        const token = jwt.sign(
            {
                user_id: invite.invited_by,
                email: invite.email
            },
            process.env.SECRET || "secret",
            {
                expiresIn: "7d"
            }
        );
        await sql`
            INSERT INTO auth.invitations
            (
                email,
                invited_by,
                spaces,
                token
            )
            (
                SELECT
                    ${invite.email} AS email,
                    ${invite.invited_by} AS invited_by,
                    JSONB_AGG(ROW_TO_JSON(foo)) AS spaces,
                    ${token} AS token
                FROM (
                    SELECT
                        spaces.id AS id,
                        role AS role
                    FROM
                        JSONB_TO_RECORDSET(${invite.spaces})
                        AS list(
                            slug VARCHAR,
                            role VARCHAR
                        )
                    LEFT JOIN auth.spaces
                    ON spaces.slug = list.slug
                ) AS foo
            )
        `;
    }
}

if (__filename === process.argv[1]) {
    console.log("Load fixtures...");
    const sql = postgres(
        "postgres://postgres:password@localhost:5432/myapp"
    );
    await main(sql);
    sql.end();
    console.log("Fixtures loaded");
}
export default main;
