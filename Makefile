# Copyright (c) Splendid Data Product Development B.V. 2013
# 
# This program is free software: You may redistribute and/or modify under the 
# terms of the GNU General Public License as published by the Free Software 
# Foundation, either version 3 of the License, or (at Client's option) any 
# later version.
# 
# This program is distributed in the hope that it will be useful, but WITHOUT 
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with 
# this program.  If not, Client should obtain one via www.gnu.org/licenses/.
#

MODULE_big = login_hook
OBJS = login_hook.o
EXTENSION = login_hook
DATA = login_hook--1.0.sql login_hook--1.0--1.1.sql login_hook--1.1.sql 
DOCS = login_hook.html login_hook.css
PG_CONFIG = pg_config
REGRESS = test_login_hook

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
