<script>
    export let data;
    if (data.status_code == 200) {
        window.location = data.redirect;
    }
</script>

{#if data.status_code != 200}
    <p>Error: {data.status}</p>
{/if}
