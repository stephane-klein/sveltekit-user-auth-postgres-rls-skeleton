<script>
    import { page } from "$app/stores";

    export let data;
</script>

{#if data?.user}
    <p>
        Connected as <strong>{data.user.username}</strong>
        {#if data.current_space}
            , who has
            <strong>{data.current_space.role}</strong>
            role on
            <a href={`/spaces/${data.current_space.slug}/`}>{data.current_space.title}</a>
        {/if}
        {#if data?.impersonated_by}
            (Impersonated by
            {data?.impersonated_by?.username}
            |
            <a href={`/impersonate/quit/?redirect=${$page.url}`}>Quit impersonate</a>
            )
        {/if}
        |
        <a data-sveltekit-reload href="/spaces/">Spaces</a>
        {#if data.current_space && ["space.OWNER", "space.ADMIN"].includes(data.current_space.role)}
            |
            <a data-sveltekit-reload href="/audit-events/">Audit events</a>
        {/if}
        |
        <a data-sveltekit-reload href="/logout/">Logout</a>
    </p>

    <hr />

    <slot />
{:else}
    <p>This page does not exist or you are not authorized to access it.</p>

    <p>
        Go to <a href="/">home page...</a>
    </p>
{/if}
