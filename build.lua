section [[
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
]]

local F = require "F"
local fs = require "fs"
local sys = require "sys"

help.name "LuaX"
help.description [[
Lua eXtended
Copyright (C) 2021-2023 Christophe Delord (https://cdelord.fr/luax)

luax is a Lua interpreter and REPL based on Lua 5.4
augmented with some useful packages.
luax can also produce standalone executables from Lua scripts.

luax runs on several platforms with no dependency:

- Linux (x86_64, x86, aarch64)
- MacOS (x86_64, aarch64)
- Windows (x86_64, x86)

luax can « cross-compile » scripts from and to any of these platforms.
]]

section [[
WARNING: This file has been generated by bang. DO NOT MODIFY IT.
If you need to update the build system, please modify build.lua
and run bang to regenerate build.ninja.
]]

local targets = F{
    -- Linux
    "x86_64-linux-musl",
    "x86_64-linux-gnu",
    --"x86-linux-musl",         -- 32-bit targets are deprecated
    --"x86-linux-gnu",          -- 32-bit targets are deprecated
    "aarch64-linux-musl",
    "aarch64-linux-gnu",

    -- Windows
    "x86_64-windows-gnu",
    --"x86-windows-gnu",        -- 32-bit targets are deprecated

    -- MacOS
    "x86_64-macos-none",
    "aarch64-macos-none",
}

local mode = nil -- fast, small, quick, debug
local host = false
local upx = false

F.foreach(arg, function(a)
    local function set_mode()
        if mode~=nil then F.error_without_stack_trace(a..": duplicate compilation mode", 2) end
        mode = a
    end
    (case(a) {
        fast   = set_mode,
        small  = set_mode,
        quick  = set_mode,
        debug  = set_mode,
        host   = function() host = true end,
        upx    = function() upx = true end,
    } or F.error_without_stack_trace(a..": unknown parameter", 1)) ()
end)

mode = F.default("fast", mode)
if mode=="debug" and upx then F.error_without_stack_trace("UPX compression not available in debug mode") end

if host then
    targets = targets : filter(function(target)
        local target_arch, target_os, _ = target:split"%-":unpack()
        return target_os == sys.os and target_arch == sys.arch
    end)
end

section("Compilation options")
comment(("Compilation mode: %s"):format(mode))
targets : foreachi(function(i, target)
    comment(("%-16s: %s"):format(i==1 and "Targets" or "", target))
end)
comment(("Compression     : %s"):format(upx and "UPX" or "none"))

--===================================================================
section "Build environment"
---------------------------------------------------------------------

var "builddir" ".build"

var "bin" "$builddir/bin"
var "lib" "$builddir/lib"
var "doc" "$builddir/doc"
var "tmp" "$builddir/tmp"
var "test" "$builddir/test"

local compile = {}
local test = {}
local doc = {}

--===================================================================
section "Zig compiler"
---------------------------------------------------------------------

local zig_version = "0.11.0"
var "zig"       (".zig" / zig_version / "zig")
var "zig_cache" (vars.zig:dirname() / "cache")

local set_cache = "export ZIG_LOCAL_CACHE_DIR=$zig_cache;"

build "$zig" { "tools/install_zig.sh",
    description = {"GET zig", zig_version},
    command = {"$in", zig_version, "$out"},
    pool = "console",
}

rule "mkdir" {
    description = "MKDIR $out",
    command = "mkdir -p $out",
}

build "$zig_cache" { "mkdir" }

local include_path = {
    ".",
    "$tmp",
    "lua",
    "ext/c/lz4/lib",
    "libluax",
}

local native_cflags = {
    "-std=gnu2x",
    "-s -O3 -flto=thin",
    F.map(F.prefix"-I", include_path),
    "$$LUA_CFLAGS",
    "-Wno-constant-logical-operand",
}

local native_ldflags = {
    "-rdynamic",
    "-s -flto=thin",
}

local cflags = {
    "-std=gnu2x",
    case(mode) {
        fast  = "-s -O3",
        small = "-s -Os",
        quick = {},
        debug = "-g",
    },
    F.map(F.prefix"-I", include_path),
}

local luax_cflags = {
    cflags,
    "-Werror",
    "-Wall",
    "-Wextra",
    "-Weverything",
    "-Wno-padded",
    "-Wno-reserved-identifier",
    "-Wno-disabled-macro-expansion",
    "-Wno-used-but-marked-unused",
    "-Wno-documentation",
    "-Wno-documentation-unknown-command",
    "-Wno-declaration-after-statement",
    "-Wno-unsafe-buffer-usage",
}

local ext_cflags = {
    cflags,
    "-Wno-constant-logical-operand",
}

local ldflags = {
    case(mode) {
        fast  = "-s",
        small = "-s",
        quick = {},
        debug = {},
    },
}

rule "cc" {
    description = "CC $in",
    command = {
        ". tools/build_env.sh;",
        set_cache,
        "$zig cc -c", "-target", "$$ARCH-$$OS-$$LIBC", native_cflags, "-MD -MF $depfile $in -o $out",
    },
    implicit_in = {
        "$zig", "$zig_cache",
        "tools/build_env.sh",
    },
    depfile = "$out.d",
}

rule "ld" {
    description = "LD $out",
    command = {
        ". tools/build_env.sh;",
        set_cache,
        "$zig cc", "-target", "$$ARCH-$$OS-$$LIBC", native_ldflags, "$in -o $out",
    },
    implicit_in = {
        "$zig", "$zig_cache",
        "tools/build_env.sh",
    },
}

local cc = {}
local cc_ext = {}
local ld = {}
local so = {}

targets : foreach(function(target)
    local target_arch, target_os, target_abi = target:split "%-":unpack()
    local lto = case(mode) {
        fast = case(target_os) {
            linux   = "-flto=thin",
            macos   = {},
            windows = "-flto=thin",
        },
        small = {},
        quick = {},
        debug = {},
    }
    local target_flags = {
        "-DLUAX_ARCH='\""..target_arch.."\"'",
        "-DLUAX_OS='\""..target_os.."\"'",
        "-DLUAX_ABI='\""..target_abi.."\"'",
    }
    local lua_flags = {
        case(target_os) {
            linux   = "-DLUA_USE_LINUX",
            macos   = "-DLUA_USE_MACOSX",
            windows = {},
        },
    }
    local target_ld_flags = {
        case(target_abi) {
            gnu  = "-rdynamic",
            musl = {},
            none = "-rdynamic",
        },
        case(target_os) {
            linux   = {},
            macos   = {},
            windows = "-lws2_32 -ladvapi32",
        },
    }
    local target_so_flags = {
        "-shared",
    }
    cc[target] = rule("cc-"..target) {
        description = "CC["..target.."] $in",
        command = {
            set_cache,
            "$zig cc", "-target", target, "-c", lto, luax_cflags, lua_flags, target_flags, "-MD -MF $depfile $in -o $out",
            case(target_os) {
                linux = {},
                macos = {},
                windows = "$build_as_dll",
            }
        },
        implicit_in = {
            "$zig", "$zig_cache",
        },
        depfile = "$out.d",
    }
    cc_ext[target] = rule("cc_ext-"..target) {
        description = "CC["..target.."] $in",
        command = {
            set_cache,
            "$zig cc", "-target", target, "-c", lto, ext_cflags, lua_flags, "$additional_flags", "-MD -MF $depfile $in -o $out",
        },
        implicit_in = {
            "$zig", "$zig_cache",
        },
        depfile = "$out.d",
    }
    ld[target] = rule("ld-"..target) {
        description = "LD["..target.."] $out",
        command = {
            set_cache,
            "$zig cc", "-target", target, lto, ldflags, target_ld_flags, "$in -o $out",
        },
        implicit_in = {
            "$zig", "$zig_cache",
        },
    }
    if target_abi~="musl" then
        so[target] = rule("so-"..target) {
            description = "SO["..target.."] $out",
            command = {
                set_cache,
                "$zig cc", "-target", target, lto, ldflags, target_ld_flags, target_so_flags, "$in -o $out",
            },
            implicit_in = {
                "$zig", "$zig_cache",
            },
        }
    end
end)

local ar = rule "ar" {
    description = "AR $out",
    command = {
        set_cache,
        "$zig ar -crs $out $in",
    },
    implicit_in = {
        "$zig", "$zig_cache",
    },
}

--===================================================================
section "Third-party modules update"
---------------------------------------------------------------------

build "update_modules" {
    description = "UPDATE",
    command = {"tools/update-third-party-modules.sh", "$builddir/update"},
    pool = "console",
}

--===================================================================
section "lz4 cli"
---------------------------------------------------------------------

var "lz4" "$tmp/lz4"

build "$lz4" { "ld",
    ls "ext/c/lz4/**.c"
    : map(function(src)
        return build("$tmp/obj/lz4"/src:splitext()..".o") { "cc", src }
    end),
}

--===================================================================
section "LuaX sources"
---------------------------------------------------------------------

local linux_only = F{
    "ext/c/luasocket/serial.c",
    "ext/c/luasocket/unixdgram.c",
    "ext/c/luasocket/unixstream.c",
    "ext/c/luasocket/usocket.c",
    "ext/c/luasocket/unix.c",
    "ext/c/linenoise/linenoise.c",
    "ext/c/linenoise/utf8.c",
}
local windows_only = F{
    "ext/c/luasocket/wsocket.c",
}
local ignored_sources = F{
    "ext/c/lqmath/src/imath.c",
}

local sources = {
    lua_c_files = ls "lua/*.c"
        : filter(function(name) return F.not_elem(name:basename(), {"lua.c", "luac.c"}) end),
    lua_main_c_files = F{ "lua/lua.c" },
    luax_main_c_files = F{ "luax/luax.c" },
    libluax_main_c_files = F{ "luax/libluax.c" },
    luax_c_files = ls "libluax/**.c",
    third_party_c_files = ls "ext/c/**.c"
        : filter(function(name) return not name:match "lz4/programs" end)
        : filter(function(name) return F.not_elem(name, linux_only) end)
        : filter(function(name) return F.not_elem(name, windows_only) end)
        : filter(function(name) return F.not_elem(name, ignored_sources) end),
    linux_third_party_c_files = linux_only,
    windows_third_party_c_files = windows_only,
}

--===================================================================
section "Native Lua interpreter"
---------------------------------------------------------------------

var "lua" "$tmp/lua"

var "lua_path" (
    F{
        ".",
        "$tmp",
        "libluax",
        ls "libluax/*" : filter(fs.is_dir),
    }
    : flatten()
    : map(function(path) return path / "?.lua" end)
    : str ";"
)

build "$lua" { "ld",
    (sources.lua_c_files .. sources.lua_main_c_files) : map(function(src)
        return build("$tmp/obj/lua"/src:splitext()..".o") { "cc", src }
    end),
}

--===================================================================
section "LuaX configuration"
---------------------------------------------------------------------

comment [[
The configuration file (luax_config.h and luax_config.lua)
are created in `libluax`
]]

var "luax_config_h"   "$tmp/luax_config.h"
var "luax_config_lua" "$tmp/luax_config.lua"
var "luax_crypt_key"  "$tmp/luax_crypt_key.h"

local magic_id = "LuaX"

local luax_config_table = (F.I % "%%()") {
    MAGIC_ID = magic_id,
    TARGETS = targets:show(),
}

F.compose { file "tools/gen_config_h.sh", luax_config_table } [[
#!/bin/bash

LUAX_CONFIG_H="$1"

cat <<EOF > "$LUAX_CONFIG_H"
#pragma once
#define LUAX_VERSION "$(git describe --tags)"
#define LUAX_DATE "$(git show -s --format=%cd --date=format:'%Y-%m-%d')"
#define LUAX_MAGIC_ID "%(MAGIC_ID)"
EOF
]]

F.compose { file "tools/gen_config_lua.sh", luax_config_table } [[
#!/bin/bash

LUAX_CONFIG_LUA="$1"

cat <<EOF > "$LUAX_CONFIG_LUA"
--@LIB
return {
    version = "$(git describe --tags)",
    date = "$(git show -s --format=%cd --date=format:'%Y-%m-%d')",
    magic_id = "%(MAGIC_ID)",
    targets = %(TARGETS),
}
EOF
]]

rule "gen_config" {
    description = "GEN $out",
    command = {
        ". tools/build_env.sh;",
        "bash", "$in", "$out",
    },
    implicit_in = {
        "tools/build_env.sh",
        ".git/refs/tags", ".git/index",
        "$lua"
    },
}

build "$luax_config_h"   { "gen_config", "tools/gen_config_h.sh" }
build "$luax_config_lua" { "gen_config", "tools/gen_config_lua.sh" }

build "$luax_crypt_key"  {
    description = "GEN $out",
    command = {
        ". tools/build_env.sh;",
        "$lua", "tools/crypt_key.lua", "LUAX_CRYPT_KEY", '"$$CRYPT_KEY"', "> $out",
    },
    implicit_in = {
        "$lua",
        "tools/build_env.sh",
        "tools/crypt_key.lua",
    }
}

--===================================================================
section "Lua runtime"
---------------------------------------------------------------------

local luax_runtime = {
    ls "libluax/**.lua",
    ls "ext/**.lua",
}

var "luax_runtime_bundle" "$tmp/lua_runtime_bundle.dat"

build "$luax_runtime_bundle" { "$luax_config_lua", luax_runtime,
    description = "BUNDLE $out",
    command = {
        ". tools/build_env.sh;",
        "PATH=$tmp:$$PATH",
        "LUA_PATH=\"$lua_path\"",
        "$lua",
        "-l tools/rc4_runtime",
        "luax/bundle.lua", "-lib -ascii",
        "$in > $out",
    },
    implicit_in = {
        "tools/build_env.sh",
        "$lz4",
        "$lua",
        "luax/bundle.lua",
        "tools/rc4_runtime.lua",
    },
}

--===================================================================
section "C runtimes"
---------------------------------------------------------------------

local function target_os(target)
    return target:split"%-":snd()
end

local function ext(target)
    return case(target_os(target)) {
        linux   = "",
        macos   = "",
        windows = ".exe",
    }
end

local function libext(target)
    return case(target_os(target)) {
        linux   = ".so",
        macos   = ".dylib",
        windows = ".dll",
    }
end

-- imath is also provided by qmath, both versions shall be compatible
rule "diff" {
    description = "DIFF $in",
    command = "diff $in > $out",
}
phony "check_limath_version" {
    build "$tmp/check_limath_header_version" { "diff", "ext/c/lqmath/src/imath.h", "ext/c/limath/src/imath.h" },
    build "$tmp/check_limath_source_version" { "diff", "ext/c/lqmath/src/imath.c", "ext/c/limath/src/imath.c" },
}

local runtimes, shared_libraries =
    targets : map(function(target)

        section(target.." runtime")

        local liblua = build("$tmp/lib/liblua-"..target..".a") { ar,
            F.flatten {
                sources.lua_c_files,
            } : map(function(src)
                return build("$tmp/obj"/target/src:splitext()..".o") { cc_ext[target], src }
            end),
        }

        local libluax = build("$tmp/lib/libluax-"..target..".a") { ar,
            F.flatten {
                sources.luax_c_files,
            } : map(function(src)
                return build("$tmp/obj"/target/src:splitext()..".o") { cc[target], src,
                    implicit_in = {
                        "$luax_config_h",
                        case(src:basename():splitext()) {
                            crypt = "$luax_crypt_key",
                        } or {},
                    },
                }
            end),
            F.flatten {
                sources.third_party_c_files,
                case(target_os(target)) {
                    linux   = sources.linux_third_party_c_files,
                    macos   = sources.linux_third_party_c_files,
                    windows = sources.windows_third_party_c_files,
                },
            } : map(function(src)
                return build("$tmp/obj"/target/src:splitext()..".o") { cc_ext[target], src,
                    additional_flags = case(src:basename():splitext()) {
                        usocket = "-Wno-#warnings",
                    },
                    implicit_in = case(src:basename():splitext()) {
                        limath = "check_limath_version",
                        imath  = "check_limath_version",
                    },
                }
            end),
        }

        local main_luax = F.flatten { sources.luax_main_c_files }
            : map(function(src)
                return build("$tmp/obj"/target/src:splitext()..".o") { cc[target], src,
                    implicit_in = {
                        "$luax_config_h",
                    },
                }
            end)

        local main_libluax = F.flatten { sources.libluax_main_c_files }
            : map(function(src)
                    return build("$tmp/obj"/target/src:splitext()..".o") { cc[target], src,
                        build_as_dll = case(target_os(target)) {
                            windows = "-DLUA_BUILD_AS_DLL -DLUA_LIB",
                        },
                        implicit_in = {
                            "$luax_config_h",
                            "$luax_runtime_bundle",
                        },
                    }
                end)

        local runtime = build("$tmp/run/luaxruntime-"..target..ext(target)) { ld[target],
            main_luax,
            main_libluax,
            liblua,
            libluax,
        }

        local shared_library = so[target] and
            build("$tmp/lib/libluax-"..target..libext(target)) { so[target],
                main_libluax,
                case(target_os(target)) {
                    linux   = {},
                    macos   = liblua,
                    windows = liblua,
                },
                libluax,
        }

        return {runtime, shared_library or F.Nil}

    end)
    : unzip()

shared_libraries = shared_libraries : filter(function(lib) return lib ~= F.Nil end)

if upx and mode~="debug" then
    rule "upx" {
        description = "UPX $in",
        command = "rm -f $out; upx -qqq -o $out $in && touch $out",
    }
    runtimes = runtimes : map(function(runtime)
        return build("$tmp/run-upx"/runtime:basename()) { "upx", runtime }
    end)
    shared_libraries = shared_libraries : map(function(library)
        return case(library:ext()) {
            [".dylib"] = library,
        } or build("$tmp/lib-upx"/library:basename()) { "upx", library }
    end)
end

rule "cp" {
    description = "CP $out",
    command = "cp -f $in $out",
}

shared_libraries = shared_libraries : map(function(library)
    return build("$lib"/library:basename()) { "cp", library }
end)

--===================================================================
section "LuaX binaries"
---------------------------------------------------------------------

local luax_packages = {
    ls "luax/*.lua",
    "$luax_config_lua",
}

local binaries = {}
local libraries = {}

F{targets, runtimes} : zip(function(target, runtime)

    section("LuaX "..target)

    local e = ext(target)

    acc(binaries) {
        build("$bin/luax-"..target..e) { luax_packages,
        description = "LUAX $out",
            command = {
                ". tools/build_env.sh;",
                "cp", runtime, "$out",
                "&&",
                "PATH=$tmp:$$PATH",
                "LUA_PATH=\"$lua_path\"",
                "$lua",
                "-l tools/rc4_runtime",
                "luax/bundle.lua", "-binary",
                "$in >> $out",
            },
            implicit_in = {
                "tools/build_env.sh",
                "$lz4",
                "$lua",
                "tools/rc4_runtime.lua",
                "luax/bundle.lua",
                runtime,
            },
        }
    }

end)

var "luax" "$bin/luax"

acc(binaries) {
    build "$luax" {
        description = "CP $out",
        command = {
            ". tools/build_env.sh;",
            "cp", "-f", "$bin/luax-$$ARCH-$$OS-$$LIBC$$EXT", "$out$$EXT",
        },
        implicit_in = {
            "tools/build_env.sh",
            binaries,
        },
    }
}

--===================================================================
section "LuaX Lua implementation"
---------------------------------------------------------------------

--===================================================================
section "$lib/luax.lua"
---------------------------------------------------------------------

local lib_luax_sources = {
    ls "libluax/**.lua",
    ls "ext/lua/**.lua",
}

acc(libraries) {
    build "$lib/luax.lua" { "$luax_config_lua", lib_luax_sources,
        description = "LUAX $out",
        command = {
            ". tools/build_env.sh;",
            "PATH=$tmp:$$PATH",
            "LUA_PATH=\"$lua_path\"",
            "$lua",
            "-l tools/rc4_runtime",
            "luax/bundle.lua", "-lib -lua",
            "$in > $out",
        },
        implicit_in = {
            "tools/build_env.sh",
            "$lz4",
            "$lua",
            "luax/bundle.lua",
            "tools/rc4_runtime.lua",
        },
    }
}

--===================================================================
section "$bin/luax-lua"
---------------------------------------------------------------------

acc(binaries) {
    build "$bin/luax-lua" { "luax/luax.lua",
        description = "LUAX $out",
        command = { "$luax", "-q -t lua", "-o $out $in" },
        implicit_in = { "$luax", "$lib/luax.lua" },
    }
}

--===================================================================
section "$bin/luax-pandoc"
---------------------------------------------------------------------

acc(binaries) {
    build "$bin/luax-pandoc" { "luax/luax.lua",
        description = "LUAX $out",
        command = { "$luax", "-q -t pandoc", "-o $out $in" },
        implicit_in = { "$luax", "$lib/luax.lua" },
    }
}

--===================================================================
section "Tests"
---------------------------------------------------------------------

local test_sources = ls "tests/luax-tests/*.*"
local test_main = "tests/luax-tests/main.lua"

local valgrind = {
    case(mode) {
        fast  = {},
        small = {},
        quick = {},
        debug = "VALGRIND=true valgrind --quiet",
    },
}

acc(test) {

---------------------------------------------------------------------

    build "$test/test-1-luax_executable.ok" {
        description = "TEST $out",
        command = {
            ". tools/build_env.sh;",
            valgrind,
            "$luax -q -o $test/test-luax", test_sources,
            "&&",
            "PATH=$tmp:$$PATH",
            "LUA_PATH='tests/luax-tests/?.lua'",
            "TEST_NUM=1",
            valgrind,
            "$test/test-luax Lua is great",
            "&&",
            "touch $out",
        },
        implicit_in = {
            "tools/build_env.sh",
            "$luax",
            test_sources,
        },
    },

---------------------------------------------------------------------

    build "$test/test-2-lib.ok" {
        description = "TEST $out",
        command = {
            ". tools/build_env.sh;",
            "eval $$($luax env);",
            "PATH=$tmp:$$PATH",
            "LUA_PATH='tests/luax-tests/?.lua'",
            "TEST_NUM=2",
            valgrind,
            "$lua", "-l libluax", test_main, "Lua is great",
            "&&",
            "touch $out",
        },
        implicit_in = {
            "tools/build_env.sh",
            "$lua",
            "$luax",
            libraries,
            test_sources,
        },
    },

---------------------------------------------------------------------

    build "$test/test-3-lua.ok" {
        description = "TEST $out",
        command = {
            ". tools/build_env.sh;",
            "PATH=$tmp:$$PATH",
            "LIBC=lua LUA_PATH='$lib/?.lua;tests/luax-tests/?.lua'",
            "TEST_NUM=3",
            "$lua", "-l luax", test_main, "Lua is great",
            "&&",
            "touch $out",
        },
        implicit_in = {
            "tools/build_env.sh",
            "$lua",
            "$lib/luax.lua",
            test_sources,
        },
    },

---------------------------------------------------------------------

    build "$test/test-4-lua-luax-lua.ok" {
        description = "TEST $out",
        command = {
            ". tools/build_env.sh;",
            "PATH=$tmp:$$PATH",
            "LIBC=lua LUA_PATH='$lib/?.lua;tests/luax-tests/?.lua'",
            "TEST_NUM=4",
            "$bin/luax-lua", test_main, "Lua is great",
            "&&",
            "touch $out",
        },
        implicit_in = {
            "tools/build_env.sh",
            "$lua",
            "$bin/luax-lua",
            test_sources,
        },
    },

---------------------------------------------------------------------

    build "$test/test-5-pandoc-luax-lua.ok" {
        description = "TEST $out",
        command = {
            ". tools/build_env.sh;",
            "PATH=$tmp:$$PATH",
            "LIBC=lua LUA_PATH='$lib/?.lua;tests/luax-tests/?.lua'",
            "TEST_NUM=5",
            "pandoc lua ", "-l luax", test_main, "Lua is great",
            "&&",
            "touch $out",
        },
        implicit_in = {
            "tools/build_env.sh",
            "$lua",
            "$lib/luax.lua",
            test_sources,
        },
    },

---------------------------------------------------------------------

-- This test is disabled since most of the binary distributions of Pandoc do not support dynamic loading
--[[
    build "$test/test-6-pandoc-luax-so.ok" {
        description = "TEST $out",
        command = {
            ". tools/build_env.sh;",
            "eval $$($luax env);",
            "PATH=$tmp:$$PATH",
            "LUA_CPATH='$lib/?.so' LUA_PATH='$lib/?.lua;tests/luax-tests/?.lua'",
            "TEST_NUM=6",
            "pandoc lua ", "-l libluax", test_main, "Lua is great",
            "&&",
            "touch $out",
        },
        implicit_in = {
            "tools/build_env.sh",
            "$lua",
            "$luax",
            "$lib/luax.lua",
            test_sources,
        },
    },
--]]

---------------------------------------------------------------------

    build "$test/test-ext-1-lua.ok" { "tests/external_interpreter_tests/external_interpreters.lua",
        description = "TEST $out",
        command = {
            ". tools/build_env.sh;",
            "eval $$($luax env);",
            "$luax -q -t lua -o $test/ext-lua", "$in",
            "&&",
            "PATH=$tmp:$$PATH",
            "TARGET=lua",
            "$test/ext-lua Lua is great",
            "&&",
            "touch $out",
        },
        implicit_in = {
            "tools/build_env.sh",
            "$lib/luax.lua",
            "$luax",
            binaries,
        },
    },

---------------------------------------------------------------------

    build "$test/test-ext-2-lua-luax.ok" { "tests/external_interpreter_tests/external_interpreters.lua",
        description = "TEST $out",
        command = {
            ". tools/build_env.sh;",
            "eval $$($luax env);",
            "$luax -q -t lua-luax -o $test/ext-lua-luax", "$in",
            "&&",
            "PATH=$tmp:$$PATH",
            "TARGET=lua-luax",
            "$test/ext-lua-luax Lua is great",
            "&&",
            "touch $out",
        },
        implicit_in = {
            "tools/build_env.sh",
            "$lib/luax.lua",
            "$luax",
        },
    },

---------------------------------------------------------------------

    build "$test/test-ext-3-luax.ok" { "tests/external_interpreter_tests/external_interpreters.lua",
        description = "TEST $out",
        command = {
            ". tools/build_env.sh;",
            "eval $$($luax env);",
            "$luax -q -t luax -o $test/ext-luax", "$in",
            "&&",
            "PATH=$tmp:$$PATH",
            "TARGET=luax",
            "$test/ext-luax Lua is great",
            "&&",
            "touch $out",
        },
        implicit_in = {
            "tools/build_env.sh",
            "$lib/luax.lua",
            "$luax",
        },
    },

---------------------------------------------------------------------

    build "$test/test-ext-4-pandoc.ok" { "tests/external_interpreter_tests/external_interpreters.lua",
        description = "TEST $out",
        command = {
            ". tools/build_env.sh;",
            "eval $$($luax env);",
            "$luax -q -t pandoc -o $test/ext-pandoc", "$in",
            "&&",
            "PATH=$tmp:$$PATH",
            "TARGET=pandoc",
            "$test/ext-pandoc Lua is great",
            "&&",
            "touch $out",
        },
        implicit_in = {
            "tools/build_env.sh",
            "$lib/luax.lua",
            "$luax",
            binaries,
        },
    },

---------------------------------------------------------------------

-- This test is disabled since most of the binary distributions of Pandoc do not support dynamic loading
--[[
    build "$test/test-ext-5-pandoc-luax.ok" { "tests/external_interpreter_tests/external_interpreters.lua",
        description = "TEST $out",
        command = {
            ". tools/build_env.sh;",
            "eval $$($luax env);",
            "$luax -q -t pandoc-luax -o $test/ext-pandoc-luax", "$in",
            "&&",
            "PATH=$tmp:$$PATH",
            "TARGET=pandoc-luax",
            "$test/ext-pandoc-luax Lua is great",
            "&&",
            "touch $out",
        },
        implicit_in = {
            "tools/build_env.sh",
            "$lib/luax.lua",
            "$luax",
        },
    },
--]]

---------------------------------------------------------------------

}

--===================================================================
section "Documentation"
---------------------------------------------------------------------

local markdown_sources = ls "doc/src/*.md"

local url = "cdelord.fr/luax"

rule "banner-1024" { description = "LSVG $in", command = {"lsvg $in $out -- 1024 192"} }
rule "logo-256"    { description = "LSVG $in", command = {"lsvg $in $out -- 256 256"} }
rule "logo-1024"   { description = "LSVG $in", command = {"lsvg $in $out -- 1024 1024"} }
rule "social-1280" { description = "LSVG $in", command = {"lsvg $in $out -- 1280 640", F.show(url)} }

local images = {
    build "doc/luax-banner.svg"         {"banner-1024", "doc/src/luax-logo.lua"},
    build "doc/luax-logo.svg"           {"logo-256",    "doc/src/luax-logo.lua"},
    build "$builddir/luax-banner.png"   {"banner-1024", "doc/src/luax-logo.lua"},
    build "$builddir/luax-social.png"   {"social-1280", "doc/src/luax-logo.lua"},
    build "$builddir/luax-logo.png"     {"logo-1024",   "doc/src/luax-logo.lua"},
}

acc(doc)(images)

local pandoc_gfm = {
    "pandoc",
    "--to gfm",
    "--lua-filter doc/src/fix_links.lua",
    "--fail-if-warnings",
}

rule "ypp" {
    description = "YPP $in",
    command = {
        "LUAX=$luax",
        "ypp --MD --MT $out --MF $depfile $in -o $out",
    },
    depfile = "$out.d",
    implicit_in = {
        "$luax",
    },
}

rule "md_to_gfm" {
    description = "PANDOC $out",
    command = {
        pandoc_gfm, "$in -o $out",
    },
    implicit_in = {
        "doc/src/fix_links.lua",
        images,
    },
}

acc(doc) {

    build "README.md" { "md_to_gfm",
        build "$tmp/doc/README.md" { "ypp", "doc/src/luax.md" },
    },

    markdown_sources : map(function(src)
        return build("doc"/src:basename()) { "md_to_gfm",
            build("$tmp"/src) { "ypp", src },
        }
    end)

}

--===================================================================
section "Shorcuts"
---------------------------------------------------------------------

acc(compile) {binaries, libraries, shared_libraries}

install "bin" {binaries}
install "lib" {libraries, shared_libraries}

clean "$builddir"
clean.mrproper "$zig_cache"

phony "compile" (compile)
default "compile"
help "compile" "compile LuaX"

phony "test-fast" (test[1])
help "test-fast" "run LuaX tests (fast, native tests only)"

phony "test" (test)
help "test" "run all LuaX tests"

phony "doc" (doc)
help "doc" "update LuaX documentation"

phony "all" {"compile", "test", "doc"}
help "all" "alias for compile, test and doc"

phony "update" "update_modules"
help "update" "update third-party modules"
