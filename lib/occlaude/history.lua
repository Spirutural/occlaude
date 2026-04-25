-- Conversation persistence for OCClaude.
-- One slot, on disk at /home/.occlaude.history. Always reflects the most
-- recent conversation. Loaded explicitly by `--continue`; overwritten on
-- the first turn of a new session; cleared by `/reset`.

local fs = require("filesystem")
local json = require("occlaude.json")

local M = {}
M.path = "/home/.occlaude.history"

function M.save(messages, model)
  local f, err = io.open(M.path, "w")
  if not f then return false, err end
  local ok, payload = pcall(json.encode, { messages = messages, model = model })
  if not ok then
    f:close()
    return false, "encode failed: " .. tostring(payload)
  end
  f:write(payload)
  f:close()
  return true
end

function M.load()
  if not fs.exists(M.path) then return nil end
  local f, err = io.open(M.path, "r")
  if not f then return nil, err end
  local raw = f:read("*a") or ""
  f:close()
  if raw == "" then return nil end
  local ok, data = pcall(json.decode, raw)
  if not ok then return nil, "history corrupt: " .. tostring(data) end
  if type(data) ~= "table" or type(data.messages) ~= "table" then
    return nil, "history malformed"
  end
  return data
end

function M.clear()
  if fs.exists(M.path) then pcall(fs.remove, M.path) end
end

return M
