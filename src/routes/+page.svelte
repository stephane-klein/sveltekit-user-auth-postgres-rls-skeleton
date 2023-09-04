<script>
    import { page } from "$app/stores";

    export let data;
</script>

<h1>Users</h1>

<ul>
    {#each data.users as user}
        <li>
            {user.id} - {user.username} - {user.email}
            {#if data?.user?.is_staff}
                | <a href={`/impersonate/${user.username}/?redirect=${$page.url}`}>impersonate</a>
            {/if}
        </li>
    {/each}
</ul>

<hr />

{#if data?.user}
    {data?.user?.first_name}
    {data?.user?.last_name}

    {#if data?.impersonated}
        (Impersonated by
        {data?.impersonated_by?.first_name}
        {data?.impersonated_by?.last_name} |
        <a href={`/impersonate/quit/?redirect=${$page.url}`}>Quit impersonate</a>
        )
    {/if}

    <hr />

    <a data-sveltekit-reload href="/logout/">Logout</a>

    |

    <a href="/invitations/">Invitations</a>
{:else}
    <a data-sveltekit-reload href="/login/">Login</a>
    |
    <a href="../reset_password/">Forget password?</a>
    |
    <a data-sveltekit-reload href="/signup/">Signup</a>
{/if}
