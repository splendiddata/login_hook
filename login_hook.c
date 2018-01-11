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

#include "postgres.h"
#include "executor/spi.h"
#include "miscadmin.h"
#include "commands/dbcommands.h"
#include "access/xact.h"
#include "catalog/namespace.h"

#ifdef PG_MODULE_MAGIC
PG_MODULE_MAGIC;
#endif

void _PG_init(void);

/* Module entry point */
void _PG_init(void)
{
	char* dbName;
	Oid loginHookNamespaceOid;

	if (IsBackgroundWorker)
	{
		elog(DEBUG3,
				"login_hook did not do anything because we are in a background worker");
		return;
	}

	if (!OidIsValid(MyDatabaseId))
	{
		elog(DEBUG3,
				"login_hook did not do anything because MyDatabaseId is invalid");
		return;
	}

	/*
	 * Start a transaction
	 */
	StartTransactionCommand();

	dbName = get_database_name(MyDatabaseId);

	/*
	 * See if schema 'login_hook' exists in this database. If it isn't, we're
	 * done. If it is, it is supposed to contain a no-argument function
	 * login() returns void. So we will invoke that.
	 */
	loginHookNamespaceOid = get_namespace_oid("login_hook", true);
	if (OidIsValid(loginHookNamespaceOid))
	{
		SPI_connect();

		elog(DEBUG3,
				"login_hook will execute select login_hook.login() in database %s",
				dbName);
		SPI_execute("select login_hook.login()", false, 1);
		elog(DEBUG3,
				"login_hook is back from select login_hook.login() in database %s",
				dbName);

		SPI_finish();
	}
	else
	{
		elog(DEBUG1,
				"login_hook will not execute anything because extension login_hook does not exist in database %s",
				dbName);
	}

	/*
	 * commit
	 */
	CommitTransactionCommand();
}
