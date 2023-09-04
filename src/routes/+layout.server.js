export async function load({ locals }) {
    if (locals?.user) {
        return {
            ...locals
        };
    }
}
