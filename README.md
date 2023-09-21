# SvelteKit SSR user auth PostgreSQL RLS skeleton

I hope to use this skeleton as a foundation to integrate user authentication, with _workspace/groupspace_ support in SvelteKit web app.

Status : I think it's stable, but it hasn't been tested in production.

This project is a spin-off of [`sveltekit-user-auth-skeleton`](https://github.com/stephane-klein/sveltekit-user-auth-skeleton).

Repository starting point issue (in French): https://github.com/stephane-klein/sveltekit-user-auth-skeleton/issues/7

In a real project, the tables `main.resource_a` and `main.resource_b` should be replaced by `products`, `issues`,
`customers`, `invoices`… entities.

Features:

- User login
- User signup
- User signup by invitation
- User password reset support
- User impersonate support for staff user
- User role support
- Space resource support, to implement _workspace_ or _groupspace_, multitenancy
- A user can belong to one or more spaces
- A space can belong to another space
- Permission control implemented in PostgreSQL using [Row-Level Security](https://www.postgresql.org/docs/16/ddl-rowsecurity.html)
- The data model has been designed with performance in mind, i.e. the `POLICY` query plans have been reviewed to ensure that the best indexes are used (I'm not claiming that everything is perfect at the moment, but this is one of the main objectives of this project)
- Audit events support

Next tasks on the roadmap:

- Improve unit tests
- Implement end2end tests

Opinions:

- No ORM pattern
- The security layer, i.e. permission control is implemented by PostgreSQL [Row-Level Security](https://www.postgresql.org/docs/16/ddl-rowsecurity.html)
- `impersonate_user_id` is stored in `auth.sessions` table (this can be challenged)
- I'm trying to move towards [Radical Simplicity](https://www.radicalsimpli.city/)
- [Don’t Build A General Purpose API To Power Your Own Front End](https://max.engineer/server-informed-ui)
- The page rendering spped, and therefore the execution speed of SQL queries, needs special attention

Components and libraries:

- ✅ [SSR](https://kit.svelte.dev/docs/page-options#ssr) [SvelteKit](https://github.com/sveltejs/kit) with [Hydration](https://kit.svelte.dev/docs/glossary#hydration)
- ✅ PostgreSQL database server
- ✅ [Postgres.js](https://github.com/porsager/postgres) - PostgreSQL client for Node.js
- ✅ Migration powered by [graphile-migrate](https://github.com/graphile/migrate)
- ✅ Token generated with [jsonwebtoken](https://github.com/auth0/node-jsonwebtoken)
- ✅PostgreSQL [Row-Level Security](https://www.postgresql.org/docs/16/ddl-rowsecurity.html)

Tooling:

- ✅ [asdf](https://asdf-vm.com/)
- ✅ [Docker](<https://en.wikipedia.org/wiki/Docker_(software)>) and [Docker Compose](https://docs.docker.com/compose/)
- ✅ [NodeJS](https://nodejs.org/en/)
- ✅ [pnpm](https://pnpm.io/)
- ✅ [Jest](https://jestjs.io/) for unittest

## Getting started

```sh
$ asdf install
```

```sh
$ pnpm install
```

Start database engine:

```sh
$ ./scripts/init.sh
$ ./load-fixtures.js
```

Start web server:

```sh
$ pnpm run dev
```

Go to http://localhost:5173/

## Valid logins

- email: `john.doe1@example.com`
  password: `secret1`
- email: `john.doe2@example.com`
  password: `secret2`
- email: `john.doe3@example.com`
  password: `secret3`

Create new user with:

```
$ pnpm run user create --email=john.doe4@example.com --username=john-doe4 --password=password --firstname=John --lastname=Doe
```

## Maildev

You can access to Maildev on http://localhost:1080

## Database migration

```
$ pnpm run migrate:watch
```

Apply migration in `migrations/current.sql` and commit:

```
$ pnpm run migrate:commit
```

## Execute Unittest

```
$ pnpm run migrate-test:watch
```

```sh
$ pnpm run -s tests
 PASS  tests/auth.js
  ✓ Create a user (39 ms)

Test Suites: 1 passed, 1 total
Tests:       1 passed, 1 total
Snapshots:   0 total
Time:        0.255 s, estimated 1 s
Ran all test suites.
```

## Prettier

Launch Prettier check:

```sh
$ pnpm run prettier-check
```

Apply Prettier fix example:

```sh
$ pnpm run prettier src/app.html
```

## ESlint

```sh
$ pnpm run eslint
```
