import postgres from "postgres";
import fixture from "../load-fixtures.js";

let sql;
let sqlFixture;

beforeAll(() => {
    sqlFixture = postgres(
        "postgres://postgrestest:passwordtest@localhost:5433/myapp"
    );
});
afterAll(() => {
    sqlFixture.end();
});

describe("When session is open", () => {
    beforeAll(async() => {
        sql = postgres(
            "postgres://webapp:password@localhost:5433/myapp"
        );
        await fixture(sqlFixture);
    });
    afterAll(async() => {
        sql.end();
    });
    it("User must be able to read sessions informations", async() => {
        let result = await sql`
            SELECT auth.open_session(
                (SELECT auth.authenticate(
                    input_username := 'john-doe1',
                    input_email := NULL,
                    input_password := 'secret1'
                ) ->> 'session_id')::UUID
            )
        `;
        // console.dir(result, { depth: null});
        expect(
            result[0].open_session.user.id
        ).toBe(1);
        expect(
            result[0].open_session.impersonated_by
        ).toBe(null);
        expect(
            result[0].open_session.spaces
        ).toMatchObject([1, 2, 3, 4]);

        result = await sql`
            SELECT
                CURRENT_SETTING('auth.session_id', TRUE) AS session_id,
                NULLIF(CURRENT_SETTING('auth.user_id', TRUE), '')::INTEGER AS user_id,
                CURRENT_SETTING('auth.spaces', TRUE) AS spaces;
        `;
        // console.log(result[0]);
        expect(
            result[0].user_id
        ).toBe(1);
        expect(
            result[0].spaces
        ).toBe("1,2,3,4");

        result = await sql`SELECT user_id FROM auth.sessions`;
        expect(
            result[0].user_id
        ).toBe(1);
    });
});

describe("When john-doe1 user request the list of spaces", () => {
    it("Should return 4 spaces", async() => {
        sql = postgres(
            "postgres://webapp:password@localhost:5433/myapp"
        );
        await fixture(sqlFixture);
        const result = await sql.begin((sql) => [
            sql`SELECT auth.open_session(
                    (SELECT auth.authenticate(
                        input_username := 'john-doe1',
                        input_email := NULL,
                        input_password := 'secret1'
                    ) ->> 'session_id')::UUID
            )`,
            sql`SELECT COUNT(*)::INTEGER FROM auth.spaces`
        ]);
        expect(
            result.at(-1)[0].count
        ).toBe(4);
        sql.end();
    });
});

describe("When john-doe2 user request the list of users", () => {
    beforeAll(async() => {
        sql = postgres(
            "postgres://webapp:password@localhost:5433/myapp"
        );
        await fixture(sqlFixture);
        await sql`SELECT auth.open_session(
                (SELECT auth.authenticate(
                    input_username := 'john-doe2',
                    input_email := NULL,
                    input_password := 'secret2'
                ) ->> 'session_id')::UUID
        )`;
    });
    afterAll(async() => {
        sql.end();
    });
    it("Should return 3 users", async() => {
        expect(
            (await sql`SELECT COUNT(*)::INTEGER FROM auth.users`)[0].count
        ).toBe(3);
    });
    it("The first user should be John Doe1", async() => {
        expect(
            (await sql`
                SELECT id, username, first_name, last_name
                FROM auth.users
                ORDER BY id LIMIT 1
            `)[0]
        ).toMatchObject({
            id: 1,
            username: "john-doe1",
            first_name: "John",
            last_name: "Doe1"
        });
    });
});

describe("When john-doe2 user request the list of spaces", () => {
    it("Should return 1 space", async() => {
        sql = postgres(
            "postgres://webapp:password@localhost:5433/myapp"
        );
        await fixture(sqlFixture);
        const result = await sql.begin((sql) => [
            sql`SELECT auth.open_session(
                    (SELECT auth.authenticate(
                        input_username := 'john-doe2',
                        input_email := NULL,
                        input_password := 'secret2'
                    ) ->> 'session_id')::UUID
            )`,
            sql`SELECT COUNT(*)::INTEGER FROM auth.spaces`
        ]);
        expect(
            result.at(-1)[0].count
        ).toBe(3);
        sql.end();
    });
});

describe("When admin john-doe1 is connected", () => {
    it("john-doe1 should be able to read sessions informations", async() => {
        sql = postgres(
            "postgres://webapp:password@localhost:5433/myapp"
        );
        await fixture(sqlFixture);
        const result = await sql.begin((sql) => [
            sql`SELECT auth.open_session(
                    (SELECT auth.authenticate(
                        input_username := 'john-doe1',
                        input_email := NULL,
                        input_password := 'secret1'
                    ) ->> 'session_id')::UUID
            )`,
            sql`SELECT user_id FROM auth.sessions`
        ]);
        expect(
            result.at(-1)[0].user_id
        ).toBe(1);
        sql.end();
    });
    it("john-doe1 should be able to impersonate john-doe2", async() => {
        sql = postgres(
            "postgres://webapp:password@localhost:5433/myapp"
        );
        await fixture(sqlFixture);
        const sessionId = (await sql`
            SELECT (auth.authenticate(
                input_username := 'john-doe1',
                input_email := NULL,
                input_password := 'secret1'
            ) ->> 'session_id')::UUID AS session_id
        `)[0].session_id;

        let openSessionResult = (await sql`SELECT auth.open_session(${sessionId})`)[0].open_session;
        expect(openSessionResult.user.id).toBe(1);
        expect(openSessionResult.impersonated_by).toBe(null);
        expect(openSessionResult.spaces).toMatchObject([ 1, 2, 3, 4]);

        expect(
            (await sql`SELECT CURRENT_SETTING('auth.spaces') AS spaces`)[0].spaces
        ).toBe("1,2,3,4");
        expect(
            (await sql`SELECT auth.impersonate('john-doe2')`)[0].impersonate.status_code
        ).toBe(200);

        openSessionResult = (await sql`SELECT auth.open_session(${sessionId})`)[0].open_session;
        expect(openSessionResult.user.id).toBe(2);
        expect(openSessionResult.impersonated_by.id).toBe(1);
        expect(openSessionResult.spaces).toMatchObject([ 1 ]);
        expect(
            (await sql`SELECT CURRENT_SETTING('auth.spaces') AS spaces`)[0].spaces
        ).toBe("1");

        await sql`SELECT auth.exit_impersonate()`;

        openSessionResult = (await sql`SELECT auth.open_session(${sessionId})`)[0].open_session;
        expect(openSessionResult.user.id).toBe(1);
        expect(openSessionResult.impersonated_by).toBe(null);
        expect(openSessionResult.spaces).toMatchObject([ 1, 2, 3, 4]);
        expect(
            (await sql`SELECT CURRENT_SETTING('auth.spaces') AS spaces`)[0].spaces
        ).toBe("1,2,3,4");

        sql.end();
    });
    it("john-doe1 should be able to create an invitation for space-1", async() => {
        sql = postgres(
            "postgres://webapp:password@localhost:5433/myapp"
        );
        await fixture(sqlFixture);
        const sessionId = (await sql`
            SELECT (auth.authenticate(
                input_username := 'john-doe1',
                input_email := NULL,
                input_password := 'secret1'
            ) ->> 'session_id')::UUID AS session_id
        `)[0].session_id;

        await sql`SELECT auth.open_session(${sessionId})`;
        const invitationId = (await sql`
                INSERT INTO auth.invitations
                    (
                        id,
                        invited_by,
                        email,
                        token
                    )
                    VALUES(
                        1000,
                        1,
                        'test1@example.com',
                        'fake token'
                    )
                RETURNING id
        `)[0].id;
        expect(invitationId).toBe(1000);

        await sql`
            INSERT INTO auth.space_invitations
                (
                    invitation_id,
                    space_id,
                    role
                )
                VALUES(
                    ${invitationId},
                    1,
                    'space.MEMBER'
                );
        `;

        sql.end();
    });
});

describe("When admin john-doe2 is connected", () => {
    it("john-doe1, a space.MEMBER can not create an invitation for space-1", async() => {
        sql = postgres(
            "postgres://webapp:password@localhost:5433/myapp"
        );
        await fixture(sqlFixture);
        const sessionId = (await sql`
            SELECT (auth.authenticate(
                input_username := 'john-doe2',
                input_email := NULL,
                input_password := 'secret2'
            ) ->> 'session_id')::UUID AS session_id
        `)[0].session_id;

        await sql`SELECT auth.open_session(${sessionId})`;
        const invitationId = (await sql`
                INSERT INTO auth.invitations
                    (
                        id,
                        invited_by,
                        email,
                        token
                    )
                    VALUES(
                        1000,
                        2,
                        'test1@example.com',
                        'fake token'
                    )
                RETURNING id
        `)[0].id;
        expect(invitationId).toBe(1000);

        expect.assertions(1);
        try {
            await sql`
                INSERT INTO auth.space_invitations
                    (
                        invitation_id,
                        space_id,
                        role
                    )
                    VALUES(
                        ${invitationId},
                        1,
                        'space.MEMBER'
                    );
            `;
        } catch (e) {
        }

        sql.end();
    });
});

describe("Anonymous user is connected", () => {
    beforeAll(async() => {
        sql = postgres(
            "postgres://webapp:password@localhost:5433/myapp"
        );
        await fixture(sqlFixture);
    });

    afterAll(async() => {
        sql.end();
    });

    it("Anonymous should be able to list is_publicly_browsable spaces", async() => {
        expect(
            (await sql`SELECT COUNT(*)::INTEGER FROM auth.spaces`)[0].count
        ).toBe(3);
    });

    it("Anonymous should be able to create a user", async() => {
        const result = (await sql`SELECT auth.create_user(
            _id           => null,
            _username     => 'john-doe-created',
            _first_name   => 'John',
            _last_name    => 'Doe',
            _email        => 'john.doe-created@example.com',
            _password     => 'mysecret',
            _is_active    => true,
            _is_superuser => false,
            _spaces       => '[{"slug": "space-1", "role": "space.MEMBER"}]'
        )`)[0].create_user;
        expect(result.status_code).toBe(200);
        expect(result.user_id).toBe(5);
    });

    it("Anonymous should be able to create_user with invitation", async() => {
        let result = (await sql`SELECT auth.create_user_from_invitation(
            _id             => null,
            _invitation_id  => 1,
            _username       => 'invited_user1',
            _first_name     => 'Alice',
            _last_name      => 'Doe',
            _email          => 'alice.doe@example.com',
            _password       => 'secret',
            _is_active      => true
        )`)[0].create_user_from_invitation;
        expect(result.status_code).toBe(200);
        expect(result.user_id).toBe(6);

        const invitations = await sqlFixture`SELECT * FROM auth.invitations WHERE id=1`;
        expect(invitations[0].user_id).toBe(result.user_id);

        result = (await sql`SELECT auth.create_user_from_invitation(
            _id             => null,
            _invitation_id  => 1,
            _username       => 'invited_user1',
            _first_name     => 'Alice',
            _last_name      => 'Doe',
            _email          => 'alice.doe@example.com',
            _password       => 'secret',
            _is_active      => true
        )`)[0].create_user_from_invitation;
        expect(result.status_code).toBe(401);
    });
});
