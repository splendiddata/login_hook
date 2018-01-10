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

create function login_hook.login() returns void language plpgsql as $$
-- This function is to be overridden to be effective
begin
	raise notice 'login_hook.login() invoked - please override';
end $$;

grant execute on function login_hook.login() to public;