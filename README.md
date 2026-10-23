# Plotline

A snake auto-battler made with [LÖVE](https://love2d.org) 11. Steer a line of heroes that fight on their own, recruit units between levels, stack copies to rank them up, and combine classes for set bonuses. Survive 25 levels, with a boss every 6.

- 40 units across 4 tiers and 11 classes; every class has its own colour and each hero its own shade of it.
- Merchants make money: enemies can drop coins, and merchants add interest, gold per level, or gold per kill.
- The shop has 5 levels. Upgrading it with gold raises the odds of higher tiers; the Catalogue lists every unit and the current odds.
- Colliding with an enemy damages both sides. Rammers take half the collision damage and hit much harder.

**Play in the browser:** https://ianbedard.github.io/plotline/

## Controls

| Key | Action |
| --- | --- |
| A / D or Left / Right | Steer |
| Space | Start a run / start the next level |
| R | Reroll the shop |
| U | Upgrade the shop |
| C | Open / close the catalogue |
| Right-click a unit | Sell it |
| P or Esc | Pause |

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
