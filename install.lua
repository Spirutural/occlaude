-- Bootstrap installer for OCClaude.
-- Run on the OpenOS computer:
--   wget https://raw.githubusercontent.com/<you>/OCClaude/main/install.lua
--   install.lua https://raw.githubusercontent.com/<you>/OCClaude/main
-- (The base URL must point at the directory that contains bin/ and lib/.)

local shell = require("shell")
local fs    = require("filesystem")
local internet = require("internet")

local args = {...}
local base = args[1]
if not base or base == "" then
  io.write("Usage: install.lua <base-url>\n")
  io.write("Example: install.lua https://raw.githubusercontent.com/you/OCClaude/main\n")
  os.exit(1)
end
base = base:gsub("/+$", "")

local files = {
  "bin/occlaude.lua",
  "lib/occlaude/json.lua",
  "lib/occlaude/api.lua",
  "lib/occlaude/tools.lua",
  "lib/occlaude/agent.lua",
}

local function fetch(url)
  local handle, err = internet.request(url)
  if not handle then return nil, err end
  local parts = {}
  for chunk in handle do parts[#parts + 1] = chunk end
  return table.concat(parts)
end

local function ensure_dir(p)
  if not fs.exists(p) then
    local ok, err = fs.makeDirectory(p)
    if not ok then error("mkdir " .. p .. ": " .. tostring(err)) end
  end
end

ensure_dir("/home/bin")
ensure_dir("/home/lib")
ensure_dir("/home/lib/occlaude")

for _, rel in ipairs(files) do
  io.write("fetching " .. rel .. " ... ")
  io.flush()
  local body, err = fetch(base .. "/" .. rel)
  if not body then
    io.write("FAIL (" .. tostring(err) .. ")\n")
    os.exit(1)
  end
  local dest = "/home/" .. rel
  local f = io.open(dest, "w")
  if not f then
    io.write("FAIL (cannot write " .. dest .. ")\n")
    os.exit(1)
  end
  f:write(body)
  f:close()
  io.write("ok (" .. #body .. " bytes) -> " .. dest .. "\n")
end

io.write("\nInstalled. Next steps:\n")
io.write("  1. Save your API key:  echo sk-ant-... > /home/.occlaude.key\n")
io.write("  2. Run:                occlaude\n")
