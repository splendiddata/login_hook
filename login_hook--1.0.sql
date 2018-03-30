/*
 * Copyright (c) Splendid Data Product Development B.V. 2013
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

create schema if not exists login_hook;
comment on schema login_hook is 'Belongs to the login_hook extension';
grant usage on schema login_hook to public;

/*
 * login_hook.get_login_hook_version() just returns the current version
 * of the login_hook database extension. Currently: "1.0".
 */
create or replace function login_hook.is_executing_login_hook()
    returns boolean 
    leakproof
    language C
    security definer
    as 'login_hook.so', 'is_executing_login_hook';
comment on function login_hook.is_executing_login_hook() is
    'Returns true if the login_hook.login() function is executed under control of the login_hook logic';
grant execute on function login_hook.is_executing_login_hook() to public;

/*
 * login_hook.get_login_hook_version() just returns the current version
 * of the login_hook database extension. Currently: "1.0".
 */
create or replace function login_hook.get_login_hook_version()
    returns text 
    immutable leakproof
    as 'login_hook.so', 'get_login_hook_version'
    language C
    security definer;
comment on function login_hook.get_login_hook_version() is
    'Returns the version of this database''s login_hook database extension';
grant execute on function login_hook.get_login_hook_version() to public;
