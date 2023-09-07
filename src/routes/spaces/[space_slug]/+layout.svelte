<script>
    export let data;
</script>

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
