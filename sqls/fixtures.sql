\echo "Loading fixtures..."

SET client_min_messages TO WARNING;

TRUNCATE auth.users CASCADE;

SELECT auth.create_user(
    username   => 'john-doe1',
    first_name => 'John',
    last_name  => 'Doe1',
    email      => 'john.doe1@example.com',
    password   => 'secret1',
    is_staff   => true,
    is_active  => true
);

SELECT auth.create_user(
    username   => 'john-doe2',
    first_name => 'John',
    last_name  => 'Doe2',
    email      => 'john.doe2@example.com',
    password   => 'secret2',
    is_staff   => false,
    is_active  => true
);

SELECT auth.create_user(
    username   => 'john-doe3',
    first_name => 'John',
    last_name  => 'Doe3',
    email      => 'john.doe3@example.com',
    password   => 'secret3',
    is_staff   => false,
    is_active  => false
);
