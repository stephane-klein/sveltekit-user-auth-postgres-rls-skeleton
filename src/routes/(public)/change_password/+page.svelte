<script>
    export let data;
    export let form;
</script>

{#if data?.tokenValid || form?.tokenValid}
    {#if form?.passwordUpdated}
        <p>
            Password updated with succes, <a href="../../login/">go to Login page</a>
            .
        </p>
    {:else}
        <h1>New Password</h1>

        <p>Define a new password for "{data.email}" account.</p>

        <form method="POST">
            {#if form?.error}<p class="error">{form.error}</p>{/if}

            <div>
                <label for="password">Password:</label>
                <input
                    id="password"
                    name="password"
                    type="password"
                    required="required"
                    value={form?.password ?? ""}
                    placeholder="Password"
                    autocomplete="new-password"
                />
            </div>
            <div>
                <label for="passwordConfirm">Password (retype):</label>
                <input
                    id="passwordConfirm"
                    name="passwordConfirm"
                    type="password"
                    required="required"
                    value={form?.passwordConfirm ?? ""}
                    placeholder="Password"
                    autocomplete="new-password"
                />
            </div>

            <div>
                <input type="submit" value="Change the password" />
                |
                <a href="../../login/">Cancel (go to login page)</a>
            </div>
        </form>
    {/if}
{:else}
    <p>
        Error, invalid or expired reset url, please generate now reset link on <a href="../">Password reset page</a>
        .
    </p>
{/if}
