# GcView V4 (beta)

V4 is in beta. The V3 loader (`PublicLoader.luau`) is unchanged and still the stable entry point.

## Load

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Awakenchan/GcViewerV3/main/GcViewV4/bundled.luau"))()
```

## Plugins

Everything is toggled from the **Plugins** tab, or from the **Settings** page of the web app.
Settings are saved to `GcView@awakenkn/gcview.json` in the executor workspace and apply on the next load.

| Plugin | Default | What it does |
| --- | --- | --- |
| Script tools | on | Scripts, Anti Cheat, AC Tables and Actor Scripts tabs |
| Web bridge | on | WebSocket bridge so a browser front-end can drive the session |
| Safe mode | off | Rejoin the server and dump every sandboxed script before the game boots |
| Web only | off | Skip the in-game UI entirely and run headless through the bridge |
| Auto connect | off | Connect to the relay as soon as GcView loads |
| Auto safe mode | off | Run safe mode on load instead of waiting for the button |

If **Web only** cannot reach the relay it falls back to the in-game UI, so a dead relay cannot lock you out.
`getgenv().gcviewui = true` before loading always forces the UI regardless of config.

## Web bridge

The executor can only open WebSocket connections, it cannot listen for them, so the browser and the
game both connect out to a small relay you run locally.

Press **Download bridge server** in the Plugins tab (or Settings in the web app) to write
`relay.js`, `index.html` and `package.json` into `GcView@awakenkn/bridge` in the executor workspace.

Then:

```
npm install
node relay.js
```

The relay prints two URLs:

- `ws://127.0.0.1:8765` — put this in the Relay URL field and press Connect
- `http://127.0.0.1:8766` — open this in a browser

The front-end lists scripts, anti-cheat hits, actor scripts and unresolved functions, with decompiled
source, per-function constants and upvalues, copy buttons and `.luau` / `.luac` downloads.

Set a different port with `GCVIEW_WS_PORT` / `GCVIEW_HTTP_PORT`.

## Safe mode

Safe mode caches the bundle, queues a post-teleport bootstrap, and rejoins the same server. On the
fresh session it dumps every script's bytecode and source to `GcView@awakenkn/GcViewSafeCapture`
before the game's own scripts get going, then returns to normal.

It needs `queueonteleport` and `writefile`.

## Requirements

Built against the [Volt](https://docs.voltbz.net/docs) environment and the sUNC naming convention.
Optional APIs are resolved by every documented alias, so other executors work where they implement
the same functions.
