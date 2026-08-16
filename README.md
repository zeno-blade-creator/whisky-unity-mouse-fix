# Mouse-click fix for Unity 6 games in Whisky (macOS)

**The problem:** you're running a Windows game on your Mac through
[Whisky](https://github.com/frankea/Whisky). The cursor moves fine. Menus
highlight when you hover. But **nothing you click responds.** Keyboard works,
mouse movement works, clicks do nothing.

**This fixes it.** Left click, right click, middle click, and click-and-drag all
work afterwards.

Games affected: anything built with **Unity 6** — released late 2025, so mostly
newer titles. Older games were never affected. Confirmed working with PEAK;
the same bug is reported for Civilization VI and others.

---

## Why it happens

Unity 6 asks Windows for a *newer* kind of mouse message than games used to use,
then listens only for that kind. Whisky's version of Wine doesn't implement it —
it replies "not implemented" and keeps sending the old kind of message, which the
game isn't listening for. So the clicks genuinely happen; nothing is listening.

CodeWeavers implemented this properly in **CrossOver 26.3**. Whisky's engine is
built from an *older* CrossOver, from before that work existed. This installs an
engine that has it.

> The fix itself is CodeWeavers' work, used under the LGPL licence.
> See [Credit and licence](#credit-and-licence).

---

## Start here

> ### 🚀 Never done any of this before?
> **Read [SETUP.md](Software/SETUP.md) instead.** It's a complete walkthrough from a Mac
> with nothing installed: Homebrew, Whisky, a bottle, Steam, your game, then this
> fix. Assumes no programming knowledge and explains every step.
>
> The instructions below assume you **already** have Whisky running your game.

## Before you start

You need:

- **A Mac with Apple Silicon** (M1–M4). Intel Macs aren't supported by Whisky.
- **macOS Sequoia 15.0 or later**
- **Whisky installed**, with a bottle and your game already running in it
- **About 20 minutes**, most of it your computer working while you don't
- **Around 2 GB of free disk space** during the build

You do **not** need to know how to program. Every command below is copy-and-paste.

---

## Install

### Step 1 — Open Terminal

Press **Cmd + Space**, type `Terminal`, press **Enter**. A window with text
appears. That's it — that's the terminal.

### Step 2 — Download this project

Copy this line, paste it into Terminal, press **Enter**:

```bash
git clone https://github.com/zeno-blade-creator/whisky-unity-mouse-fix.git ~/whisky-mouse-fix
```

If it says `git: command not found`, macOS will offer to install developer
tools — accept, wait for it to finish, then run the line again.

### Step 3 — Run the installer

```bash
cd ~/whisky-mouse-fix/Software/wine-patch && ./install.sh
```

That's the whole thing. The script will:

1. Check you have what's needed, and **offer to install anything missing**
2. Download CodeWeavers' source code (~142 MB)
3. Build it (~15 minutes — leave it running)
4. Check the result is sound **before** touching anything
5. Back up your original engine, then install the new one

**It stops rather than guessing.** If any check fails it tells you which one and
changes nothing, so you're never left half-installed.

### Step 4 — Play

Start your game as usual and try clicking.

---

## If something goes wrong

### First: run the doctor

```bash
cd ~/whisky-mouse-fix/Software/wine-patch && ./doctor.sh
```

It checks your macOS version, Whisky, whether the fix is actually installed, the
graphics stack, file ownership, and whether a game launcher exists — then prints
one report. It changes nothing. Send the whole output to whoever is helping you.

### Undo everything

```bash
cd ~/whisky-mouse-fix/Software/wine-patch && ./install-pointer-fix.sh uninstall
```

This puts your original engine back exactly as it was. Your games and Whisky
setup are untouched.

### The game crashes when it starts

Almost certainly **not** this fix. Whisky switches graphics systems by copying
files into your bottle, and its two graphics packages contain different numbers
of files — so switching leaves a mismatched set that can't start a game. Launching
a game *from Whisky* can trigger it.

The error usually mentions failing to create a graphics device, or
`0x80004005`, and looks nothing like a graphics problem.

Fix it by running:

```bash
cd ~/whisky-mouse-fix/Playing && ./"FIX graphics stack.command"
```

Full explanation in [FINDINGS.md](Software/FINDINGS.md#2-whiskys-backend-switch-is-not-transactional).

### The game says it can't switch resolution

On a Retina Mac, macOS reports your screen as a smaller size than it physically
is, and Unity saves that fake size. Wine then checks it against real display
modes, finds nothing matching, and refuses to start — permanently, because the
bad value is saved.

Fix: delete the saved resolution so the game asks for your screen's real size.
[Details and the fix](Software/FINDINGS.md#3-the-retina-resolution-trap).

### Check what's currently installed

```bash
cd ~/whisky-mouse-fix/Software/wine-patch && ./install-pointer-fix.sh status
```

---

## Is this safe?

Reasonable question — you're installing something into the layer that handles all
window and input operations.

- **You build it yourself.** Nothing pre-compiled is downloaded. The source comes
  straight from CodeWeavers' official servers, and your own Mac compiles it.
- **Your original is backed up** before anything is replaced, and `uninstall`
  restores it.
- **The installer refuses to install anything it can't verify.** It compares the
  built engine against your existing one and stops if they don't match up.

If you'd rather read the code first, it's five shell scripts and one Python file
in `Software/wine-patch/` — `install.sh` (the one you run), `build-engine.sh`,
`verify-engine.sh`, `install-pointer-fix.sh`, `doctor.sh`, and
`apply-pointer-patch.py`.

---

## What it actually replaces

One file: `win32u.so` inside Whisky's Wine — the part that handles windows and
input. Your bottles, games, saves and settings are never touched.

The build also produces a Windows-side `win32u.dll`. The installer compares it
against the one already there and only replaces it if it genuinely differs, and
it tells you which of those happened rather than assuming.

> **Whisky's data is per-account.** macOS keeps a separate Whisky — bottles and
> Wine engine both — for every user account on the Mac. Install this from the
> same account you actually play in, or it will appear to succeed and change
> nothing for the account that matters.

---

## The deeper write-up

[**FINDINGS.md**](Software/FINDINGS.md) documents all six problems found getting this
working, with the evidence for each — including two bugs in Whisky itself, a
Retina display trap affecting any Mac, and a default setting that can consume
15 GB of memory. Written for people who want to know *why*, not just *how*.

---

## What's in here

```
Playing/     double-click these to play
Software/    the fix itself, plus the write-ups
```

### Playing

All double-clickable. They **find your Whisky bottle automatically** rather than
having one hardcoded, so nothing here is tied to one game or one Mac.

| Script | What it does |
|---|---|
| **`Add a game.command`** | **Start here.** Give it a game's Steam App ID; it installs the game and creates a `Play <game>.command` you use from then on. Run it once per game. |
| `Play <game>.command` | Created by the above. Repairs the graphics stack and the saved screen size, then launches that game. |
| `FIX graphics stack.command` | Repairs the mismatched DXVK/DXMT set described above. |
| `Launch Steam (Windows).command` | Opens Steam on its own, with the graphics repair applied. |
| `STOP everything.command` | Kills every Windows process, including the runaway debugger. |
| `Check performance before playing.command` | Warns about anything that will make games run badly. |

> **Tip:** once `Add a game.command` has made your `Play <game>.command`, drag it
> to your Dock. That's then the only thing you ever need to click.

If you have more than one bottle and the scripts can't tell which to use, they
list them and ask you to save the right ID into `Playing/bottle.conf`.

### Software

| | |
|---|---|
| `wine-patch/` | The fix: `install.sh` (the one command), the build and install scripts, and your backed-up original engine |
| `wine-patch/doctor.sh` | **Run this when anything goes wrong.** Checks everything and prints one report you can send to someone. Changes nothing. |
| [`SETUP.md`](Software/SETUP.md) | Complete walkthrough from a Mac with nothing installed |
| [`FINDINGS.md`](Software/FINDINGS.md) | All six problems, with the evidence for each |
| [`CREDITS.md`](Software/CREDITS.md) | Who wrote what, and the licence |

---

## Credit and licence

**The mouse fix is CodeWeavers' work**, from CrossOver 26.3, used under the
**GNU Lesser General Public License v2.1 or later**. I diagnosed why Whisky was
affected, and built and verified a way to apply it there. I did not write the
implementation.

- **Wine** — the compatibility layer everything here builds on ([winehq.org](https://www.winehq.org))
- **CodeWeavers / CrossOver** — the pointer implementation, published as LGPL
  source at [codeweavers.com/crossover/source](https://www.codeweavers.com/crossover/source)
- **Whisky** — the macOS wrapper ([frankea/Whisky](https://github.com/frankea/Whisky),
  the maintained fork)
- **DXMT** — Direct3D-to-Metal translation, which is what makes graphics work at all

See [CREDITS.md](Software/CREDITS.md) and [LICENSE](LICENSE).
