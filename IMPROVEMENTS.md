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
