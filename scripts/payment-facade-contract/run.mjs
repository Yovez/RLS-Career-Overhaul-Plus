#!/usr/bin/env node
/**
 * Offline Payment Domain facade contract runner (#2).
 *
 * Usage (from repo root or this directory):
 *   npm install
 *   node run.mjs
 *
 * Requires Node.js. Does not need BeamNG.
 */
import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath } from "node:url";
import fs from "node:fs";

const require = createRequire(import.meta.url);
const fengari = require("fengari");
const { lua, lauxlib, lualib, to_luastring } = fengari;

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, "../..");
const harnessPath = path.join(here, "harness.lua");

if (!fs.existsSync(harnessPath)) {
  console.error("Missing harness.lua at", harnessPath);
  process.exit(1);
}

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

// Expose repo root for harness loadfile paths (forward slashes for Lua).
const rootLua = repoRoot.replace(/\\/g, "/");
lua.lua_pushstring(L, to_luastring(rootLua));
lua.lua_setglobal(L, to_luastring("__PAYMENT_CONTRACT_ROOT"));

const status = lauxlib.luaL_dofile(L, to_luastring(harnessPath.replace(/\\/g, "/")));
if (status !== lua.LUA_OK) {
  const err = lua.lua_tojsstring(L, -1);
  console.error("Lua error:", err);
  process.exit(1);
}

// harness calls os.exit; if we get here without exit, treat as success.
process.exit(0);
