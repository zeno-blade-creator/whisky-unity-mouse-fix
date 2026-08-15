# Credits

## The mouse fix is not my work

The implementation of the Windows pointer API — `NtUserEnableMouseInPointer`,
`NtUserIsMouseInPointerEnabled`, and the `WM_MOUSE*` → `WM_POINTER*` translation
in `process_mouse_message` — was written by **CodeWeavers** and ships in
CrossOver 26.3.

It is licensed under the **GNU Lesser General Public License, version 2.1 or
later**, and CodeWeavers publishes the source because that licence requires them
to. Source:
[codeweavers.com/crossover/source](https://www.codeweavers.com/crossover/source)
(`crossover-sources-26.3.0.tar.gz`).

I did not write it, and this project does not claim to.

## What is original here

- Diagnosing why Whisky is affected when CrossOver 26.3 is not
- Establishing by binary comparison that **Whisky's engine is CrossOver's Wine**,
  one release behind the fix — and therefore that patching vanilla Wine cannot
  work
- The build and verification pipeline, including the import-parity gate and the
  runtime checks that caught defects static analysis missed
- Findings 2–6 in [FINDINGS.md](FINDINGS.md): Whisky's non-transactional backend
  switch, the Retina resolution trap, the missing bottle-level DLL overrides, the
  `winedbg` process explosion, and the non-existent `WINEDLLPATH_PREPEND`

## Projects this depends on

| Project | What it does | Licence |
|---|---|---|
| [**Wine**](https://www.winehq.org) | The compatibility layer everything here builds on. Decades of work by hundreds of contributors. | LGPL-2.1+ |
| [**CodeWeavers / CrossOver**](https://www.codeweavers.com) | The pointer implementation, plus the macOS-specific Wine work Whisky's engine is built from. | LGPL-2.1+ (Wine portions) |
| [**Whisky**](https://github.com/frankea/Whisky) | The macOS Wine wrapper. Originally by Isaac Marovitz; the maintained fork is by [@frankea](https://github.com/frankea) after the original was archived in May 2025. | GPL-3.0 |
| [**DXMT**](https://github.com/3Shain/dxmt) | Translates Direct3D 11 to Apple Metal. Without it there is no working D3D11 on macOS and Steam's interface never renders. | zlib |
| [**DXVK**](https://github.com/doitsujin/dxvk) | Direct3D to Vulkan translation. Bundled by Whisky; relevant here mainly as half of the mismatched-DLL bug. | zlib |

## Prior art on this specific bug

- [kiku-jw/peak-crossover-mouse-fix](https://github.com/kiku-jw/peak-crossover-mouse-fix)
  — binary patch for CrossOver 25.1.1 and 26.0
- [dabielf/crossover-unity-mouse-fix](https://github.com/dabielf/crossover-unity-mouse-fix)
  — binary patch for CrossOver, with drag and hold-to-fire fixes
- [Kron4ek/Wine-Builds](https://github.com/Kron4ek/Wine-Builds/blob/master/EnableMouseInPointer.patch)
  — a community source patch, applied in some Linux Wine builds

All three target CrossOver or Linux Wine. This project exists because none of
them worked for Whisky.

## Licence

This project's own scripts and documentation are released under **LGPL-2.1+**,
matching the Wine code they build and install. See [LICENSE](LICENSE).
