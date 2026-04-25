-- Minimal JSON encoder/decoder for OCClaude.
-- Pure Lua 5.3, no deps. Good enough for the Anthropic Messages API.

local M = {}

-- Sentinel for explicit empty arrays (since {} is ambiguous).
M.empty_array = setmetatable({}, { __tostring = function() return "[]" end })

----------------------------------------------------------------------
-- Encoder
----------------------------------------------------------------------

local encode_value

local escape_map = {
  ["\\"] = "\\\\", ['"'] = '\\"',
  ["\b"] = "\\b",  ["\f"] = "\\f",
  ["\n"] = "\\n",  ["\r"] = "\\r", ["\t"] = "\\t",
}

local function encode_string(s)
  local out = s:gsub('[%z\1-\31\\"]', function(c)
    return escape_map[c] or string.format("\\u%04x", c:byte())
  end)
  return '"' .. out .. '"'
end

local function is_array(t)
  if t == M.empty_array then return true, 0 end
  local n = 0
  for k in pairs(t) do
    if type(k) ~= "number" then return false end
    if k > n then n = k end
  end
  -- Must be dense 1..n with no holes.
  for i = 1, n do
    if t[i] == nil then return false end
  end
  return true, n
end

encode_value = function(v)
  local t = type(v)
  if t == "nil" then
    return "null"
  elseif t == "boolean" then
    return tostring(v)
  elseif t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return "null" end
    -- Integer-friendly formatting.
    if math.type(v) == "integer" then return tostring(v) end
    return string.format("%.14g", v)
  elseif t == "string" then
    return encode_string(v)
  elseif t == "table" then
    local arr, n = is_array(v)
    if arr then
      if n == 0 then return "[]" end
      local parts = {}
      for i = 1, n do parts[i] = encode_value(v[i]) end
      return "[" .. table.concat(parts, ",") .. "]"
    else
      local parts = {}
      for k, val in pairs(v) do
        parts[#parts + 1] = encode_string(tostring(k)) .. ":" .. encode_value(val)
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end
  end
  error("json: cannot encode value of type " .. t)
end

function M.encode(v)
  return encode_value(v)
end

----------------------------------------------------------------------
-- Decoder
----------------------------------------------------------------------

local decode_value

local function skip_ws(s, i)
  while i <= #s do
    local c = s:byte(i)
    if c ~= 32 and c ~= 9 and c ~= 10 and c ~= 13 then return i end
    i = i + 1
  end
  return i
end

local function decode_error(s, i, msg)
  local line, col, p = 1, 1, 1
  while p < i and p <= #s do
    if s:sub(p, p) == "\n" then line = line + 1; col = 1
    else col = col + 1 end
    p = p + 1
  end
  error(("json decode error at line %d col %d: %s"):format(line, col, msg))
end

local function codepoint_to_utf8(cp)
  if cp < 0x80 then
    return string.char(cp)
  elseif cp < 0x800 then
    return string.char(0xC0 + (cp >> 6), 0x80 + (cp & 0x3F))
  elseif cp < 0x10000 then
    return string.char(0xE0 + (cp >> 12), 0x80 + ((cp >> 6) & 0x3F), 0x80 + (cp & 0x3F))
  else
    return string.char(
      0xF0 + (cp >> 18),
      0x80 + ((cp >> 12) & 0x3F),
      0x80 + ((cp >> 6) & 0x3F),
      0x80 + (cp & 0x3F))
  end
end

local function parse_string(s, i)
  -- s:sub(i,i) == '"'
  i = i + 1
  local parts, p = {}, i
  while i <= #s do
    local c = s:byte(i)
    if c == 34 then -- "
      parts[#parts + 1] = s:sub(p, i - 1)
      return table.concat(parts), i + 1
    elseif c == 92 then -- backslash
      parts[#parts + 1] = s:sub(p, i - 1)
      local nc = s:sub(i + 1, i + 1)
      if nc == "n" then parts[#parts + 1] = "\n"
      elseif nc == "t" then parts[#parts + 1] = "\t"
      elseif nc == "r" then parts[#parts + 1] = "\r"
      elseif nc == "b" then parts[#parts + 1] = "\b"
      elseif nc == "f" then parts[#parts + 1] = "\f"
      elseif nc == '"' then parts[#parts + 1] = '"'
      elseif nc == "\\" then parts[#parts + 1] = "\\"
      elseif nc == "/" then parts[#parts + 1] = "/"
      elseif nc == "u" then
        local hex = s:sub(i + 2, i + 5)
        local cp = tonumber(hex, 16)
        if not cp then decode_error(s, i, "bad \\u escape") end
        -- Surrogate pair handling.
        if cp >= 0xD800 and cp <= 0xDBFF and s:sub(i + 6, i + 7) == "\\u" then
          local hex2 = s:sub(i + 8, i + 11)
          local cp2 = tonumber(hex2, 16)
          if cp2 and cp2 >= 0xDC00 and cp2 <= 0xDFFF then
            cp = 0x10000 + ((cp - 0xD800) << 10) + (cp2 - 0xDC00)
            i = i + 6
          end
        end
        parts[#parts + 1] = codepoint_to_utf8(cp)
        i = i + 4
      else
        decode_error(s, i, "bad escape \\" .. nc)
      end
      i = i + 2
      p = i
    else
      i = i + 1
    end
  end
  decode_error(s, i, "unterminated string")
end

local function parse_number(s, i)
  local start = i
  local c = s:byte(i)
  if c == 45 then i = i + 1 end -- '-'
  while i <= #s do
    c = s:byte(i)
    -- digits, '.', e/E, +/-
    if (c >= 48 and c <= 57) or c == 46 or c == 43 or c == 45 or c == 69 or c == 101 then
      i = i + 1
    else break end
  end
  local n = tonumber(s:sub(start, i - 1))
  if n == nil then decode_error(s, start, "bad number") end
  return n, i
end

decode_value = function(s, i)
  i = skip_ws(s, i)
  if i > #s then decode_error(s, i, "unexpected end of input") end
  local c = s:sub(i, i)
  if c == '"' then
    return parse_string(s, i)
  elseif c == "{" then
    local obj = {}
    i = skip_ws(s, i + 1)
    if s:sub(i, i) == "}" then return obj, i + 1 end
    while true do
      i = skip_ws(s, i)
      if s:sub(i, i) ~= '"' then decode_error(s, i, "expected string key") end
      local key
      key, i = parse_string(s, i)
      i = skip_ws(s, i)
      if s:sub(i, i) ~= ":" then decode_error(s, i, "expected ':'") end
      i = i + 1
      local val
      val, i = decode_value(s, i)
      obj[key] = val
      i = skip_ws(s, i)
      local nc = s:sub(i, i)
      if nc == "}" then return obj, i + 1
      elseif nc == "," then i = i + 1
      else decode_error(s, i, "expected ',' or '}'") end
    end
  elseif c == "[" then
    local arr = {}
    i = skip_ws(s, i + 1)
    if s:sub(i, i) == "]" then return arr, i + 1 end
    local n = 0
    while true do
      local val
      val, i = decode_value(s, i)
      n = n + 1
      arr[n] = val
      i = skip_ws(s, i)
      local nc = s:sub(i, i)
      if nc == "]" then return arr, i + 1
      elseif nc == "," then i = i + 1
      else decode_error(s, i, "expected ',' or ']'") end
    end
  elseif c == "t" then
    if s:sub(i, i + 3) ~= "true" then decode_error(s, i, "expected true") end
    return true, i + 4
  elseif c == "f" then
    if s:sub(i, i + 4) ~= "false" then decode_error(s, i, "expected false") end
    return false, i + 5
  elseif c == "n" then
    if s:sub(i, i + 3) ~= "null" then decode_error(s, i, "expected null") end
    return nil, i + 4
  elseif c == "-" or (c >= "0" and c <= "9") then
    return parse_number(s, i)
  end
  decode_error(s, i, "unexpected character '" .. c .. "'")
end

function M.decode(s)
  if type(s) ~= "string" then error("json.decode: expected string") end
  local v = decode_value(s, 1)
  return v
end

return M
