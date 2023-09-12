import postgres from "postgres";

let sql;

beforeAll(() => {
    sql = postgres(
        "postgres://postgrestest:passwordtest@localhost:5433/myapp"
    );
});
afterAll(() => {
    sql.end();
});

test("Create a user and login", async() => {
    await sql`DELETE FROM auth.space_invitations CASCADE`;
    await sql`DELETE FROM auth.invitations CASCADE`;
    await sql`DELETE FROM auth.space_users CASCADE`;
    await sql`DELETE FROM auth.spaces CASCADE`;
    await sql`DELETE FROM auth.users CASCADE`;
    await sql`DELETE FROM auth.sessions CASCADE`;

    const userId = (await sql`SELECT auth.create_user(
        id         => null,
        username   => 'john-doe',
        first_name => 'John',
        last_name  => 'Doe',
        email      => 'john.doe@example.com',
        password   => 'secret',
        is_active  => true,
        spaces => null
    )`)[0]?.create_user;

    expect(
        (await sql`SELECT COUNT(*)::INTEGER FROM auth.users WHERE first_name = 'John'`)[0].count
    ).toBe(1);

    let authenticateResult = (await sql`
        SELECT auth.authenticate(
            input_username =>'',
            input_email    =>'john.doe@example.com',
            input_password =>'secret'
        )
    `)[0]?.authenticate;

    expect(authenticateResult.status_code).toBe(200);

    expect(
        (await sql`SELECT user_id FROM auth.sessions WHERE id=${authenticateResult.session_id}`)[0].user_id
    ).toBe(userId);

    authenticateResult = (await sql`
        SELECT auth.authenticate(
            input_username =>'',
            input_email    =>'john.doe@example.com',
            input_password =>'badpassword'
        )
    `)[0]?.authenticate;

    expect(authenticateResult.status_code).toBe(401);

    authenticateResult = (await sql`
        SELECT auth.authenticate(
            input_username =>'',
            input_email    =>'unknow@example.com',
            input_password =>'secret'
        )
    `)[0]?.authenticate;

    expect(authenticateResult.status_code).toBe(401);
});
