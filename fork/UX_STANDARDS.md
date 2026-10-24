# OpenBite UX standards

What a screen in the app is held to. A UX review cites these by id
(`A3`, `H6`…). A finding without an id is an opinion: it may still be
worth raising, as a note.

Sources, checked 2026-10-24:
[Android core app quality](https://developer.android.com/docs/quality-guidelines/core-app-quality),
[Android accessibility](https://developer.android.com/guide/topics/ui/accessibility/apps),
[Android touch target size](https://support.google.com/accessibility/android/answer/7101858),
[WCAG 2.2, what's new](https://www.w3.org/WAI/standards-guidelines/wcag/new-in-22/),
[NN/g ten usability heuristics](https://www.nngroup.com/articles/ten-usability-heuristics/),
[MacroFactor's food logging speed index](https://macrofactorapp.com/fastest-food-logger/).

## A. Accessibility (pass/fail)

| Id | Rule | How to check on the emulator |
|---|---|---|
| A1 | Every touch target is at least 48×48 dp, with 8 dp between targets (Android; WCAG 2.5.8 sets 24 px as the floor). | `bounds` in the UI dump: 48 dp = 126 px at 420 dpi. |
| A2 | Text contrast at least 4.5:1, large text (≥ 18 sp, or ≥ 14 sp bold) and icons/graphics at least 3:1 (WCAG 1.4.3, 1.4.11). | Pixel colours from the screenshot. |
| A3 | Every control without visible text has a spoken label, saying what it does, not what it looks like, without "button" (Android content description; WCAG 4.1.2). | `content-desc` in the dump; a clickable node with empty text and desc fails. |
| A4 | What is spoken matches what is shown: a control with visible text has that text in its label (WCAG 2.5.3). | Compare text and `content-desc`. |
| A5 | Numbers and abbreviations are spoken as words a listener understands ("22 g protein", not "22 p"). | `content-desc`. |
| A6 | At 200% font scale nothing that matters is cut off or overlaps: text wraps rather than ellipsizes, and the screen still scrolls to everything (WCAG 1.4.4, 1.4.10). | `adb shell settings put system font_scale 2.0`, then back to `1.0`. |
| A7 | Section titles and group names are headings, so TalkBack can jump between them (WCAG 1.3.1). | The UI dump does not show headings: read the widget's code for `Semantics(header: true)`. |
| A8 | Anything done by dragging or a long press also has a plain tap path (WCAG 2.5.7). | Look for the same action in a menu or button. |
| A9 | Content is not hidden behind sticky bars, the bottom navigation or the FAB when it has focus or is the last item (WCAG 2.4.11). | Scroll to the end of each list; the last row must be fully tappable. |
| A10 | Both light and dark themes work, with the contrast of A2 (Android Theme_Support). | `adb shell cmd uimode night yes`, then `no`. |

## P. Android platform

| Id | Rule |
|---|---|
| P1 | System back always works and goes where the user expects; no screen needs a custom back button (Back_Button_Nav). |
| P2 | Leaving and coming back (Recents, screen off) returns to the same state, with typed input kept (State_Preservation). |
| P3 | Material 3 components and patterns: dialogs with sentence-case actions, confirming action on the right; snackbars for transient results; switches for on/off settings that act at once. |
| P4 | Text blocks stay within about 45–75 characters a line (Line_Length). |
| P5 | Images are sharp and show what they claim to (Graphic_Quality). |

## H. Usability heuristics (NN/g)

| Id | Heuristic | What it means here |
|---|---|---|
| H1 | Visibility of system status | After every action the user sees it happened: a logged food appears, an import says what it did, a long task shows progress. |
| H2 | Match the real world | The user's words, not the code's: "meal", "weigh-in", "day", never ids or enum names. Units and dates as the user's locale writes them. |
| H3 | User control and freedom | Every destructive or bulk action can be undone or is confirmed; every dialog can be left with back or Cancel. |
| H4 | Consistency and standards | The same thing looks and is named the same everywhere: macro order, rows in Settings, button wording, capitalisation. |
| H5 | Error prevention | Inputs reject what cannot be right (negative grams, a date in the future where it means nothing) before saving. |
| H6 | Recognition rather than recall | What the user needs is on screen: the current setting shows on its row, a disabled button says why. |
| H7 | Flexibility and efficiency | Shortcuts for the frequent path (recents, copy, quick add) without hiding the slow path. |
| H8 | Aesthetic and minimalist design | Every element earns its place; no repeated information, no clutter of identical controls. |
| H9 | Recover from errors | Errors say what went wrong in plain words and what to do next; never only "Error" or a code. |
| H10 | Help and documentation | Where a feature is not obvious, a short subtitle or info button explains it in place. |

## F. Food logging

| Id | Rule |
|---|---|
| F1 | Logging a food the user ate before takes at most three taps from Home (open add, pick from recents, confirm). |
| F2 | Recent and frequent foods come first, for the meal being added to. |
| F3 | The amount defaults to the user's usual portion for that food. |
| F4 | A day's totals against its targets are visible without scrolling on Home. |
| F5 | Imported, copied and AI-recognised entries are told apart from typed ones only where it helps; otherwise they look like any entry. |
| F6 | Times: a food logged now is stamped now; a food added to a past day can be given a time. |

## C. Copy

| Id | Rule |
|---|---|
| C1 | Plain, short sentences; sentence case for titles, buttons and labels. |
| C2 | Say what happens, not how it works: "Import" not "Run import job". |
| C3 | No zero counts or empty clauses ("0 weigh-ins"); leave the part out. |
| C4 | Singular and plural agree with the count ("1 day", "2 days"; "the file" for one, "the files" for several). |
| C5 | The same word for the same thing throughout (meal vs. section; weigh-in vs. weight entry). |

## Severity

- **high**: a user cannot finish a task, loses data, or an accessibility rule (A) fails on a main path.
- **medium**: a task is slower or confusing for most users, or an A rule fails off the main path.
- **low**: polish: wording, alignment, consistency that does not cost the user anything real.

Upstream screens are in scope: a finding there is fixed at a seam (see `SEAMS.md`) or deferred to upstream after phase 4.
