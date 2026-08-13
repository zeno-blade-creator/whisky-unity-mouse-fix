# Cleanup inventory — everything created on 2026-08-11

Nothing here is deleted automatically. This is the checklist for tidying up
once a working setup exists (or once the attempt is abandoned).

Disk free at start of the Whisky step: **67 GB**.

## Safe to delete once Whisky works (or if we give up)

| Item | Size | What it is |
|---|---|---|
| `~/.wine-steam-11` | 1.7 GB | STEP 1 prefix (Wine 11.10 + DXMT). Black. Dead end. |
| `~/.wine-steam-gptk` | 2.0 GB | STEP 2 prefix (Apple D3DMetal). Black. Dead end. |
| `~/wine-11.10` | 727 MB | Gcenx Wine 11.10, downloaded by the reference project. |
| `~/DXMT` | 52 MB | Never loaded once — no Wine build here supports `WINEDLLPATH_PREPEND`. |
| `/Applications/Game Porting Toolkit.app` | 963 MB | Wine 7.7, far too old for modern Steam. **Keep for now** — Whisky's import flow may want its D3DMetal payload. Delete only after Whisky is settled. |
| `/Applications/Wine Staging 11.15.app` | ~700 MB | Installed only to compare against 11.14. Behaved identically. |
| `~/Desktop/Wine Windows Games/reference-project-macos-wine-steam/` | small | Reference project source. |
| `/tmp/SteamSetup.exe`, `/tmp/wine-steam-*.log` | small | Scratch files from tonight's tests. |

**Roughly 5–6 GB recoverable immediately, ~13 GB if the old Wine attempt is
abandoned entirely.**

## Depends on the outcome

| Item | Size | Decision |
|---|---|---|
| `~/Games/wine-gaming` | 8.5 GB | The original prefix, contains PEAK (6.5 GB). Delete **only** once PEAK works elsewhere — or keep if Whisky can reuse it. |
| `/Applications/Wine Staging.app` | ~700 MB | Wine 11.14. Not needed if Whisky manages its own engine. |

## Never delete

| Item | Size | Why |
|---|---|---|
| `~/Library/Application Support/Steam` | **32 GB** | Native macOS Steam — logged in, and your actual Mac game library. Biggest single item on the disk; it is *not* from tonight. |
| `~/Applications/CrossOver.app` + its bottle | — | The only setup that currently runs PEAK. Untouched all night, and stays that way. |

## Test scripts in this folder

`TEST 3`–`TEST 12`, `STEP 1`, `STEP 2`, `Restore Steam session.command` — all
diagnostic, all superseded once a working route exists. Keep `STOP
everything.command` (it has the CrossOver-safe explorer cleanup) and
`config.sh`.

## Changes made to the existing prefix (`~/Games/wine-gaming`)

Reversible; backups were taken with timestamps.

- `config/`, `userdata/`, `registry.vdf` — replaced with copies from native Mac
  Steam. Originals saved as `*.bak-20260811-*`.
- `ssfn4862480228889042879` — copied in from native Steam.
- `steam.cfg` — written, then moved aside to
  `steam.cfg.disabled-20260811-225402` (it was blocking Steam from swapping its
  own components, which made TEST 10 void the first time).
- `config.sh` — `WINEDLLPATH_PREPEND` corrected to `WINEDLLPATH` plus
  `WINEDLLOVERRIDES`. Worth keeping: the old line was a no-op.
- 18 stale `explorer.exe` processes killed; `STOP everything.command` now
  prevents them accumulating.

Nothing was ever deleted from the prefix — only added or backed up.
