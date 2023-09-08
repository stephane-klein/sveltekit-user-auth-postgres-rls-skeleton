import postgres from "postgres";

const sql = postgres(
    process.env.POSTGRES_URL || "postgres://webapp:password@localhost:5432/myapp"
);

// await sql.reserve() have a bug, it didn't execute auto fetching of array types
// then, I call this query to force auto fetching of array types loading
await sql`SELECT 1`;

export default sql;
