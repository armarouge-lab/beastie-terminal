# BEASTIE

**Technical Documentation - V1.0.0**

Terminal emulator for RedhotBSD (FreeBSD) and Linux, built on suckless `st 0.9.3`

---

## 1. Philosophy and scope

Beastie is the official terminal of RedhotBSD. It does not reinvent the terminal emulator. It curates a minimalist, controllable base. The suckless `st` is the implementation that best embodies the project's principles: roughly 2,500 lines of C, minimal dependencies (X11, Xft, Xrender, fontconfig, freetype), imperceptible latency, and configuration that lives directly in the source code via `config.h`.

What Beastie adds on top of `st`:

1. A predefined `config.h` for RedhotBSD, carrying the suite's visual theme.
2. Essential patches that suckless does not ship by default (`scrollback`, `alpha`, `xresources`), plus a local `spawn` injection built on `fork` and `execvp`.
3. Integration with the suite: shortcuts that dispatch to `devil` and `nid`.
4. A `beastie` wrapper that sets default flags, exports `TERM=beastie-256color`, and answers `--version` and `--selftest`.
5. A dedicated `terminfo` entry (`beastie-256color`), generated from `st.info` and installed to the user or system database, so that TUI applications like `htop`, `vim`, `less`, and `mc` behave correctly.

What Beastie does not do in V1.0: Wayland (RedhotBSD is X11 with `cwm`, and the development environment runs MiniOS with Fluxbox), tabs of any kind (each window is an independent terminal managed by the window manager), kitty or sixel graphics, and GUI configuration.

The guiding rule is simple. The terminal is a utility. Latency and predictability matter more than exotic features. Anything that requires a heavy graphics stack (GPU, Electron, Wayland) or a recompile for trivial adjustments is out of scope, unless the adjustment can be made through Beastie's `config.h`, which is exactly how `st` is meant to be customized.

---

## 2. Why `st` and not something else

The choice came down to a small comparison:

| Criterion | `rxvt-unicode` | `st` |
|---|---|---|
| Memory footprint (RSS) | around 6.5 to 8 MB | around 2 to 4 MB |
| Lines of code | around 32,000 | around 2,500 |
| Configuration | `Xresources` at runtime | `config.h` at compile time, plus `Xresources` via patch |
| Dependencies | X11, Xft, fontconfig, freetype, libc | X11, Xft, Xrender, fontconfig, freetype, libc |
| Official patches | none | `scrollback`, `alpha`, `xresources` |
| True color | patched to 24-bit | natively supported since 0.8 |
| UTF-8 and wide characters | mature | supported |
| Built-in fork/execvp | yes | yes, through the local `spawn` injection |

`rxvt-unicode` was set aside because its runtime configuration and its daemon mode are features RedhotBSD simply does not need. `st` starts in ten to fifteen milliseconds without a daemon, and its configuration model is coherent with the project's stance that the code is the source of truth.

`foot` was rejected outright because it only runs under Wayland, and RedhotBSD is an X11 system. `alacritty` was rejected because it is GPU-accelerated and has documented idle CPU problems on FreeBSD.

`st` is the right base. The trade-off is that changing a color or a font requires a recompile, and that is consistent with the "focused, not minimalist" philosophy: the Beastie `config.h` is versioned and stable, and a user who wants to customize accepts the cost of recompiling.

---

## 3. Requirements and dependencies

Required:

- FreeBSD 14 or later with X11 (`xorg-server`, `xinit`), or Linux (validated on Debian 12 and MiniOS).
- `libX11`, `libXft`, `libXrender`, `fontconfig`, and `freetype2`, which are build and runtime dependencies of `st` with the applied patches.
- `pkg-config`, and `gcc` or `clang`, to compile `st` against the RedhotBSD `config.h`.
- `ncurses-bin` on Debian, or the equivalent on FreeBSD, dnf, or pacman. This provides `tic`, which is required to generate the `terminfo` entry.
- `xrdb`, available through `x11-xserver-utils` on Debian and already bundled with Xorg on FreeBSD.
- `fontconfig`, which provides `fc-cache` for registering Iosevka Term.

Optional at runtime:

- `picom` on Debian, or `xcompmgr` and `picom` on FreeBSD, is a compositor needed to see the transparency that the `alpha` patch produces. MiniOS with Fluxbox already has a compositor running.
- `xclip`, if the user wants to copy from `st` to the rest of the system without recompiling. It is not a Beastie dependency.
- `devil` and `nid`, which only exist on the metal RedhotBSD system. On MiniOS, `Ctrl+Shift+D` and `Ctrl+Shift+F` fail silently inside `execvp`.

There are some rules around dependencies that the installer respects. Beastie does not depend on Java, Python, Node, or any managed runtime. It is pure C with X11. The installer compiles `st` from source and never touches the `x11/sterm` port, because the RedhotBSD `config.h` can only be applied at compile time. And `tmux` is not installed by Beastie at all: the tab feature was removed from V1.0 scope, and anyone who wants multiple terminals opens a new window with `Ctrl+Shift+N` or lets the window manager handle it.

---

## 4. Installation, patches, and config.h

### 4.1 Compiling from source

The `install.sh` script does the following, in order:

1. Downloads `st 0.9.3` from `https://dl.suckless.org/st/`.
2. Applies the essential patches from section 4.2.
3. Injects the `spawn` function via `awk`, anchored on `ttynew`.
4. Injects the `void spawn(const Arg *)` prototype into `st.h`.
5. Attempts to swap the default title in `x.c` or `st.c`, best-effort, as described in section 4.2.
6. Generates the RedhotBSD `config.h` with `sed` and `awk` and copies it into the source directory.
7. Compiles with `make` on Linux, or `gmake` on FreeBSD.
8. Installs `st` to `/usr/local/bin/st` with `make install PREFIX=/usr/local`.
9. Generates `beastie.info` from `st.info` and runs `tic` to register `beastie-256color`.
10. Installs the `beastie` wrapper to `/usr/local/bin/beastie`.
11. Writes the four `st.*` keys to `~/.Xresources` and merges them with `xrdb -merge`.

The reason for compiling from source instead of using the port is straightforward. The port compiles `st` against the default suckless `config.h`. Beastie needs a different `config.h`, and there is no way to apply one after the fact.

### 4.2 Applied patches

A plain `st` has no scrollback, no transparency, and no `Xresources` reading. Beastie applies three official patches and two local injections:

| Patch | Origin | Purpose | Fallback |
|---|---|---|---|
| `scrollback` | `st.suckless.org/patches/scrollback/st-scrollback-0.9.2.diff` | 5,000 lines of history, reachable with `Shift+PgUp` and `Shift+PgDn`, using `HISTSIZE 5000` in `st.c` | none needed, applies cleanly |
| `alpha` | `st.suckless.org/patches/alpha/st-alpha-20220206-0.8.5.diff` | Transparency at 0.95 for the background, requires `-lXrender` and a compositor | One hunk in `xinit()` fails against `st 0.9.3`. The installer substitutes `XDefaultDepth` and `DefaultDepth` with `xw.depth`. |
| `xresources` | `st.suckless.org/patches/xresources/st-xresources-20200604-9ba7ecf.diff` | Reads colors and font from `Xresources`, reloads on restart | none needed, applies cleanly against 0.9.3 |
| `spawn` (local) | Injected via `awk` into `st.c` | `void spawn(const Arg *arg)` using `setsid`, `fork`, and `execvp`, with no shell in between | none, injection is verified by a guard |
| `title` (local, best-effort) | `sed` against `x.c` and `st.c` | Replaces `"st"` with `"Beastie"` as the default title | Never fails the build. If the anchor is missing, `logWarn` runs and the script continues. The wrapper guarantees `-t "Beastie"`. |

The order matters because each patch shifts the context of the next one. The sequence is `scrollback`, then `alpha`, then `xresources`, then `spawn`, then `title`, and finally `config.h`.

Three optional patches are documented but not applied: `ligatures` (requires `libharfbuzz`), `boxdraw` (improves box drawing inside TUIs), and `font2` (a font fallback chain for emoji and wide characters).

### 4.3 The RedhotBSD config.h

The `config.h` is generated on every build by `applyConfigHeader`, through `sed` and `awk`. It is never versioned. It defines:

The font is `Iosevka Term:size=13:antialias=true:autohint=true`, shipped inside `fonts/iosevka/` as described in section 4.7.

The colors are background `#0a0a0a`, foreground `#e0e0e0`, cursor `#ff6600`, and a 16-color palette derived from the Redhot theme. The normal colors are `#0a0a0a`, `#e64132`, `#a8c977`, `#f0a843`, `#5b9dd9`, `#d97ea3`, `#7ec9c9`, and `#e0e0e0`. The bright colors are `#7a7a7a`, `#ff6b4a`, `#c3e88d`, `#ffd166`, `#82aaff`, `#f78ca2`, `#89ddff`, and `#ffffff`. Four extra slots cover `[256]` to `[259]`: `#0a0a0a` for background, `#e0e0e0` for foreground, `#ff6600` for cursor, and `#555555` for reverse cursor.

The `defaultbg`, `defaultfg`, `defaultcs`, and `defaultrcs` values are aligned to `256`, `257`, `258`, and `259`, which is how the `xresources` patch maps its keys. Without that alignment, `st.background` ends up coloring the cursor instead of the background. That is a class of bug that costs hours to diagnose.

The transparency value is `alpha = 0.95`. The shortcuts are `Ctrl+Shift+C` for copy, `Ctrl+Shift+V` for paste, `Ctrl+Shift+N` for a new `beastie` window, `Ctrl+Shift+D` to open `devil .`, and `Ctrl+Shift+F` to open `nid .`. Scrollback is `HISTSIZE 5000`, defined in `st.c` because the 0.9.2 patch uses a `#define` rather than a configurable.

### 4.4 terminfo

`st` sets `TERM=st-256color` by default, but that entry does not exist on Debian or MiniOS out of the box. Without it, `htop`, `vim`, `less`, and any other TUI abort with `Error opening terminal`. Beastie resolves this with three steps.

First, it generates `beastie.info` from the `st.info` shipped in the tarball, replacing `st-256color|` with `beastie-256color|`. That file is never versioned; it always derives from the exact `st.info` of the `st` version being compiled.

Second, it runs `tic -x -o "$TERMINFO_DIR"`. On Linux the destination is `$HOME/.terminfo`, the user database, which survives as long as `$HOME` does. On FreeBSD the destination is `/usr/local/share/misc`, the system database.

Third, it verifies the result with `infocmp -A "$TERMINFO_DIR" beastie-256color`. The wrapper then exports `TERM=beastie-256color` before running `st`, so every TUI inside the terminal inherits the correct `TERM` and finds the entry.

### 4.5 The beastie wrapper

The wrapper is a short POSIX shell script:

```sh
#!/bin/sh
if [ "${1:-}" = "--version" ]; then
    printf 'beastie 1.0.0 (st 0.9.3)\n'
    exit 0
fi
if [ "${1:-}" = "--selftest" ]; then
    printf 'beastie selftest\n'
    # verifies st in PATH and terminfo
    exit 0
fi
export TERM=beastie-256color
exec /usr/local/bin/st \
  -f "Iosevka Term:size=13" \
  -g 100x30 \
  -t "Beastie" \
  "$@"
```

The three `st` flags matter. `-f` sets `Iosevka Term:size=13` as the default font, overriding what `config.h` says when `xresources` is active. `-g` sets `100x30` as the default geometry, ten columns wider than the minimum. `-t` sets `Beastie` as the window title, which guarantees the title even when the best-effort `applyWindowTitle` did not find its anchor.

There is no `system()`, no interactive shell, and no interpolation. The wrapper is a direct `exec st`.

### 4.6 Verification

Two commands confirm the installation:

```sh
beastie --version        # "beastie 1.0.0 (st 0.9.3)"
beastie --selftest       # checks st in PATH and beastie-256color in terminfo
```

`--selftest` modifies nothing. It reads and reports. Exit code is `0` on success and `1` on failure.

### 4.7 Bundled fonts

Iosevka Term is versioned in the repository under `fonts/iosevka/`, with four essential TTFs and the license:

- `IosevkaTerm-Regular.ttf`
- `IosevkaTerm-Bold.ttf`
- `IosevkaTerm-Italic.ttf`
- `IosevkaTerm-BoldItalic.ttf`
- `OFL.txt`, the SIL Open Font License 1.1

The total is around 35 MB. The installer copies them to `$HOME/.local/share/fonts/iosevka/` and runs `fc-cache`. The font is static on purpose, never downloaded at runtime, so that the build is reproducible. The SIL OFL license requires `OFL.txt` to accompany the font files in any redistribution, so it is part of the tarball.

---

## 5. File layout

In the repository at `~/beastie/`:

| Purpose | Path |
|---|---|
| OS detection script | `detect-os.sh` |
| Installer | `install.sh` |
| Unit tests | `tests/detect-os.sh`, `tests/install.sh` |
| Bundled fonts | `fonts/iosevka/*.ttf` and `OFL.txt` |
| `.gitignore` | `.build/` |

On the system after installation:

| Purpose | Linux | FreeBSD |
|---|---|---|
| `st` binary | `/usr/local/bin/st` | `/usr/local/bin/st` |
| `beastie` wrapper | `/usr/local/bin/beastie` | `/usr/local/bin/beastie` |
| `terminfo` | `$HOME/.terminfo/b/beastie-256color` | `/usr/local/share/misc/terminfo.db` |
| Fonts | `$HOME/.local/share/fonts/iosevka/` | `$HOME/.local/share/fonts/iosevka/` |
| `Xresources` | `$HOME/.Xresources` with four `st.*` keys | `$HOME/.Xresources` with four `st.*` keys |
| Font cache | `$HOME/.cache/fontconfig/` | `$HOME/.cache/fontconfig/` |

Permissions are `0755` for `/usr/local/bin/st` and `/usr/local/bin/beastie`, and `0644` for the `terminfo` entry and the fonts.

Three things are never versioned: `config.h`, generated by the installer; `beastie.info`, generated from `st.info`; and `.build/`, which holds intermediate artifacts.

---

## 6. Interface and keybindings

Beastie has no interface of its own. The interface is `st`. The keybindings are defined in the generated `config.h` and include the standard `st` copy and paste shortcuts plus the suite's dispatch shortcuts.

| Shortcut | Action | Status |
|---|---|---|
| `Ctrl+Shift+C` | Copy to `CLIPBOARD` | implemented |
| `Ctrl+Shift+V` | Paste from `CLIPBOARD` | implemented |
| `Ctrl+Shift+N` | Open a new `beastie` window | implemented, requires the wrapper in `PATH` |
| `Ctrl+Shift+D` | Open `devil` in the current directory | requires `devil` in `PATH`, which exists only on RedhotBSD |
| `Ctrl+Shift+F` | Open `nid` in the current directory | requires `nid` in `PATH`, same caveat |
| `Shift+PgUp`, `Shift+PgDn` | Scroll through the 5,000-line history | implemented |
| `Ctrl+Shift+Q` | Quit | not implemented in V1.0; `exit` is a shell builtin, and `spawn` with `execvp("exit")` returns `ENOENT` |

Mouse support exists in `st`, but Beastie does not configure any mouse binding. Anyone who wants it can edit `config.def.h` and recompile.

One shortcut was removed in V1.0: `Ctrl+Shift+T`, which was supposed to open `tmux new-window`. The tab feature was cut from scope, and the installer no longer installs `tmux`. Each window is an independent terminal, managed by the window manager.

---

## 7. Integration with the suite

Beastie is the entry point of RedhotBSD. The dispatch shortcuts in section 6 invoke `devil` and `nid` directly in the current directory, without going through the Summoner.

Beastie has no built-in multiplexer. Each window is an independent terminal managed by the window manager, which is `cwm` on RedhotBSD and Fluxbox on MiniOS. `Ctrl+Shift+N` opens a new `beastie` window.

| App | How Beastie invokes it |
|---|---|
| Devil | `Ctrl+Shift+D` dispatches `devil .` |
| Nidhogg | `Ctrl+Shift+F` dispatches `nid .` |
| Imp | Indirectly, when `devil` or `nid` open media |
| Mnemo | `medic` runs as a normal command |
| Siren | `notify-send` runs through Daemonics or the apps |

---

## 8. Performance and footprint

| Metric | Value | Note |
|---|---|---|
| RSS per instance | around 2 to 4 MB | `st` is about 2,500 lines of C |
| Cold startup | around 15 to 20 ms | wrapper (about 5 ms of shell) plus `st` (about 10 to 15 ms) |
| Idle CPU | near zero | no render loop, no polling |
| 5,000-line scrollback | around 1 MB extra | depends on content |

There is no daemon mode. `st` starts in ten to fifteen milliseconds, and a daemon in the `urxvtd` style would add complexity without a measurable gain.

---

## 9. Security

The `spawn` function uses `fork`, `setsid`, and `execvp` with an argument array, never a shell. It does not interpret `|`, `>`, `;`, or `$()`. The `setsid` call matters because without it the child inherits the parent bash's controlling terminal, and `tmux` or `vim` end up hijacking the terminal that opened `st`.

Clipboard handling is standard for a terminal. `Ctrl+Shift+V` pastes from the X11 `CLIPBOARD` with no sanitization, matching what every other terminal does.

The `beastie-256color` terminfo entry is compiled locally from the `st.info` inside the tarball. There is no custom terminfo that could inject malicious sequences.

Beastie runs as an ordinary user. It does not need setuid.

It also does not implement a sandbox. The security of the terminal is the security of `st` plus X11. RedhotBSD does not promise `pledge` or `unveil` on the terminal side (those are OpenBSD features), and on FreeBSD `capsicum` does not apply to an emulator that relies on `fork` and `exec`.

---

## 10. Limitations and roadmap

### V1.0, current state at commit `f69c0df`

`st 0.9.3` is compiled with the RedhotBSD `config.h`, which brings Iosevka Term, the Redhot theme, and the aligned `defaultXX` values.

Three patches are applied. `scrollback` gives 5,000 lines via `HISTSIZE`. `alpha` gives transparency at 0.95, with the `xw.depth` fallback. `xresources` maps `background` to `[256]`, `foreground` to `[257]`, and `cursorColor` to `[258]`.

The `spawn` function is injected with `setsid`, `fork`, and `execvp`, and its prototype lives in `st.h`. The default title is set on a best-effort basis through `sed` in `x.c` and `st.c`, with the wrapper providing `-t "Beastie"` as a guarantee.

`st` is installed to `/usr/local/bin/st` and the wrapper to `/usr/local/bin/beastie`. The `beastie-256color` terminfo entry is generated and installed. `~/.Xresources` is managed with four `st.*` keys and merged with `xrdb`. The wrapper answers `--version` and `--selftest`.

The following are not present in V1.0. There is no `tmux`, since the tab feature was removed. There is no `Ctrl+Shift+Q`, because `spawn exit` fails and the proper fix is deferred to V1.1. There is no man page. There are no opt-in integration tests for `xclip` and `tmux`.

### V1.1, future work

`Ctrl+Shift+Q` will become a real `die()` action in the parent, or a `quit` handler inside `x.c`, equivalent to closing the window through the window manager. It will not use `spawn exit`, since `exit` is a shell builtin.

A man page `beastie.1` will document the flags, `--version`, `--selftest`, `TERM=beastie-256color`, and `~/.Xresources`.

Opt-in integration tests will use `xdotool` and `xclip` to verify `Ctrl+Shift+C` and `Ctrl+Shift+V` inside `beastie` without relying on visual inspection.

FreeBSD will be validated on real hardware. The things to confirm are `make install PREFIX`, `tic -x -o /usr/local/share/misc`, `pkg` inside `detect-os.sh`, and the absence of `-lrt` in `config.mk`. None of this has been tested on FreeBSD yet.

The `ligatures` and `boxdraw` patches will be documented as opt-in.

Finally, `beastie` will be added to the MiniOS `PATH` by default, by verifying that `/usr/local/bin` is on `$PATH`.

### Permanently out of scope

Wayland. GPU acceleration, given Alacritty's idle CPU problems on FreeBSD. Tabs of any kind, native or through a multiplexer. And any managed runtime on the execution path of the terminal.

---

## 11. Invariants that cannot break

1. Never use the `x11/sterm` port without `ST_CONF`. The RedhotBSD `config.h` is mandatory. Without it, Beastie loses both its visual identity and its dispatch shortcuts.
2. Never depend on a managed runtime. Beastie is pure C.
3. Never invoke `system()` or a shell inside the `beastie` wrapper. The wrapper is `exec st`, no interpolation.
4. Never disable `terminfo`. The `beastie-256color` entry is mandatory for TUIs. Without it, `htop`, `vim`, and `less` abort.
5. Never configure mouse bindings by default. RedhotBSD is keyboard-first, and mouse support is opt-in.
6. Never recompile `st` at runtime. The `config.h` is generated by the installer. User customization requires a documented manual recompile.
7. `spawn` always uses `setsid`. Without it, the child inherits the parent bash's tty and `tmux` or `vim` hijack the original terminal.
8. `applyWindowTitle` is best-effort. If the `opt_title ? opt_title : "st"` anchor is absent, the build must not abort. Log a warning and continue. The wrapper guarantees `-t "Beastie"` as a fallback.
9. Patch order matters. The sequence is `scrollback`, then `alpha`, then `xresources`, then `spawn`, then `title`, and finally `config.h`, because each patch shifts the context of the next.
10. `defaultbg`, `defaultfg`, `defaultcs`, and `defaultrcs` in `config.h` must be `256`, `257`, `258`, and `259`, matching the `xresources` mapping. Without that, `st.background` colors the cursor instead of the background.

---

## 12. Portability notes: Linux versus FreeBSD

| Aspect | Linux (Debian, MiniOS) | FreeBSD |
|---|---|---|
| Package manager | `apt`, `dnf`, or `pacman` | `pkg` |
| make | `make` | `gmake`, since BSD make fails on the suckless Makefile |
| X11 paths | `/usr/include`, `/usr/lib` | `/usr/local/include`, `/usr/local/lib` |
| `-lrt` | needed | removed, functions live in libc |
| `tic` destination | `$HOME/.terminfo` | `/usr/local/share/misc` |
| `xrdb` | `x11-xserver-utils` | part of `xorg-server` |
| Compositor | `picom` | `xcompmgr` or `picom` |

Testing status is honest about where things stand. Linux, specifically Debian 12 and MiniOS, has been validated across every implementation block. FreeBSD has not been tested on real hardware. Every point in the table above is mapped in `detect-os.sh` and `install.sh`, but adjustments will follow once there is hardware to test on. That is tracked under V1.1.

---

## Author's note

The `st` base remains the right call. It is about 2,500 lines, uses 2 to 4 MB of memory, starts in ten to fifteen milliseconds, and puts configuration in `config.h`, which is the suckless contract. The cost of a recompile to change a color or a font is consistent with the "focused" philosophy: the Beastie `config.h` is versioned and stable, and customization is a responsibility the user opts into.

Removing `tmux` was the right move for V1.0. On paper it solved tabs without reimplementing them. In practice, on a Live USB where `$HOME` is ephemeral, the "persistent session" it promised disappeared along with the disk. The feature existed in the spec but not in the context of use.

The point of attention is `terminfo`. Without it, `htop`, `vim`, and `less` break with `Error opening terminal`. Beastie solves this by generating `beastie.info` from `st.info` and running `tic` against `$HOME/.terminfo` on Linux or `/usr/local/share/misc` on FreeBSD. That step cannot be skipped, and it lives in the installer rather than in the user's head.

What makes the setup robust is the fallback layer: `xw.depth` for the alpha patch, best-effort for the title, and `infocmp` guards for `terminfo`. None of the three official patches were written for 0.9.3. The fallbacks are what make them work against it.

Beastie is, in the end, a configuration package over `st`: a generated `config.h`, a few patches, a wrapper, and a `terminfo` entry. `st` does the heavy lifting, and Beastie dresses it with RedhotBSD identity. Removing `tmux` simplified things, the wrapper consolidated them, and `terminfo` closed the last TUI compatibility hole. What is missing (`Ctrl+Shift+Q`, a man page, real FreeBSD validation) belongs to V1.1.

---

**End of document, V1.0.0**