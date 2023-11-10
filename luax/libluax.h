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

#pragma once

#include "lauxlib.h"
#include "lualib.h"

#include <stdlib.h>

/* C module registration function */
LUAMOD_API int luaopen_libluax(lua_State *L);

/* libluax functions to decode and execute a LuaX chunk of Lua code */

/* decrypt and decompress a LuaX/app runtime */
void decode_runtime(const char *input, size_t input_len, char **output, size_t *output_len);

/* get arg[0] */
const char *arg0(lua_State *L);

/* run a decrypted and decompressed chunk */
int run_buffer(lua_State *L, char *buffer, size_t size, const char *name);