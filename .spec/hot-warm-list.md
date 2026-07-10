# Hot and warm list

## Goal and end state

Remove automatic file addition from the dotfiles integration.

Saving an edited Harpoon menu replaces its authoritative state, so deletions and ordering persist.

Rows 1–7 are hot slots labeled and mapped to fingers `A S E T G F D`.

Rows 8+ are a warm list available for later swapping into hot slots.

## Phases

### 1. Fork state and menu

**Owner:** `/home/cullyn/cogikyo/harpoon/lua/harpoon` and existing relevant tests, if present.

**Status:** Repaired and verified, uncommitted.

Implement save-as-replacement semantics and the hot/warm menu presentation with an unambiguous line-to-finger cue.

Preserve warm rows when editing, deleting, and reordering menu lines.

### 2. Dotfiles integration

**Owner:** `/home/cullyn/dotfiles/config/nvim/lua/plugins/editor/harpoon.lua`.

**Status:** Pending.

Remove only automatic-add behavior and retain the explicit/manual add mapping.

Map hot rows 1–7 to `A S E T G F D` in that order.

Do not curate `harpoon.json`.

If committing dotfiles, include its existing user change as required by the repository instructions.

### 3. Verification and recovery

**Owner:** the changed fork and dotfiles files.

**Status:** Pending.

Verify a menu edit that deletes and reorders lines survives close, reopen, and restart.

Verify each hot mapping opens its corresponding numbered row and rows 8+ remain reachable in the menu.

Recover by restoring the prior commits in each repository, then reopen Harpoon and confirm the persisted list is readable.

## Decisions and deviations

- Approved: menu saves replace authoritative state rather than merging with it.
- Approved: the first seven lines are fixed hot positions with finger order `A S E T G F D`.
- Approved: remaining lines form the warm list for swaps.
- Evidence: the current dotfiles integration maps `nav_file` positions and exposes `<leader>nn` for explicit addition.
- Correction: `<leader>nn` is an explicit/manual add mapping and must remain available for curation.
- Root cause: `fe2904d` added a `BufEnter` visit tracker and appended ranked visits in `get_active_list()`, allowing deleted menu entries to reappear from visit state.
- Implemented: active entries now come only from curated pins, replacement clears legacy visit state, menu line collection preserves sequence order, and the status column labels rows `A S E T G F D` then `warm`.
- Repaired: empty projects persist as an explicit `pins: []` tombstone, preventing lower-precedence legacy marks from returning after restart.
- Repaired: every changed menu save rerenders the canonical 20-slot list after blank removal and stable duplicate removal.
- Repaired: `BufWriteCmd` forces persistence even when `save_on_change=false`.
- Repaired: the plugin applies its status column after the `harpoon` FileType event, so the dotfiles callback can still disable signs without erasing hot/warm labels.
- Repaired: pin saves refresh inactive projects from disk before writing, preserving sequential saves from stale sessions in different projects.
- Verification: isolated headless Neovim checks passed for empty clear plus legacy-backed restart, canonical blank/duplicate display, explicit write with `save_on_change=false`, and stale concurrent sessions saving separate projects.
- Integration verification: headless Neovim with the real dotfiles init confirmed the `HarpoonColumns` FileType callback ran and the plugin-owned `A S E T G F D / warm` status column survived.
- Residual risk: the bounded project merge is last-writer-wins for concurrent sessions in the same project and does not lock truly simultaneous read-modify-write cycles.
- No fork-local `AGENTS.md` was found at the requested path.
- Existing product tests do not cover mark persistence or the menu; `manage_cmd_spec.lua` covers terminal commands and `manage-a-mark.lua` is a placeholder.
- Contract: `get_length()` reports the dense populated pin count so `nav_next`/`nav_prev` wrap across existing entries only.
- Contract: the menu still renders fixed editable capacity via `get_capacity()` (20 slots), independently of `get_length()`.
- Contract: `set_current_at(index)` keeps a dense list — replace when `index <= #pins`, append when past the dense tail (no sparse holes); out-of-range indices are ignored.
- Root cause (medium): phase-1 `get_length()` returned `active_slots` (20) when unmarked, so two-pin `nav_next` from slot 2 called `nav_file(3)` and no-op'd instead of wrapping.
- Root cause (medium): phase-1 `set_current_at(idx)` wrote `pins[idx]` directly, creating sparse holes that `unique_pins`/`ipairs` drop on save and restart.
- Decision: append past the dense tail rather than reject; keeps the curated list dense and still accepts intentional placement without inventing empty middle slots.
- Verification: headless probes (21/21) covered two-pin next/prev wrap, replace-in-range and append-past-tail `set_current_at`, OOR ignore, no sparse keys, save/restart density, manual add, and menu 20-row capacity with `(empty)` padding.
- Contrast: HEAD reported `get_length=20`, `nav_next` from pin 2 stayed put, and `set_current_at(5)` with two pins left the list unchanged after canonicalization.
- No deviations are recorded.

## Open questions for the user

- Queue only: should the line-to-finger cue be labels in the menu text, highlights, or both?
- Queue only: should swapping be an explicit command or remain manual line reordering in the menu?

## Condensed next steps

Proceed to phase 2 with the explicit/manual add mapping preserved.

Create separate commits: one in `/home/cullyn/cogikyo/harpoon` and one in `/home/cullyn/dotfiles`.
