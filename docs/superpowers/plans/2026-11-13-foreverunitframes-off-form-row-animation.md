# Plan: the off-form power row slides in and out

Design: `docs/superpowers/specs/2026-11-13-foreverunitframes-off-form-row-animation-design.md`.
One step, one PR: `feat(foreverunitframes): slide the off-form power row in and out`.

## Tasks

1. **`PowerBar.lua`:** add `ns.PowerBar.CreateBackground(frame)` and use it for the power bar's own
   background; remove `SetHeadroom`.
2. **`OffFormPower.lua`:** a clipping frame under the border's frame; the row inside it with its own
   background; the borders on a child frame of the row; the slide `AnimationGroup`;
   `SetRowShown(shown, animate)`; `SetBars` and `Refresh` pass `animate` through, true only from the
   event handler. Log `OFFFORM slide`.
3. **`CHANGELOG.md`:** the druid row's line under `## Unreleased` mentions the slide.

No SavedVariables, settings, slash commands or TOC changes.

## Reviewers

Core (`addon-reviewer`, `api-verifier`, correctness, spec) plus the UI reviewer.

## Review focus

- Frame levels: the row is a child of the clip (itself a child of the border's frame) but set to
  the holder's level; bars at holder + 1; borders at the border's level.
- `Play(reverse, offset)` and `GetProgress()` when a slide turns around mid-way.
- `OnFinished` hiding the row after a slide out: no path where it hides a row that should be shown.
- `SetLayout` (settings, login) must snap and stop a slide in flight.

## In-game checks

The table in the design. Devlog tag: `OFFFORM` (`slide in|out from <offset>`).
