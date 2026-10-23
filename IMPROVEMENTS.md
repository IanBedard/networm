# NetWorm improvement log

Each cycle picks the weakness that costs the player the most, fixes it, and is checked with automated
tests (behaviour tests that drive the real game) and a QA bot that plays full runs and reports how far
it gets and how long frames take. Every cycle is its own commit, so any change can be reverted alone.

Baseline QA bot (4 runs, seed 1): average level 6.8, 3 of 4 runs die at the first boss (level 6).
Update p95 0.03 ms, max 1.4 ms; draw p50 0.46 ms (CPU side). Performance is not the bottleneck.

## Cycle 1: never lose a run by accident

**Problem.** In the darkmarket a single Esc sent you to the menu and threw the whole run away, and the
menu's Space then started a fresh run. Switching windows or browser tabs mid-fight kept the level
running, so the worm crashed while you were away.

**Change.** Esc in the market now needs a second press within 2.5 s ("Press [Esc] again to abandon
this run"); the footer hint says so. Losing window focus during a fight pauses the game.

**Checked.** Tests: one Esc keeps the run, a slow second Esc only re-arms, a quick second Esc abandons;
focus loss in the arena sets pause.

## Cycle 2: a fair first boss

**Problem.** The QA bot, now tagging every point of damage by its source, showed that 3 of 4 runs died
at the first antivirus boss (level 6) and that 78% of the damage there came from its bullet rings:
full 360-degree rings with no warning and no gap, which a long worm cannot dodge. On levels 7-9 the
repulsor pulse became the top damage source because it hits nearly every segment at once.

**Change.** Boss rings are now telegraphed for 0.6 s with a spoke drawn for every bullet about to fire;
each ring leaves a gap (5 of 16 bullets, 4 of 24 when enraged) whose missing spokes show where to steer.
Ring bullets are slower (105 vs 120) and hit a little softer (40% vs 50% of contact damage).
Repulsor pulses do half damage; their shove stays, since that is their real threat.

**Checked.** Test: a forced ring fires nothing during the warning, then exactly 11 of 16 bullets.
QA bot: average level 6.8 -> 7.8 (seed 1, 4 runs) and 8.7 over 6 runs on seed 2; the level-6 wall is
gone (most runs now pass it) even though the bot does not aim for the gap.
