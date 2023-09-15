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

    await sql`TRUNCATE auth.audit_events, auth.users, auth.sessions, auth.space_invitations, auth.invitations, auth.spaces, auth.space_users, main.resource_a, main.resource_b`;
    await sql`
        ALTER SEQUENCE auth.invitations_id_seq RESTART WITH 1;
        ALTER SEQUENCE auth.spaces_id_seq RESTART WITH 1;
        ALTER SEQUENCE auth.users_id_seq RESTART WITH 1;
        ALTER SEQUENCE main.resource_a_id_seq RESTART WITH 1;
        ALTER SEQUENCE main.resource_b_id_seq RESTART WITH 1;
    `.simple();

    // Fixture execute all actions logged in as root user
    await sql`
        SELECT SET_CONFIG(
            'auth.user_id',
            '0',
            FALSE
        );
    `;

    await sql`
        INSERT INTO auth.users (
            id,
            username,
            email,
            password,
            is_active,
            is_superuser,
            is_serviceuser,
            date_joined
        )
        VALUES (
            0,                   -- id,
            'root',              -- username,
            'noreply@localhost', -- email,
            '',                  -- password,
            TRUE,                -- is_active,
            TRUE,                -- is_superuser,
            TRUE,                -- is_serviceuser,
            NOW()                -- date_joined
        )
    `;

    async function import_spaces(spaces, parent_space_id) {
        for await (const space of spaces) {
            const space_id = (await sql`
                INSERT INTO auth.spaces
                ${
                    sql({
                        "parent_space_id": parent_space_id,
                        "slug": space.slug,
                        "title": space.title,
                        "is_publicly_browsable": space.is_publicly_browsable,
                        "invitation_required": space.invitation_required
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
        await sql`
            SELECT auth.create_user(
                _id           => ${user?.id || undefined},
                _username     => ${user.username},
                _first_name   => ${user.first_name},
                _last_name    => ${user.last_name},
                _email        => ${user.email},
                _password     => ${user.password},
                _is_active    => TRUE,
                _is_superuser => ${user?.is_superuser || false},
                _spaces       => ${user.spaces}
            )->>'user_id' AS user_id;
        `;
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
        const invitation_id = (await sql`
            INSERT INTO auth.invitations
            ${
                sql({
                    "email": invite.email,
                    "invited_by": invite.invited_by,
                    "token": token
                })
            } RETURNING id
        `)[0].id;

        for await (const space_invitation of invite.spaces) {
            await sql`
                INSERT INTO auth.space_invitations
                (
                    invitation_id,
                    space_id,
                    role
                )
                VALUES(
                    ${invitation_id},
                    (
                        SELECT id
                        FROM auth.spaces
                        WHERE slug=${space_invitation.slug}
                    ),
                    ${space_invitation.role}
                )
            `;
        };
    }

    for await (const resource_a of data.resource_a) {
        await sql`
            INSERT INTO main.resource_a
            (
                space_id,
                slug,
                title,
                content,
                created_by
            )
            VALUES(
                (
                    SELECT id
                    FROM auth.spaces
                    WHERE slug=${resource_a.space_slug}
                ),
                ${resource_a.slug},
                ${resource_a.title},
                ${resource_a.content},
                ${resource_a.created_by}
            );
        `;
    }

    for await (const resource_b of data.resource_b) {
        await sql`
            INSERT INTO main.resource_b
            (
                space_id,
                slug,
                title,
                content,
                created_by
            )
            VALUES(
                (
                    SELECT id
                    FROM auth.spaces
                    WHERE slug=${resource_b.space_slug}
                ),
                ${resource_b.slug},
                ${resource_b.title},
                ${resource_b.content},
                ${resource_b.created_by}
            );
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
