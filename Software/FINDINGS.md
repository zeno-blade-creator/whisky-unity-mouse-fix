# Findings

Six problems found while getting a Unity 6 game (PEAK) running on free,
open-source tooling on macOS — Whisky, Wine and DXMT. Each is documented with
the evidence that settled it, because several earlier conclusions on this
project were confidently wrong and cheap to disprove.

Where something remains unexplained, it says so.

**Environment:** macOS 15 on Apple Silicon (M2), Whisky 3.6.0, Wine 11.0
(CrossOver-derived), DXMT 0.80, August 2026.

---

## 1. Unity 6 games get no mouse clicks, and why Whisky specifically

### Symptom

Cursor moves. Hover highlights work. Keyboard works. **No click ever registers.**

### Cause

Unity 6 calls `EnableMouseInPointer()` and then listens only for `WM_POINTER*`
messages, ignoring the classic `WM_MOUSE*` ones. Wine stubs the relevant
functions — they exist, log a FIXME, and return failure:

```
fixme:win:NtUserIsMouseInPointerEnabled stub!
fixme:win:NtUserEnableMouseInPointer enable 1 stub!
```

So Wine keeps sending old-style messages that the game isn't listening for. The
clicks happen; nothing receives them. Movement uses a different code path, which
is why the cursor still moves — and why the failure looks so strange.

### Why Whisky is affected when CrossOver 26.3 isn't

Disassembling both engines settles it. Whisky's:

```asm
leaq  "enable %u stub!"(%rip), %rcx    ; the literal word "stub"
movl  $0x78, %edi                      ; ERROR_CALL_NOT_IMPLEMENTED
xorl  %eax, %eax                       ; return FALSE
```

CrossOver 26.3's:

```asm
leaq  "enable %u"(%rip), %rcx          ; no "stub"
lock  cmpxchgl %ecx, enable_mouse_in_pointer(%rip)   ; actually stores state
movl  $0x1, %eax                       ; return TRUE
```

CodeWeavers implemented it. Whisky did not — **because Whisky's engine is
CrossOver's engine, from an older release**. Comparing the two shipped binaries:

```
Whisky win32u.so  vs  CrossOver 26.3 win32u.so
  imports: 164 vs 164   ->  ZERO differences
  exports: 504 vs 505   ->  one symbol apart (NtUserSetWindowFNID)
```

That is not "similar." That is the same lineage, one release apart.

### Consequence for anyone attempting this

**Patching vanilla Wine cannot produce a working replacement.** Whisky's build
carries CodeWeavers' shared-memory surface code (`create_shm_surface`,
`process_surface_message`, and the `NtCreateSection`/`NtOpenProcess` machinery
behind it) which vanilla Wine has never had. A vanilla build reaches 156 of 164
imports and is silently missing exactly that.

The working approach is to build **CrossOver 26.3's own source**, which already
contains the implementation, and take its `win32u.so`. No patching required.

### Status elsewhere

- Reported on the **archived** Whisky repo as
  [#1169](https://github.com/Whisky-App/Whisky/issues/1169) (Civilization VI),
  open since 2024-10-18, alongside #1145 and #1175. That repo was archived in
  May 2025 with 443 open issues.
- **Not reported** on the maintained fork,
  [frankea/Whisky](https://github.com/frankea/Whisky).
- Tracked upstream as WineHQ bug 53847. Status not independently confirmed —
  Bugzilla is behind a bot check.
- Two existing community fixes ([kiku-jw](https://github.com/kiku-jw/peak-crossover-mouse-fix),
  [dabielf](https://github.com/dabielf/crossover-unity-mouse-fix)) patch
  **CrossOver only**, by injecting assembly into a code cave. Nothing existed for
  Whisky.

---

## 2. Whisky's backend switch is not transactional

**This is a bug in Whisky, and it is reproducible on demand.**

Whisky switches Direct3D backends by **copying DLLs** into the bottle. The two
packages contain different file lists:

| package | files |
|---|---|
| DXMT | `d3d11`, `d3d10core`, `dxgi`, `winemetal` (+2 NVIDIA shims) |
| DXVK | `d3d11`, `d3d10core` — **only two** |

Nothing removes the previous backend's files. So switching DXMT → DXVK
overwrites two files and **leaves the other two in place**, producing DXVK's
D3D11 running on DXMT's DXGI — two unrelated implementations:

```
d3d11.dll      DXVK   (mtime matches Whisky's DXVK folder)
d3d10core.dll  DXVK
dxgi.dll       DXMT
winemetal.dll  DXMT
```

Confirmed by checksum against Whisky's own library folders, in both `system32`
and `syswow64`.

### What it looks like

```
d3d12: failed to create D3D12 device (0x80004005).
GfxDevice: creating device client; kGfxThreadingModeClientWorkerJobs
d3d11: failed to create device and context (80004005).
Failed to initialize graphics.
```

**A trap in that output:** `GfxDevice: creating device client` is Unity
*narrating each retry*, not the failure. The real line is `d3d11: failed to
create device and context`. Chasing the narration led an earlier investigation
nowhere for hours.

### Reproduction

Launch a game from Whisky's own interface rather than from a script. Whisky
re-applies its configured backend on launch, and the mismatch reappears every
time.

### Fix

Make the DLL set consistent, and set the bottle's backend to `dxmt` so Whisky
re-applies the right thing. `FIX graphics stack.command` does both and verifies
the result.

---

## 3. The Retina resolution trap

Affects **any Retina Mac**, not just this setup.

macOS reports a scaled *logical* screen size (e.g. 1470×956) while the display is
physically 2560×1664. Unity saves the logical number:

```
Screenmanager Resolution Width_h182942802   = 0x5be = 1470
Screenmanager Resolution Height_h2627697771 = 0x3bc =  956
```

Wine matches resolution requests against **real** CoreGraphics display modes
(`macdrv_ChangeDisplaySettings` → `find_best_display_mode` →
`DISP_CHANGE_BADMODE`). 1470×956 is not a real mode, so the switch can never
succeed:

```
Couldn't switch to requested monitor resolution
DX11 could not switch resolution (1470x891 fs=1)
```

And the bad value **persists**, so the game becomes permanently unlaunchable.

### Fix

**Delete** the saved resolution rather than writing a new one. Unity's borderless
fullscreen is defined as "use the display's native resolution", so with nothing
saved it asks for a size that always exists. No hardcoded numbers, works on any
monitor, self-healing.

A 1:1 external display (e.g. 3440×1440 ultrawide) is unaffected — logical and
physical sizes match there.

---

## 4. DLL overrides are never written to the bottle

Wine prefers its **own** `d3d11.dll` over anything in `system32` unless
explicitly told otherwise. Whisky sets `WINEDLLOVERRIDES` **only when Whisky
itself launches a program** — it never writes the setting into the bottle
registry, which is empty:

```
[Software\\Wine\\DllOverrides]     <- no values
```

So anything launched outside Whisky silently falls back to builtin
`d3d11 → wined3d → OpenGL`, which cannot create a device on macOS. The crash log
proves which was loaded:

```
d3d11.dll   ... size: 454656      <- Wine's builtin. DXMT's is 5,350,886
wined3d.dll ... size: 3178496     <- the OpenGL fallback
```

**Fix:** write `"d3d11"`, `"d3d10core"`, `"dxgi"` = `native` into the bottle
registry so every launch path works.

**Critical exception:** `winemetal` must stay **builtin**. Its `.dll` is a thin
shim that pairs with `winemetal.so` (31 MB) compiled *into* Wine, and Wine only
pairs the two for builtin DLLs. Forcing it native breaks DXGI and takes Steam's
entire UI down with it:

```
err:module:import_dll Library winemetal.dll (which is needed by
L"C:\windows\system32\dxgi.dll") not found
```

---

## 5. `winedbg` can consume a machine

Wine ships with `AeDebug\Auto=1`, so **every crash auto-launches a debugger**
that then hangs. In a crash loop this compounds:

```
1,325 winedbg processes (each dragging a conhost.exe)
15 GB swap used, 0.1 GB RAM free
killing them freed ~13 GB instantly
```

Nothing warns you, and the machine's unresponsiveness looks like the game's
fault.

**Fix:** delete the `AeDebug\Debugger` value. Note that setting `Auto=0` is *not*
the fix — it means "ask the user", producing an endless dialog loop.

---

## 6. `WINEDLLPATH_PREPEND` does not exist

A widely-copied instruction for enabling DXMT tells users to set
`WINEDLLPATH_PREPEND`. **That variable exists in no Wine build** — not Staging
11.14/11.15, not Gcenx 11.10, not Whisky's 11.0. Searching the source trees for
the string finds nothing.

It is a silent no-op. Everyone following that guidance gets no DXMT, and every
"I tried DXMT and it didn't help" result derived from it is meaningless.

The real variable is `WINEDLLPATH`. But see finding 4 — for Whisky, the DLLs are
already in place and what's actually needed is the override, not a path.

---

## Method notes

Several conclusions on this project were confidently wrong. What separated the
wrong ones from the right ones:

### Compare imports, not exports

An earlier investigation compared *exported* symbols of two builds, got
`504 = 504`, and concluded they were equivalent. Exports are a library's public
API — declared in a spec file, unchanged by what you compile out. The comparison
could not possibly detect the difference.

Imports told the truth: **164 vs 118**, with CoreText, CoreFoundation and the
`dlopen` family missing — because `--without-freetype` silently removes the
entire macOS font backend, since CoreText enumeration lives inside
`dlls/win32u/freetype.c`.

### Some defects are invisible to every static check

After fixing the above, the rebuilt engine passed everything: imports matched,
exports matched, correct frameworks linked, correct library name recorded, all 32
required freetype symbols present in the target library.

**It still failed at runtime.** The cause was a missing search path:

```
whisky:  @loader_path/   @loader_path/../../
ours:    @loader_path/
```

`win32u.so` lives in `lib/wine/x86_64-unix/`, so `@loader_path/../../` is what
reaches `lib/`. Only running the engine and reading its output caught it.

### Baseline before claiming a regression

When the patched build printed a freetype error, the decisive test was
reinstalling the untouched original and confirming it printed **zero**. Two
minutes, and it converted a guess into a fact.

### Environment traps

Five build failures, each pointing away from its own cause:

| Presented as | Actually |
|---|---|
| "C compiler cannot create executables" | a **space** in `Application Support` splitting `-L` into two arguments |
| "your bison version is too old" | macOS's 2006-era bison shadowing Homebrew's keg-only 3.8 |
| build dies generating bitmap fonts | SIP strips `DYLD_*` when make invokes recipes via `/bin/sh` |
| nothing — the build succeeded | soname mis-parsed into a whole `otool -L` line, failing only at runtime |
| everything checked out | the missing rpath above |

---

## Unresolved

- The original crash onset (Aug 12, ~22:43) has never been explained. The
  patched engine had been installed ~20 hours earlier and working. Something
  changed at that moment; the evidence doesn't say what.
- A cursor offset inside PEAK's settings menu only — clicks land away from the
  pointer there and nowhere else. Likely related to Whisky
  [#1289](https://github.com/Whisky-App/Whisky/issues/1289), "Apps running in
  retina mode receive mouse position as if they were not." Untested.
- WineHQ bug 53847's current status is unconfirmed.

---

## Attribution

The pointer implementation is **CodeWeavers' work**, from CrossOver 26.3, used
under LGPL-2.1-or-later. What is documented here as original: the diagnosis of
why Whisky is affected, the measurement that Whisky's engine is CrossOver-derived
and one release behind, the verification method, and findings 2–6.
