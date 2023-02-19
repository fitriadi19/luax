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

--[[------------------------------------------------------------------------@@@
## Additional functions (Lua)
@@@]]

--@LOAD
local _, fs = pcall(require, "_fs")
fs = _ and fs

local F = require "F"

-- Pure Lua / Pandoc Lua implementation
if not fs then
    fs = {}

    if pandoc then
        fs.sep = pandoc.path.separator
        fs.path_sep = pandoc.path.search_path_separator
    else
        fs.sep = package.config:match("^([^\n]-)\n")
        fs.path_sep = fs.sep == '\\' and ";" or ":"
    end

--[[@@@
```lua
fs.getcwd()
```
returns the current working directory.
@@@]]

    if pandoc then
        fs.getcwd = pandoc.system.get_working_directory
    else
        function fs.getcwd()
            return sh.read "pwd" : trim()
        end
    end

--[[@@@
```lua
fs.dir([path])
```
returns the list of files and directories in
`path` (the default path is the current directory).
@@@]]

    if pandoc then
        fs.dir = F.compose{F, pandoc.system.list_directory}
    else
        function fs.dir(path)
            return sh.read("ls", path) : lines() : sort()
        end
    end

--[[@@@
```lua
fs.remove(name)
```
deletes the file `name`.
@@@]]

    function fs.remove(name)
        return os.remove(name)
    end

--[[@@@
```lua
fs.rename(old_name, new_name)
```
renames the file `old_name` to `new_name`.
@@@]]

    function fs.rename(old_name, new_name)
        return os.rename(old_name, new_name)
    end

--[[@@@
```lua
fs.copy(source_name, target_name)
```
copies file `source_name` to `target_name`.
The attributes and times are preserved.
@@@]]

    function fs.copy(source_name, target_name)
        local from, err_from = io.open(source_name, "rb")
        if not from then return from, err_from end
        local to, err_to = io.open(target_name, "wb")
        if not to then from:close(); return to, err_to end
        while true do
            local block = from:read(64*1024)
            if not block then break end
            local ok, err = to:write(block)
            if not ok then
                from:close()
                to:close()
                return ok, err
            end
        end
        from:close()
        to:close()
    end

--[[@@@
```lua
fs.mkdir(path)
```
creates a new directory `path`.
@@@]]

    if pandoc then
        fs.mkdir = pandoc.system.make_directory
    else
        function fs.mkdir(path)
            return sh.run("mkdir", path)
        end
    end

--[[@@@
```lua
fs.stat(name)
```
reads attributes of the file `name`. Attributes are:

- `name`: name
- `type`: `"file"` or `"directory"`
- `size`: size in bytes
- `mtime`, `atime`, `ctime`: modification, access and creation times.
- `mode`: file permissions
- `uR`, `uW`, `uX`: user Read/Write/eXecute permissions
- `gR`, `gW`, `gX`: group Read/Write/eXecute permissions
- `oR`, `oW`, `oX`: other Read/Write/eXecute permissions
- `aR`, `aW`, `aX`: anybody Read/Write/eXecute permissions
@@@]]

    local S_IRUSR = 1 << 8
    local S_IWUSR = 1 << 7
    local S_IXUSR = 1 << 6
    local S_IRGRP = 1 << 5
    local S_IWGRP = 1 << 4
    local S_IXGRP = 1 << 3
    local S_IROTH = 1 << 2
    local S_IWOTH = 1 << 1
    local S_IXOTH = 1 << 0

    fs.uR = S_IRUSR
    fs.uW = S_IWUSR
    fs.uX = S_IXUSR
    fs.aR = S_IRUSR|S_IRGRP|S_IROTH
    fs.aW = S_IWUSR|S_IWGRP|S_IWOTH
    fs.aX = S_IXUSR|S_IXGRP|S_IXOTH
    fs.gR = S_IRGRP
    fs.gW = S_IWGRP
    fs.gX = S_IXGRP
    fs.oR = S_IROTH
    fs.oW = S_IWOTH
    fs.oX = S_IXOTH

    function fs.stat(name)
        local st = sh.read("LANG=C", "stat", "-L", "-c '%s;%Y;%X;%W;%F;%f'", name, "2>/dev/null")
        if not st then return nil, "cannot stat "..name end
        local size, mtime, atime, ctime, type, mode = st:trim():split ";":unpack()
        mode = tonumber(mode, 16)
        if type == "regular file" then type = "file" end
        return F{
            name = name,
            size = tonumber(size),
            mtime = tonumber(mtime),
            atime = tonumber(atime),
            ctime = tonumber(ctime),
            type = type,
            mode = mode,
            uR = (mode & S_IRUSR) ~= 0,
            uW = (mode & S_IWUSR) ~= 0,
            uX = (mode & S_IXUSR) ~= 0,
            gR = (mode & S_IRGRP) ~= 0,
            gW = (mode & S_IWGRP) ~= 0,
            gX = (mode & S_IXGRP) ~= 0,
            oR = (mode & S_IROTH) ~= 0,
            oW = (mode & S_IWOTH) ~= 0,
            oX = (mode & S_IXOTH) ~= 0,
            aR = (mode & (S_IRUSR|S_IRGRP|S_IROTH)) ~= 0,
            aW = (mode & (S_IWUSR|S_IWGRP|S_IWOTH)) ~= 0,
            aX = (mode & (S_IXUSR|S_IXGRP|S_IXOTH)) ~= 0,
        }
    end

--[[@@@
```lua
fs.inode(name)
```
reads device and inode attributes of the file `name`.
Attributes are:

- `dev`, `ino`: device and inode numbers
@@@]]

    function fs.inode(name)
        local st = sh.read("LANG=C", "stat", "-L", "-c '%d;%i'", name, "2>/dev/null")
        if not st then return nil, "cannot stat "..name end
        local dev, ino = st:trim():split ";":unpack()
        return F{
            ino = tonumber(ino),
            dev = tonumber(dev),
        }
    end

--[[@@@
```lua
fs.chmod(name, other_file_name)
```
sets file `name` permissions as
file `other_file_name` (string containing the name of another file).

```lua
fs.chmod(name, bit1, ..., bitn)
```
sets file `name` permissions as
`bit1` or ... or `bitn` (integers).
@@@]]

    function fs.chmod(name, ...)
        local mode = {...}
        if type(mode[1]) == "string" then
            return sh.run("chmod", "--reference="..mode[1], name, "2>/dev/null")
        else
            return sh.run("chmod", ("%o"):format(F(mode):fold(F.op.bor, 0)), name)
        end
    end

--[[@@@
```lua
fs.touch(name)
```
sets the access time and the modification time of
file `name` with the current time.

```lua
fs.touch(name, number)
```
sets the access time and the modification
time of file `name` with `number`.

```lua
fs.touch(name, other_name)
```
sets the access time and the
modification time of file `name` with the times of file `other_name`.
@@@]]

    function fs.touch(name, opt)
        if opt == nil then
            return sh.run("touch", name, "2>/dev/null")
        elseif type(opt) == "number" then
            return sh.run("touch", "-d", '"'..os.date("%c", opt)..'"', name, "2>/dev/null")
        elseif type(opt) == "string" then
            return sh.run("touch", "--reference="..opt, name, "2>/dev/null")
        else
            error "bad argument #2 to touch (none, nil, number or string expected)"
        end
    end

--[[@@@
```lua
fs.basename(path)
```
return the last component of path.
@@@]]

    if pandoc then
        fs.basename = pandoc.path.filename
    else
        function fs.basename(path)
            return sh.read("basename", path) : trim()
        end
    end

--[[@@@
```lua
fs.dirname(path)
```
return all but the last component of path.
@@@]]

    if pandoc then
        fs.dirname = pandoc.path.directory
    else
        function fs.dirname(path)
            return sh.read("dirname", path) : trim()
        end
    end

--[[@@@
```lua
fs.splitext(path)
```
return the name without the extension and the extension.
@@@]]

    if pandoc then
        function fs.splitext(path)
            if fs.basename(path):match "^%." then
                return path, ""
            end
            return pandoc.path.split_extension(path)
        end
    else
        function fs.splitext(path)
            local name, ext = path:match("^(.*)(%.[^/\\]-)$")
            if name and ext and #name > 0 and not name:has_suffix(fs.sep) then
                return name, ext
            end
            return path, ""
        end
    end

--[[@@@
```lua
fs.realpath(path)
```
return the resolved path name of path.
@@@]]

    if pandoc then
        fs.realpath = pandoc.path.normalize
    else
        function fs.realpath(path)
            return sh.read("realpath", path) : trim()
        end
    end

--[[@@@
```lua
fs.absname(path)
```
return the absolute path name of path.
@@@]]

    function fs.absname(path)
        if path:match "^[/\\]" or path:match "^.:" then return path end
        return fs.getcwd()..fs.sep..path
    end

--[[@@@
```lua
fs.mkdirs(path)
```
creates a new directory `path` and its parent directories.
@@@]]

    if pandoc then
        function fs.mkdirs(path)
            return pandoc.system.make_directory(path, true)
        end
    else
        function fs.mkdirs(path)
            return sh.run("mkdir", "-p", path)
        end
    end

end

--[[@@@
```lua
fs.join(...)
```
return a path name made of several path components
(separated by `fs.sep`).
If a component is absolute, the previous components are removed.
@@@]]

if pandoc then
    function fs.join(...)
        return pandoc.path.join(F.flatten{...})
    end
else
    function fs.join(...)
        local function add_path(ps, p)
            if p:match("^"..fs.sep) then return F{p} end
            ps[#ps+1] = p
            return ps
        end
        return F{...}
            :flatten()
            :fold(add_path, F{})
            :str(fs.sep)
    end
end

--[[@@@
```lua
fs.is_file(name)
```
returns `true` if `name` is a file.
@@@]]

function fs.is_file(name)
    local stat = fs.stat(name)
    return stat ~= nil and stat.type == "file"
end

--[[@@@
```lua
fs.is_dir(name)
```
returns `true` if `name` is a directory.
@@@]]

function fs.is_dir(name)
    local stat = fs.stat(name)
    return stat ~= nil and stat.type == "directory"
end

--[[@@@
```lua
fs.findpath(name)
```
returns the full path of `name` if `name` is found in `$PATH` or `nil`.
@@@]]

function fs.findpath(name)
    local function exists_in(path) return fs.is_file(fs.join(path, name)) end
    local path = os.getenv("PATH")
        :split(fs.path_sep)
        :find(exists_in)
    if path then return fs.join(path, name) end
    return nil, name..": not found in $PATH"
end

--[[@@@
```lua
fs.mkdirs(path)
```
creates a new directory `path` and its parent directories.
@@@]]

if not fs.mkdirs then
    function fs.mkdirs(path)
        if path == "" or fs.stat(path) then return end
        fs.mkdirs(fs.dirname(path))
        fs.mkdir(path)
    end
end

--[[@@@
```lua
fs.mv(old_name, new_name)
```
alias for `fs.rename(old_name, new_name)`.
@@@]]

fs.mv = fs.rename

--[[@@@
```lua
fs.rm(name)
```
alias for `fs.remove(name)`.
@@@]]

fs.rm = fs.remove

--[[@@@
```lua
fs.rmdir(path, [params])
```
deletes the directory `path` and its content recursively.
@@@]]

if pandoc then
    function fs.rmdir(path)
        pandoc.system.remove_directory(path, true)
        return true
    end
else
    function fs.rmdir(path)
        fs.walk(path, {reverse=true}):map(fs.rm)
        return fs.rm(path)
    end
end

--[[@@@
```lua
fs.walk([path], [{reverse=true|false, links=true|false, cross=true|false}])
```
returns a list listing directory and
file names in `path` and its subdirectories (the default path is the current
directory).

Options:

- `reverse`: the list is built in a reverse order
  (suitable for recursive directory removal)
- `links`: follow symbolic links
- `cross`: walk across several devices
- `func`: function applied to the current file or directory.
  `func` takes two parameters (path of the file or directory and the stat object returned by `fs.stat`)
  and returns a boolean (to continue or not walking recursively through the subdirectories)
  and a value (e.g. the name of the file) to be added to the listed returned by `walk`.
@@@]]

function fs.walk(path, options)
    options = options or {}
    local reverse = options.reverse
    local follow_links = options.links
    local cross_device = options.cross
    local func = options.func or function(name, _) return true, name end
    local dirs = {path or "."}
    local acc_files = {}
    local acc_dirs = {}
    local seen = {}
    local dev0 = nil
    local function already_seen(name)
        local inode = fs.inode(name)
        if not inode then return true end
        dev0 = dev0 or inode.dev
        if dev0 ~= inode.dev and not cross_device then
            return true
        end
        if not seen[inode.dev] then
            seen[inode.dev] = {[inode]=true}
            return false
        end
        if not seen[inode.dev][inode.ino] then
            seen[inode.dev][inode.ino] = true
            return false
        end
        return true
    end
    while #dirs > 0 do
        local dir = table.remove(dirs)
        if not already_seen(dir) then
            local names = fs.dir(dir)
            if names then
                table.sort(names)
                for i = 1, #names do
                    local name = dir..fs.sep..names[i]
                    local stat = fs.stat(name)
                    if stat then
                        if stat.type == "directory" or (follow_links and stat.type == "link") then
                            local continue, new_name = func(name, stat)
                            if continue then
                                dirs[#dirs+1] = name
                            end
                            if new_name then
                                if reverse then acc_dirs = {new_name, acc_dirs}
                                else acc_dirs[#acc_dirs+1] = new_name
                                end
                            end
                        else
                            local _, new_name = func(name, stat)
                            if new_name then
                                acc_files[#acc_files+1] = new_name
                            end
                        end
                    end
                end
            end
        end
    end
    return F.flatten(reverse and {acc_files, acc_dirs} or {acc_dirs, acc_files})
end

--[[@@@
```lua
fs.with_tmpfile(f)
```
calls `f(tmp)` where `tmp` is the name of a temporary file.
@@@]]

if pandoc then
    function fs.with_tmpfile(f)
        return pandoc.system.with_temporary_directory("luax-XXXXXX", function(tmpdir)
            return f(fs.join(tmpdir, "tmpfile"))
        end)
    end
else
    function fs.with_tmpfile(f)
        local tmp = os.tmpname()
        local ret = {f(tmp)}
        fs.rm(tmp)
        return table.unpack(ret)
    end
end

--[[@@@
```lua
fs.with_tmpdir(f)
```
calls `f(tmp)` where `tmp` is the name of a temporary directory.
@@@]]

if pandoc then
    function fs.with_tmpdir(f)
        return pandoc.system.with_temporary_directory("luax-XXXXXX", f)
    end
else
    function fs.with_tmpdir(f)
        local tmp = os.tmpname()
        fs.rm(tmp)
        fs.mkdir(tmp)
        local ret = {f(tmp)}
        fs.rmdir(tmp)
        return table.unpack(ret)
    end
end

--[[@@@
```lua
fs.with_dir(path, f)
```
changes the current working directory to `path` and calls `f()`.
@@@]]

if pandoc then
    fs.with_dir = pandoc.system.with_working_directory
elseif fs.chdir then
    function fs.with_dir(path, f)
        local old = fs.getcwd()
        fs.chdir(path)
        local ret = {f()}
        fs.chdir(old)
        return table.unpack(ret)
    end
end

--[[@@@
```lua
fs.with_env(env, f)
```
changes the environnement to `env` and calls `f()`.
@@@]]

if pandoc then
    fs.with_env = pandoc.system.with_environment
end

--[[@@@
```lua
fs.read(filename)
```
returns the content of the text file `filename`.
@@@]]

function fs.read(name)
    local f, oerr = io.open(name, "r")
    if not f then return f, oerr end
    local content, rerr = f:read("a")
    f:close()
    return content, rerr
end

--[[@@@
```lua
fs.write(filename, ...)
```
write `...` to the text file `filename`.
@@@]]

function fs.write(name, ...)
    local content = F{...}:flatten():str()
    local f, oerr = io.open(name, "w")
    if not f then return f, oerr end
    local ok, werr = f:write(content)
    f:close()
    return ok, werr
end

--[[@@@
```lua
fs.read_bin(filename)
```
returns the content of the binary file `filename`.
@@@]]

function fs.read_bin(name)
    local f, oerr = io.open(name, "rb")
    if not f then return f, oerr end
    local content, rerr = f:read("a")
    f:close()
    return content, rerr
end

--[[@@@
```lua
fs.write_bin(filename, ...)
```
write `...` to the binary file `filename`.
@@@]]

function fs.write_bin(name, ...)
    local content = F{...}:flatten():str()
    local f, oerr = io.open(name, "wb")
    if not f then return f, oerr end
    local ok, werr = f:write(content)
    f:close()
    return ok, werr
end

return fs