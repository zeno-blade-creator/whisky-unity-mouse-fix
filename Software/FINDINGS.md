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

## 7. Whisky is per-account, and nothing tells you

Found the hard way when this was installed on a second Mac.

macOS keeps a **completely separate Whisky for every user account** — separate
bottles, separate games, and a separate Wine engine. Whisky's interface gives no
indication of this, and no error is ever produced.

On a managed school Mac with two logins, the entire install — clone, build,
engine replacement — ran as one user:

```
/Users/eopsstaff/whisky-mouse-fix                the project
/Users/eopsstaff/Library/.../com.franke.Whisky   an engine, patched successfully
```

while the bottle containing the game belonged to another:

```
/Users/eopsstudent/Library/Containers/com.franke.Whisky/Bottles/3D87F42E-...
```

Two Whisky installations, two Wine engines. The patched one was never the one
running the game. Every command succeeded. Every diagnostic was accurate. The
game still didn't click.

**The diagnostic was right and still unhelpful.** `doctor.sh` reported "no bottle
found" — entirely correct for the account it ran in, and read by everyone as a
bug in the tool. A tool that correctly reports "not found" while pointed at the
wrong user is indistinguishable from a broken one, except that it is right.

**Fix:** do everything in one account. `doctor.sh` now prints which account it is
running as, whether that account can use `sudo`, and — when it finds no bottle —
which *other* accounts on the Mac have Whisky data.

### The permission layers underneath this

macOS refuses writes for four independent reasons that all surface as the same
`Permission denied`:

| Layer | Blocked even if… | Inspect with |
|---|---|---|
| **Ownership** (`user:group`, `rwx`) | — | `ls -lO file` |
| **File flags** (`uchg`) | …you own the file | flags column of `ls -lO` |
| **TCC / privacy** | …you own it *and* it's writable | System Settings → Privacy & Security |
| **SIP** | …you are root | protects `/System`, `/usr` — not `~/Library` |

Only the first is fixed by `chown`. Being refused on a file you own is exactly
what pushes people toward `sudo`, which cannot fix a privacy-layer block and
actively creates ownership problems.

On the machine above, Whisky's engine was owned by `root`:

```
-rwxr-xr-x@ 1 root staff ... win32u.so
```

almost certainly because something had earlier been run with `sudo`. Note the
symmetry: **the account with `sudo` was the one with the permission problem**,
and the account without it had none, because Whisky created its own files
normally there. Reaching for `sudo` caused the damage; the hunt for `sudo` then
caused the account split.

Two traps worth naming:

- **`sudo cd X && ./script`** does not run the script as root. `sudo` applies to
  `cd`; `&&` then runs the script unprivileged. The output is byte-identical to
  not using `sudo` at all, so it looks like `sudo` was ignored.
- **Homebrew is per-installer too.** `/opt/homebrew` belongs to whoever installed
  it, so `brew install` can fail for a second account on the same Mac.

---

## Method notes

Several conclusions on this project were confidently wrong. What separated the
wrong ones from the right ones:

### Your own machine cannot test your assumptions

This worked flawlessly for days on the machine that built it. The **first
outside user found six genuine defects in an afternoon**, every one in the code:

1. A verification gate that rejected a perfectly correct build, because the same
   check existed in two scripts and only one had been updated when four
   differences were found benign.
2. That install discovering it could not write **after** a 15-minute build,
   rather than in the one second it takes to test.
3. `Done! Created: Play PEAK.command` printed when the write had failed.
4. `win32u.dll unchanged - left alone` printed for a file at a path that never
   existed, so the reassuring branch always ran.
5. A hardcoded bottle path, when bottles can live under four different roots or
   on an external drive.
6. A `[found]` / `[absent]` report that never opened the folder it found — hiding
   that the one existing location contained no bottles at all.

The author's machine had every assumption already satisfied: data in the default
place, files owned by the right user, a writable working directory, and the one
code path he happened to exercise. None of that was true anywhere else.

### Never announce success you have not verified

Three of those six were the same mistake: a script printing a cheerful
confirmation of something it had not checked. Two of them cost more time than any
genuine bug, because a success message stops you looking.

After writing a file, check it exists. After a copy, compare. If a message says
an action succeeded, something must have confirmed it.

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

## The Rosetta deadline — a separate problem from the pointer bug

These two get conflated constantly, so: **they share no mechanism.**

The **pointer bug** is a Windows API problem. Unity 6 calls `EnableMouseInPointer()`
and then listens only for `WM_POINTER` messages; Whisky's Wine never implemented
them and keeps sending `WM_MOUSE`, so clicks land nowhere. Keyboard input was
never affected (different path), which is why WASD worked while clicking didn't,
and why "use a controller" was a workaround — XInput is a third path, also
unaffected. **This is fixed**, by building CrossOver 26.3's implementation into
`win32u.so`.

The **Rosetta problem** is one layer below Wine, about CPU instruction sets, and
is *not* fixed because it cannot be fixed here.

### Why the engine needs Rosetta

Wine translates Windows API calls into macOS ones — but the game is a Windows
**x86** binary, real Intel machine code, and something must execute it on an ARM
chip. Two architectures exist:

1. **Compile all of Wine as x86_64 and let Rosetta translate the whole process.**
   Wine and game together as one Intel program. This is what Whisky and Game
   Porting Toolkit do. Measured here: `bin/wine`, `bin/wine64` and `bin/wineserver`
   are all `Mach-O 64-bit executable x86_64`, and `lib/wine/` contains only
   `i386-windows`, `x86_64-unix` and `x86_64-windows` — **no arm64 directory at
   all.**
2. **Compile Wine itself as ARM64-native with an x86 emulator embedded**, so only
   the *game's* code is emulated. This survives Rosetta's removal.

### The dates

| When | What |
|---|---|
| macOS 26.4 / 26.5 | "Support Ending for Intel-based Apps" alerts begin |
| **macOS 27** (fall 2026) | Apple-silicon only; removes Rosetta 2 on upgrade, reinstallable |
| **macOS 28** (fall 2027) | Rosetta largely gone. A narrow carve-out remains for "older, unmaintained gaming titles that rely on Intel-based frameworks" — whether Wine qualifies is unclear, and Wine is not itself a game |

### Whisky is a dead end for this

Whisky was **discontinued in April 2025**; its developer endorsed CrossOver on the
grounds that CodeWeavers' revenue is what keeps Wine-on-Mac alive at all. Whisky's
engine is frozen as Intel-only. Making it ARM64-native would mean rebuilding the
engine in Wine's "new WoW64" mode *and* bundling an x86-on-ARM emulator *and*
solving macOS's W^X restriction on JIT memory. That is an organisation's project,
not a patch — and nobody is doing it for a discontinued app.

### CrossOver is the migration target, and it already shipped

On **2026-07-31** CodeWeavers released a
[CrossOver Preview built natively for ARM64 on macOS](https://www.codeweavers.com/blog/mjohnson/2026/7/31/crossover-preview-the-right-to-bear-arm64-on-mac),
using **FEX** — their own open-source x86 emulator — instead of Rosetta. That is
architecture #2, shipping. CrossOver 27 (penciled for early 2027) drops Intel Macs
entirely, landing before Rosetta's removal.

Preview limitations at time of writing: no D3DMetal, Direct3D 12 still coming,
many launchers non-functional, and **existing bottles cannot be converted** — they
must be rebuilt.

### The wrinkle: migrating re-introduces the pointer bug

CodeWeavers has never shipped the pointer implementation in a CrossOver *release*,
even though it exists in their source — which is exactly where this repo got it.
So a CrossOver migration means re-applying a pointer fix. Two published options
already exist:

- [dabielf/crossover-unity-mouse-fix](https://github.com/dabielf/crossover-unity-mouse-fix)
  — pre-patched binaries for CrossOver 26.0, no compilation
- [kiku-jw/peak-crossover-mouse-fix](https://github.com/kiku-jw/peak-crossover-mouse-fix)
  — CrossOver 25.1.1 and 26.0, PEAK-specific

…or rebuild this repo's patch against CrossOver's engine, which is what
`engine-detect.sh` exists to make possible.

### What was changed here to prepare

The scripts used to hardcode both the engine root (`com.franke.Whisky`) and its
architecture (`x86_64-unix`). Neither survives an engine change, and a hardcoded
path doesn't fail with "the engine moved" — it fails with "file not found" deep in
a build, which reads like a broken patch.

`engine-detect.sh` now discovers both: it searches every known engine root
(both Whisky bundle ids, sandboxed and not, plus CrossOver) and **globs**
`lib/wine/*-unix/` rather than assuming the arch. `build-engine.sh` derives its
compiler triple, `--enable-archs` and mingw prefix from what it finds.
`doctor.sh` reports host arch, engine arch and Rosetta status up front, and
`install-pointer-fix.sh` refuses to patch an engine that cannot execute.

**This does not make the patch Rosetta-independent** — `win32u.so` is compiled
code and must match its engine. It makes the patch *portable to a different
engine*, and makes the eventual failure legible instead of cryptic.

### Verified after the refactor (2026-08-17)

The refactor touches shell scripts only, and the installed engine binary is
byte-identical before and after (`e75a4dc2b6755a7ce9faf7bf204aa9551fd426f9`), so
there was nothing that *could* regress — but it was checked rather than assumed:

- `doctor.sh` still reports the fix as **INSTALLED** against the same engine, and
  now leads with host arch / engine arch / Rosetta status.
- `install-pointer-fix.sh status` still reads the engine as patched.
- **PEAK was launched and played — mouse clicks work.** This is the check that
  matters, because it exercises the actual `WM_POINTER` path rather than a hash.


---

## Attribution

The pointer implementation is **CodeWeavers' work**, from CrossOver 26.3, used
under LGPL-2.1-or-later. What is documented here as original: the diagnosis of
why Whisky is affected, the measurement that Whisky's engine is CrossOver-derived
and one release behind, the verification method, and findings 2–6.
