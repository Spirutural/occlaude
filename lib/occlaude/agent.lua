-- The agent loop: send → handle tool_use → reply with tool_result → loop.

local api = require("occlaude.api")
local tools = require("occlaude.tools")

local M = {}

M.system_prompt = [[You are OCClaude, a coding assistant running on an OpenComputers computer in Minecraft (OpenOS, Lua 5.3).
Resources are limited: small RAM, narrow screen, slow disk. Keep replies concise and tool calls minimal.
You have these tools: bash, read, edit, write. Paths are POSIX-style under OpenOS (e.g. /home, /tmp, /usr/bin).
Common OpenOS commands: ls, cd, cat, edit, mkdir, rm, cp, mv, wget, ping, df, components.
When the user gives a task, do it directly with the tools. Avoid long explanations unless asked.]]

local function new_state(opts)
  return {
    api_key   = assert(opts.api_key, "api_key required"),
    model     = opts.model or api.default_model,
    messages  = {},
    max_steps = opts.max_steps or 20,
  }
end
M.new_state = new_state

-- Print a long string with simple wrapping for the OC screen.
local function print_text(s, width)
  width = width or 78
  for line in (s .. "\n"):gmatch("([^\n]*)\n") do
    if #line == 0 then
      io.write("\n")
    else
      local i = 1
      while i <= #line do
        io.write(line:sub(i, i + width - 1))
        io.write("\n")
        i = i + width
      end
    end
  end
end
M.print_text = print_text

-- Send one user turn, run tool calls until the model stops.
function M.run_turn(state, user_input)
  state.messages[#state.messages + 1] = {
    role = "user",
    content = user_input,
  }

  for _ = 1, state.max_steps do
    local resp, err = api.send({
      api_key  = state.api_key,
      model    = state.model,
      messages = state.messages,
      system   = M.system_prompt,
      tools    = tools.schemas,
    })
    if not resp then
      io.write("[error] " .. tostring(err) .. "\n")
      return false
    end

    -- Persist the assistant turn verbatim so tool_use ids line up.
    state.messages[#state.messages + 1] = {
      role    = "assistant",
      content = resp.content,
    }

    local tool_results = {}
    for _, block in ipairs(resp.content or {}) do
      if block.type == "text" then
        if block.text and block.text ~= "" then
          print_text(block.text)
        end
      elseif block.type == "tool_use" then
        io.write(("[tool] %s\n"):format(block.name))
        local result, is_err = tools.run(block.name, block.input or {})
        tool_results[#tool_results + 1] = {
          type        = "tool_result",
          tool_use_id = block.id,
          content     = result,
          is_error    = is_err or nil,
        }
      end
    end

    if resp.stop_reason ~= "tool_use" or #tool_results == 0 then
      return true
    end

    state.messages[#state.messages + 1] = {
      role    = "user",
      content = tool_results,
    }
  end

  io.write("[error] hit max_steps (" .. state.max_steps .. ") without end_turn\n")
  return false
end

return M
