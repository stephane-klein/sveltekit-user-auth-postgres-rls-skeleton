export async function load({ locals }) {
    if (locals.client?.user) {
        return {
            ...locals.client
        };
    }
}
