# CleanCombatLog 0.2.0-experimental

A standalone test shell for a compact three-column World of Warcraft combat log.

This package is intentionally independent. It contains no dependencies on any UI suite or addon framework.

> This branch is experimental. `main` remains the CLEU-first test build. The player-centric adapter on this branch is a fallback candidate only and should not be merged until CLEU has been definitively ruled out for World of Warcraft: Forever.

## Current experiment

This branch keeps the existing CLEU path unchanged and adds an opt-in player-centric adapter built around `UNIT_COMBAT` plus player/pet spell-cast tracking.

The fallback is intentionally narrower than a full combat log:

- incoming damage to the player
- incoming healing to the player
- incoming miss/block/dodge/parry style results
- outgoing damage against the current target when recent player/pet activity makes attribution plausible
- outgoing healing against the current target under the same attribution model
- pet attribution marker when recent pet activity is the best match
- damage-school colour where the school mask is accessible
- critical marker from the `UNIT_COMBAT` flag text

It does **not** claim perfect outgoing attribution in groups. Damage to the current target can also have been caused by another player, and DoTs on targets that are no longer the current target need a more sophisticated tracking strategy.

## Secret Values

Midnight-style combat values may be secret while combat restrictions are active. The normal scrolling-message-frame path performs string conversion and therefore is not suitable for secret combat amounts.

This branch adds `SecretDisplay.lua`, which passes combat amounts directly to `FontString:SetText()` and keeps prefixes, suffixes and colours separate. The value itself is not inspected, formatted, compared or converted by addon code.

## Installation

1. Check out `feature/player-centric-combat-adapter` and place the repository folder in the client `Interface/AddOns` directory as `CleanCombatLog`.
2. If the client marks the addon as out of date, enable **Load out of date AddOns**.
3. Log into a character.
4. `/ccl test` verifies the original display shell.
5. `/ccl api` prints API diagnostics.
6. `/ccl cleu` attempts to register `COMBAT_LOG_EVENT_UNFILTERED`.
7. `/ccl unitcombat` toggles the experimental player-centric fallback.

## Commands

- `/ccl test` — populate representative dummy rows.
- `/ccl api` — print client/API diagnostics.
- `/ccl cleu` — toggle/attempt CLEU registration.
- `/ccl unitcombat` — toggle the experimental `UNIT_COMBAT` adapter.
- `/ccl clear` — clear both legacy and secret-safe display rows.
- `/ccl move` — unlock and drag the display.
- `/ccl lock` — lock it and hide the move background.

## Decision gate

The preferred implementation remains the full structured combat-log path if Forever exposes it.

Do not merge this branch solely because Midnight restrictions are expected to apply. We should first obtain direct evidence that Forever rejects or does not fire `COMBAT_LOG_EVENT_UNFILTERED` for third-party addons. If CLEU is definitively unavailable, this branch becomes the basis for the restricted player-centric implementation.

If that happens, the next work should focus on:

1. improving outgoing attribution in groups;
2. tracking engaged targets for DoTs and delayed effects;
3. adding spell icons using player/pet cast history;
4. recreating the original periodic-event aggregation behaviour without inspecting secret numeric values;
5. validating which `UNIT_COMBAT` fields become secret in Forever specifically.
