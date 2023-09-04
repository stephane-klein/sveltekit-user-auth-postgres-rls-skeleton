<script>
    export let form;
</script>

<form method="POST">
    {#if form?.error}<p class="error">{form.error}</p>{/if}
    <div>
        <label for="email">Email:</label>
        <input id="email" name="email" type="email" value={form?.email ?? ""} />
    </div>
    <div>
        <label for="password">Password:</label>
        <input id="password" name="password" type="password" />
    </div>

    <input type="submit" value="Login" />
    |
    <a href="../password_reset/">Forget password?</a>
    |
    <a href="../">back</a>
</form>
