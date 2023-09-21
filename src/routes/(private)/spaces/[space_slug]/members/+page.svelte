<script>
    import { page } from "$app/stores";

    export let data;
    console.log(data);
</script>

<p>
    Member of <a href={`/spaces/${data.current_space.slug}/`}>{data.current_space.title}</a>
</p>

<h1>Members</h1>

<table>
    <thead>
        <tr>
            <th>Username</th>
            <th>Email</th>
            <th>Role</th>
            <th>Last login</th>
            <th>Created at</th>
            <th>Actions</th>
        </tr>
    </thead>
    <tbody>
        {#each data.members as member}
            <tr>
                <td>{member.username}</td>
                <td>{member.email}</td>
                <td>{member.role}</td>
                <td>{member.last_login}</td>
                <td>{member.created_at}</td>
                <td>
                    {#if ["space.OWNER", "space.ADMIN"].includes(data.current_space.role)}
                        <a href={`/impersonate/${member.username}/?redirect=${$page.url}`}>impersonate</a>
                    {/if}
                </td>
            </tr>
        {/each}
    </tbody>
</table>
