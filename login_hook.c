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

#include "postgres.h"
#include "miscadmin.h"
#include "commands/dbcommands.h"
#include "access/xact.h"
#include "access/xlog.h"
#include "access/transam.h"
#include "catalog/namespace.h"
#include "executor/spi.h"
#include "utils/snapmgr.h"
#include "utils/syscache.h"
#include "utils/builtins.h"
#include "catalog/pg_proc_d.h"

#if PG_VERSION_NUM < 170000
#define AmBackgroundWorkerProcess() (IsBackgroundWorker)
#endif

#ifdef PG_MODULE_MAGIC
PG_MODULE_MAGIC;
#endif

static char* version = "1.7";

static bool isExecutingLogin = false;

/*
 * function login_hook.get_login_hook_version() returns text.
 *
 * This function returns the current version of this database extension
 */
PG_FUNCTION_INFO_V1(get_login_hook_version);
PGDLLEXPORT Datum get_login_hook_version( PG_FUNCTION_ARGS)
{
	Datum login_hook_version = (Datum) palloc(VARHDRSZ + strlen(version));
	SET_VARSIZE(login_hook_version, VARHDRSZ + strlen(version));
	memcpy(VARDATA(login_hook_version), version, strlen(version));
	PG_RETURN_DATUM(login_hook_version);
}

/*
 * function login_hook.is_executing_login_hook() returns booean.
 *
 * This function returns true if the loginhook.login() function is executing
 * under control of the login_hook code.
 */
PG_FUNCTION_INFO_V1(is_executing_login_hook);
PGDLLEXPORT Datum is_executing_login_hook( PG_FUNCTION_ARGS)
{
	PG_RETURN_BOOL(isExecutingLogin);
}

void _PG_init(void);
/* Module entry point */
void _PG_init(void)
{
	char* dbName;
	Oid loginHookNamespaceOid;
	int startedATransaction = 0;
	Oid loginFuncOid;

	elog(DEBUG3,
	     "_PG_init() in login_hook.so, MyProcPid=%d, MyDatabaseId=%d, AmBackgroundWorkerProcess()=%d, isExecutingLogin=%d, login_hook version=%s",
	     MyProcPid, MyDatabaseId, AmBackgroundWorkerProcess(), isExecutingLogin, version);

#if PG_VERSION_NUM >= 170000
	if (MyDatabaseHasLoginEventTriggers) {
	    elog(DEBUG1, "A login event trigger is present in this database, so login_hook will not execute");
	    return;
	}
#endif
	/*
	 * If no database is selected, then it makes no sense trying to execute
	 * login code.
	 * This may occur for example in a replication target database.
	 */
	if (!OidIsValid(MyDatabaseId)) {
	    elog(DEBUG1, "No database selected so login_hook will not execute");
	    return;
	}

	/*
	 * When _PG_init invokes the login() function, _PG_init processing is not
	 * complete. So when that function invokes is_executing_login_hook() - which
	 * it is supposed to do - then shared library loading code is executed
	 * again, including the invocation of this _PG_init function.
	 */
	if (isExecutingLogin)
	{
		elog(DEBUG3, "nested invocation of login_hook._PG_INIT");
		return;
	}

	/*
	 * Parallel workers have their own initialisation. The login() function
	 * must not be invoked for them.
	 */
	if (AmBackgroundWorkerProcess())
	{
		elog(DEBUG1,
		     "login_hook did not do anything because we are in a background worker");
		return;
	}

	/*
	 * The login() function should only be executed on a primary server.
	 * If recovery is in progress, we are probably on a secondary server.
	 */
	if (RecoveryInProgress())
	{
		elog(DEBUG1,
		     "login_hook did not do anything because recovery is in progress. This is probably not the primary server.");
		return;
	}

#if PG_VERSION_NUM < 150000
	/*
	 * Since Postgres version 15beta3 we are already in a transaction here. But older
	 * versions will need to start one here.
	 */
    if (GetCurrentTransactionIdIfAny() == InvalidTransactionId)
    {
        /*
         * If we're not in a transaction, start one.
         */

        elog(DEBUG3,
             "login_hook is starting a transaction");
        StartTransactionCommand();
        PushActiveSnapshot(GetTransactionSnapshot());
        startedATransaction = 1;
    } else {
        elog(DEBUG3,
                     "login_hook did not start a transaction as one is already in progress");
    }
#else
    elog(DEBUG3,
                         "login_hook started a subtransaction");
    BeginInternalSubTransaction("login_hook");
    PushActiveSnapshot(GetTransactionSnapshot());
    startedATransaction = 1;
#endif

    dbName = get_database_name(MyDatabaseId);
    Assert(dbName); // warning: only active if kernel compiled with --enable-cassert

	/*
	 * See if schema 'login_hook' exists in this database. If it doesn't, we're
	 * done.
	 */
	loginHookNamespaceOid = get_namespace_oid("login_hook", true); // Do not generate error if schema does not exit (mising_ok = true)
	if (OidIsValid(loginHookNamespaceOid))
	{
	    /*
	     * See if a function login_hook.login() exists.
	     */
	    loginFuncOid = GetSysCacheOid(PROCNAMEARGSNSP,
	            Anum_pg_proc_oid,
                CStringGetDatum("login"),
                PointerGetDatum(buildoidvector(NULL, 0)),
                ObjectIdGetDatum(loginHookNamespaceOid),
                0);
	    if (OidIsValid(loginFuncOid)) {
#if PG_VERSION_NUM >= 170000
			elog(WARNING,
				 "Beware! Postgres17 is the last release for which the login_hook extension is maintained. Please use a login event trigger instead!");
#endif

            // Make the function login_hook.is_executing_login_hook() return true now
            isExecutingLogin = true;

            PG_TRY();
            {
                elog(DEBUG3,
                     "login_hook will execute login_hook.login() in database %s",
                     dbName);
                OidFunctionCall0Coll(loginFuncOid, InvalidOid);
                elog(DEBUG3,
                     "login_hook is back from excuting login_hook.login() in database %s",
                     dbName);

                // Make sure function login_hook.is_executing_login_hook() will return false ever after
                isExecutingLogin = false;
            }
            PG_CATCH();
            {
                // Make sure function login_hook.is_executing_login_hook() will return false ever after
                isExecutingLogin = false;
#if PG_VERSION_NUM < 150000
                AbortCurrentTransaction();
                startedATransaction = false;
#else
                RollbackAndReleaseCurrentSubTransaction();
                startedATransaction = false;
#endif
                if (superuser())
                {
                    ErrorData *edata = CopyErrorData();
#if PG_VERSION_NUM < 150000
                    ereport(WARNING,
                            ( errcode(edata->sqlerrcode),
                              errmsg("Function login_hook.login() returned with error in database %s.\nPlease resolve the error as only superusers can login now.",
                            		  dbName),
                              errhint("original message = %s", edata->message)));
#else
                    ereport(WARNING,
                            ( errcode(edata->sqlerrcode),
                              errmsg("Function login_hook.login() returned with error in database %s.\nPlease resolve the error as only superusers can login now.",
                            		  get_database_name(MyDatabaseId)),
                              errhint("original message = %s", edata->message)));
#endif
                }
                else
                {
                	dbName = get_database_name(MyDatabaseId);
#if PG_VERSION_NUM < 150000
                    elog(ERROR,
                         "Function login_hook.login() returned with error in database %s, only a superuser can login",
                         dbName);
#else
                    elog(ERROR,
                         "Function login_hook.login() returned with error in database %s, only a superuser can login",
						 get_database_name(MyDatabaseId));
#endif
                }
            }
            PG_END_TRY();
	    }
	    else
	    {
            elog(WARNING,
                 "Function login_hook.login() is not invoked because it does not exist in database %s",
                 dbName);
	    }
	}
	else
	{
		elog(DEBUG1,
		     "login_hook will not execute anything because schema login_hook does not exist in database %s",
		     dbName);
	}

#if PG_VERSION_NUM < 150000
	if (startedATransaction)
	{
		/*
		 * commit the transaction we started
		 */
	    PopActiveSnapshot();
		CommitTransactionCommand();
	}
#else
    if (startedATransaction)
    {
        PopActiveSnapshot();
        ReleaseCurrentSubTransaction();
    }
#endif

}
