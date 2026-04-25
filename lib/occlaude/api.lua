-- Anthropic Messages API client for OpenComputers.
-- Uses the `internet` component (requires an Internet Card).

local internet = require("internet")
local json = require("occlaude.json")

local M = {}

M.url = "https://api.anthropic.com/v1/messages"
M.anthropic_version = "2023-06-01"

-- Default model. Override per call by setting state.model in the agent.
M.default_model = "claude-sonnet-4-6"

-- Send a single Messages API request.
-- Returns (response_table, nil) on success, or (nil, err_string) on failure.
function M.send(opts)
  assert(opts.api_key, "api_key required")
  assert(opts.messages, "messages required")

  local body = {
    model = opts.model or M.default_model,
    max_tokens = opts.max_tokens or 4096,
    messages = opts.messages,
  }
  if opts.system then body.system = opts.system end
  if opts.tools then body.tools = opts.tools end

  local body_str = json.encode(body)
  local headers = {
    ["x-api-key"] = opts.api_key,
    ["anthropic-version"] = M.anthropic_version,
    ["content-type"] = "application/json",
  }

  local ok, handle = pcall(internet.request, M.url, body_str, headers, "POST")
  if not ok then
    return nil, "internet.request failed: " .. tostring(handle)
  end

  -- Drain the response. The handle is callable as an iterator yielding chunks.
  local chunks, err = {}, nil
  local drain_ok, drain_err = pcall(function()
    for chunk in handle do
      chunks[#chunks + 1] = chunk
    end
  end)
  if not drain_ok then
    return nil, "stream read failed: " .. tostring(drain_err)
  end

  local raw = table.concat(chunks)
  if raw == "" then
    return nil, "empty response"
  end

  local decode_ok, decoded = pcall(json.decode, raw)
  if not decode_ok then
    return nil, "could not decode response: " .. tostring(decoded) .. " (raw: " .. raw:sub(1, 200) .. ")"
  end

  if decoded.type == "error" or decoded.error then
    local e = decoded.error or decoded
    return nil, "API error: " .. (e.type or "?") .. ": " .. (e.message or "unknown")
  end

  return decoded
end

return M
