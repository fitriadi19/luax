--[[
This file is part of luax.

luax is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

luax is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with luax.  If not, see <https://www.gnu.org/licenses/>.

For further information about luax you can visit
http://cdelord.fr/luax
--]]

-- bundle a set of scripts into a single Lua script that can be added to the runtime

local bundle = {}

local fs = require "fs"
local lz4 = require "lz4"
local crypt = require "crypt"
local config = require "luax_config"

bundle.magic = "\0"..config.magic_id.."\0"

local header_format = ("<I4c%d"):format(#bundle.magic)

local function read(name)
    local f = io.open(name)
    if f == nil then
        io.stderr:write("error: ", name, ": File not found\n")
        os.exit(1)
    end
    assert(f)
    local content = f:read "a"
    f:close()
    return content
end

local function Bundle()
    local self = {}
    local fragments = {}
    function self.emit(s) fragments[#fragments+1] = s end
    function self.get() return table.concat(fragments) end
    return self
end

local function strip_ext(path)
    return path:gsub("%.lua$", "")
end

local function last_line(s)
    local last = ""
    s:gsub("[^\r\n]+", function(line)
        line = line:gsub("^%s*(.-)%s*$", "%1")
        if #line > 0 then last = line end
    end)
    return last
end

local function mlstr(code)
    local n = 0
    code:gsub("](=*)]", function(s)
        n = math.max(n, #s+1)
    end)
    local eqs = ("="):rep(n)
    return table.concat{"[", eqs, "[", code, "]", eqs, "]"}
end

function bundle.bundle(arg)

    local kind = "prog"
    local format = "binary"
    local scripts = {}
    local explicit_main = false
    for i = 1, #arg do
        if arg[i] == "-lib" then kind = "lib"
        elseif arg[i] == "-binary" then format = "binary"
        elseif arg[i] == "-ascii"  then format = "ascii"
        elseif arg[i] == "-lua"    then format = "lua"
        elseif fs.ext(arg[i]) == ".lua" then
            local content = read(arg[i]):gsub("^#![^\n]*", "")
            local new_name = content:match("@".."LIB=([%w%._%-]+)")
            local name = new_name or fs.basename(strip_ext(arg[i]))
            local main = content:match("@".."MAIN")
            local load = content:match("@".."LOAD")
            local new_load_name = content:match("@".."LOAD=([%w%._%-]+)")
            local load_name = new_load_name or name
            local lib = new_name or load or content:match("@".."LIB")
            local maybe_main =
                    not lib
                and not load
                and not main
                and not last_line(content):match "^%s*return"
            scripts[#scripts+1] = {
                path = arg[i],
                name = name,
                main = main,
                lib = lib,
                load = load,
                load_name = load_name,
                maybe_main = maybe_main,
                content = content,
            }
            explicit_main = explicit_main or main
        else
            -- file embeded as a Lua module returning the content of the file
            local name = fs.basename(arg[i])
            local content = read(arg[i])
            if content:match "^[%g%s]*$" then
                content = ("return %s"):format(mlstr(content))
            else
                content = ("return require'crypt'.unbase64 %s"):format(mlstr(crypt.base64(content)))
            end
            scripts[#scripts+1] = {
                path = arg[i],
                name = name,
                main = false,
                lib = true,
                load = false,
                load_name = name,
                maybe_main = false,
                content = content,
            }
        end
    end

    local main_scripts = {}
    if explicit_main then
        -- If there are explicit main scripts, only keep them
        for i = 1, #scripts do
            if scripts[i].main then
                main_scripts[#main_scripts+1] = scripts[i].path
            end
            scripts[i].maybe_main = false
        end
    else
        -- No explicit main, count other plausible main scripts
        for i = 1, #scripts do
            if scripts[i].maybe_main then
                scripts[i].main = true
                main_scripts[#main_scripts+1] = scripts[i].path
            end
        end
    end
    if kind == "lib" then
        -- libraries shall not contain main scripts
        if #main_scripts > 0 then
            error "The LuaX runtime shall not contain main scripts"
        end
    else
        -- real LuaX applications shall contain one and only one main script
        if #main_scripts > 1 then
            error("Too many main scripts:\n"..table.concat(main_scripts, "\n"))
        elseif #main_scripts == 0 then
            error "No main script"
        end
    end

    local home = os.getenv"HOME"

    local function home_path(name)
        if name:match("^"..home) then
            return fs.realpath(name):gsub("^"..home, "~")
        end
        return name
    end

    local plain = Bundle()
    if kind == "lib" and format == "lua" and config.version then
        plain.emit("--@LOAD=_: load luax to expose LuaX modules\n")
        plain.emit("_LUAX_VERSION = '"..config.version.."'\n");
        plain.emit("_LUAX_DATE = '"..config.date.."'\n");
    end
    plain.emit "local function lib(path, src) return assert(load(src, '@'..path, 't')) end\n"
    local function compile_library(script)
        assert(load(script.content, "@"..script.path, 't'))
        plain.emit(("[%q] = lib(%q, %s),\n"):format(script.name, home_path(script.path), mlstr(script.content)))
    end
    local function load_library(script)
        if script.load_name == "_" then
            plain.emit(("require %q\n"):format(script.name))
        else
            plain.emit(("_ENV[%q] = require %q\n"):format(script.load_name, script.name))
        end
    end
    local function run_script(script)
        assert(load(script.content, "@"..script.path, 't'))
        plain.emit(("return lib(%q, %s)()\n"):format(home_path(script.path), mlstr(script.content)))
    end
    if #scripts > 1 then -- there are libs
        plain.emit "local libs = {\n"
        for i = 1, #scripts do
            -- add non main scripts to the libs table used by the require function
            if not scripts[i].main then
                compile_library(scripts[i])
            end
        end
        plain.emit "}\n"
        plain.emit "table.insert(package.searchers, 2, function(name) return libs[name] end)\n"
    end
    for i = 1, #scripts do
        if scripts[i].load then
            -- load packages are require'd and stored in a global variable
            load_library(scripts[i])
        end
    end
    for i = 1, #scripts do
        if scripts[i].main then
            -- finally the main script is executed
            run_script(scripts[i])
        end
    end

    local plain_payload = plain.get()
    local payload = crypt.rc4(lz4.lz4(plain_payload))

    if format == "binary" then
        return payload .. header_format:pack(#payload, bundle.magic)
    end

    if format == "ascii" then
        return crypt.hex(payload):gsub("..", "'\\x%0',") .. "\n"
    end

    if format == "lua" then
        return plain_payload
    end

    error(format..": invalid format")

end

local function drop_chunk(exe)
    local header_size = header_format:packsize()
    local size, magic = header_format:unpack(exe, #exe - header_size + 1)
    if magic ~= bundle.magic then
        io.stderr:write("error: no LuaX header found in the current target\n")
        os.exit(1)
    end
    return exe:sub(1, #exe - header_size - size + 1)
end

function bundle.combine(target, scripts)
    local runtime = drop_chunk(read(target))
    local chunk = bundle.bundle(scripts)
    return runtime..chunk, chunk
end

function bundle.combine_lua(scripts)
    local F = require "F"
    local chunk = bundle.bundle(F.flatten{scripts})
    return chunk
end

local function called_by(f, level)
    level = level or 1
    local caller = debug.getinfo(level, "f")
    if caller == nil then return false end
    if caller.func == f then return true end
    return called_by(f, level+1)
end

if called_by(require) then return bundle end

io.stdout:write(bundle.bundle(arg))