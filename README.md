# container-ui

A native app for [apple/container](https://github.com/apple/container). It has a
window. It has a menu bar. It has a terminal companion. They all talk to the
`container` CLI, and they show you what it knows.

There is no daemon here. There is nothing new to keep running. The CLI does the
work. These front-ends read it and draw it.

```
┌──────────────────────────────────────────────┐
│ ▣ Containers │  ubuntu           ● Running    │
│ ▤ Images     │  ubuntu:latest                 │
│ ⚙ System     │  [cpu 4] [mem 1 GB] [192.168…] │
│              │        ▶ ⏹  logs  🗑            │
│ ● Engine running                              │
└──────────────────────────────────────────────┘
```

## What it does

- Shows your containers. It refreshes every two seconds while you watch, and
  stops when you look away. You see the state, the image, the CPU, the memory,
  the address.
- Starts and stops them. Removes them. Starts and stops the engine.
- Follows the logs. The lines come in as they happen. You can select them.
- Runs a new container. You pick the image, the name, the memory, the CPUs, the
  mounts, the ports, the environment. It shows you the command before you run it.
- Lists the images. It sorts them.
- Sits in the menu bar. It shows how many run. You start and stop from there.
- Runs in the terminal too. That is `ctui`. It is fast. You drive it with keys.

It looks the way a Mac app should. The surfaces are Liquid Glass. The rows blend
and morph. A mesh gradient breathes behind the details, drawn on the GPU. It
turns green when the engine runs.

## The assistant

If you have Apple's on-device model — the `fm` CLI — the app uses it. It is
private. It runs on the Mac. Nothing leaves.

- Describe a container in plain words. It writes the `run` command.
- Ask what a container is. It tells you.
- Point it at the logs. It says what went wrong.

No key. No account. If `fm` is not there, the assistant hides itself.

## What you need

- An Apple silicon Mac. macOS 26 or newer. The glass wants it.
- The Swift 6 toolchain. Xcode 26 or newer.
- A working [`container`](https://github.com/apple/container). The app looks for
  the binary in this order: `$CONTAINER_BIN`, `~/container/bin/container`,
  `/usr/local/bin/container`, `/opt/homebrew/bin/container`, then your `PATH`.
- The `fm` CLI, if you want the assistant. It is optional.

## Build it. Run it.

```bash
make run      # build the app, bundle it, open it
make tui      # build the terminal UI and run it
make app      # just build build/Container.app
make install  # put Container.app in /Applications, ctui in /usr/local/bin
make help     # show the targets
```

Point it at a different binary:

```bash
CONTAINER_BIN=/path/to/container make run
```

## The terminal keys

```
↑/↓ or j/k   move          s   start or stop the one you picked
r            refresh        x   remove the one you picked
e            start or stop the engine
l            follow the logs. Ctrl-C brings you back.
q            quit
```

## How it is built

```
Sources/
  ContainerKit/     the engine. No UI. Just the work.
    CLI.swift         an actor around the binary. It runs it. It streams logs.
    Models.swift      the types for `ls` and `image ls --format json`.
  ContainerUI/      the SwiftUI app. A window and a menu bar.
  ctui/             the terminal UI. Raw mode. ANSI. Keys.
scripts/bundle.sh   wraps the binary into Container.app
```

## Things to know

The engine does not start when you log in. That is on purpose. Start it from the
System tab, the menu bar, the `e` key in `ctui`, or `container system start`.

A container's memory, its CPUs, its mounts — you set them once, when you run it.
You do not change them later. To change them, you remove it and run it again. The
Run form makes that quick.

## License

MIT.
