WINDOWS GAMES ON MAC - QUICK REFERENCE
=======================================

This runs Windows-only Steam games on your Mac using free, open-source software.
No CrossOver licence, no subscription, no Apple Developer account.


HOW TO LAUNCH THINGS
--------------------
  Windows Steam.app          In your Applications folder. Double-click to open
                             Windows Steam. Drag it to the Dock if you like.

  Launch Steam (Windows)     Same thing, from this folder.

  Play PEAK.command          Launches PEAK directly (starts Steam if needed).

  Add a game.command         Installs any Windows Steam game and creates a
                             double-click launcher for it. All it asks for is
                             the Steam App ID, and it explains how to find one.

  FPS overlay - toggle       Turns the on-screen FPS counter on/off for ALL
                             games. Restarts Steam so the change takes effect.

  Check performance...       Run before a long session. Tells you whether to
                             reboot or just close some apps.


FIRST TIME
----------
Open Windows Steam and log in with your normal Steam account. This Steam is
completely separate from the Mac Steam app, so it needs its own login once.
It remembers you afterwards.

If a game closes immediately after launching, the usual cause is that Steam
isn't logged in.


WHAT'S ACTUALLY INSTALLED
-------------------------
  Wine Staging 11.14    /Applications/Wine Staging.app
                        Translates Windows programs so macOS can run them.
                        Free and open source (LGPL).

  DXMT v0.80            Installed inside Wine.
                        Translates DirectX 11 graphics into Apple Metal.
                        Free and open source.

  The prefix            ~/Games/wine-gaming
                        A self-contained fake Windows "C: drive". Every Windows
                        program you install lives in here. Delete that one
                        folder and everything Windows-related is gone.

Total: about 3 GB, plus whatever your games take.


IMPORTANT: WINE VERSION MATTERS
-------------------------------
Apple's Game Porting Toolkit ships Wine 7.7, which is from 2022. Modern Steam
will NOT work on it - the Steam interface is a current Chromium build and
crashes with "steamwebhelper is not responding". Wine 11.14 fixes this.

If you ever reinstall, use a current Wine. This cost an evening to work out.


IF A GAME STUTTERS
------------------
Work through these in order. Most stutter on a Mac is memory, not graphics.

  1. Run "Check performance before playing.command".
     High swap = reboot. Swap does not shrink on its own.

  2. Close your web browser (usually 1-2 GB), Discord, Spotify.
     Quitting frees memory immediately - no reboot needed for that part.

  3. Reboot before long sessions. On this machine that once dropped wired
     memory from 4.16 GB to 1.89 GB and cleared 8.4 GB of swap.

  4. ONLY THEN change graphics settings. In-game the biggest lever is
     Render Scale, then shadow distance, then resolution.

  5. A steady 30 FPS cap often FEELS smoother than a wandering 45.

Telling the two problems apart:
  Stutter WITH crackly audio        = memory
  Evenly low FPS with clean audio   = graphics settings


WHAT WON'T WORK
---------------
  Anti-cheat games. Anything with kernel-level anti-cheat (most competitive
  multiplayer - Valorant, Fortnite, Destiny 2, and Elden Ring's ONLINE mode)
  will not run, or will run offline only. This is not fixable from this side;
  the anti-cheat deliberately refuses to run under translation.

  Very new AAA games may need DirectX 12, which DXMT doesn't cover yet.

  Games needing exotic CPU instructions (AVX-512) generally won't work.

Simple and indie games, especially Unity ones, tend to work well.


HARDWARE NOTES (this Mac: M2, 8 GPU cores, 16 GB)
-------------------------------------------------
Around 1080p with moderate settings is the realistic target. Rendering at a
3440x1440 ultrawide's native resolution is not achievable - that's 5 million
pixels per frame. You CAN still play fullscreen on a big monitor by rendering
lower and letting the monitor upscale.

M3/M4 chips are faster but need no setup changes - it's the same architecture
and the same software.


MICROPHONE
----------
Games with voice chat need macOS microphone permission. Go to:
  System Settings > Privacy & Security > Microphone
and enable "Wine Staging" (or "Windows Steam").

If it isn't listed, launch a game that uses the mic once, then look again -
apps only appear after they first ask. If you toggle it while the game is
running, quit and relaunch: macOS only reads permissions at startup.
