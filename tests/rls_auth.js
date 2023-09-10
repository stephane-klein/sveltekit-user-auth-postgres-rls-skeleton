import postgres from "postgres";
import fixture from "../load-fixtures.js";

let sql;

describe("When john-doe1 user request the list of spaces", () => {
    it("Should return 4 spaces", async() => {
        sql = postgres(
            "postgres://postgrestest:passwordtest@localhost:5433/myapp"
        );
        await fixture(sql);
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
            "postgres://postgrestest:passwordtest@localhost:5433/myapp"
        );
        await fixture(sql);
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
        ).toBe(4);
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
            "postgres://postgrestest:passwordtest@localhost:5433/myapp"
        );
        await fixture(sql);
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
