<script>
    import { page } from "$app/stores";

    export let data;
</script>

<p>
    Connected as <strong>{data.user.username}</strong>
    {#if data.current_space}
        , who has
        <strong>{data.current_space.role}</strong>
        role on
        <a href={`/spaces/${data.current_space.slug}/`}>{data.current_space.title}</a>
        {#if data?.impersonated}
            (Impersonated by
            {data?.impersonated_by?.username}
            |
            <a href={`/impersonate/quit/?redirect=${$page.url}`}>Quit impersonate</a>
            )
        {/if}
    {/if}
    |
    <a data-sveltekit-reload href="/audit-events/">Audit events</a>
    |
    <a data-sveltekit-reload href="/logout/">Logout</a>
</p>

<hr />

<slot />
