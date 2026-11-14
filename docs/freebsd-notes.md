# FreeBSD notes

Status: mapped but not tested on real hardware. Every item below was
inferred from the Linux build and from the FreeBSD-specific branches in
`detect-os.sh` and `install.sh`. Treat them as hypotheses to confirm, not
as facts.

## Pre-flight

```
pkg install -y git
git clone https://github.com/armarouge-lab/beastie-terminal ~/beastie
cd ~/beastie
chmod 0755 detect-os.sh install.sh tests/*.sh
```

Run `./detect-os.sh --print` and confirm the output:

```
OS=FreeBSD
PKG=pkg
BUILD_TOOL=gmake
X11_PREFIX=/usr/local
TERMINFO_DIR=/usr/local/share/misc
```

If any value is wrong, stop. Fix `detect-os.sh` before running
`install.sh`. Everything downstream reads these five variables.

## Test checklist

Run each command, confirm the expected output, record pass or fail.

### 1. Dependencies resolve

```
./install.sh 2>&1 | tee /tmp/beastie-freebsd.log
```

Expected: line `[ OK ] dependencies installed via pkg`. If `pkg install`
fails on a specific package, the name is wrong in `install.sh`. Most
likely suspects: `xrdb` (may be part of `xorg-apps`, not standalone),
`ncurses` (base system already has `tic`), `picom` (may need
`xcompmgr` instead).

### 2. gmake succeeds

Expected: line `[ OK ] build clean, 0 warnings`. If `make: not found`
appears, `BUILD_TOOL` was `make` instead of `gmake`. Re-check item 0.

### 3. Patches apply

Expected: four `[ OK ]` lines for scrollback, alpha, xresources, spawn.
The alpha patch will emit a warning about the rejected `xinit` hunk and
apply the fallback. That is normal on 0.9.3 and matches Linux.

### 4. terminfo lands where expected

```
ls /usr/local/share/misc/terminfo.db
```

or

```
ls /usr/local/share/misc/b/beastie-256color
```

FreeBSD `tic` may write either the hashed database (`terminfo.db`) or a
tree of directories. Both are valid; the guard is `infocmp -A`. If
neither exists, check `$TERMINFO_DIR` in `detect-os.sh`.

### 5. man page installs

```
man beastie
```

Expected: the page renders. If `man: no entry` appears, the manpath is
missing `/usr/local/man`. Add to `~/.profile`:

```
export MANPATH=/usr/local/man:$MANPATH
```

FreeBSD does not ship `mandb`, so `install.sh` skips that step silently.
That is expected. The page still works if the path is correct.

### 6. wrapper runs

```
beastie --version
beastie --selftest
```

Expected: `beastie 1.0.0 (st 0.9.3)` and `st: OK`, `terminfo: OK`.

### 7. window opens

```
beastie
```

Inside, check:
- title says `Beastie`
- background is `#0a0a0a` with slight transparency
- cursor is `#ff6600`
- font is Iosevka Term
- `echo $TERM` prints `beastie-256color`
- `Ctrl+Shift+Q` closes the window with exit code 0

### 8. TUI works

```
beastie -e sh -c 'htop; read x'
```

Expected: `htop` renders without `Error opening terminal`. This is the
canary for terminfo.

## Known risks

Ordered by likelihood of breaking.

**xrdb package name.** On Debian it is `x11-xserver-utils`. On FreeBSD,
`xrdb` is usually part of the base Xorg install. If `pkg install xrdb`
fails with "no such package", remove it from the `pkg` case in
`install.sh` and rely on the base system.

**ncurses package name.** FreeBSD base has `tic` in `/usr/bin/tic`.
The port `ncurses` may be redundant. If `pkg install ncurses` fails,
remove it. `tic` from base works.

**picom availability.** FreeBSD ports has `x11-wm/picom` but availability
varies by release. If `pkg install picom` fails, use `xcompmgr` (in base
Xorg) and start it manually. The `alpha` patch itself works either way.

**gmake missing.** FreeBSD base does not ship `gmake`. It must come from
`pkg install gmake`. If `BUILD_TOOL=gmake` but the binary is missing,
item 1 failed to install it.

**`-lrt` still present in `config.mk`.** The `patchConfigMk` function
strips it for FreeBSD. If the build fails with `-lrt: not found`, check
that `patchConfigMk` ran before `buildSource` (it does in the current
`main()`).

**`make install PREFIX=/usr/local`.** Suckless Makefile respects
`PREFIX`, but this is untested on FreeBSD. If `st` does not end up in
`/usr/local/bin/st`, check the `install` target in
`st-0.9.3/Makefile`. Fallback: `cp st /usr/local/bin/st` and
`chmod 0755 /usr/local/bin/st`.

**terminfo.db versus tree.** FreeBSD's `tic` may write a hashed
database instead of directories. The `infocmp -A "$TERMINFO_DIR"` guard
accepts both. If `infocmp` fails but the file exists, the directory is
wrong. Check `tic -o` behavior with `tic -V` and the `TERMINFO` manual.

**`~/.Xresources` and Xsession.** MiniOS loads `~/.Xresources` at login
through `xrdb`. FreeBSD with `cwm` may not, unless the user starts `xrdb
-merge ~/.Xresources` in `.xinitrc`. The installer merges explicitly,
so the current session works. A future login without that line would
lose the theme. Add to `.xinitrc`:

```
xrdb -merge ~/.Xresources
```

## Expected differences versus Linux

| Aspect | Linux | FreeBSD |
|---|---|---|
| Package manager | apt | pkg |
| Build tool | make | gmake |
| X11 headers | /usr/include | /usr/local/include |
| X11 libs | /usr/lib | /usr/local/lib |
| `-lrt` | present | absent |
| terminfo path | $HOME/.terminfo | /usr/local/share/misc |
| terminfo format | tree | tree or .db |
| man path | /usr/local/share/man | /usr/local/man |
| man indexer | mandb | none (silently skipped) |

## Recovery

If `./install.sh` fails mid-run, the `.build/` directory holds the
partial state. Delete it and re-run. The tarball and patches are
re-downloaded, so there is no leftover from a bad run.

```
rm -rf ~/beastie/.build
./install.sh
```

If the build itself fails with a compiler error, capture it:

```
cat .build/build.log
```

That log is the only reliable diagnostic. Report the first `error:` line,
not the summary.

If the binary was previously installed and now the old one runs, `st` was
overwritten but the wrapper still points to `/usr/local/bin/st`. Check:

```
ls -la /usr/local/bin/st
ls -la /usr/local/bin/beastie
which st
```

The wrapper hardcodes `/usr/local/bin/st`. If FreeBSD's `make install`
put it somewhere else, edit `ST_INSTALL_PREFIX` in `install.sh` and
re-run.

## What to update after validation

If everything passes, update `beastie-spec.md`:

- Section 10: move FreeBSD from "not tested" to "validated on FreeBSD 14
  at commit <hash>"
- Section 12: mark every row as tested, or correct the ones that changed
- Section 11: add any new invariant discovered during testing

If something fails, fix the code, not the notes. The notes describe what
should be; the code is what is.

---

**End of FreeBSD notes.**