# HANDOFF: PEAK on free Wine (macOS) — paste this whole file into a new chat

---

## READ THIS FIRST — how to work on this problem

This project burned a very long session mostly because of **how** it was
debugged, not because the problem was hard. Please follow these:

1. **Search for what already solves this before debugging it yourself.**
   The single biggest time loss was searching the *symptom*
   ("Steam black screen Wine") instead of the *question*
   ("what do people use to run Windows Steam on macOS?"). The first returns
   debugging threads; the second returns Whisky immediately — which solved in
   15 minutes what hours of manual work had not.

2. **Never treat a setting as applied until you have proved it was read.**
   Five separate conclusions in this project were wrong because a setting was
   assumed to have taken effect:
   - `-cef-disable-gpu` — applied, but irrelevant
   - `-cef-use-angle=...` — **silently discarded by Steam**
   - `ANGLE_DEFAULT_PLATFORM` — ignored by ANGLE
   - `-cef-force-32bit`, `-noreactlogin` — removed from modern Steam
   - `WINEDLLPATH_PREPEND` — **a variable that exists in no Wine build at all**

   Every test script should self-verify and report **VOID**, not "failed", when
   the setting did not reach the target. A black screen with an unapplied
   setting is not evidence.

3. **Check your own recent changes first when something breaks.**
   Two outages were self-inflicted and took far too long to spot:
   `AeDebug\Auto=0` (which means *"ask the user"*, causing an endless dialog
   loop) and a `pkill -f "steam.exe"` that never matched `Steam.exe` because
   `pkill` is case-sensitive.

4. **Stop after ~3 wrong theories and re-gather evidence.** Tonight ended with
   five dead theories in a row on one bug. That is a signal to stop guessing
   and go measure something.

5. **Verify version/date claims from disk, not memory.** "Whisky is
   discontinued" was true of the original and false of the active fork; "PEAK
   updated" was disproved by file timestamps.

*(A reusable "research-first problem solving" skill was discussed but **has not
been created**. Worth building.)*

---

## CURRENT STATE — what works right now

**PEAK runs on free Wine via Whisky. No CrossOver needed.**

- Steam's UI renders, login works, PEAK launches and plays
- Moves cleanly to the external ultrawide
- **Missing: mouse clicks.** Stock Wine stubs the API PEAK needs (see below)

Machine is clean: 0 Wine processes, 0 swap, 79 GB free.

### The setup

| Thing | Where |
|---|---|
| Whisky 3.6.0 (active fork by @frankea) | `/Applications/Whisky.app` |
| Wine engine (wine-11.0 + DXMT 0.80 + DXVK) | `~/Library/Application Support/com.franke.Whisky/Libraries/` |
| Bottle "Steam" (Steam + PEAK + login) | `~/Library/Containers/com.franke.Whisky/Bottles/2E15BCAB-7F6A-4116-9BBF-2A78C47970B1` |
| Scripts | `~/Desktop/Wine Windows Games/` |
| CrossOver 26.3 (**still installed, still works**) | `~/Applications/CrossOver.app` — do not delete until mouse is fixed |
| Native macOS Steam (32 GB, real library) | `~/Library/Application Support/Steam` — **never delete** |

### How to launch

**`Play PEAK.command`** — do not launch any other way. It clears PEAK's saved
resolution before starting (see "resolution trap" below), which is what keeps
the game launchable.

---

## THE ONE REMAINING BUG: mouse clicks

### Cause (proven, not theorised)

Unity 6 games call `EnableMouseInPointer()` and then listen **only** for
`WM_POINTER*` messages, ignoring classic `WM_MOUSE*`. Wine **stubs** three
functions — they exist, log a FIXME, and return FALSE:

```c
BOOL WINAPI NtUserEnableMouseInPointer( BOOL enable )
{
    FIXME( "enable %u stub!\n", enable );
    RtlSetLastWin32Error( ERROR_CALL_NOT_IMPLEMENTED );
    return FALSE;
}
```
(`dlls/win32u/input.c`, wine-11.0 — also `NtUserEnableMouseInPointerForThread`
and `NtUserIsMouseInPointerEnabled`)

**Caught in the act** — PEAK really does call it:
```
fixme:win:NtUserIsMouseInPointerEnabled stub!
fixme:win:NtUserEnableMouseInPointer enable 1 stub!
```

So Wine sends old-style messages, PEAK isn't listening, clicks vanish. Movement
still works (different path), which is why the cursor moves but nothing clicks.

CrossOver 26.3 implements this properly — that is why PEAK works there.

### What was tried, and the decisive result

A source patch exists
([Kron4ek/Wine-Builds/EnableMouseInPointer.patch](https://github.com/Kron4ek/Wine-Builds/blob/master/EnableMouseInPointer.patch),
98 lines / 3 files). Wine 11.0 was built from source with it and installed into
Whisky.

**It worked.** Clicks worked, and an enhanced version (added right/middle button
support + per-thread state) gave working right-click for ~20 hours of play.

**Then it started crashing** at `GfxDevice: creating device client`, reproducibly.

**Five theories, all killed by evidence:**

| Theory | Killed by |
|---|---|
| Missing freetype in my build | Neither build links freetype (macOS uses CoreText) |
| PEAK updated | `PEAK.exe`/`UnityPlayer.dll` dated Aug 09; `LastUpdated` Aug 12 00:04 — *before* the patch |
| I removed Whisky's Wine patches | Symbol exports **identical**: 504 each, zero differences |
| Struct ABI mismatch | `ntuser_thread_info` used only by `user32` + `win32u`, both rebuilt |
| My enhancement caused it | **Reference patch, rebuilt clean, crashes identically** |

**That last test is the important one.** With my additions stripped out and only
the upstream reference patch applied, it *still* crashes. So:

> **The patch source is exonerated. The problem is in HOW I am compiling.**

Nothing else on disk changed between working and crashing: Steam Aug 03, Whisky
Aug 11, its Wine binary Jan 18, DXMT Jun 12. The "worked 20 hours then stopped"
gap remains **unexplained** — do not pretend otherwise.

### NEXT STEP: binary patching (do this instead of rebuilding)

Do **not** compile a replacement. Edit Whisky's **existing, known-good**
`win32u.so` in place, changing only the stub functions. Nothing of mine gets
compiled, so compiler/flag differences cannot matter.

This is exactly what the working CrossOver fixes do — *"a binary patch (42 bytes
of x86_64 assembly injected into a code cave)"*:
- https://github.com/kiku-jw/peak-crossover-mouse-fix (named after this game)
- https://github.com/dabielf/crossover-unity-mouse-fix

**Scope, honestly:** the three stubs are small and easy. The hard part is
`NtUserMessageCall`, where the message translation must go — that needs assembly
injected into a code cave inside a large function, and **without it the patch
does nothing**. Several hours, delicate, real chance of a subtly broken engine.
Back up first; `RESTORE Whisky original files.command` exists.

Files ready: `wine-patch/built/` (enhanced) and `wine-patch/built-reference/`
(upstream only), plus the full wine-11.0 source tree with the patch applied.

---

## THE RESOLUTION TRAP (solved — keep the fix)

PEAK became **unlaunchable**, erroring:
```
Couldn't switch to requested monitor resolution
DX11 could not switch resolution (1470x891 fs=1)
```

Registry proved it:
```
Screenmanager Resolution Width_h182942802   = 0x5be = 1470
Screenmanager Resolution Height_h2627697771 = 0x37b =  891
```

1470x891 is a **scaled Retina logical size**, not a real display mode. Wine
matches requests against real CoreGraphics modes
(`macdrv_ChangeDisplaySettings` -> `find_best_display_mode` -> `DISP_CHANGE_BADMODE`),
so the switch can never succeed, and the bad value persists across launches.

**Affects any Retina Mac.** The DELL ultrawide is unaffected — it is 1:1
(3440x1440 physical = logical). Built-in is 2560x1664 physical vs ~1470x956
logical.

**Fix (already implemented in `Play PEAK.command`):** *delete* the saved
resolution before each launch rather than writing one. Unity's borderless
fullscreen is defined as "use the display's native resolution", so with nothing
saved it asks for a size that always exists. No hardcoded numbers, works on any
monitor, self-healing.

---

## OTHER FINDINGS WORTH PUBLISHING (universal, not machine-specific)

1. **`winedbg` can eat a machine.** Wine ships `AeDebug\Auto=1`, so every crash
   auto-launches a debugger that then hangs. A crash loop produced **1,325
   winedbg processes** (each dragging a `conhost.exe`), taking swap to 15 GB
   with 0.1 GB RAM free. Killing them freed ~13 GB instantly. Nothing warns you.
   Fixed here by deleting the `AeDebug\Debugger` value.
   *(Note: `Auto=0` is NOT the fix — it means "ask the user" and causes an
   endless "Exception raised" dialog loop.)*

2. **`WINEDLLPATH_PREPEND` does not exist in any Wine build** — not Staging
   11.14/11.15, not Gcenx 11.10, not Whisky's 11.0. Yet a 140-star project uses
   it to "enable" DXMT, meaning everyone following it silently gets no DXMT.

3. **DXMT is half a Wine engine component.** `winemetal.so` (31 MB) is built
   *into* Whisky's Wine. Copying DXMT DLLs into a prefix alone can never work.
   This invalidated every earlier DXMT attempt.

4. **Steam silently discards unknown `-cef-*` flags** — tests using them are
   void, not negative.

5. **The original black-screen cause:** Steam's Chromium UI needs OpenGL ES 3.0;
   with no working D3D11, ANGLE falls back to Vulkan -> MoltenVK, which offers
   only ES 2.0, so nothing is ever painted. A working D3D11 translator (DXMT,
   properly loaded by Whisky) is what fixes it.

---

## STILL OPEN

- **Mouse clicks** — binary patch (above)
- **Cursor offset in PEAK's settings menu only** — clicks land away from the
  pointer there but nowhere else. Likely how the bad resolution got set.
  Candidates: `UseConfinementCursorClipping`, `CursorClippingLocksWindows`
  under `HKCU\Software\Wine\Mac Driver`. Untested.
- **Whisky's yellow "!" on the bottle** — undocumented, harmless so far
- **Launching PEAK from Whisky's own Steam Library view** fails (says running,
  isn't). Use `Play PEAK.command`.

---

## CONSTRAINTS (learned the hard way)

- **Claude cannot launch GUI apps** — anything it starts comes up windowless.
  Enzo must double-click; Claude verifies from logs/disk.
- **Claude must never type Enzo's Steam password.**
- **Launch PEAK only via `Play PEAK.command`.**
- **`STOP everything.command`** now kills `winedbg`, `conhost`, Wine services
  and Whisky's wineserver, is case-insensitive, and warns on >20 of anything.
  Run it between attempts.
- **Do not delete:** CrossOver (until mouse works), native macOS Steam, the
  bottle.
- Enzo uses **voice-to-text** — read for intent.
- Enzo explicitly wants **research before action**, not trial-and-error.

## GOAL AFTER THIS

Publish under `zeno-blade-creator` (gh CLI authenticated): the diagnosis
write-up plus, ideally, a Whisky mouse-fix installer. **No Whisky equivalent of
the CrossOver fix exists** — that is the gap worth filling.
