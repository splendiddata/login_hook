use strict;
use warnings;
use Test::More;

# PostgreSQL 13/14 used the older name for the TAP node module.
BEGIN
{
    unless (eval { require PostgresNode; 1; })
    {
        require PostgreSQL::Test::Cluster;
    }
}
my $node = PostgresNode->can('get_new_node')
    ? PostgresNode->get_new_node('login_error')
    : PostgreSQL::Test::Cluster->new('login_error');

$node->init;
# Load the library at session startup, including the setup connections.
$node->append_conf('postgresql.conf', "session_preload_libraries = 'login_hook'");
$node->append_conf('postgresql.conf', 'log_error_verbosity = verbose');
$node->append_conf('postgresql.conf', 'logging_collector = off');
$node->append_conf('postgresql.conf', 'restart_after_crash = on');
$node->start;

# Exercise the full database name in diagnostics after transaction cleanup.
my $dbname = 'login_hook_' . ('d' x 52);
$node->safe_psql('postgres', "CREATE DATABASE $dbname");
$node->safe_psql($dbname, q{
    CREATE EXTENSION login_hook;
    CREATE ROLE login_hook_test_user LOGIN;
    CREATE TABLE login_hook.attempts (username text);
    GRANT INSERT, SELECT ON login_hook.attempts TO PUBLIC;
    CREATE FUNCTION login_hook.login() RETURNS void LANGUAGE plpgsql AS $$
    BEGIN
        IF NOT login_hook.is_executing_login_hook() THEN
            RAISE EXCEPTION 'login hook is not marked as executing';
        END IF;
        INSERT INTO login_hook.attempts VALUES (current_user);
    END
    $$;
});

my ($ret, $stdout, $stderr) = $node->psql($dbname,
    'SELECT login_hook.is_executing_login_hook()');
is($ret, 0, 'superuser can log in with a healthy hook');
is($stdout, 'f', 'execution flag is reset after a successful hook');

($ret, $stdout, $stderr) = $node->psql($dbname,
    'SELECT login_hook.is_executing_login_hook()',
    extra_params => ['-U', 'login_hook_test_user']);
is($ret, 0, 'ordinary user can log in with a healthy hook');
is($stdout, 'f', 'ordinary user sees the execution flag reset');

$node->safe_psql($dbname, q{
    TRUNCATE login_hook.attempts;
    CREATE OR REPLACE FUNCTION login_hook.login() RETURNS void LANGUAGE plpgsql AS $$
    BEGIN
        INSERT INTO login_hook.attempts VALUES (current_user);
        RAISE EXCEPTION USING
            ERRCODE = '22012', MESSAGE = 'login hook diagnostic marker';
    END
    $$;
});

($ret, $stdout, $stderr) = $node->psql($dbname,
    'SELECT login_hook.is_executing_login_hook(), count(*) FROM login_hook.attempts');
is($ret, 0, 'superuser can log in when the hook raises an exception');
is($stdout, 'f|0', 'failed hook is rolled back and execution flag is reset');
like($stderr,
    qr/WARNING:  Function login_hook\.login\(\) returned with error in database \Q$dbname\E\./,
    'warning preserves the database name');
like($stderr, qr/HINT:  original message = login hook diagnostic marker/,
    'warning preserves the original error message');

# psql's verbosity setting does not affect notices received while connecting.
my $server_log;
{
    open my $log, '<', $node->logfile or die "cannot read server log: $!";
    local $/;
    $server_log = <$log>;
}
like($server_log,
    qr/WARNING:  22012: Function login_hook\.login\(\) returned with error in database \Q$dbname\E\./,
    'warning preserves the original SQLSTATE');

($ret, $stdout, $stderr) = $node->psql($dbname, 'SELECT 1',
    extra_params => ['-U', 'login_hook_test_user']);
isnt($ret, 0, 'ordinary user is denied login when the hook raises an exception');
like($stderr,
    qr/Function login_hook\.login\(\) returned with error in database \Q$dbname\E, only a superuser can login/,
    'ordinary user receives the intended rejection instead of a backend crash');

# Let recovery finish when running this test against the buggy implementation.
$node->poll_query_until('postgres', 'SELECT true')
    or die 'server did not become ready after the failed login';
$node->safe_psql($dbname, q{
    CREATE OR REPLACE FUNCTION login_hook.login() RETURNS void LANGUAGE plpgsql AS $$
    BEGIN
        IF NOT login_hook.is_executing_login_hook() THEN
            RAISE EXCEPTION 'login hook is not marked as executing';
        END IF;
    END
    $$;
});
($ret, $stdout, $stderr) = $node->psql($dbname,
    'SELECT login_hook.is_executing_login_hook()',
    extra_params => ['-U', 'login_hook_test_user']);
is($ret, 0, 'superuser can repair the hook and restore ordinary logins');
is($stdout, 'f', 'execution flag is reset after the repaired hook');

$node->stop;
done_testing();
