<script>
    export let form;
</script>

<h1>Reset your password</h1>

{#if form?.success}
    <p>
        Check your email for a link to reset your password. If it doesn’t appear within a few minutes, check your spam
        folder.
    </p>
    <p><a href="../login/">Back to login page</a></p>
{:else}
    <form method="POST">
        {#if form?.error}<p class="error">{form.error}</p>{/if}

        <p>Enter your user account's verified email address and we will send you a password reset link.</p>

        <div>
            <input id="email" name="email" type="email" value={form?.email ?? ""} />
        </div>

        <div>
            <input type="submit" value="Send password reset email" />
            |
            <a href="../">back</a>
        </div>
    </form>
{/if}
