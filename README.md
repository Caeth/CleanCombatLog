# CleanCombatLog 0.2.0-probe

This branch is an isolated **World of Warcraft: Forever combat API instrumentation build**. It is intentionally separate from both `main` and the experimental `feature/player-centric-combat-adapter` fallback branch.

The goal is to recover as much of the old `COMBAT_LOG_EVENT_UNFILTERED` capability as Forever actually permits, and only accept missing functionality after direct beta testing shows that it cannot be reconstructed reliably.

## What the probe tests

The probe attempts runtime registration rather than assuming that every Mainline event is enabled on Forever. It records registration success/failure, event counts and sanitised event payloads for:

- `PLAYER_SWING` / `PLAYER_SWING_RANGE_UPDATE`
- `UNIT_COMBAT`
- `UNIT_AURA`
- the player/unit spell-cast lifecycle (`UNIT_SPELLCAST_*`)
- `COMBAT_TEXT_UPDATE` plus `C_CombatText.GetCurrentEventInfo()`
- `COMBAT_LOG_MESSAGE` without attempting to parse its protected message payload
- player combat-state events
- target/focus/pet/nameplate context changes
- threat updates
- death lifecycle events
- `DAMAGE_METER_*` update events

It also probes:

- `C_DamageMeter.GetCombatSessionFromType()` for all current damage-meter categories
- `C_DeathRecap.GetRecapEvents()` after player death; this is especially important because death recap can expose CLEU-like fields for the final damaging events
- `C_CombatLog.IsCombatLogRestricted()` when present
- secret-value predicates (`canaccessvalue`, `issecretvalue`)

Potentially secret values are never converted, compared or parsed by the logger. Inaccessible values are stored as `<secret>` markers. The `COMBAT_LOG_MESSAGE` text itself is deliberately represented only as `<protected-combat-message>`.

## Installation

1. Check out `experiment/forever-combat-probe`.
2. Place the repository folder in the Forever beta client's `Interface/AddOns` directory as `CleanCombatLog`.
3. Log in and run `/ccl api`.
4. Run `/ccl probe start` before testing combat.

The branch uses Forever beta interface `16001`.

## Recommended test matrix

Run several short tests separately where possible:

1. main-hand auto attacks
2. off-hand auto attacks if available
3. ranged auto attacks if available
4. a direct instant damage spell/ability
5. a cast-time damage spell
6. a DoT through several ticks
7. an incoming melee hit
8. incoming spell damage
9. dodge/parry/block/miss/absorb cases where practical
10. a direct heal and a HoT
11. an interrupt
12. a dispel/purge
13. pet attacks and pet abilities if available
14. multiple players attacking the same target
15. player death, so `C_DeathRecap` can be inspected

For outgoing-target experiments, `/ccl probe combattext target` asks `C_CombatText` to track the current target. This deliberately changes the active combat-text unit for the duration of the test and is restored to `player` when the probe stops. Target/focus tracking is refreshed when those units change.

## Probe commands

- `/ccl probe start` — clear old in-memory data, register candidate events and begin recording.
- `/ccl probe stop` — stop recording and save the sanitised capture to `CleanCombatLogDB.probe`.
- `/ccl probe status` — show build/API state and key registration results.
- `/ccl probe events` — print the full registration matrix.
- `/ccl probe summary` — print event counts.
- `/ccl probe dump [n]` — print the last `n` records (default 40, maximum 200).
- `/ccl probe meter` — take an explicit `C_DamageMeter` snapshot.
- `/ccl probe death` — explicitly inspect the latest death recap.
- `/ccl probe combattext player|target|pet|focus` — choose the active `C_CombatText` unit for focused testing.
- `/ccl probe clear` — clear in-memory and saved probe data.

The normal `/ccl cleu` command remains available for direct CLEU testing; this branch does not merge the player-centric fallback implementation.

## What to return from a beta test

The most useful minimum output is:

1. `/ccl api`
2. `/ccl probe events`
3. `/ccl probe summary`
4. `/ccl probe dump 100` after one controlled combat scenario
5. `/ccl probe meter` after combat
6. `/ccl probe death` after a player death

For a longer session, the sanitised capture is also persisted at `CleanCombatLogDB.probe` on stop and after post-combat snapshots.

## Decision criteria

We will use the capture to classify each old CLEU capability as:

- **native** — directly exposed by a permitted Forever event/API;
- **correlated** — reconstructable with high confidence from multiple permitted signals;
- **aggregate/post-combat** — available only through `C_DamageMeter` or death recap;
- **unrecoverable** — no reliable player-centric reconstruction found.

The production implementation should preserve all native and reliably correlated functionality. A cut-down combat log is the fallback, not the starting assumption.
