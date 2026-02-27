# SDK Dev Setup — Loading ADO Lua SDK locally

This guide explains how to load the [ADO Lua SDK](../../../ADO_Lua_SDK) from a local
checkout during development without modifying your Neovim plugin manager configuration.

## Why an env var?

The SDK path is gated behind `ADO_LUA_SDK_DEV_PATH` so the plugin stays portable.
Collaborators or CI don't need the local SDK checkout; the env var is simply absent and
the plugin falls back to whatever SDK installation is on `runtimepath`.

## Setup

1. **Clone the SDK** (if not already done):

   ```bash
   git clone <sdk-repo> ~/dev/Lua/ADO_Lua_SDK
   # or wherever you keep it
   ```

2. **Export the path before starting Neovim:**

   ```bash
   export ADO_LUA_SDK_DEV_PATH=/home/n8/dev/Lua/ADO_Lua_SDK
   nvim
   ```

   Add it to your shell profile (`~/.zshrc`, `~/.bashrc`) or a `.envrc` (direnv) so
   it's always set in your dev environment:

   ```bash
   # ~/.zshrc (or .envrc in the plugin repo)
   export ADO_LUA_SDK_DEV_PATH=/home/n8/dev/Lua/ADO_Lua_SDK
   ```

3. **Start Neovim normally.** The plugin's `plugin/ado.lua` appends the SDK's `lua/`
   directory to `package.path` at startup.

## How it works internally

`plugin/ado.lua` appends `$ADO_LUA_SDK_DEV_PATH/lua/?.lua` (and `?/init.lua`) to
`package.path` when the env var is set.  The plugin's own `ado.*` modules are at the
front of the path (loaded via runtimepath), so they take priority for any shared module
names.  The one name collision (`ado.config`) is handled transparently by
`lua/ado/ado_client.lua` — see comments there.

## Verifying it works

Run this in Neovim after setting the env var:

```vim
:lua print(require('ado.ado_client').get())
```

You should see a table (the SDK client), not an error string.

Or more verbosely:

```vim
:lua local c, err = require('ado.ado_client').get(); print(c and "SDK OK" or err)
```

Expected output: `SDK OK`

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `ADO SDK not available` notification | `ADO_LUA_SDK_DEV_PATH` not set — restart Neovim after exporting |
| `ado.client load error: ...` | SDK path is wrong or SDK not built — check the path |
| `Auth error: ...` | `ADO_PAT` env var is missing or the token is invalid |
