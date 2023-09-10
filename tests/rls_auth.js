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
    it("User must be able to read sessions informations", async() => {
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
        ).toBe(1);
        sql.end();
    });
});

describe("When admin john-doe1 is connected", () => {
    it("john-doe1 should be able update to read sessions informations", async() => {
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
        const result = await sql.begin((sql) => [
            sql`SELECT auth.open_session(
                    (SELECT auth.authenticate(
                        input_username := 'john-doe1',
                        input_email := NULL,
                        input_password := 'secret1'
                    ) ->> 'session_id')::UUID
            )`,
            sql`SELECT auth.impersonate('john-doe2')`,
            sql`SELECT impersonate_user_id FROM auth.sessions WHERE user_id=1`,
            sql`SELECT auth.exit_impersonate()`,
            sql`SELECT impersonate_user_id FROM auth.sessions WHERE user_id=1`
        ]);
        expect(
            result.at(-4)[0].impersonate.status_code
        ).toBe(200);
        expect(
            result.at(-3)[0].impersonate_user_id
        ).toBe(2);
        expect(
            result.at(-1)[0].impersonate_user_id
        ).toBe(null);
        sql.end();
    });
});
