/* This file is part of luax.
 *
 * luax is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * luax is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with luax.  If not, see <https://www.gnu.org/licenses/>.
 *
 * For further information about luax you can visit
 * http://cdelord.fr/luax
 */

/***************************************************************************@@@
# sys: System module

```lua
local sys = require "sys"
```
@@@*/

#include "sys.h"

#include <stdlib.h>
#include <string.h>

#include "luax_config.h"

#include "crypt/crypt.h"
#include "lz4/lz4.h"

#include "tools.h"

#include "libluax.h"

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

static int sys_bootstrap(lua_State *L)
{
    /* Read and execute a chunk in arg[0] */

    /* exe = arg[0] */
    int type = lua_getglobal(L, "arg");
    if (type != LUA_TTABLE)
    {
        error(NULL, "Can not read arg[0]");
    }
    lua_rawgeti(L, -1, 0);
    const char *exe = luaL_checkstring(L, -1);

    luax_run(L, exe); /* no return */
}

static const luaL_Reg blsyslib[] =
{
    {"bootstrap", sys_bootstrap},
    {NULL, NULL}
};

static inline void set_string(lua_State *L, const char *name, const char *val)
{
    lua_pushstring(L, val);
    lua_setfield(L, -2, name);
}

/*@@@
```lua
sys.os
```
`"linux"`, `"macos"` or `"windows"`.

```lua
sys.arch
```
`"x86_64"`, `"i386"` or `"aarch64"`.

```lua
sys.abi
```
`"musl"` or `"gnu"`.
@@@*/

LUAMOD_API int luaopen_sys (lua_State *L)
{
    luaL_newlib(L, blsyslib);
    set_string(L, "arch", LUAX_ARCH);
    set_string(L, "os", LUAX_OS);
    set_string(L, "abi", LUAX_ABI);
    return 1;
}
