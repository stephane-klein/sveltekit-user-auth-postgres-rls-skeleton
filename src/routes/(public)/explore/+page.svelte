<script>
    export let data;
</script>

<h1>Public spaces</h1>

<table>
    <thead>
        <tr>
            <th>Space</th>
        </tr>
    </thead>
    {#each data.spaces as space}
        <tr>
            <td><a href={`/spaces/${space.slug}/`}>{space.title}</a></td>
        </tr>
    {/each}
</table>
