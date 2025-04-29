/*
 * Copyright (c) Splendid Data Product Development B.V. 2013 - 2025
 *
 * This program is free software: You may redistribute and/or modify under the
 * terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at Client's option) any
 * later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, Client should obtain one via www.gnu.org/licenses/.
 */

-- init
create extension login_hook;

-- Login to find that the login_hook.login() function does not exist
\c contrib_regression

create sequence login_hook.invocation_count;
-- Create the login_hook.login() function
create function login_hook.login() returns void language plpgsql as $$
BEGIN
	IF NOT login_hook.is_executing_login_hook()
	THEN
	    RAISE EXCEPTION 'The login_hook.login() function should only be invoked by the login_hook code';
	END IF;

	RAISE NOTICE 'login_hook.login() invocation %.', nextval('login_hook.invocation_count');
END
$$;

-- Login again and see that the login_hook.login() function is invoked
\c contrib_regression

/* Make sure that parallel workers do not invoke login_hook.login() */
-- encourage use of parallel plans
set parallel_setup_cost=0;
set parallel_tuple_cost=0;
set min_parallel_table_scan_size=0;
set max_parallel_workers_per_gather=4;
explain (costs off) select pronamespace::regnamespace, proname from pg_proc where upper(prosrc) = 'nonexisting function';
select pronamespace::regnamespace, proname from pg_proc where upper(prosrc) = 'nonexisting function';

-- Verify that parallel workers didn't increment the invocation count
select currval('login_hook.invocation_count');

-- Verify that  the login_hook.login() function can only be invoked as part of the login code
select login_hook.login();

select login_hook.get_login_hook_version();

/*
 * Test that if the login() function fails, the superuser can still login
 */
create or replace function login_hook.login() returns void language plpgsql as $$
BEGIN
	RAISE EXCEPTION 'The login_hook.login() function now intentionally fails';
END
$$;
\c contrib_regression
-- Create a login event trigger
create function login_hook.login_trigger() returns event_trigger language plpgsql as $$
BEGIN
    RAISE NOTICE 'login_hook.login_trigger() invocation %.', nextval('login_hook.invocation_count');
END
$$;
create event trigger login_trigger
    on login
    execute function login_hook.login_trigger();
alter event trigger login_trigger enable always;
-- login_hook.login() is not supposed to be executed any more now
\c contrib_regression
-- even with a disabled login event trigger, the login_hook.login() function should not be executed.
alter event trigger login_trigger disable;
\c contrib_regression
-- cleanup
drop function login_hook.login();
drop sequence login_hook.invocation_count;
drop event trigger login_trigger;
drop function login_hook.login_trigger();
drop schema login_hook cascade;
