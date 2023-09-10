import postgres from "postgres";
import fixture from "../load-fixtures.js";

let sql;
let sqlFixture;

beforeEach(async() => {
    sql = postgres(
        "postgres://webapp:password@localhost:5433/myapp"
    );
    sqlFixture = postgres(
        "postgres://postgrestest:passwordtest@localhost:5433/myapp"
    );
});
afterEach(() => {
    sql.end();
    sqlFixture.end();
});

describe("When john-doe2 user request the list of resource_a", () => {
    it("Should return 3 resource_a", async() => {
        await fixture(sqlFixture);
        const result = await sql.begin((sql) => [
            sql`SELECT auth.open_session(
                    (SELECT auth.authenticate(
                        input_username := 'john-doe2',
                        input_email := NULL,
                        input_password := 'secret2'
                    ) ->> 'session_id')::UUID
            )`,
            sql`SELECT COUNT(*)::INTEGER FROM main.resource_a`
        ]);
        expect(
            result.at(-1)[0].count
        ).toBe(3);
    });
});
