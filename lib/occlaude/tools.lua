-- Tool implementations + schemas for OCClaude.

local fs = require("filesystem")

local M = {}

----------------------------------------------------------------------
-- Schemas (sent to the API)
----------------------------------------------------------------------

M.schemas = {
  {
    name = "bash",
    description = "Run a shell command in the OpenOS shell. Captures stdout and stderr together. Use this for filesystem listing (ls), running programs, fetching with wget, etc.",
    input_schema = {
      type = "object",
      properties = {
        command = { type = "string", description = "The command line to execute." },
      },
      required = { "command" },
    },
  },
  {
    name = "read",
    description = "Read the full contents of a file at an absolute path. Returns the file's text.",
    input_schema = {
      type = "object",
      properties = {
        path = { type = "string", description = "Absolute path to the file." },
      },
      required = { "path" },
    },
  },
  {
    name = "edit",
    description = "Replace `old_string` with `new_string` in the given file. `old_string` must appear exactly once; if not, returns an error and you should add more surrounding context to make the match unique.",
    input_schema = {
      type = "object",
      properties = {
        path       = { type = "string" },
        old_string = { type = "string", description = "Exact text to find. Whitespace-sensitive." },
        new_string = { type = "string", description = "Replacement text." },
      },
      required = { "path", "old_string", "new_string" },
    },
  },
  {
    name = "write",
    description = "Write content to a file, creating it (and parent directories) or overwriting if it exists. Use sparingly — prefer `edit` for changes to existing files.",
    input_schema = {
      type = "object",
      properties = {
        path    = { type = "string" },
        content = { type = "string" },
      },
      required = { "path", "content" },
    },
  },
}

----------------------------------------------------------------------
-- Implementations
----------------------------------------------------------------------

local function tmp_path()
  return "/tmp/.occlaude_" .. tostring(os.time()) .. "_" .. tostring(math.random(1, 1e6))
end

local function bash(input)
  local cmd = input.command
  if type(cmd) ~= "string" or cmd == "" then
    return "Error: command must be a non-empty string", true
  end
  local out_path = tmp_path()
  -- Redirect stdout and stderr together so the model sees real errors.
  local ok = os.execute(cmd .. " > " .. out_path .. " 2>&1")
  local f = io.open(out_path, "r")
  local out = ""
  if f then
    out = f:read("*a") or ""
    f:close()
    pcall(fs.remove, out_path)
  end
  if out == "" then
    out = ok and "(no output)" or "(command failed, no output)"
  end
  return out, not ok
end

local function read(input)
  local path = input.path
  if type(path) ~= "string" then return "Error: path must be a string", true end
  local f = io.open(path, "r")
  if not f then return "Error: cannot open " .. path, true end
  local content = f:read("*a") or ""
  f:close()
  return content, false
end

local function edit(input)
  local path = input.path
  local old_s = input.old_string
  local new_s = input.new_string
  if type(path) ~= "string" or type(old_s) ~= "string" or type(new_s) ~= "string" then
    return "Error: path, old_string, new_string must all be strings", true
  end

  local f = io.open(path, "r")
  if not f then return "Error: cannot open " .. path, true end
  local content = f:read("*a") or ""
  f:close()

  if old_s == "" then
    return "Error: old_string must not be empty", true
  end

  local first = content:find(old_s, 1, true)
  if not first then return "Error: old_string not found in file", true end
  local second = content:find(old_s, first + #old_s, true)
  if second then
    return "Error: old_string appears multiple times — include more context to make it unique", true
  end

  local new_content = content:sub(1, first - 1) .. new_s .. content:sub(first + #old_s)

  local fw = io.open(path, "w")
  if not fw then return "Error: cannot write to " .. path, true end
  fw:write(new_content)
  fw:close()
  return "Edited " .. path .. " (" .. #content .. " -> " .. #new_content .. " bytes).", false
end

local function write(input)
  local path = input.path
  local content = input.content
  if type(path) ~= "string" then return "Error: path must be a string", true end
  if type(content) ~= "string" then content = tostring(content or "") end

  -- Ensure parent dir exists.
  local parent = path:match("^(.*)/[^/]+$")
  if parent and parent ~= "" and not fs.exists(parent) then
    local mk_ok, mk_err = fs.makeDirectory(parent)
    if not mk_ok then return "Error: cannot create directory " .. parent .. ": " .. tostring(mk_err), true end
  end

  local fw = io.open(path, "w")
  if not fw then return "Error: cannot open " .. path .. " for writing", true end
  fw:write(content)
  fw:close()
  return "Wrote " .. #content .. " bytes to " .. path .. ".", false
end

local handlers = {
  bash = bash,
  read = read,
  edit = edit,
  write = write,
}

----------------------------------------------------------------------
-- Optional: remote_bash via ocnodes. Registered only if ocnet.client
-- is on the package path (i.e. ocnodes is installed on this machine).
----------------------------------------------------------------------

local ocnet_ok, ocnet_client = pcall(require, "ocnet.client")
if ocnet_ok then
  M.schemas[#M.schemas + 1] = {
    name = "remote_bash",
    description = "Run a shell command on a remote OpenComputers node by alias. Aliases are defined on this machine in /home/.ocnodes (one line per node: `<alias> <via> <address>`, where `via` is `wireless` or `linked:<local-modem-addr>`). Output is captured the same way as `bash`, with exit code propagated. Use this when the user names a remote node, references the personal-dim crops, or asks to operate on a machine other than this one. List defined aliases with `bash` running `ocsh --list`.",
    input_schema = {
      type = "object",
      properties = {
        alias   = { type = "string", description = "Alias of the remote node, as defined in /home/.ocnodes." },
        command = { type = "string", description = "Shell command to run on the remote node." },
        timeout = { type = "number", description = "Optional timeout in seconds (default 30)." },
      },
      required = { "alias", "command" },
    },
  }

  handlers.remote_bash = function(input)
    local alias = input.alias
    local cmd   = input.command
    if type(alias) ~= "string" or alias == "" then return "Error: alias must be a non-empty string", true end
    if type(cmd)   ~= "string" or cmd   == "" then return "Error: command must be a non-empty string", true end
    local timeout = tonumber(input.timeout) or 30

    local out, exit_or_err = ocnet_client.exec(alias, cmd, timeout)
    if out == nil then
      return "remote: " .. tostring(exit_or_err), true
    end
    if exit_or_err ~= nil and exit_or_err ~= 0 then
      return (out == "" and "(no output)" or out) .. "\n[exit " .. tostring(exit_or_err) .. "]", true
    end
    if out == "" then return "(no output)", false end
    return out, false
  end
end

-- Run a tool by name. Returns (result_string, is_error_bool).
function M.run(name, input)
  local h = handlers[name]
  if not h then return "Unknown tool: " .. tostring(name), true end
  local ok, result, is_err = pcall(h, input or {})
  if not ok then
    return "Tool crashed: " .. tostring(result), true
  end
  return result, is_err and true or false
end

return M
