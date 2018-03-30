# login_hook
Postgres database extension to execute som code on user login, comparable to
Oracle's after logon trigger.
## Postgres versions
The login_hook database extension is developed in Postgres 10. It might work on 
older Postgres versions as well but that hasn't been tested.
## Installation
First you'll need to compile the database extension. Please check the
[Postgres manual](https://www.postgresql.org/docs/10/static/extend-pgxs.html) 
for that.

After compilation, the login_hook.so library must be set to load at session
start. So please alter the postgresql.conf file and add the login\_hook.so
library to the session\_preload\_libraries setting. For example:

```
      .
      .
      .

#------------------------------------------------------------------------------
# CUSTOMIZED OPTIONS
#------------------------------------------------------------------------------

# Add settings for extensions here
#
session_preload_libraries = 'login_hook'
```
 
Restart the database to activate the setting.
 
Then logon to then database and execute:
 
```SQL
create extension login_hook;
```

And create function login_hook.login() that is to be executed when a client
logs in. For example:

```PLpgSQL
CREATE OR REPLACE FUNCTION login_hook.login() RETURNS VOID LANGUAGE PLPGSQL AS $$
DECLARE
    ex_state   TEXT;
    ex_message TEXT;
    ex_detail  TEXT;
    ex_hint    TEXT;
    ex_context TEXT;
BEGIN
	IF NOT login_hook.is_executing_login_hook()
	THEN
	    RAISE EXCEPTION 'The login_hook.login() function should only be invoked by the login_hook code';
	END IF;
	
	BEGIN
	   -- 
	   -- Do whatever you need to do at login here.
	   -- For example:
	   RAISE NOTICE 'Hello %', current_user;
	EXCEPTION
	   WHEN OTHERS THEN
	       GET STACKED DIAGNOSTICS ex_state   = RETURNED_SQLSTATE
	                             , ex_message = MESSAGE_TEXT
	                             , ex_detail  = PG_EXCEPTION_DETAIL
	                             , ex_hint    = PG_EXCEPTION_HINT
	                             , ex_context = PG_EXCEPTION_CONTEXT;
	       RAISE LOG e'Error in login_hook.login()\nsqlstate: %\nmessage : %\ndetail  : %\nhint    : %\ncontext : %'
	               , ex_state
	               , ex_message
	               , ex_detail
	               , ex_hint
	               , ex_context;
    END	;       
END 
$$;
GRANT EXECUTE ON FUNCTION login_hook.login() TO PUBLIC;
```
#### Remarks:
the public execute permission is absolutely necessary because the function will
be invoked for every body/thing that logs in to the database.

Having public access granted to everybody might tempt people to execute the
login_hook.login() function at any time. But of course it is intended to run
only at login. The login\_hook.is\_executing\_login\_hook() function can be used
to check if the function is invoked under the control of the login_hook code.

Make sure that all exceptions that occur in the login\_hook.login() function
are properly dealt with because otherwise logging in to the database might
prove challenging.
## Functions
**login_hook.is_executing_login_hook() returns boolean**

    returns true when the login_hook.login() function is invoked under 
    control of the login_hook code. When invoked during a normal
    session, it will always return false.
    
**login_hook.get_login_hook_version() returns text**

    returns the compiled version of the login_hook software.
    
**login_hook.login() returns void**

    To be provided by you! 
