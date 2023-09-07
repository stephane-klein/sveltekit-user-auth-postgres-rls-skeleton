<script>
    export let data;
</script>

<p>
    Invitations of <a href={`/spaces/${data.current_space.slug}/`}>{data.current_space.title}</a>
</p>

<h1>Invitations</h1>

<table>
    <thead>
        <tr>
            <th>Email</th>
            <th>Invited by</th>
            <th>Expire at</th>
        </tr>
    </thead>
    <tbody>
        {#each data.invitations as invite}
            <tr>
                <td>{invite.email}</td>
                <td>{invite.invited_by_username}</td>
                <td>{invite.expires_at}</td>
            </tr>
        {/each}
    </tbody>
</table>
