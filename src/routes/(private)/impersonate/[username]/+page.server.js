export async function load({locals, params, url}) {
    const result = await locals.sql`
        SELECT auth.impersonate(${params.username})
    `;
    return {
        redirect: url.searchParams.get("redirect") || "/",
        ...result[0].impersonate
    };
};
