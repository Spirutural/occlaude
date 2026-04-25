-- OCClaude CLI — REPL entry point.
-- Install location: /home/bin/occlaude.lua  (run as `occlaude` from the OpenOS shell).

local shell = require("shell")
local fs = require("filesystem")

local args, opts = shell.parse(...)

local function usage()
  io.write([[
Usage: occlaude [options]
  -c, --continue     Resume the most recent conversation
  -m, --model <id>   Override the model (default: claude-sonnet-4-6)
  -k, --keyfile <p>  Path to API key file (default: /home/.occlaude.key)
      --update       Pull the latest version from the install root and exit
  -h, --help         Show this help

Inside the REPL:
  /quit        Exit
  /reset       Clear conversation history (in-memory and on-disk)
  /model <id>  Switch model
  /update      Pull the latest version and exit
  (anything else is sent to the model)
]])
end

if opts.h or opts.help then usage(); return end

----------------------------------------------------------------------
-- --update
----------------------------------------------------------------------

local INSTALLROOT_PATH = "/home/.occlaude.installroot"

local function do_update()
  if not fs.exists(INSTALLROOT_PATH) then
    io.write("No saved install root at " .. INSTALLROOT_PATH .. ".\n")
    io.write("Re-run install.lua manually:\n")
    io.write("  install.lua https://raw.githubusercontent.com/<you>/occlaude/main\n")
    os.exit(1)
  end
  local rf = io.open(INSTALLROOT_PATH, "r")
  local base = ((rf:read("*l") or ""):gsub("%s+$", ""):gsub("^%s+", ""))
  rf:close()
  if base == "" then
    io.write("Install root file is empty.\n"); os.exit(1)
  end

  io.write("Updating from " .. base .. " ...\n")

  local ok = shell.execute("wget -fq " .. base .. "/install.lua /home/install.lua")
  if not ok then io.write("Failed to fetch install.lua\n"); os.exit(1) end

  ok = shell.execute("/home/install.lua " .. base)
  if not ok then io.write("install.lua failed\n"); os.exit(1) end

  io.write("Update complete. Restart occlaude to use the new code.\n")
  os.exit(0)
end

if opts.update then do_update() end

----------------------------------------------------------------------
-- Normal startup
----------------------------------------------------------------------

local agent   = require("occlaude.agent")
local api     = require("occlaude.api")
local history = require("occlaude.history")

local key_path = opts.k or opts.keyfile or "/home/.occlaude.key"
if not fs.exists(key_path) then
  io.write("No API key found at " .. key_path .. ".\n")
  io.write("Create it with:  echo sk-ant-... > " .. key_path .. "\n")
  os.exit(1)
end

local kf = io.open(key_path, "r")
local api_key = (kf:read("*l") or ""):gsub("%s+$", ""):gsub("^%s+", "")
kf:close()
if api_key == "" then
  io.write("API key file is empty: " .. key_path .. "\n")
  os.exit(1)
end

local state = agent.new_state{
  api_key = api_key,
  model   = opts.m or opts.model or api.default_model,
}

if opts.c or opts.continue then
  local saved, err = history.load()
  if saved then
    state.messages = saved.messages or {}
    -- Saved model wins unless the user explicitly overrode it on the CLI.
    if saved.model and not (opts.m or opts.model) then
      state.model = saved.model
    end
    io.write(("(resumed %d messages, model %s)\n"):format(#state.messages, state.model))
  elseif err then
    io.write("(could not load history: " .. err .. ")\n")
  else
    io.write("(no previous conversation)\n")
  end
end

io.write("OCClaude — model " .. state.model .. ". /quit to exit, /reset to clear history.\n")

while true do
  io.write("> ")
  io.flush()
  local line = io.read("*l")
  if line == nil then break end          -- EOF (Ctrl-D)
  if line == "/quit" or line == "/exit" then break
  elseif line == "/reset" then
    state.messages = {}
    history.clear()
    io.write("(history cleared)\n")
  elseif line == "/update" then
    do_update()
  elseif line:sub(1, 7) == "/model " then
    state.model = line:sub(8):gsub("%s+$", "")
    io.write("(model: " .. state.model .. ")\n")
  elseif line ~= "" then
    local pcall_ok, run_err = pcall(agent.run_turn, state, line)
    if not pcall_ok then
      io.write("[crash] " .. tostring(run_err) .. "\n")
    end
    history.save(state.messages, state.model)
  end
end
