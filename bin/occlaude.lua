-- OCClaude CLI — REPL entry point.
-- Install location: /home/bin/occlaude.lua  (run as `occlaude` from the OpenOS shell).

local shell = require("shell")
local fs = require("filesystem")

local args, opts = shell.parse(...)

local function usage()
  io.write([[
Usage: occlaude [options]
  -m, --model <id>   Override the model (default: claude-sonnet-4-6)
  -k, --keyfile <p>  Path to API key file (default: /home/.occlaude.key)
  -h, --help         Show this help

Inside the REPL:
  /quit        Exit
  /reset       Clear conversation history
  /model <id>  Switch model
  (anything else is sent to the model)
]])
end

if opts.h or opts.help then usage(); return end

local agent = require("occlaude.agent")
local api   = require("occlaude.api")

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

io.write("OCClaude — model " .. state.model .. ". /quit to exit, /reset to clear history.\n")

while true do
  io.write("> ")
  io.flush()
  local line = io.read("*l")
  if line == nil then break end          -- EOF (Ctrl-D)
  if line == "/quit" or line == "/exit" then break
  elseif line == "/reset" then
    state.messages = {}
    io.write("(history cleared)\n")
  elseif line:sub(1, 7) == "/model " then
    state.model = line:sub(8):gsub("%s+$", "")
    io.write("(model: " .. state.model .. ")\n")
  elseif line ~= "" then
    local ok, err = pcall(agent.run_turn, state, line)
    if not ok then
      io.write("[crash] " .. tostring(err) .. "\n")
    end
  end
end
