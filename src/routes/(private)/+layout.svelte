<script>
    export let data;
</script>

{#if data?.user}
    <slot />
{:else}
    <p>This page does not exist or you are not authorized to access it.</p>

    <p>
        Go to <a href="/">home page...</a>
    </p>
{/if}
