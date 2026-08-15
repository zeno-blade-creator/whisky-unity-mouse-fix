# Setup guide — from nothing to a working game

This walks you through everything, starting from a Mac with none of this
installed. **You do not need to know how to program.** Every command is
copy-and-paste, in order.

Total time: about **45 minutes**, most of it waiting.

If you already have Whisky and a game running, skip to [Part 5](#part-5--install-the-mouse-fix).

---

## What you'll end up with

A Windows game running on your Mac, with mouse clicks working, using entirely
free software. No paid tools.

## What you need first

| | |
|---|---|
| **A Mac with Apple Silicon** | M1, M2, M3, M4 — any of them. Intel Macs won't work. |
| **macOS Sequoia 15.0 or later** | Apple menu → About This Mac to check. |
| **About 20 GB free space** | The game, Steam, and build files. |
| **A Steam account** | Free. The game must be one you own. |

> **Which chip do I have?** Apple menu → About This Mac. If it says "Apple M1"
> through "Apple M4", you're fine. If it says "Intel", this won't work.

---

## Part 1 — Open Terminal

Terminal is an app where you type commands instead of clicking buttons. It comes
with every Mac.

1. Press **Cmd + Space** (hold Command, tap Space). A search bar appears.
2. Type **Terminal**
3. Press **Enter**

A window with text appears. That's Terminal. Leave it open — you'll use it
throughout.

**How to use it:** copy a command from this guide, click into the Terminal
window, paste (**Cmd + V**), press **Enter**. Then wait for it to finish before
running the next one. "Finished" means you get a fresh line with your username
on it again.

> Some commands ask for your Mac password. Type it and press Enter — **the
> characters won't appear as you type**, not even dots. That's normal. Type it
> and press Enter anyway.

---

## Part 2 — Install Homebrew

Homebrew installs developer software. Whisky and the build tools both come
through it.

Paste this into Terminal and press Enter:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

It will explain what it's about to do and ask you to press Enter to continue,
then ask for your password. Takes a few minutes.

**When it finishes**, it may print two lines starting with `eval` and tell you to
run them. If it does, copy and run them. Then check it worked:

```bash
brew --version
```

If you see a version number, you're good. If you see `command not found`, close
Terminal completely, open it again, and try once more.

---

## Part 3 — Install Whisky

Whisky is the app that runs Windows programs on your Mac.

```bash
brew install --cask frankea/whisky/whisky
```

> **Important — don't shorten this command.** Typing `brew install --cask whisky`
> instead will install a **different, abandoned version** that was last updated in
> April 2025 and won't work with this guide. The long form with `frankea/whisky/`
> in it is the maintained one. This trips people up constantly.

When it's done, open Whisky:

1. **Cmd + Space**, type **Whisky**, press **Enter**
2. macOS may say the app is from an unidentified developer — if so, go to
   **System Settings → Privacy & Security**, scroll down, and click **Open Anyway**
3. Whisky will offer to download some support files on first launch. **Say yes**
   and let it finish. This takes a few minutes.
4. If macOS asks to install **Rosetta**, say yes. It's Apple's software for
   running Intel programs, and Whisky needs it.

---

## Part 4 — Create a bottle and install Steam

A **bottle** is a self-contained pretend Windows computer. Your games live inside
it. It keeps Windows software from touching the rest of your Mac.

### Create it

1. In Whisky, click the **+** button
2. Give it a name — `Games` is fine
3. For Windows version, leave it on **Windows 10**
4. Click **Create**. Takes a minute or two.

### Install Steam

1. Download the Windows Steam installer:
   [steamsetup.exe](https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe)
   — it'll land in your Downloads folder
2. In Whisky, select your bottle and click **Run...**
3. Choose the `SteamSetup.exe` you just downloaded
4. Click through the installer normally — Next, Next, Install
5. Steam will start and update itself. **This takes a while the first time.**
6. Log in to Steam

> **If Steam's window is completely black**, that's a known graphics problem and
> it's fixable — see [Troubleshooting](#steams-window-is-black).

### Install your game

Inside Steam, go to your Library, find the game, click **Install**. Wait for the
download.

---

## Part 5 — Install the mouse fix

This is the part that makes clicking work.

### Get the files

```bash
git clone https://github.com/zeno-blade-creator/whisky-unity-mouse-fix.git ~/whisky-mouse-fix
```

If you see `git: command not found`, macOS will pop up a window offering to
install developer tools. Click **Install**, wait for it, then run the command
again.

### Run the installer

```bash
cd ~/whisky-mouse-fix/wine-patch && ./install.sh
```

That's it — one command. It will:

1. Check what you have and **offer to install anything missing**
2. Download the source code it needs (~142 MB)
3. **Build it — this takes about 15 minutes.** Your Mac is compiling roughly
   12,000 files. Leave it running and go do something else.
4. Check the result is sound *before* touching anything
5. Back up your original files, then install

**It stops rather than guessing.** If any check fails, it tells you which one and
changes nothing — you can't end up half-installed.

> **Why is it building instead of just downloading a finished file?** Because you
> shouldn't have to trust a stranger's compiled program, especially one that sits
> this deep in your system. Building it yourself means the code that runs is the
> code you can read. It also means the licence is satisfied properly.

---

## Part 6 — Play

You can launch your game normally from Whisky. But the scripts in this repo
handle two problems automatically, so they're worth using.

### Set up the launcher

Open the folder in Finder:

```bash
open ~/whisky-mouse-fix
```

Double-click **`Play a game.command`**.

The first time, it asks for your game's **Steam App ID**. To find it:

1. Go to the game's page on [store.steampowered.com](https://store.steampowered.com)
2. Look at the web address. The number after `/app/` is the App ID:

```
https://store.steampowered.com/app/3527290/PEAK/
                                   ^^^^^^^ this is the App ID
```

Type that number and press Enter. It remembers it — you won't be asked again.

> **macOS may refuse to open the file**, saying it's from an unidentified
> developer. Right-click it → **Open** → **Open**. You only need to do that once
> per file.

### What the launcher does before starting the game

- **Repairs the graphics setup**, which Whisky sometimes breaks when it launches
  a game
- **Clears a bad saved screen size** that can make the game permanently refuse to
  start on a Retina display

Both are explained in [FINDINGS.md](FINDINGS.md).

---

## Troubleshooting

### Clicking still doesn't work

Check the fix actually installed:

```bash
cd ~/whisky-mouse-fix/wine-patch && ./install-pointer-fix.sh status
```

It should say `pointer API : IMPLEMENTED`. If it says `STUBBED`, the install
didn't complete — re-run `./install.sh` and read what it reports.

### The game crashes the moment it starts

Almost certainly the graphics problem, not the mouse fix. The error usually
mentions failing to create a graphics device, or the number `0x80004005`.

```bash
cd ~/whisky-mouse-fix && ./"FIX graphics stack.command"
```

This happens because Whisky copies graphics files into your bottle when it
launches a game, and its two graphics packages contain different numbers of
files — so switching leaves a mismatched set. It can recur any time you launch
from Whisky itself. `Play a game.command` repairs it automatically.

### Steam's window is black

Same underlying cause. Run `FIX graphics stack.command` as above, then start
Steam with:

```bash
cd ~/whisky-mouse-fix && ./"Launch Steam (Windows).command"
```

### "Couldn't switch to requested monitor resolution"

Your Mac's screen reports a size that isn't a real display mode, the game saved
it, and now it can't start. `Play a game.command` clears this automatically every
time — just use it to launch.

### Everything is stuck / the Mac is slow

```bash
cd ~/whisky-mouse-fix && ./"STOP everything.command"
```

This kills every Windows process, including a debugger that Wine launches
automatically on crashes and which can multiply into hundreds of processes.

### I want to undo the whole thing

```bash
cd ~/whisky-mouse-fix/wine-patch && ./install-pointer-fix.sh uninstall
```

Puts Whisky's original files back exactly as they were. Your bottle, games and
saves are never touched by any of this.

### More than one bottle

The scripts find your bottle automatically if there's only one, or if only one
has Steam in it. If you have several and it can't decide, it lists them and asks
you to save the right ID:

```bash
echo 'PASTE-THE-ID-HERE' > ~/whisky-mouse-fix/bottle.conf
```

---

## What got changed on my Mac?

Only one file inside Whisky: `win32u.so`, the part that handles windows and
mouse input. It's backed up first, and `uninstall` restores it.

Your bottles, games, saves and settings are never modified by the fix itself.
The launcher scripts do adjust two things in your bottle — the graphics files and
the saved screen size — and both are explained above.

---

## Which games does this help?

Any **Unity 6** game — those started appearing in late 2025. Older games were
never affected and don't need this.

If your game's cursor moves but clicks do nothing, this is your problem.
