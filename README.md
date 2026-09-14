# CleanCombatLog 0.1.0-test

A standalone test shell for a compact three-column World of Warcraft combat log.

This package is intentionally independent. It contains no dependencies on any UI suite or addon framework.

## Purpose of this build

This is the Thursday beta/API test build. It provides:

- Three synchronized scrolling columns:
  - left: incoming
  - centre: information/recovery
  - right: outgoing
- Right/centre/left text alignment matching the intended visual grammar.
- Row synchronization by inserting blank rows into the two inactive columns.
- Hover tooltips for compact entries.
- Combat start/end markers.
- A dummy-data display test.
- A compatibility adapter that detects either:
  - `C_CombatLog.GetCurrentEventInfo()`, or
  - legacy `CombatLogGetCurrentEventInfo()`.
- An explicit `/ccl cleu` test so we can see whether Forever permits
  `COMBAT_LOG_EVENT_UNFILTERED`.
- A minimal live parser for damage, healing, misses, auras and deaths if CLEU works.

## Installation

1. Place the repository folder in the beta client's `Interface/AddOns` directory as `CleanCombatLog`.
2. If the client marks the addon as out of date, enable **Load out of date AddOns**.
   The `## Interface` value in this test build is provisional because Forever's interface
   number is not public yet.
3. Log into a character.
4. Type:

   `/ccl test`

   You should see representative entries across all three columns.

5. Type:

   `/ccl api`

   Copy the output if you want to compare the client/build/API details.

6. Type:

   `/ccl cleu`

   This explicitly attempts to register `COMBAT_LOG_EVENT_UNFILTERED`.

7. If registration succeeds, attack a target and watch for live rows.

## Commands

- `/ccl test` — populate representative dummy rows.
- `/ccl api` — print client/API diagnostics.
- `/ccl cleu` — toggle/attempt CLEU registration.
- `/ccl clear` — clear the display.
- `/ccl move` — unlock and drag the display.
- `/ccl lock` — lock it and hide the move background.

## What to report from Thursday's test

The most useful outputs are:

1. The full `/ccl api` chat output.
2. What happens immediately after `/ccl cleu`.
3. Whether attacking a target creates entries.
4. Any Lua error text.
5. The interface number reported by `/ccl api`.

This test build is deliberately not the finished addon. Periodic-event aggregation,
full combat summaries, exact historical formatting, icon handling, configuration UI,
and any Forever-specific fallback adapter will be added after the API result is known.
