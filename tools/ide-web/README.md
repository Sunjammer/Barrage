# Barrage IDE Web Preview

Small local web app for interactive Barrage script iteration with canvas preview.

## Build

```powershell
cd tools/ide-web
haxe build.hxml
```

## Run

Serve `tools/ide-web` from any static server, then open `index.html`.

Example with Python:

```powershell
cd tools/ide-web
python -m http.server 8080
```

Open: `http://localhost:8080`

## Features

- Live parse/rebuild on script edits
- Seeded deterministic simulation
- Play/pause, single-step, reset
- Script presets (Waveburst, Swarm, Multitarget Demo)
- Mouse-driven player target in canvas
