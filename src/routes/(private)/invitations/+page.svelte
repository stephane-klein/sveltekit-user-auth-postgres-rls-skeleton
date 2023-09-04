<script>
    export let data;
</script>

<div>
    <a href="./add/">Invite a member...</a>
    |
    <a href="../">Home</a>
</div>

<table>
    {#each data.invitations as invitation}
        <tr>
            <td>{invitation.invited_by}</td>
            <td>{invitation.email}</td>
            <td>{invitation.expires}</td>
            <td>{invitation.user_id}</td>
        </tr>
    {/each}
</table>
