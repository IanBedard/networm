# Plotline

A kernel worm auto-battler made with [LÖVE](https://love2d.org) 11. You are the operator: inject a worm into the kernel, steer it, and let its modules kill every hostile process on their own. Between levels, buy modules at the darkmarket, stack copies to rank them up, and combine classes for set bonuses. Survive 25 levels, with an antivirus boss every 6.

- 40 units across 4 tiers and 11 classes; every class has its own colour and each hero its own shade of it.
- Merchants make money: enemies can drop coins, and merchants add interest, gold per level, or gold per kill.
- The darkmarket (shop) has 5 levels. Upgrading it with gold raises the odds of higher tiers; the Catalogue lists every unit and the current odds.
- Colliding with an enemy damages both sides. Rammers take half the collision damage and hit much harder.
- From level 2 on, a security update types out at the start of most levels as the kernel hardens its defences.
- Enemies include kamikazes that dive in and explode, repulsors whose pulses shove the worm, and snipers with laser sights.
- Terminal look: phosphor-green text in Roboto Mono, CRT scanlines, a dmesg-style boot screen.

**Play in the browser:** https://ianbedard.github.io/plotline/

## Controls

| Key | Action |
| --- | --- |
| A / D or Left / Right | Steer |
| Space | Start a run / start the next level |
| R | Reroll the darkmarket |
| U | Upgrade the darkmarket |
| C | Open / close the catalogue |
| Right-click a unit | Sell it |
| P or Esc | Pause |
| M | Music on / off |

## Run on desktop

Install LÖVE 11.x, then from this folder:

```
love .
```

## Rebuild the web version

The browser build lives in `web/` and is made with [love.js](https://github.com/Davidobot/love.js). After changing `main.lua` or `conf.lua`, run (needs Node.js):

```
powershell -ExecutionPolicy Bypass -File build-web.ps1
```

This refreshes the runtime files in `web/` and keeps the hand-written `web/index.html`. Pushing to `main` redeploys the page through GitHub Actions.

## Credits

Music: [Madness - Jebediah: Disarmed](https://www.newgrounds.com/audio/listen/1627299) by Xtrullor feat. Cheshyre, licensed [CC BY-NC-SA 3.0](https://creativecommons.org/licenses/by-nc-sa/3.0/). Newgrounds allows its use in web-based games; ask the artist before using it in a non-web build. Plotline is non-commercial.

Roboto Mono font: Copyright 2015 The Roboto Mono Project Authors, Apache License 2.0 (see `font/NOTICE.txt`).
