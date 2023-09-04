<script>
    export let form;
</script>

<h1>Invite a member</h1>

<form method="POST">
    {#if form?.error}<p class="error">{form.error}</p>{/if}
    <div>
        <label for="email">Email:</label>
        <input id="email" name="email" type="email" required="required" value={form?.email ?? ""} />
    </div>

    <input type="submit" value="Invite" />
    |
    <a href="../">back</a>
</form>
