<script>
    import { page } from "$app/stores";

    export let data;
</script>

<p>
    Connected as <strong>{data.user.username}</strong>
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
    |
    <a data-sveltekit-reload href="/logout/">Logout</a>
</p>

<hr />

<p>
    Current space: <a href={`/spaces/${data.current_space.slug}/`}>{data.current_space.title}</a>
</p>

<hr />

<p>
    Switch space:
    <select name="space" on:change={(event) => (window.location = `/spaces/${event.target.value}/`)}>
        {#each data.spaces as space}
            <option value={space.slug} selected={space.slug == data.current_space.slug}>{space.title}</option>
        {/each}
    </select>
</p>

<hr />

<p>
    Navigation : <a href={`/spaces/${data.current_space.slug}/members/`}>Members</a>
    |
    <a href={`/spaces/${data.current_space.slug}/invitations/`}>Invitations</a>
</p>
<hr />

<slot />
