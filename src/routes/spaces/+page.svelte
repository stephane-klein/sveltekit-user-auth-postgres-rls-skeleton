<script>
    export let data;
</script>

<h1>You can access to this spaces</h1>

<ul>
    {#each data.spaces as space}
        <li>
            <a data-sveltekit-reload href={`/spaces/${space.slug}/`}>{space.id} - {space.title}</a>
        </li>
    {/each}
</ul>
