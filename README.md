# OCClaude

A tiny Claude Code-style agent CLI for **OpenComputers** (Minecraft mod) running **OpenOS 1.8.9**. Pure Lua, single internet-card dependency, no luarocks.

It talks to the [Anthropic Messages API](https://docs.anthropic.com/en/api/messages) and lets the model drive the box with `bash`, `read`, `edit`, and `write` tools.

## Layout

```
bin/occlaude.lua           -> /home/bin/occlaude.lua
lib/occlaude/json.lua      -> /home/lib/occlaude/json.lua
lib/occlaude/api.lua       -> /home/lib/occlaude/api.lua
lib/occlaude/tools.lua     -> /home/lib/occlaude/tools.lua
lib/occlaude/agent.lua     -> /home/lib/occlaude/agent.lua
install.lua                -> bootstrap fetcher
```

`/home/bin` and `/home/lib` are already on OpenOS's default `PATH` and `package.path`, so no extra config is needed.

## Hardware requirements

- Tier 2+ CPU/RAM (1MB minimum recommended; replies can be a few hundred KB)
- **Internet Card** (HTTPS-capable; OC 1.7+ supports it)
- Disk with ~20 KB free

## Install

### Option A: from a hosted repo (recommended)

1. Push this folder to GitHub.
2. On the OC computer:
   ```sh
   wget https://raw.githubusercontent.com/<you>/OCClaude/main/install.lua
   install.lua https://raw.githubusercontent.com/<you>/OCClaude/main
   ```

### Option B: copy by hand

`wget` each of the files in the layout above to its destination path. (Tedious, but works if you can't push to a hosting service.)

### Option C: pastebin

Upload each file to pastebin and use `pastebin get <id> <dest>` for each one.

## Configure

Save your Anthropic API key to `/home/.occlaude.key`:

```sh
echo sk-ant-... > /home/.occlaude.key
```

(Just the key, one line. No quotes.)

## Run

```sh
occlaude
```

REPL commands:

| Command       | What it does                       |
|---------------|------------------------------------|
| `/quit`       | Exit                               |
| `/reset`      | Clear conversation history         |
| `/model <id>` | Switch model mid-session           |

Flags:

```
occlaude --model claude-haiku-4-5     # cheaper / faster
occlaude --keyfile /etc/anthropic.key
```

## Tools the model has

| Tool    | What it does                                              |
|---------|-----------------------------------------------------------|
| `bash`  | Runs an OpenOS shell command, captures stdout+stderr      |
| `read`  | Reads a file at an absolute path                          |
| `edit`  | Replaces a unique substring in a file                     |
| `write` | Writes/overwrites a file (creates parent dirs)            |

## Notes / gotchas

- **Memory:** Big responses + big conversation history can exceed your OC RAM. Use `/reset` between unrelated tasks, or bump RAM to tier 3.5.
- **HTTPS:** OpenComputers' internet card has a server-side allowlist. `api.anthropic.com` is on the default allowlist in vanilla OC; if your server has a custom one, ask the admin to add it.
- **No streaming:** Responses are buffered in full before printing. Long outputs feel laggy. Tradeoff for simplicity.
- **No syntax highlighting / fancy TUI.** It's a REPL.

## Files at a glance

- `lib/occlaude/json.lua` — pure-Lua JSON encoder/decoder with proper UTF-8/escape handling.
- `lib/occlaude/api.lua` — `internet`-card HTTPS client for `POST /v1/messages`.
- `lib/occlaude/tools.lua` — tool schemas + implementations.
- `lib/occlaude/agent.lua` — the `tool_use` ↔ `tool_result` loop.
- `bin/occlaude.lua` — REPL entry point.
- `install.lua` — bootstrap downloader.
