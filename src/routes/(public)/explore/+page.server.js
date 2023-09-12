export async function load({locals}) {
    return {
        spaces: (
            await locals.sql`
                SELECT
                    slug,
                    title
                FROM
                    auth.spaces
                WHERE
                    is_publicly_browsable IS TRUE
                ORDER BY
                    created_at
            `
        )
    };
}
