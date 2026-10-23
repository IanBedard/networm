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

## Cycle 3: shots that land, levels that end

**Problem.** On one QA seed, 3 of 4 runs stalled on levels 4-6: a lone shooter with 12 HP outlived 240
seconds against two ranged modules. Logging showed every projectile passing 25-35 px from it. All
projectiles were aimed at where an enemy *was*; a shooter strafing at ~47 px/s moves ~20 px while a shot
is in flight, more than the hit radius, so kiting enemies dodged indefinitely. For the player this reads
as "my modules keep missing" and a level that never ends.

**Change.** Projectile attacks (14 single-shot modules, the Fanblade fan, Slinger stones and turrets)
now lead their target using its velocity and the projectile's speed. As a safety net, 25 s after the
last wave of a level is out, the remaining shooters, snipers and repulsors stop kiting and charge the
worm ("TRACE COMPLETE" banner), so a level always resolves.

**Checked.** Tests: the aim helper returns the lead angle; a lone strafing shooter is shot down within
20 s; a sniper with infinite HP switches to hunting and closes in. All three fail on the previous
commit and pass now. QA bot on the stalling seed: average level 5.3 -> 9.3 (best run reached level 16).
The remaining bot timeouts come from the bot's own steering (it avoids walls and blobs), not the game.

## Cycle 4: see the worm's health at a glance

**Problem.** A module's health only showed as a tiny bar over its segment, and only after it was hurt,
so the first sign that a module was in trouble was usually its death message.

**Change.** The HUD now has a `top`-style module table: one entry per segment in worm order (head
first) with its colour block and a health bar that is green, amber below 60%, and blinking red below
30%; a terminated module shows as an empty slot with an x. The antivirus health bar moved to the
arena's top edge so the two never overlap.

**Checked.** Screenshot of a level-12 boss fight with modules forced to 100/75/dead/20/90/60%: every
entry and the boss bar render where expected. Behaviour tests and the random-play 25-level harness pass.
(While capturing it, cycle 1's pause-on-focus-loss correctly paused the unfocused test window.)

## Cycle 5: hits you can feel, deaths you notice

**Problem.** Every hit on the worm added the same screen shake, so under steady fire the screen shook
constantly and the shake stopped carrying information; a module dying looked almost the same as a scratch.

**Change.** Shake now scales with the share of the module's health the hit took. The screen edges pulse
red in proportion to recent damage. A module's death or the antivirus going down triggers a short
hit-stop (0.1 s / 0.18 s) so the moment registers.

**Checked.** Test: a 60% hit flashes harder than a 5% hit; a lethal hit starts a hit-stop that freezes
the simulation and then resumes. Screenshot of a level-9 fight at the moment the head is hit shows the
red edge pulse and the head's entry flashing in the module table. QA bot runs complete without errors.

## Cycle 6: boss fights about the boss

**Problem.** The boss summoned 3-5 minions on about a third of its attacks with no limit. Long fights
snowballed into swarms: a QA run ended with the boss dead and 15 of its minions still alive, and boss
levels took the bot 130-200 s against 30-60 s for normal levels.

**Change.** Boss summons are tagged as its escort; while 6 or more escort minions are alive the boss
picks a bullet ring or a charge instead of summoning again.

**Checked.** Test: with 6 escort minions alive, 80 forced ability rolls add none; with the escort gone
the boss summons again. QA bot (4 runs each): seed 1 average level 7.8 -> 10.5, seed 2 unchanged at 7.8
(its runs die before the boss gets long); one run reached level 15. Also fixed a flaky test that
depended on which random unit it bought.

## Cycle 7: perks (requested) and music removed (requested)

**Request.** Perks bought in the shop: a separate single perk slot, rerolled with the same button whose
cost doubles on every click in the same market visit; up to 3 perks; priced above units and by rarity;
some perks favour classes; e.g. touching a wall fires bullets. Separately: remove the music for now.

**Change.** 13 perks in 4 rarities (common $5, rare $8, epic $12, legendary $16), rarer odds at higher
market levels, never offering one already installed:
Ricochet Protocol (wall hits fire a fan of bullets; +1 per Marksman), Thick Firmware (+20% HP; Bruisers
+40%), Overclock (+15% attack speed; Arcanists +15% damage), Coin Magnet (coins fly in from afar, +1 max
interest; more drops per Merchant), Spiked Hull (ram x2; Rammers take less), Firewall Breach (kills
explode; bigger with Demolishers), Self-Repair (1%/s regen; doubled by Sages), Packet Storm (head fires a
ring every 5 s; +2 bullets per Cutthroat), Root Access (first death each level is undone; 100% with
Sages), Fork Bomb (tail launches fuse-imps; faster with Artificers), Virulence (curses jump on death;
further with Hexers), Zero-Day Exploit (+10% crit; Cutthroat crits x4), Polymorphic Code (+1 slot).
The market shows the perk card beside a narrower class panel (full class text moved to a hover
tooltip); installed perks appear as `name.ko` chips under the party (hover for details, right-click to
remove for half the price). Perk damage scales with the level. The music, its M key and credit are gone.

**Checked.** 8 new tests: reroll cost 1/2/4 then 8, reset next visit; reroll changes the perk; prices by
rarity, 3-perk cap, half refund; ricochet fires on a wall hit; +1 slot; Root Access once per level;
HP/crit/attack-speed perks; breach explosion and Packet Storm ring. Screenshot of the market with perks
installed, a legendary on offer and a class tooltip. QA bot with a perk-buying policy: runs that afford
perks reach levels 12-17.

## Cycle 8: the catalogue lists perks

**Problem.** The catalogue is meant to show everything the market can offer, but after perks were added
it only listed modules, so there was no way to see which perks exist, their rarities or their odds.

**Change.** The catalogue has two tabs, modules and perks (click or press Tab). The perks page groups all
13 perks by rarity with each rarity's price and current odds, marks installed ones, and shows the effect
and class synergy of the hovered perk.

**Checked.** Test: C opens the catalogue, Tab switches to perks and back (drawing the perks page on the
way), Esc closes it without leaving the market. Screenshots of both tabs; an overlap between the
"installed" tag and long perk names was found in the first capture and fixed.

## Sound on the web (fix)

**Problem.** Reported: no sound on the web version. Browsers start Web Audio suspended until the player
interacts with the page, and love.js never resumes it, so the synthesized sound effects stayed silent.
(The music was removed on request in cycle 7; the effects were always meant to remain.)

**Change.** The page tracks every AudioContext the engine creates and resumes them on the first click or
key press.

**Checked.** In the browser the engine has one audio context; instrumenting it showed clicking Start in
the menu starts an audio buffer (the click effect). The embedded test browser allows autoplay, so the
suspended-context case itself could not be reproduced there; I could not listen to the output.
