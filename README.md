# CleanCombatLog 0.2.0-probe

This branch is an isolated **World of Warcraft: Forever combat API instrumentation build**. It is intentionally separate from both `main` and the experimental `feature/player-centric-combat-adapter` fallback branch.

The goal is to recover as much of the old `COMBAT_LOG_EVENT_UNFILTERED` capability as Forever actually permits, and only accept missing functionality after direct shipping-client testing shows that it cannot be reconstructed reliably.

## What the probe tests

The probe attempts runtime registration rather than assuming that every Mainline event is enabled on Forever. It records registration success/failure, event counts and sanitised event payloads for:

- `PLAYER_SWING` / `PLAYER_SWING_RANGE_UPDATE`
- `UNIT_COMBAT`, `PARTY_KILL`, and `UNIT_DIED`
- `UNIT_AURA` and helpful/harmful aura-instance ID snapshots
- the player/unit spell-cast lifecycle (`UNIT_SPELLCAST_*`)
- `COMBAT_TEXT_UPDATE` plus `C_CombatText.GetCurrentEventInfo()`
- `COMBAT_LOG_MESSAGE` without attempting to parse its protected message payload
- the secure Blizzard combat-log formatter via `C_CombatLog.ApplyFilterSettings()` and `C_CombatLog.RefilterEntries()`
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

Potentially secret values are never converted, compared or parsed by the logger. Inaccessible values are stored as `<secret>` markers. The capture still represents `COMBAT_LOG_MESSAGE` text only as `<protected-combat-message>`, but the formatter experiment can pass the protected message directly into a `FontString` preview unchanged so we can visually compare Blizzard-generated output without parsing it.

## Secure formatter experiment

The release-day probe now tests a separate avenue: whether addons can configure Blizzard's secure combat-log processor closely enough that **Blizzard performs the filtering and formatting before the result becomes a protected KString**.

The probe uses the existing built-in combat-log profiles as its source settings, snapshots the currently selected profile before changing anything, and can apply either compact or full-text formatting. It can also apply Blizzard's built-in **My Actions** or **Me** profiles so we can test whether source/destination filtering remains usable from addon code.

Commands:

- `/ccl probe formatter status` — report whether `ApplyFilterSettings` and the built-in filter tables are available.
- `/ccl probe formatter compact current` — apply the currently selected combat-log profile with compact text, no timestamp and amount/school colouring.
- `/ccl probe formatter compact myactions` — ask Blizzard to generate compact protected messages for its built-in **My Actions** filter.
- `/ccl probe formatter compact me` — same for Blizzard's built-in **Me** filter.
- `/ccl probe formatter full current|myactions|me` — equivalent tests with `fullText=true`.
- `/ccl probe formatter refilter` — ask Blizzard to regenerate retained combat-log entries using the current secure filter/format settings.
- `/ccl probe formatter preview on|off` — show/hide the protected-message preview.
- `/ccl probe formatter restore` — reapply the snapshot captured before the first formatter experiment.

`/ccl probe stop` also restores the original formatter settings automatically if a formatter experiment is still active.

This experiment deliberately does **not** attempt to modify or parse the returned protected message. Its purpose is to determine whether the secure formatter itself can get close enough to CleanCombatLog's desired output that the protected message can be used as an accuracy-first display path.

## Installation

1. Check out `experiment/forever-combat-probe`.
2. Place the repository folder in the shipping Forever client's `Interface/AddOns` directory as `CleanCombatLog`.
3. Log in and run `/ccl api` and `/ccl cleu`. The project report recognizes `WOW_PROJECT_CAMELOT` and ID 18. Registration and payload-reader checks run independently of project identity.
4. Run `/ccl probe start`, `/ccl probe events`, and `/ccl probe formatter status` before testing combat.

The branch uses Forever interface `16001`.

## Passive My Actions test

1. After a fresh login, leave Blizzard's Combat Log unopened. Start recording and run `/ccl probe mark unopened`. Fight a short, repeatable pull.
2. Open Blizzard's Combat Log manually and select **My Actions**. Wait for history to settle. Then run `/ccl probe mark my-actions-open` and repeat the pull.
3. Switch back to the normal chat tab and run `/ccl probe mark my-actions-hidden`. Repeat to see whether the stream continues. Keep formatter apply/refilter commands out of these passive trials. The status command only reads state.
4. With My Actions selected, run marked trials for player-only attacks, another player attacking while you idle, alternating attacks and simultaneous attacks against the same enemy. Repeat with pet-only attacks, several DoT ticks after the cast, a damage shield, and AoE across nameplates. Compare the cast-free tick and ally-only intervals for false candidates.
5. Enable `/ccl probe formatter preview on` during a separate trial. Verify the displayed output visually and check `PREVIEW_SET_TEXT_OK` and `PREVIEW_SET_TEXT_ERROR` in the summary. The preview passes the original message directly to the UI setter.

Every pulse records its receipt time, order argument, reported filter and filtered-event state, ChatFrame2 visibility, and active formatter experiment. ChatFrame2 visibility is a UI hint. The phase marker records the tester's observation of the actual selected tab and filter. Filter/refilter notifications start a new phase and flag pulses in the next 750 ms as possible history replay.

`/ccl probe correlate [n]` reports retained candidates within ±750 ms of each `UNIT_COMBAT` or aura snapshot. Negative offsets arrived before the anchor. Look at how many result rows share a pulse, how many pulses surround a result, and whether multiple tokens report the same readable GUID and result fields. Equal payloads across tokens are possible duplicates. Use the signed offsets and isolated trials to estimate tighter timing windows by ability and avoidance type. The report caps each displayed and saved candidate list at 40 and counts omissions.

Aura snapshots show baseline IDs with `=`, additions with `+`, and removals with `-`. The `updated` field reports client-provided changed IDs when readable. An update can represent several kinds of change. An unavailable snapshot clears the comparison baseline for that filter. Cross-check aura candidates against player or pet casts and inspect changes after switching targets or replacing pets.

After combat, the probe records the meter's current-session local-player totals when available alongside raw readable player damage and unattributed tracked-unit activity from the captured combat interval. The meter session can have a different scope than the probe interval. Keep pulls isolated and compare the ranges and coverage before interpreting totals. A post-death comparison records IDs of recent player `UNIT_COMBAT` rows alongside the Death Recap query. Save each short scenario on stop before starting another, because the capture retains the most recent 2,500 records.

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
16. a channel, resource change and aura application, update and removal
17. pet final blow and a nameplate death while another unit is targeted
18. several enemies taking AoE damage and periodic ticks

For outgoing-target experiments, `/ccl probe combattext target` asks `C_CombatText` to track the current target. This deliberately changes the active combat-text unit for the duration of the test and is restored to `player` when the probe stops. Target/focus tracking is refreshed when those units change.

## Probe commands

- `/ccl probe start` — clear old in-memory data, register candidate events and begin recording.
- `/ccl probe stop` — stop recording and save the sanitised capture to `CleanCombatLogDB.probe`.
- `/ccl probe status` — show build/API state and key registration results.
- `/ccl probe events` — print the full registration matrix.
- `/ccl probe summary` — print event and preview counts.
- `/ccl probe mark <label>` — record passive filter state and start a new correlation phase.
- `/ccl probe correlate [n]` — report signed candidate offsets for recent combat and aura records.
- `/ccl probe dump [n]` — print the last `n` records (default 40, maximum 200).
- `/ccl probe meter` — take an explicit `C_DamageMeter` snapshot.
- `/ccl probe death` — explicitly inspect the latest death recap.
- `/ccl probe combattext player|target|pet|focus` — choose the active `C_CombatText` unit for focused testing.
- `/ccl probe formatter ...` — run the secure Blizzard combat-log formatter experiment described above.
- `/ccl probe clear` — clear in-memory and saved probe data.

The normal `/ccl cleu` command remains available for direct CLEU testing; this branch does not merge the player-centric fallback implementation.

## What to return from a shipping-client test

The most useful minimum output is:

1. `/ccl api`
2. `/ccl probe events`
3. `/ccl probe summary`
4. `/ccl probe dump 100` after one controlled combat scenario
5. `/ccl probe meter` after combat
6. `/ccl probe death` after a player death and `/ccl probe correlate 10` for representative hits and aura updates
7. `/ccl probe formatter status`, followed by `compact myactions` and `compact me` during separate short combat tests, then `restore`

For a longer session, the sanitised capture is also persisted at `CleanCombatLogDB.probe` on stop and after post-combat snapshots.

## Decision criteria

We will use the capture to classify each old CLEU capability as:

- **native** — directly exposed by a permitted Forever event/API;
- **correlated** — reconstructable with high confidence from multiple permitted signals;
- **aggregate/post-combat** — available only through `C_DamageMeter` or death recap;
- **unrecoverable** — no reliable player-centric reconstruction found.

The production implementation should preserve all native and reliably correlated functionality. A cut-down combat log is the fallback, not the starting assumption.
