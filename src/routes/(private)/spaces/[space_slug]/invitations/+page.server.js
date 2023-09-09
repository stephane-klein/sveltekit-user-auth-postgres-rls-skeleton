export async function load({locals}) {
    return {
        invitations: (
            await locals.sql`
                SELECT
                    invitations.id                             AS id,
                    invitations.invited_by                     AS invited_by,
                    users.username                             AS invited_by_username,
                    users.first_name                           AS invited_by_first_name,
                    users.last_name                            AS invited_by_last_name,
                    invitations.email                          AS email,
                    TO_CHAR(invitations.expires, 'YYYY-MM-dd') AS expires_at
                FROM auth.invitations

                LEFT JOIN auth.users
                       ON invitations.invited_by = users.id

                WHERE spaces @> ${[{id: locals.client.current_space.id}]}

                ORDER BY invitations.expires
            `
        )
    };
}

