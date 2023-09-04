<script>
    export let data;
    export let form;
</script>

{#if data.error}
    <p class="error">{data.error}</p>
{:else if data.invitation_required && !data.email}
    <p>Registration by invitation only</p>
{:else}
    <form method="POST">
        {#if form?.error}<p class="error">{form.error}</p>{/if}
        <div>
            <label for="email">Email:</label>
            <input
                id="email"
                name="email"
                type="email"
                required="required"
                readonly={data.email}
                value={data?.email ?? form?.email ?? ""}
            />
            {#if data.token}
                <input type="hidden" name="token" value={data.token} />
            {/if}
        </div>
        <div>
            <label for="username">Username:</label>
            <input id="username" name="username" type="text" required="required" value={form?.username ?? ""} />
        </div>
        <div>
            <label for="password">Password:</label>
            <input id="password" name="password" type="password" />
        </div>
        <div>
            <label for="first_name">First name:</label>
            <input id="first_name" name="first_name" type="text" value={form?.first_name ?? ""} />
        </div>
        <div>
            <label for="last_name">Last name:</label>
            <input id="last_name" name="last_name" type="text" value={form?.last_name ?? ""} />
        </div>

        <input type="submit" value="Signup" />
        |
        <a href="../">back</a>
    </form>
{/if}
