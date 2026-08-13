#!/usr/bin/env python3
"""
Apply Unity-6 mouse-pointer support to a vanilla wine-11.0 source tree.

WHAT THIS FIXES
---------------
Unity 6 games call EnableMouseInPointer() and then listen ONLY for WM_POINTER*
messages, ignoring the classic WM_MOUSE* ones. Wine 11.0 stubs the three
relevant functions - they exist, log "stub!", and return FALSE - so Wine keeps
sending old-style messages that the game is not listening for. The cursor moves
(a different code path) but nothing ever clicks.

WHERE THIS CODE COMES FROM
--------------------------
This is CodeWeavers' own implementation, taken verbatim from
crossover-sources-26.3.0.tar.gz (sources/wine). CrossOver 26 is built on
Wine 11.0 - the same base Whisky uses - so it applies directly.

It is LGPL, like the rest of Wine. It is preferred over the community patch
(Kron4ek's EnableMouseInPointer.patch) for two reasons:

  1. It stores the enabled state PROCESS-wide via InterlockedCompareExchange
     on a global initialised to -1, which is what Windows actually does. The
     community patch stores it per-thread, so a game that enables pointer mode
     on one thread and pumps messages on another silently gets nothing.
  2. It handles the full message set - down/up/update/wheel/hwheel - including
     the subtle rules that WM_POINTERDOWN is only sent on the FIRST button
     press and WM_POINTERUP only once ALL buttons are released.

Only the pointer hunks are taken. CrossOver's tree also contains unrelated
changes in these same files (CX HACK 23950 shm-surface plumbing, CXHACK 19488
WM_PAINT/WS_EX_COMPOSITED handling) which depend on CrossOver-only structs and
would not compile against vanilla Wine. Those are deliberately excluded.

USAGE
-----
    python3 apply-pointer-patch.py <path-to-wine-11.0-tree> <path-to-pristine>

Every edit is anchored on exact text that must appear EXACTLY ONCE. If any
anchor is missing or ambiguous the script changes nothing and exits non-zero
with VOID - never a partial patch, and never a silent no-op that would make a
later test result meaningless.
"""

import shutil
import sys
from pathlib import Path

FILES = [
    "dlls/win32u/input.c",
    "dlls/win32u/message.c",
    "dlls/win32u/win32u_private.h",
]

# ---------------------------------------------------------------- edits ----
# Each entry: (file, description, anchor_text, replacement_text)
# The anchor must occur exactly once in the pristine file.

EDITS = []

# --- win32u_private.h: declare the helper --------------------------------
EDITS.append((
    "dlls/win32u/win32u_private.h",
    "declare is_mouse_in_pointer_enabled",
    r"""extern BOOL grab_pointer;
extern BOOL grab_fullscreen;
""",
    r"""extern BOOL grab_pointer;
extern BOOL grab_fullscreen;
extern BOOL is_mouse_in_pointer_enabled( HWND hwnd );
""",
))

# --- input.c: the process-wide state -------------------------------------
EDITS.append((
    "dlls/win32u/input.c",
    "add enable_mouse_in_pointer state",
    r"""static LONG clipping_cursor; /* clipping thread counter */
""",
    r"""static LONG clipping_cursor; /* clipping thread counter */
static LONG enable_mouse_in_pointer = -1;
""",
))

# --- input.c: implement NtUserEnableMouseInPointer -----------------------
EDITS.append((
    "dlls/win32u/input.c",
    "implement NtUserEnableMouseInPointer",
    r"""BOOL WINAPI NtUserEnableMouseInPointer( BOOL enable )
{
    FIXME( "enable %u stub!\n", enable );
    RtlSetLastWin32Error( ERROR_CALL_NOT_IMPLEMENTED );
    return FALSE;
}""",
    r"""BOOL WINAPI NtUserEnableMouseInPointer( BOOL enable )
{
    LONG prev;

    TRACE( "enable %u\n", enable );

    if ((prev = InterlockedCompareExchange( &enable_mouse_in_pointer, !!enable, -1 )) != -1 && prev != enable)
    {
        RtlSetLastWin32Error( ERROR_ACCESS_DENIED );
        return FALSE;
    }

    return TRUE;
}""",
))

# --- input.c: implement NtUserIsMouseInPointerEnabled + helper -----------
# NOTE: NtUserEnableMouseInPointerForThread is deliberately left as a stub,
# exactly as CodeWeavers ships it. PEAK calls EnableMouseInPointer and
# IsMouseInPointerEnabled (confirmed in the captured FIXME log), not the
# per-thread variant. Matching CrossOver exactly keeps this a known-good
# configuration rather than an improvised one.
EDITS.append((
    "dlls/win32u/input.c",
    "implement NtUserIsMouseInPointerEnabled + is_mouse_in_pointer_enabled",
    r"""BOOL WINAPI NtUserIsMouseInPointerEnabled(void)
{
    FIXME( "stub!\n" );
    RtlSetLastWin32Error( ERROR_CALL_NOT_IMPLEMENTED );
    return FALSE;
}""",
    r"""BOOL WINAPI NtUserIsMouseInPointerEnabled(void)
{
    BOOL ret = ReadNoFence( &enable_mouse_in_pointer ) == 1;
    TRACE( "-> %d.\n", ret );
    return ret;
}

BOOL is_mouse_in_pointer_enabled( HWND hwnd )
{
    return ReadNoFence( &enable_mouse_in_pointer ) == 1;
}""",
))

# --- message.c: MK_* -> POINTER_MESSAGE_FLAG_* mapping helper ------------
EDITS.append((
    "dlls/win32u/message.c",
    "add pointer_buttons_from_mouse_buttons helper",
    r"""/***********************************************************************
 *          process_mouse_message
 *
 * returns TRUE if the contents of 'msg' should be passed to the application
 */""",
    r"""static WORD pointer_buttons_from_mouse_buttons( WORD mouse_flags )
{
    static const struct
    {
        WORD mouse_flag;
        WORD pointer_flag;
    }
    flags[] =
    {
        { MK_LBUTTON, POINTER_MESSAGE_FLAG_FIRSTBUTTON },
        { MK_RBUTTON, POINTER_MESSAGE_FLAG_SECONDBUTTON },
        { MK_MBUTTON, POINTER_MESSAGE_FLAG_THIRDBUTTON },
        { MK_XBUTTON1, POINTER_MESSAGE_FLAG_FOURTHBUTTON },
        { MK_XBUTTON2, POINTER_MESSAGE_FLAG_FIFTHBUTTON },
    };

    WORD pointer_flags = 0;
    unsigned int i;

    for (i = 0; i < ARRAY_SIZE(flags); ++i)
    {
        if (mouse_flags & flags[i].mouse_flag) pointer_flags |= flags[i].pointer_flag;
    }
    return pointer_flags;
}

/***********************************************************************
 *          process_mouse_message
 *
 * returns TRUE if the contents of 'msg' should be passed to the application
 */""",
))

# --- message.c: the actual WM_MOUSE* -> WM_POINTER* translation ----------
# The extra_info guard skips Wine's own injected/synthetic mouse input
# (0xff515700 is Wine's internal marker), so cursor-warping does not generate
# phantom pointer events.
EDITS.append((
    "dlls/win32u/message.c",
    "translate WM_MOUSE* to WM_POINTER* in process_mouse_message",
    r"""    msg->pt = point_phys_to_win_dpi( msg->hwnd, msg->pt );
    set_thread_dpi_awareness_context( get_window_dpi_awareness_context( msg->hwnd ));

    /* FIXME: is this really the right place for this hook? */""",
    r"""    msg->pt = point_phys_to_win_dpi( msg->hwnd, msg->pt );
    set_thread_dpi_awareness_context( get_window_dpi_awareness_context( msg->hwnd ));

    if ((extra_info & 0xffffff00) != 0xff515700 && is_mouse_in_pointer_enabled( msg->hwnd ))
    {
        WORD flags = POINTER_MESSAGE_FLAG_INRANGE, pointer_button_flags;
        DWORD message = 0;

        pointer_button_flags = pointer_buttons_from_mouse_buttons( LOWORD( msg->wParam ));
        if (pointer_button_flags) flags |= pointer_button_flags | POINTER_MESSAGE_FLAG_INCONTACT;

        switch (msg->message)
        {
        case WM_MOUSEMOVE:
            message = WM_POINTERUPDATE;
            if (!pointer_button_flags) flags |= POINTER_MESSAGE_FLAG_PRIMARY;
            break;
        case WM_LBUTTONDOWN:
        case WM_RBUTTONDOWN:
        case WM_MBUTTONDOWN:
        case WM_XBUTTONDOWN:
            if (pointer_button_flags & (pointer_button_flags - 1))
            {
                /* More than one flag in pointer_button_flags, some buttons were already pressed.
                 * WM_POINTERDOWN is only sent on the first button press. */
                message = WM_POINTERUPDATE;
            }
            else
            {
                message = WM_POINTERDOWN;
                flags |= POINTER_MESSAGE_FLAG_PRIMARY;
            }
            break;
        case WM_LBUTTONUP:
        case WM_RBUTTONUP:
        case WM_MBUTTONUP:
        case WM_XBUTTONUP:
            /* WM_POINTERUP is only sent once all the buttons are up. */
            message = pointer_button_flags ? WM_POINTERUPDATE : WM_POINTERUP;
            break;
        case WM_MOUSEWHEEL:
            message = WM_POINTERWHEEL;
            flags = HIWORD( msg->wParam );
            break;
        case WM_MOUSEHWHEEL:
            message = WM_POINTERHWHEEL;
            flags = HIWORD( msg->wParam );
            break;
        }

        if (message) send_message( msg->hwnd, message, MAKELONG( 1, flags ), MAKELONG( msg->pt.x, msg->pt.y ) );
    }

    /* FIXME: is this really the right place for this hook? */""",
))


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        return 2

    tree = Path(sys.argv[1])
    pristine = Path(sys.argv[2])

    for rel in FILES:
        if not (pristine / rel).is_file():
            print(f"VOID - pristine reference missing: {pristine / rel}")
            return 1
        if not (tree / rel).is_file():
            print(f"VOID - target tree missing: {tree / rel}")
            return 1

    # Start from pristine every time. Re-running is therefore safe and always
    # produces the same result, rather than stacking edits on edits.
    print("Resetting target files to pristine wine-11.0...")
    sources = {}
    for rel in FILES:
        sources[rel] = (pristine / rel).read_text(encoding="utf-8", errors="surrogateescape")
        print(f"  {rel}")

    # Verify every anchor before writing anything.
    print("\nChecking anchors...")
    for rel, desc, anchor, _ in EDITS:
        n = sources[rel].count(anchor)
        status = "ok" if n == 1 else f"FOUND {n} TIMES"
        print(f"  [{status:>13}] {desc}")
        if n != 1:
            print("\nVOID - an anchor did not match exactly once. Nothing was changed.")
            return 1

    print("\nApplying...")
    for rel, desc, anchor, replacement in EDITS:
        sources[rel] = sources[rel].replace(anchor, replacement, 1)
        print(f"  applied: {desc}")

    for rel in FILES:
        (tree / rel).write_text(sources[rel], encoding="utf-8", errors="surrogateescape")

    # Prove the result, rather than trusting that replace() did what we meant.
    print("\nVerifying the patched tree...")
    ok = True
    checks = [
        ("dlls/win32u/input.c", "static LONG enable_mouse_in_pointer = -1;", True),
        ("dlls/win32u/input.c", 'FIXME( "enable %u stub!\\n", enable );', False),
        ("dlls/win32u/input.c", "BOOL is_mouse_in_pointer_enabled( HWND hwnd )", True),
        ("dlls/win32u/message.c", "pointer_buttons_from_mouse_buttons", True),
        ("dlls/win32u/message.c", "WM_POINTERDOWN", True),
        ("dlls/win32u/message.c", "WM_POINTERUP", True),
        ("dlls/win32u/message.c", "flush_shm_surface_params", False),
        ("dlls/win32u/message.c", "CXHACK", False),
        ("dlls/win32u/win32u_private.h", "is_mouse_in_pointer_enabled", True),
    ]
    for rel, needle, want in checks:
        present = needle in (tree / rel).read_text(encoding="utf-8", errors="surrogateescape")
        good = present == want
        ok &= good
        verb = "present" if want else "absent "
        print(f"  [{'ok' if good else 'FAIL':>4}] {verb}: {needle[:56]}")

    if not ok:
        print("\nVOID - verification failed. Do not build this tree.")
        return 1

    print("\nSUCCESS - tree patched with CodeWeavers' pointer implementation.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
