<script>
    export let data;
</script>

<h1>Audit events</h1>

<table>
    <thead>
        <tr>
            <th>Date</th>
            <th>Author</th>
            <th>Event type</th>
            <th>Entity</th>
            <th>Space</th>
            <th>IP address</th>
        </tr>
    </thead>
    {#each data.audit_events as audit_event}
        <tr>
            <td>{audit_event.created_at}</td>
            <td>{audit_event.author_username}</td>
            <td>{audit_event.event_type}</td>
            <td>{audit_event.entity_details?.caption || "-"}</td>
            <td>{audit_event.entity_details?.space_title || "-"}</td>
            <td>{audit_event.ipv4_address || audit_event.ipv6_address || "-"}</td>
        </tr>
    {/each}
</table>
