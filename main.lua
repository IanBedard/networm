-- NETWORM - a kernel worm auto-battler. (LOVE 11.x)
-- Steer a line of heroes that fight on their own. Recruit between
-- levels, stack copies to rank them up, and combine classes for set bonuses.

local lg = love.graphics
local rand = love.math.random

local W, H = 960, 540
local AR = {x1 = 24, y1 = 50, x2 = 936, y2 = 524}
local UR = 8              -- unit collision radius
local SPACING = 24        -- distance between worm segments
local WORM_SPEED = 150
local TURN_SPEED = 4.2
local MAX_LEVEL = 25
local DMG_LV = {1, 1.9, 3.2}
local HP_LV = {1, 1.5, 2.2}
local HP_SCALE = 0.5      -- heroes are fragile: every unit's listed HP is halved in combat
local HEAL_LV = {1, 1.4, 1.9}
local COST = {1, 2, 4, 6}
local REROLL_COST = 1

local scale, ox, oy = 1, 0, 0
local fonts = {}
local FONT_SIZES = {s = 11, m = 14, l = 22, xl = 56}
local FONT_FILE = 'font/RobotoMono.ttf'
local state = 'menu'
local run, arena
local paused = false
local time = 0

---------------------------------------------------------------------------
-- utils
---------------------------------------------------------------------------
local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
local function lerp(a, b, t) return a + (b - a) * t end
local function rr(a, b) return a + (b - a) * rand() end
local function dist(x1, y1, x2, y2) local dx, dy = x2 - x1, y2 - y1; return math.sqrt(dx * dx + dy * dy) end
local function norm(x, y) local l = math.sqrt(x * x + y * y); if l < 1e-6 then return 0, 0 end; return x / l, y / l end
local function choice(t) return t[rand(#t)] end
local function angleTo(a, b) return math.atan2(b.y - a.y, b.x - a.x) end
local function inRect(px, py, r) return px >= r.x and px <= r.x + r.w and py >= r.y and py <= r.y + r.h end
local function hex(s, a)
  return {tonumber(s:sub(1, 2), 16) / 255, tonumber(s:sub(3, 4), 16) / 255, tonumber(s:sub(5, 6), 16) / 255, a or 1}
end
local function setc(c, a) lg.setColor(c[1], c[2], c[3], (c[4] or 1) * (a or 1)) end

-- terminal palette: near-black screen, phosphor-green text, amber money, panic-red enemies
local COL = {
  bg = hex('060908'), card = hex('0b120e'), hover = hex('122219'), grid = hex('15251b'),
  line = hex('224432'), light = hex('2f5440'), mid = hex('7fb894'), dim = hex('4d7d5f'),
  ink = hex('c9f7d4'), text = hex('c9f7d4'), dark = hex('060908'), white = {1, 1, 1, 1},
  pink = hex('ff3b5c'), pinkSoft = hex('3a1219'), mintText = hex('5af78e'), mintSoft = hex('0f2a18'),
  green = hex('5af78e'), red = hex('ff3b5c'), gold = hex('ffc777'), purple = hex('bb9af7'), coin = hex('ffc777'),
  cyan = hex('57c7ff'),
}

-- Fonts are rasterised at window scale and drawn at 1/scale so text stays crisp.
local function makeFonts()
  for k, sz in pairs(FONT_SIZES) do
    local px = math.max(1, math.floor(sz * scale + 0.5))
    fonts[k] = love.filesystem.getInfo(FONT_FILE) and lg.newFont(FONT_FILE, px) or lg.newFont(px)
  end
end
local function text(str, x, y, f, align, limit)
  lg.setFont(fonts[f or 'm'])
  local inv = 1 / scale
  if align then
    lg.printf(str, x, y, (limit or 200) * scale, align, 0, inv, inv)
  else
    lg.print(str, x, y, 0, inv, inv)
  end
end
local function textW(str, f) return fonts[f or 'm']:getWidth(str) / scale end
local function ctext(str, cx, y, f) text(str, cx - 600, y, f, 'center', 1200) end

local function resize(w, h)
  scale = math.min(w / W, h / H)
  ox = math.floor((w - W * scale) / 2)
  oy = math.floor((h - H * scale) / 2)
  makeFonts()
end
local function getMouse()
  local mx, my = love.mouse.getPosition()
  return (mx - ox) / scale, (my - oy) / scale
end

---------------------------------------------------------------------------
-- sound (synthesised at load)
---------------------------------------------------------------------------
local sfx = {}
local function makeSound(name, dur, vol, gen)
  local rate = 22050
  local n = math.floor(dur * rate)
  local sd = love.sound.newSoundData(n, rate, 16, 1)
  local st = {phase = 0, lp = 0}
  for i = 0, n - 1 do
    local t = i / n
    sd:setSample(i, clamp(gen(st, t, rate) * (1 - t) ^ 1.5 * vol, -1, 1))
  end
  sfx[name] = {src = love.audio.newSource(sd, 'static'), last = 0}
end
local function sq(st, f, rate) st.phase = (st.phase + f / rate) % 1; return st.phase < 0.5 and 1 or -1 end
local function sine(st, f, rate) st.phase = (st.phase + f / rate) % 1; return math.sin(st.phase * 2 * math.pi) end
local function noise(st, k) st.lp = st.lp + ((rand() * 2 - 1) - st.lp) * k; return st.lp end

local function initSounds()
  makeSound('shoot', 0.06, 0.10, function(st, t, r) return sq(st, lerp(900, 400, t), r) end)
  makeSound('hit', 0.05, 0.18, function(st) return noise(st, 0.6) end)
  makeSound('explode', 0.35, 0.45, function(st) return noise(st, 0.08) * 1.6 end)
  makeSound('hurt', 0.15, 0.18, function(st, t, r) return sq(st, lerp(300, 100, t), r) end)
  makeSound('die', 0.2, 0.25, function(st, t, r) return noise(st, 0.3) * 0.7 + sq(st, lerp(400, 80, t), r) * 0.15 end)
  makeSound('heal', 0.2, 0.15, function(st, t, r) return sine(st, lerp(500, 1000, t), r) end)
  makeSound('buy', 0.16, 0.2, function(st, t, r) return sine(st, t < 0.5 and 660 or 990, r) end)
  makeSound('wall', 0.12, 0.4, function(st, t, r) return sine(st, lerp(140, 60, t), r) end)
  makeSound('click', 0.03, 0.12, function(st, t, r) return sq(st, 1200, r) end)
  makeSound('error', 0.12, 0.15, function(st, t, r) return sq(st, 140, r) end)
  makeSound('boss', 0.5, 0.3, function(st, t, r) return sq(st, lerp(90, 40, t), r) * 0.5 + noise(st, 0.05) end)
end
local function play(name, pitch)
  local s = sfx[name]
  if not s then return end
  local now = love.timer.getTime()
  if now - s.last < 0.04 then return end
  s.last = now
  local c = s.src:clone()
  c:setPitch((pitch or 1) * rr(0.92, 1.08))
  c:play()
end

---------------------------------------------------------------------------
-- classes
---------------------------------------------------------------------------
-- internal keys stay generic; display names are Embercoil's own
local CLASSES = {
  warrior  = {name = 'Guardian',   color = hex('7aa2f7'), tiers = {2, 4}, desc = {'Guardians take 25% less damage', 'Guardians take 50% less damage'}},
  ranger   = {name = 'Marksman',   color = hex('5af78e'), tiers = {2, 4}, desc = {'Marksmen attack 25% faster', 'Marksmen attack 50% faster'}},
  mage     = {name = 'Arcanist',   color = hex('bb9af7'), tiers = {2, 4}, desc = {'Arcanists deal +30% damage', 'Arcanists deal +60% damage'}},
  rogue    = {name = 'Cutthroat',  color = hex('ff9e64'), tiers = {2, 4}, desc = {'Cutthroats: 15% crit chance (x3)', 'Cutthroats: 30% crit chance (x3)'}},
  healer   = {name = 'Sage',       color = hex('5ef1d0'), tiers = {1, 2}, desc = {'Healing +50%', 'Healing +100%'}},
  nuker    = {name = 'Demolisher', color = hex('f7f76a'), tiers = {2, 4}, desc = {'Demolisher blasts +30% size', 'Demolisher blasts +60% size'}},
  conjurer = {name = 'Artificer',  color = hex('57c7ff'), tiers = {1, 2}, desc = {'Gadgets +50% dmg & duration', 'Gadgets +100% dmg & duration'}},
  voider   = {name = 'Hexer',      color = hex('f38cf0'), tiers = {2, 4}, desc = {'Damage over time +50%', 'Damage over time +100%'}},
  enforcer = {name = 'Bruiser',    color = hex('a9b1d6'), tiers = {2, 4}, desc = {'All units +15% max HP', 'All units +30% max HP'}},
}
CLASSES.rammer = {name = 'Rammer', color = hex('f0f0f0'), tiers = {2, 4}, desc = {'Rams +50% dmg, -70% hit damage', 'Rams +100% dmg, -85% hit damage'}}
CLASSES.merchant = {name = 'Merchant', color = hex('ffc777'), tiers = {2, 4}, desc = {'Enemies: 6% chance to drop a coin', '15% coin drops, +2 max interest'}}
local CLASS_ORDER = {'warrior', 'ranger', 'mage', 'rogue', 'healer', 'nuker', 'conjurer', 'voider', 'enforcer', 'rammer', 'merchant'}

---------------------------------------------------------------------------
-- combat helpers (used by unit attacks)
---------------------------------------------------------------------------
local spawnEnemy

local function addText(x, y, s, c, big)
  local t = arena.texts
  t[#t + 1] = {x = x, y = y, s = s, c = c or COL.ink, life = 0.7, max = 0.7, big = big}
end
local function burst(x, y, c, n, spd, size)
  for i = 1, n do
    local a, v = rr(0, math.pi * 2), rr(spd * 0.3, spd)
    local life = rr(0.25, 0.6)
    arena.parts[#arena.parts + 1] = {x = x, y = y, vx = math.cos(a) * v, vy = math.sin(a) * v, life = life, max = life, c = c, s = size or rr(2, 4)}
  end
end
local function shake(a) arena.shake = math.max(arena.shake, a) end

local function nearestEnemy(x, y, range, skip)
  local best, bd = nil, range or 1e9
  for _, e in ipairs(arena.enemies) do
    if not e.dead and not (skip and skip[e]) then
      local d = dist(x, y, e.x, e.y) - e.r
      if d < bd then best, bd = e, d end
    end
  end
  return best
end

local function nearestUnit(x, y)
  local best, bd = nil, 1e9
  for _, u in ipairs(arena.alive) do
    local d = dist(x, y, u.x, u.y)
    if d < bd then best, bd = u, d end
  end
  return best, bd
end

local function killEnemy(e, src)
  e.dead = true
  arena.kills = arena.kills + 1
  if rand() < arena.coinChance + (src and src.coinOnKill or 0) then
    arena.coins[#arena.coins + 1] = {x = e.x, y = e.y, life = 10, value = 1}
  end
  local boss = e.type == 'boss'
  burst(e.x, e.y, e.d.color, boss and 80 or 12, boss and 320 or 180)
  play(boss and 'boss' or 'die')
  shake(boss and 14 or 2)
  if e.type == 'splitter' then
    for i = 1, 2 do
      local m = spawnEnemy('mini', e.x + rr(-6, 6), e.y + rr(-6, 6))
      m.kx, m.ky, m.spawnT = rr(-160, 160), rr(-160, 160), 0.2
    end
  end
end

local function damageEnemy(e, dmg, src, opt)
  if e.dead then return end
  local crit = false
  if src and src.crit > 0 and not (opt and opt.nocrit) and rand() < src.crit then dmg = dmg * 3; crit = true end
  e.hp = e.hp - dmg
  e.flash = 0.1
  addText(e.x + rr(-6, 6), e.y - e.r - 4, tostring(math.floor(dmg + 0.5)), crit and COL.gold or (opt and opt.color) or COL.mid, crit)
  if e.hp <= 0 then killEnemy(e, src) end
end

local function applyDot(e, total, dur, src)
  e.dots[#e.dots + 1] = {dps = total / dur * (src and src.dotm or 1), t = dur, tick = 0.3}
end

local function shootFrom(x, y, angle, o)
  local spd = o.speed or 320
  arena.projs[#arena.projs + 1] = {
    x = x, y = y, vx = math.cos(angle) * spd, vy = math.sin(angle) * spd, r = o.r or 4,
    dmg = o.dmg or o.src.dmg, src = o.src, color = o.color or o.src.color, pierce = o.pierce or 0,
    chain = o.chain or 0, explode = o.explode, dot = o.dot, stun = o.stun, life = o.life or 1.6, hit = {}, shape = o.shape,
  }
end
local function shoot(u, angle, o)
  o = o or {}
  o.src = u
  shootFrom(u.x, u.y, angle, o)
end

local function blast(x, y, r, dmg, src, o)
  o = o or {}
  arena.areas[#arena.areas + 1] = {
    x = x, y = y, r = r, dmg = dmg, src = src, delay = o.delay or 0, dur = o.dur or 0, ling = (o.dur or 0) > 0,
    tick = o.tick or 0.5, tt = 0, color = o.color or (src and src.color) or COL.white, stun = o.stun,
    knock = o.knock, age = 0, fired = false, faint = o.faint, nocrit = o.nocrit, maxdelay = o.delay or 0,
    visual = o.visual,  -- enemy effects: drawn like a blast but never hurt enemies
  }
end

local function summon(kind, x, y, src, o)
  arena.summons[#arena.summons + 1] = {
    kind = kind, x = x, y = y, src = src, a = rr(0, 6.28), cd = 0,
    life = (o.life or 6) * src.summonm, dmg = (o.dmg or src.dmg) * src.summonm, explode = o.explode,
  }
end

local function healUnit(u, amt, src)
  if u.dead then return end
  amt = amt * (src and src.healm or 1)
  local before = u.hp
  u.hp = math.min(u.maxhp, u.hp + amt)
  if u.hp > before then
    addText(u.x, u.y - 14, '+' .. math.floor(u.hp - before + 0.5), COL.green)
    burst(u.x, u.y, COL.green, 5, 60, 2)
  end
end

local function enemyShoot(x, y, a, spd, dmg)
  arena.eprojs[#arena.eprojs + 1] = {x = x, y = y, vx = math.cos(a) * spd, vy = math.sin(a) * spd, r = 5, dmg = dmg, life = 6}
end

---------------------------------------------------------------------------
-- units
---------------------------------------------------------------------------
local UNITS = {
  -- tier 1
  vagrant = {name = 'Drifter', tier = 1, classes = {'warrior', 'ranger'}, hp = 110, dmg = 10, cd = 1.0, range = 260,
    desc = 'Shoots a projectile at the nearest enemy.',
    attack = function(u, t) shoot(u, angleTo(u, t), {speed = 340}); return true end},
  swordsman = {name = 'Bladewarden', tier = 1, classes = {'warrior'}, hp = 150, dmg = 16, cd = 1.6, range = 55, aoe = true,
    desc = 'Slashes all nearby enemies.',
    attack = function(u) blast(u.x, u.y, 55 * u.aream, u.dmg, u); return true end},
  archer = {name = 'Longshot', tier = 1, classes = {'ranger'}, hp = 90, dmg = 12, cd = 1.3, range = 320,
    desc = 'Fires an arrow that pierces through 3 enemies.',
    attack = function(u, t) shoot(u, angleTo(u, t), {speed = 480, pierce = 3, shape = 'arrow'}); return true end},
  wizard = {name = 'Emberwright', tier = 1, classes = {'mage'}, hp = 90, dmg = 10, cd = 1.4, range = 280,
    desc = 'Casts a bolt that explodes on impact.',
    attack = function(u, t) shoot(u, angleTo(u, t), {speed = 300, explode = 32, r = 5}); return true end},
  scout = {name = 'Ricochet', tier = 1, classes = {'rogue'}, hp = 95, dmg = 9, cd = 1.1, range = 260,
    desc = 'Throws a knife that chains between 3 enemies.',
    attack = function(u, t) shoot(u, angleTo(u, t), {speed = 420, chain = 3, shape = 'knife'}); return true end},
  cleric = {name = 'Mender', tier = 1, classes = {'healer'}, hp = 100, dmg = 0, cd = 4.5, noTarget = true, silent = true,
    desc = 'Heals the most injured ally for 25% of its max HP.',
    attack = function(u)
      local best, br = nil, 0.999
      for _, o in ipairs(arena.alive) do
        local r = o.hp / o.maxhp
        if r < br then best, br = o, r end
      end
      if not best then return false end
      healUnit(best, best.maxhp * 0.25 * HEAL_LV[u.lv], u)
      play('heal')
      return true
    end},

  -- tier 2
  outlaw = {name = 'Fanblade', tier = 2, classes = {'warrior', 'rogue'}, hp = 130, dmg = 8, cd = 1.8, range = 230,
    desc = 'Throws a fan of 5 knives.',
    attack = function(u, t)
      local a = angleTo(u, t)
      for i = -2, 2 do shoot(u, a + i * 0.2, {speed = 380, shape = 'knife'}) end
      return true
    end},
  pyromancer = {name = 'Cinderheart', tier = 2, classes = {'mage', 'nuker'}, hp = 110, dmg = 5, cd = 0.45, range = 60, aoe = true, silent = true,
    desc = 'Constantly burns all enemies around it.',
    attack = function(u) blast(u.x, u.y, 60 * u.aream, u.dmg, u, {faint = true}); return true end},
  barbarian = {name = 'Quakefist', tier = 2, classes = {'warrior', 'enforcer'}, hp = 170, dmg = 14, cd = 3.2, range = 70, aoe = true,
    desc = 'Stomps the ground, damaging and stunning nearby enemies.',
    attack = function(u) blast(u.x, u.y, 70 * u.aream, u.dmg, u, {stun = 1.2}); shake(3); return true end},
  sentry = {name = 'Tinkerer', tier = 2, classes = {'ranger', 'conjurer'}, hp = 100, dmg = 7, cd = 7, noTarget = true,
    desc = 'Deploys a turret that shoots nearby enemies for 6s.',
    attack = function(u) summon('turret', u.x, u.y, u, {life = 6}); return true end},
  witch = {name = 'Hexweaver', tier = 2, classes = {'voider', 'mage'}, hp = 100, dmg = 6, cd = 1.5, range = 280,
    desc = 'Hexes an enemy, dealing heavy damage over time.',
    attack = function(u, t) shoot(u, angleTo(u, t), {speed = 300, dot = u.dmg * 5, r = 5, color = COL.purple}); return true end},
  saboteur = {name = 'Fusewick', tier = 2, classes = {'rogue', 'conjurer'}, hp = 100, dmg = 22, cd = 4, range = 320,
    desc = 'Lights 2 fuse-imps that run at enemies and explode.',
    attack = function(u) for i = 1, 2 do summon('bomber', u.x, u.y, u, {life = 5}) end; return true end},

  -- tier 3
  cannoneer = {name = 'Bombardier', tier = 3, classes = {'ranger', 'nuker'}, hp = 130, dmg = 34, cd = 2.8, range = 340,
    desc = 'Fires a cannonball that explodes in a large area.',
    attack = function(u, t) shoot(u, angleTo(u, t), {speed = 280, explode = 62, r = 7}); return true end},
  elementor = {name = 'Stormcaller', tier = 3, classes = {'mage', 'nuker'}, hp = 120, dmg = 36, cd = 3.2, range = 340,
    desc = 'Calls lightning on an enemy, blasting a large area.',
    attack = function(u, t) blast(t.x, t.y, 58 * u.aream, u.dmg, u, {delay = 0.35, stun = 0.3}); return true end},
  juggernaut = {name = 'Bulwark', tier = 3, classes = {'warrior', 'enforcer'}, hp = 260, dmg = 22, cd = 3.5, range = 85, aoe = true,
    desc = 'Unleashes a shockwave that hurls enemies away.',
    attack = function(u) blast(u.x, u.y, 95 * u.aream, u.dmg, u, {knock = 520, stun = 0.4}); shake(5); return true end},
  priest = {name = 'Lightkeeper', tier = 3, classes = {'healer'}, hp = 120, dmg = 0, cd = 7, noTarget = true, silent = true,
    desc = 'Heals all allies for 20% of their max HP.',
    attack = function(u)
      local any = false
      for _, o in ipairs(arena.alive) do if o.hp < o.maxhp then any = true end end
      if not any then return false end
      for _, o in ipairs(arena.alive) do healUnit(o, o.maxhp * 0.2 * HEAL_LV[u.lv], u) end
      play('heal')
      return true
    end},
  plaguedoctor = {name = 'Miasmist', tier = 3, classes = {'nuker', 'voider'}, hp = 120, dmg = 7, cd = 5, range = 300,
    desc = 'Creates a toxic cloud that hurts enemies inside for 4s.',
    attack = function(u, t)
      blast(t.x, t.y, 60 * u.aream, u.dmg * u.dotm, u, {dur = 4, tick = 0.35, color = COL.purple, nocrit = true})
      return true
    end},
  assassin = {name = 'Nightblade', tier = 3, classes = {'rogue', 'voider'}, hp = 120, dmg = 30, cd = 2.4, range = 320, critBonus = 0.2,
    desc = 'Throws a piercing poisoned blade. +20% crit chance.',
    attack = function(u, t) shoot(u, angleTo(u, t), {speed = 560, pierce = 99, dot = u.dmg * 1.5, shape = 'knife', r = 5}); return true end},

  -- more tier 1-3
  pikeguard = {name = 'Pikeguard', tier = 1, classes = {'warrior', 'enforcer'}, hp = 160, dmg = 14, cd = 1.5, range = 60,
    desc = 'Thrusts a pike forward, knocking enemies back.',
    attack = function(u, t)
      local a = angleTo(u, t)
      blast(u.x + math.cos(a) * 26, u.y + math.sin(a) * 26, 30 * u.aream, u.dmg, u, {knock = 220})
      return true
    end},
  slinger = {name = 'Slinger', tier = 1, classes = {'ranger', 'rogue'}, hp = 85, dmg = 6, cd = 0.9, range = 260,
    desc = 'Hurls two quick stones at the nearest enemy.',
    attack = function(u, t)
      local a = angleTo(u, t)
      shoot(u, a - 0.08, {speed = 380})
      shoot(u, a + 0.08, {speed = 380})
      return true
    end},
  frostbinder = {name = 'Frostbinder', tier = 2, classes = {'mage', 'enforcer'}, hp = 120, dmg = 12, cd = 2.6, range = 280,
    desc = 'Fires a frost orb that bursts and freezes for 1s.',
    attack = function(u, t) shoot(u, angleTo(u, t), {speed = 280, explode = 40, stun = 1, r = 6}); return true end},
  soulmender = {name = 'Soulmender', tier = 2, classes = {'healer', 'voider'}, hp = 110, dmg = 6, cd = 4, noTarget = true, silent = true,
    desc = 'Heals the weakest ally 15% and curses an enemy.',
    attack = function(u)
      local did, best, br = false, nil, 0.999
      for _, o in ipairs(arena.alive) do
        local r = o.hp / o.maxhp
        if r < br then best, br = o, r end
      end
      if best then healUnit(best, best.maxhp * 0.15 * HEAL_LV[u.lv], u); did = true end
      local t = nearestEnemy(u.x, u.y, 260)
      if t then applyDot(t, u.dmg * 4, 3, u); burst(t.x, t.y, COL.purple, 6, 80, 2); did = true end
      if did then play('heal') end
      return did
    end},
  volleymaster = {name = 'Volleymaster', tier = 3, classes = {'ranger', 'warrior'}, hp = 150, dmg = 14, cd = 2.6, range = 200,
    desc = 'Looses a ring of 10 arrows that each pierce one enemy.',
    attack = function(u)
      local off = rr(0, math.pi * 2)
      for i = 1, 10 do shoot(u, off + i / 10 * math.pi * 2, {speed = 420, pierce = 1, shape = 'arrow'}) end
      return true
    end},
  clockwright = {name = 'Clockwright', tier = 3, classes = {'conjurer', 'nuker'}, hp = 120, dmg = 12, cd = 8, noTarget = true,
    desc = 'Builds 2 mortar turrets whose shots explode, for 6s.',
    attack = function(u)
      for i = 1, 2 do summon('turret', u.x + rr(-20, 20), u.y + rr(-20, 20), u, {life = 6, explode = 30}) end
      return true
    end},

  -- rammers: built to hit enemies with their body; collisions hurt them half as much
  tusker = {name = 'Tusker', tier = 1, classes = {'rammer', 'warrior'}, hp = 170, dmg = 0, ram = 30, cd = 1, noAttack = true,
    desc = 'Rams hard. Takes half damage from collisions.'},
  spikeback = {name = 'Spikeback', tier = 1, classes = {'rammer', 'enforcer'}, hp = 150, dmg = 10, ram = 20, cd = 2, range = 40, aoe = true, silent = true,
    desc = 'Rams, and its spikes hit everything adjacent.',
    attack = function(u) blast(u.x, u.y, 38 * u.aream, u.dmg, u, {faint = true}); return true end},
  ironhorn = {name = 'Ironhorn', tier = 2, classes = {'rammer', 'enforcer'}, hp = 200, dmg = 0, ram = 45, ramStun = 1, cd = 1, noAttack = true,
    desc = 'Rams so hard that enemies are stunned for 1s.'},
  avalanche = {name = 'Avalanche', tier = 3, classes = {'rammer', 'warrior'}, hp = 260, dmg = 0, ram = 70, ramSplash = 55, cd = 1, noAttack = true,
    desc = 'Each ram sends a shockwave through nearby enemies.'},

  -- merchants: earn money
  peddler = {name = 'Peddler', tier = 1, classes = {'merchant'}, hp = 100, dmg = 7, cd = 1.2, range = 240, levelGold = {1, 2, 3},
    desc = 'Pelts enemies. Earns $1/$2/$3 extra each level.',
    attack = function(u, t) shoot(u, angleTo(u, t), {speed = 320}); return true end},
  pickpocket = {name = 'Pickpocket', tier = 1, classes = {'merchant', 'rogue'}, hp = 95, dmg = 8, cd = 1, range = 220, coinOnKill = {0.15, 0.22, 0.3},
    desc = 'Throws knives. Enemies it kills often drop a coin.',
    attack = function(u, t) shoot(u, angleTo(u, t), {speed = 420, shape = 'knife'}); return true end},
  banker = {name = 'Banker', tier = 2, classes = {'merchant', 'enforcer'}, hp = 170, dmg = 9, cd = 1.4, range = 240, interestCap = {2, 3, 4},
    desc = 'Tosses coins at enemies. Raises max interest by 2/3/4.',
    attack = function(u, t) shoot(u, angleTo(u, t), {speed = 300, r = 5, color = COL.coin}); return true end},
  bountyhunter = {name = 'Bounty Hunter', tier = 2, classes = {'merchant', 'ranger'}, hp = 110, dmg = 16, cd = 1.6, range = 320, coinOnKill = {0.25, 0.35, 0.45},
    desc = 'Fires piercing shots. Enemies it kills often drop a coin.',
    attack = function(u, t) shoot(u, angleTo(u, t), {speed = 520, pierce = 2, shape = 'arrow'}); return true end},
  taxcollector = {name = 'Tax Collector', tier = 3, classes = {'merchant', 'warrior'}, hp = 220, dmg = 22, cd = 1.8, range = 60, aoe = true, killGold = {12, 9, 6},
    desc = 'Swings at nearby enemies. +$1 per 12/9/6 kills.',
    attack = function(u) blast(u.x, u.y, 60 * u.aream, u.dmg, u); return true end},

  -- tier 4
  tycoon = {name = 'Tycoon', tier = 4, classes = {'merchant', 'mage'}, hp = 150, dmg = 20, cd = 1.6, range = 320, levelGold = {2, 3, 4},
    desc = 'Exploding gold: +2 dmg per $ held. +$2-4 a level.',
    attack = function(u, t)
      shoot(u, angleTo(u, t), {speed = 360, r = 6, explode = 34, color = COL.coin, dmg = u.dmg + run.gold * 2 * DMG_LV[u.lv]})
      return true
    end},
  colossus = {name = 'Colossus', tier = 4, classes = {'rammer', 'enforcer'}, hp = 380, dmg = 0, ram = 120, ramSplash = 70, ramStun = 1, cd = 1, noAttack = true,
    desc = 'Living battering ram: huge rams, shockwave, stun.'},
  archmage = {name = 'Archmage', tier = 4, classes = {'mage', 'nuker'}, hp = 140, dmg = 40, cd = 4, range = 360,
    desc = 'Rains 5 meteors on enemies in range.',
    attack = function(u)
      local pool = {}
      for _, e in ipairs(arena.enemies) do
        if not e.dead and dist(u.x, u.y, e.x, e.y) < 360 then pool[#pool + 1] = e end
      end
      if #pool == 0 then return false end
      for i = 1, 5 do
        local e = choice(pool)
        blast(e.x + rr(-12, 12), e.y + rr(-12, 12), 50 * u.aream, u.dmg, u, {delay = 0.3 + i * 0.12})
      end
      return true
    end},
  warlord = {name = 'Warlord', tier = 4, classes = {'warrior', 'enforcer'}, hp = 320, dmg = 40, cd = 4, range = 110, aoe = true,
    desc = 'Slams the ground, stunning and hurling enemies.',
    attack = function(u) blast(u.x, u.y, 120 * u.aream, u.dmg, u, {stun = 1.5, knock = 400}); shake(7); return true end},
  deadeye = {name = 'Deadeye', tier = 4, classes = {'ranger', 'rogue'}, hp = 130, dmg = 90, cd = 3, range = 450, critBonus = 0.3,
    desc = 'Snipes through every enemy in a line. +30% crit chance.',
    attack = function(u, t) shoot(u, angleTo(u, t), {speed = 900, pierce = 99, shape = 'arrow', life = 1}); return true end},
  voidcaller = {name = 'Voidcaller', tier = 4, classes = {'voider', 'conjurer'}, hp = 140, dmg = 10, cd = 6, range = 320,
    desc = 'Opens a rift that drags enemies in and drains them for 3s.',
    attack = function(u, t)
      blast(t.x, t.y, 75 * u.aream, u.dmg * u.dotm * u.summonm, u,
        {dur = 3 * u.summonm, tick = 0.3, knock = -140, color = COL.purple, nocrit = true})
      return true
    end},
  dawnbringer = {name = 'Dawnbringer', tier = 4, classes = {'healer', 'mage'}, hp = 150, dmg = 24, cd = 5, noTarget = true, silent = true,
    desc = 'Heals all allies 15% and sears enemies around the line.',
    attack = function(u)
      for _, o in ipairs(arena.alive) do healUnit(o, o.maxhp * 0.15 * HEAL_LV[u.lv], u) end
      blast(u.x, u.y, 100 * u.aream, u.dmg, u)
      play('heal')
      return true
    end},
}

local UNIT_TIERS = {{}, {}, {}, {}}
for _, k in ipairs({'vagrant', 'swordsman', 'archer', 'wizard', 'scout', 'cleric', 'pikeguard', 'slinger', 'tusker', 'spikeback',
                    'outlaw', 'pyromancer', 'barbarian', 'sentry', 'witch', 'saboteur', 'frostbinder', 'soulmender', 'ironhorn',
                    'cannoneer', 'elementor', 'juggernaut', 'priest', 'plaguedoctor', 'assassin', 'volleymaster', 'clockwright', 'avalanche',
                    'archmage', 'warlord', 'deadeye', 'voidcaller', 'dawnbringer', 'colossus',
                    'peddler', 'pickpocket', 'banker', 'bountyhunter', 'taxcollector', 'tycoon'}) do
  UNITS[k].key = k
  table.insert(UNIT_TIERS[UNITS[k].tier], k)
end

-- each hero is its own shade of its main class colour, from darker to lighter
local function lum(c) return 0.299 * c[1] + 0.587 * c[2] + 0.114 * c[3] end
do
  local byClass = {}
  for _, tier in ipairs(UNIT_TIERS) do
    for _, k in ipairs(tier) do
      local cl = UNITS[k].classes[1]
      byClass[cl] = byClass[cl] or {}
      table.insert(byClass[cl], UNITS[k])
    end
  end
  for cl, list in pairs(byClass) do
    local base = CLASSES[cl].color
    for i, d in ipairs(list) do
      local k = #list == 1 and 0 or lerp(-0.28, 0.3, (i - 1) / (#list - 1))
      if k < 0 then
        d.color = {base[1] * (1 + k), base[2] * (1 + k), base[3] * (1 + k), 1}
      else
        d.color = {lerp(base[1], 1, k), lerp(base[2], 1, k), lerp(base[3], 1, k), 1}
      end
    end
  end
end

---------------------------------------------------------------------------
-- run / party
---------------------------------------------------------------------------
local function maxUnits(l) return math.min(8, 3 + math.floor((l - 1) / 3)) end
local function nextSlotLevel(l)
  for k = l + 1, MAX_LEVEL do
    if maxUnits(k) > maxUnits(l) then return k end
  end
end
local function isBoss(l) return l % 6 == 0 or l == MAX_LEVEL end
local function hpScale(l) return 1 + 0.2 * (l - 1) + 0.015 * (l - 1) ^ 2 end
local function memberLevel(m) return m.copies >= 9 and 3 or (m.copies >= 3 and 2 or 1) end
local function sellValue(m) return math.max(1, math.floor(COST[m.def.tier] * m.copies / 2)) end

local function classCounts()
  local c = {}
  for _, m in ipairs(run.party) do
    for _, cl in ipairs(m.def.classes) do c[cl] = (c[cl] or 0) + 1 end
  end
  return c
end
local function classTier(counts, cl)
  local n, t = counts[cl] or 0, CLASSES[cl].tiers
  if n >= t[2] then return 2 elseif n >= t[1] then return 1 end
  return 0
end

-- the shop is levelled up with gold; each level shifts the tier odds upward
local SHOP_MAX = 5
local SHOP_UP_COST = {4, 8, 12, 16}
local SHOP_ODDS = {
  {1, 0, 0, 0},
  {0.7, 0.3, 0, 0},
  {0.45, 0.4, 0.15, 0},
  {0.3, 0.4, 0.25, 0.05},
  {0.2, 0.35, 0.3, 0.15},
}
local function rollOffers()
  local o = SHOP_ODDS[run.shopLevel]
  local top = 1
  for k = 1, 4 do if o[k] > 0 then top = k end end
  for i = 1, 4 do
    local r, tier = rand(), top
    for k = 1, top do
      if r < o[k] then tier = k; break end
      r = r - o[k]
    end
    run.offers[i] = choice(UNIT_TIERS[tier])
  end
end
local function findMember(key)
  for i, m in ipairs(run.party) do if m.key == key then return m, i end end
end
local function shopMsg(s, c) run.msg = {s = s, c = c or COL.text, t = 2} end

local function newRun()
  run = {gold = 4, level = 1, shopLevel = 1, party = {}, offers = {}}
  rollOffers()
  state = 'shop'
end

local function buyOffer(i)
  local key = run.offers[i]
  if not key then return end
  local def = UNITS[key]
  local cost = COST[def.tier]
  local m = findMember(key)
  if run.gold < cost then play('error'); shopMsg('Not enough gold!', COL.red); return end
  if m then
    if m.copies >= 9 then play('error'); shopMsg(def.name .. ' is already max level', COL.red); return end
    local before = memberLevel(m)
    m.copies = m.copies + 1
    if memberLevel(m) > before then shopMsg(def.name .. ' reached level ' .. memberLevel(m) .. '!', COL.gold) end
  else
    if #run.party >= maxUnits(run.level) then
      local ns = nextSlotLevel(run.level)
      play('error')
      shopMsg('Party is full - sell a unit first' .. (ns and (' (next slot at level ' .. ns .. ')') or ''), COL.red)
      return
    end
    run.party[#run.party + 1] = {key = key, def = def, copies = 1}
  end
  run.gold = run.gold - cost
  run.offers[i] = false
  play('buy')
end

local function sellMember(i)
  local m = run.party[i]
  if not m then return end
  run.gold = run.gold + sellValue(m)
  table.remove(run.party, i)
  play('click')
  shopMsg('Sold ' .. m.def.name .. ' for $' .. sellValue(m))
end

local function moveMember(i, dir)
  local j = i + dir
  if j < 1 or j > #run.party then return end
  run.party[i], run.party[j] = run.party[j], run.party[i]
  play('click')
end

---------------------------------------------------------------------------
-- enemies
---------------------------------------------------------------------------
local ENEMIES = {
  seeker   = {hp = 22,  r = 9,  speed = 55, dmg = 10, color = hex('ff3b5c')},
  shooter  = {hp = 18,  r = 9,  speed = 45, dmg = 8,  color = hex('ff6b4a')},
  charger  = {hp = 30,  r = 10, speed = 40, dmg = 14, color = hex('ff1f4b')},
  tank     = {hp = 90,  r = 15, speed = 28, dmg = 18, color = hex('c9184a')},
  splitter = {hp = 35,  r = 11, speed = 48, dmg = 10, color = hex('ff8fa3')},
  mini     = {hp = 10,  r = 6,  speed = 75, dmg = 6,  color = hex('ffb3c1')},
  boss     = {hp = 900, r = 26, speed = 35, dmg = 25, color = hex('ff3b5c')},
  kamikaze = {hp = 14,  r = 7,  speed = 95, dmg = 10, color = hex('ff006e')},   -- rushes in, arms, explodes
  repulsor = {hp = 45,  r = 12, speed = 35, dmg = 8,  color = hex('e5383b')},   -- pulses a shockwave that shoves the worm
  sniper   = {hp = 20,  r = 9,  speed = 40, dmg = 16, color = hex('ff9e80')},   -- aims a long laser-sighted shot
}

function spawnEnemy(tp, x, y)
  local d, l = ENEMIES[tp], run.level
  local e = {
    type = tp, d = d, x = clamp(x, AR.x1 + 10, AR.x2 - 10), y = clamp(y, AR.y1 + 10, AR.y2 - 10),
    vx = 0, vy = 0, kx = 0, ky = 0, r = d.r, hp = d.hp * hpScale(l),
    speed = d.speed * (1 + 0.012 * l) * rr(0.9, 1.1), dmg = d.dmg * (1 + 0.08 * (l - 1)),
    flash = 0, stun = 0, dots = {}, ccd = 0, spawnT = 0.4, a = rr(0, 6.28),
    st = rr(1, 2.5), cs = 'walk', ct = rr(1.5, 3), bt = 2.5,
  }
  if tp == 'boss' and l == MAX_LEVEL then e.hp = e.hp * 1.6; e.r = 32 end
  e.maxhp = e.hp
  arena.enemies[#arena.enemies + 1] = e
  return e
end

local function pickEnemyType(l)
  local pool = {'seeker', 'seeker', 'seeker'}
  if l >= 3 then pool[#pool + 1] = 'shooter' end
  if l >= 5 then pool[#pool + 1] = 'charger' end
  if l >= 8 then pool[#pool + 1] = 'tank' end
  if l >= 10 then pool[#pool + 1] = 'splitter' end
  if l >= 14 then pool[#pool + 1] = 'shooter'; pool[#pool + 1] = 'charger'; pool[#pool + 1] = 'tank' end
  if l >= 4 then pool[#pool + 1] = 'kamikaze' end
  if l >= 7 then pool[#pool + 1] = 'repulsor' end
  if l >= 11 then pool[#pool + 1] = 'sniper' end
  if l >= 16 then pool[#pool + 1] = 'kamikaze'; pool[#pool + 1] = 'repulsor'; pool[#pool + 1] = 'sniper' end
  return choice(pool)
end

local function banner(s, sub, c)
  arena.banner = {s = s, sub = sub, c = c or COL.text, t = 1.6, max = 1.6}
end

local function startWave()
  arena.wave = arena.wave + 1
  local l = run.level
  local list = {}
  if arena.boss and arena.wave == 1 then list[#list + 1] = 'boss' end
  local n = arena.boss and math.floor(arena.perWave / 2) or arena.perWave
  for i = 1, n do list[#list + 1] = pickEnemyType(l) end
  local groups = math.min(#list, rand(1, 3))
  local markers = {}
  for g = 1, groups do
    local x, y
    for try = 1, 30 do
      x, y = rr(AR.x1 + 60, AR.x2 - 60), rr(AR.y1 + 60, AR.y2 - 60)
      if dist(x, y, arena.head.x, arena.head.y) > 220 then break end
    end
    markers[g] = {x = x, y = y, t = 1.2, max = 1.2, list = {}}
  end
  for i, tp in ipairs(list) do table.insert(markers[(i - 1) % groups + 1].list, tp) end
  for _, m in ipairs(markers) do arena.spawns[#arena.spawns + 1] = m end
  if arena.boss and arena.wave == 1 then
    banner(l == MAX_LEVEL and 'FINAL BOSS' or 'BOSS', nil, COL.red)
    play('boss')
  else
    banner('WAVE ' .. arena.wave .. '/' .. arena.waves)
  end
end

---------------------------------------------------------------------------
-- level setup
---------------------------------------------------------------------------
local function buildUnit(m, counts)
  local d, lv = m.def, memberLevel(m)
  local function has(cl) for _, c in ipairs(d.classes) do if c == cl then return true end end return false end
  local function t(cl) return classTier(counts, cl) end
  local u = {
    m = m, def = d, lv = lv, color = d.color,
    x = 0, y = 0, a = 0, cd = rr(0.2, d.cd), flash = 0, iframe = 0,
    dmg = d.dmg * DMG_LV[lv], maxhp = d.hp * HP_LV[lv],
    defense = 0, aspd = 1, crit = d.critBonus or 0, dotm = 1, aream = 1, summonm = 1, healm = 1,
  }
  if has('warrior') then u.defense = ({0, 0.25, 0.5})[t('warrior') + 1] end
  if has('ranger') then u.aspd = 1 + 0.25 * t('ranger') end
  if has('mage') then u.dmg = u.dmg * (1 + 0.3 * t('mage')) end
  if has('rogue') then u.crit = u.crit + 0.15 * t('rogue') end
  if has('healer') then u.healm = 1 + 0.5 * t('healer') end
  if has('nuker') then u.aream = 1 + 0.3 * t('nuker') end
  if has('conjurer') then u.summonm = 1 + 0.5 * t('conjurer') end
  if has('voider') then u.dotm = 1 + 0.5 * t('voider') end
  u.maxhp = u.maxhp * HP_SCALE * (1 + 0.15 * t('enforcer'))
  u.hp = u.maxhp
  -- every segment rams what it touches; rammers hit harder and take less back
  local rammer = has('rammer')
  u.ram = (d.ram or 6) * DMG_LV[lv] * (rammer and (1 + 0.5 * t('rammer')) or 1)
  u.contactTaken = rammer and ({0.5, 0.3, 0.15})[t('rammer') + 1] or 1
  u.ramStun, u.ramSplash = d.ramStun, d.ramSplash
  u.coinOnKill = d.coinOnKill and d.coinOnKill[lv] or 0
  return u
end

local function startLevel()
  local l = run.level
  arena = {
    units = {}, alive = {}, enemies = {}, projs = {}, eprojs = {}, areas = {}, summons = {},
    parts = {}, texts = {}, spawns = {}, trail = {}, shake = 0, wallCd = 0, coins = {}, kills = 0, kx = 0, ky = 0,
    head = {x = AR.x1 + 200, y = (AR.y1 + AR.y2) / 2, a = 0},
    boss = isBoss(l), wave = 0, nextWave = 1.5, done = false, lost = false, endT = 0, t = 0,
  }
  arena.waves = arena.boss and 1 or math.min(6, 2 + math.floor(l / 4))
  arena.perWave = 5 + math.floor(l * 0.8)
  for x = arena.head.x - 200, arena.head.x, 3 do arena.trail[#arena.trail + 1] = {x = x, y = arena.head.y} end
  local counts = classCounts()
  for _, m in ipairs(run.party) do arena.units[#arena.units + 1] = buildUnit(m, counts) end
  arena.coinChance = ({0, 0.06, 0.15})[classTier(counts, 'merchant') + 1]
  banner('LEVEL ' .. l, arena.boss and 'antivirus daemon detected!' or nil)
  paused = false
  state = 'arena'
end

local function finishLevel()
  if run.level >= MAX_LEVEL then state = 'win'; return end
  -- merchants add flat gold, gold per kill, and a higher interest cap
  local extra, cap = 0, 3
  for _, m in ipairs(run.party) do
    local d, lv = m.def, memberLevel(m)
    if d.levelGold then extra = extra + d.levelGold[lv] end
    if d.killGold then extra = extra + math.floor(arena.kills / d.killGold[lv]) end
    if d.interestCap then cap = cap + d.interestCap[lv] end
  end
  if classTier(classCounts(), 'merchant') >= 2 then cap = cap + 2 end
  local interest = math.min(cap, math.floor(run.gold / 5))
  local bonus = arena.boss and 4 or 0
  local income = 4 + interest + bonus + extra
  run.gold = run.gold + income
  run.lastIncome = income
  run.level = run.level + 1
  rollOffers()
  local parts = {'4 base', '+' .. interest .. ' interest'}
  if extra > 0 then parts[#parts + 1] = '+' .. extra .. ' merchants' end
  if bonus > 0 then parts[#parts + 1] = '+' .. bonus .. ' boss' end
  shopMsg(('Level cleared! +$%d  (%s)'):format(income, table.concat(parts, ', ')), COL.gold)
  state = 'shop'
end

---------------------------------------------------------------------------
-- arena update
---------------------------------------------------------------------------
local function hurtUnit(u, dmg, force)
  if u.dead or (u.iframe > 0 and not force) then return end
  dmg = dmg * (1 - u.defense)
  u.hp = u.hp - dmg
  u.flash, u.iframe = 0.15, 0.3
  addText(u.x, u.y - 14, tostring(math.floor(dmg + 0.5)), COL.red)
  play('hurt')
  shake(3)
  if u.hp <= 0 then
    u.hp, u.dead = 0, true
    burst(u.x, u.y, u.color, 24, 240)
    play('die')
    shake(8)
    addText(u.x, u.y - 24, u.def.name .. ' [terminated]', COL.red, true)
  end
end

-- a segment that collides with an enemy hits it back
local function ramEnemy(e, u)
  damageEnemy(e, u.ram, u)
  burst(e.x, e.y, u.color, 6, 140, 2)
  if u.ramStun then e.stun = math.max(e.stun, u.ramStun) end
  if u.ramSplash then blast(e.x, e.y, u.ramSplash * u.aream, u.ram * 0.5, u, {knock = 260}) end
  play('hit')
end

local function sampleTrail(d)
  local tr = arena.trail
  local px, py = arena.head.x, arena.head.y
  local acc = 0
  for i = #tr, 1, -1 do
    local q = tr[i]
    local seg = dist(px, py, q.x, q.y)
    if seg > 0 and acc + seg >= d then
      local t = (d - acc) / seg
      return lerp(px, q.x, t), lerp(py, q.y, t), math.atan2(py - q.y, px - q.x)
    end
    acc = acc + seg
    px, py = q.x, q.y
  end
  return px, py, arena.head.a
end

local function updateWorm(dt)
  local h = arena.head
  local turn = 0
  if love.keyboard.isDown('a', 'left') then turn = turn - 1 end
  if love.keyboard.isDown('d', 'right') then turn = turn + 1 end
  h.a = h.a + turn * TURN_SPEED * dt
  h.x = h.x + math.cos(h.a) * WORM_SPEED * dt
  h.y = h.y + math.sin(h.a) * WORM_SPEED * dt
  -- shove from repulsor pulses, fading out
  h.x, h.y = h.x + arena.kx * dt, h.y + arena.ky * dt
  local kd = math.max(0, 1 - dt * 5)
  arena.kx, arena.ky = arena.kx * kd, arena.ky * kd
  local hit = false
  if h.x < AR.x1 + UR then h.x = AR.x1 + UR; h.a = math.pi - h.a; hit = true
  elseif h.x > AR.x2 - UR then h.x = AR.x2 - UR; h.a = math.pi - h.a; hit = true end
  if h.y < AR.y1 + UR then h.y = AR.y1 + UR; h.a = -h.a; hit = true
  elseif h.y > AR.y2 - UR then h.y = AR.y2 - UR; h.a = -h.a; hit = true end
  arena.wallCd = arena.wallCd - dt
  if hit and arena.wallCd <= 0 and arena.alive[1] then
    local u = arena.alive[1]
    arena.wallCd = 0.4
    play('wall')
    burst(h.x, h.y, COL.light, 8, 120, 2)
    hurtUnit(u, u.maxhp * 0.1, true)
  end
  local tr = arena.trail
  local last = tr[#tr]
  if dist(last.x, last.y, h.x, h.y) >= 3 then
    tr[#tr + 1] = {x = h.x, y = h.y}
    if #tr > 220 then table.remove(tr, 1) end
  end
end

local function updateUnits(dt)
  for i, u in ipairs(arena.alive) do
    local x, y, a = sampleTrail((i - 1) * SPACING)
    u.x, u.y = x, y
    u.a = (i == 1) and arena.head.a or a
    u.flash, u.iframe = u.flash - dt, u.iframe - dt
    u.cd = u.cd - dt * u.aspd
    if u.cd <= 0 and not u.def.noAttack then
      local d, ok = u.def, false
      if d.noTarget then
        ok = d.attack(u)
      else
        local t = nearestEnemy(u.x, u.y, d.range * (d.aoe and u.aream or 1))
        if t then ok = d.attack(u, t) end
      end
      if ok then
        u.cd = d.cd
        if not d.silent then play('shoot') end
      else
        u.cd = 0.1
      end
    end
  end
end

local function updateProjectiles(dt)
  for i = #arena.projs, 1, -1 do
    local p = arena.projs[i]
    p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
    p.life = p.life - dt
    local remove = p.life <= 0 or p.x < AR.x1 or p.x > AR.x2 or p.y < AR.y1 or p.y > AR.y2
    if not remove then
      for _, e in ipairs(arena.enemies) do
        if not e.dead and not p.hit[e] and dist(p.x, p.y, e.x, e.y) < p.r + e.r then
          p.hit[e] = true
          if p.explode then
            blast(p.x, p.y, p.explode * p.src.aream, p.dmg, p.src, {stun = p.stun})
          else
            if p.stun then e.stun = math.max(e.stun, p.stun) end
            damageEnemy(e, p.dmg, p.src)
            play('hit')
          end
          if p.dot then applyDot(e, p.dot, 3, p.src) end
          burst(p.x, p.y, p.color, 3, 100, 2)
          if p.chain > 0 then
            p.chain = p.chain - 1
            local n = nearestEnemy(p.x, p.y, 180, p.hit)
            if n then
              local a, s = math.atan2(n.y - p.y, n.x - p.x), math.sqrt(p.vx * p.vx + p.vy * p.vy)
              p.vx, p.vy, p.life = math.cos(a) * s, math.sin(a) * s, 1.0
            else
              remove = true
            end
          elseif p.pierce > 0 then
            p.pierce = p.pierce - 1
          else
            remove = true
          end
          break
        end
      end
    end
    if remove then table.remove(arena.projs, i) end
  end

  for i = #arena.eprojs, 1, -1 do
    local p = arena.eprojs[i]
    p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
    p.life = p.life - dt
    local remove = p.life <= 0 or p.x < AR.x1 or p.x > AR.x2 or p.y < AR.y1 or p.y > AR.y2
    if not remove then
      for _, u in ipairs(arena.alive) do
        if dist(p.x, p.y, u.x, u.y) < p.r + UR then
          hurtUnit(u, p.dmg)
          burst(p.x, p.y, COL.red, 5, 100, 2)
          remove = true
          break
        end
      end
    end
    if remove then table.remove(arena.eprojs, i) end
  end
end

local function hitArea(a)
  for _, e in ipairs(arena.enemies) do
    if not e.dead and dist(a.x, a.y, e.x, e.y) < a.r + e.r then
      damageEnemy(e, a.dmg, a.src, {nocrit = a.nocrit, color = a.ling and COL.purple or nil})
      if a.stun then e.stun = math.max(e.stun, a.stun) end
      if a.knock then
        local nx, ny = norm(e.x - a.x, e.y - a.y)
        local k = a.knock * (e.type == 'boss' and 0.15 or (e.type == 'tank' and 0.5 or 1))
        e.kx, e.ky = e.kx + nx * k, e.ky + ny * k
      end
    end
  end
end

local function updateAreas(dt)
  for i = #arena.areas, 1, -1 do
    local a = arena.areas[i]
    local remove = false
    if a.delay > 0 then
      a.delay = a.delay - dt
    else
      if not a.fired then
        a.fired = true
        if not a.ling then
          if not a.visual then hitArea(a) end
          if not a.faint then play('explode'); shake(a.r > 50 and 4 or 2) end
        end
      end
      if a.ling then
        a.dur, a.tt = a.dur - dt, a.tt - dt
        if a.tt <= 0 then a.tt = a.tick; hitArea(a) end
        a.age = a.age + dt
        if a.dur <= 0 then remove = true end
      else
        a.age = a.age + dt
        if a.age > 0.3 then remove = true end
      end
    end
    if remove then table.remove(arena.areas, i) end
  end
end

local function updateSummons(dt)
  for i = #arena.summons, 1, -1 do
    local s = arena.summons[i]
    s.life = s.life - dt
    if s.kind == 'turret' then
      s.cd = s.cd - dt
      if s.cd <= 0 then
        local t = nearestEnemy(s.x, s.y, 240)
        if t then
          s.a = angleTo(s, t)
          shootFrom(s.x, s.y, s.a, {src = s.src, dmg = s.dmg, speed = 380, explode = s.explode})
          play('shoot', 1.4)
          s.cd = 0.5
        else
          s.cd = 0.1
        end
      end
      if s.life <= 0 then burst(s.x, s.y, s.src.color, 8, 100) end
    elseif s.kind == 'bomber' then
      local t = nearestEnemy(s.x, s.y)
      if t then
        local nx, ny = norm(t.x - s.x, t.y - s.y)
        s.x, s.y, s.a = s.x + nx * 170 * dt, s.y + ny * 170 * dt, math.atan2(ny, nx)
        if dist(s.x, s.y, t.x, t.y) < t.r + 6 then s.life = 0 end
      end
      if s.life <= 0 then blast(s.x, s.y, 48 * s.src.aream, s.dmg, s.src) end
    end
    if s.life <= 0 then table.remove(arena.summons, i) end
  end
end

-- kamikaze reached the worm: blow up, hurting nearby segments (no kill reward)
local function kamikazeBoom(e)
  e.dead = true
  local R = 50
  for _, u in ipairs(arena.alive) do
    if dist(e.x, e.y, u.x, u.y) < R + UR then hurtUnit(u, e.dmg * 2.5) end
  end
  blast(e.x, e.y, R, 0, nil, {visual = true})
  burst(e.x, e.y, e.d.color, 18, 220)
  shake(6)
end

-- repulsor pulse: damages segments in range and shoves the head away
local REPULSE_R = 110
local function repulse(e)
  for _, u in ipairs(arena.alive) do
    if dist(e.x, e.y, u.x, u.y) < REPULSE_R + UR then hurtUnit(u, e.dmg) end
  end
  local h = arena.head
  if dist(e.x, e.y, h.x, h.y) < REPULSE_R + 40 then
    local nx, ny = norm(h.x - e.x, h.y - e.y)
    arena.kx, arena.ky = nx * 340, ny * 340
    h.a = math.atan2(ny, nx)
  end
  blast(e.x, e.y, REPULSE_R, 0, nil, {visual = true, faint = true})
  play('wall')
  shake(4)
end

local function bossAI(e, nx, ny, dt)
  e.bt = e.bt - dt
  if e.bt > 0 then return end
  local enraged = e.hp < e.maxhp * 0.5
  e.bt = enraged and 2.4 or 3.4
  local ab = rand(1, 3)
  if ab == 1 then
    local n, off = enraged and 24 or 16, rr(0, 6.28)
    for k = 1, n do enemyShoot(e.x, e.y, off + k / n * math.pi * 2, 120, e.dmg * 0.5) end
    play('boss')
  elseif ab == 2 then
    for k = 1, enraged and 5 or 3 do
      local a = rr(0, 6.28)
      spawnEnemy(choice({'seeker', 'mini', 'seeker'}), e.x + math.cos(a) * 45, e.y + math.sin(a) * 45)
    end
    burst(e.x, e.y, e.d.color, 20, 200)
  else
    e.cs, e.ct, e.ca = 'wind', 0.8, math.atan2(ny, nx)
  end
end

local function updateEnemies(dt)
  local es = arena.enemies
  for _, e in ipairs(es) do
    if not e.dead then
      e.flash, e.ccd, e.spawnT = e.flash - dt, e.ccd - dt, e.spawnT - dt
      for k = #e.dots, 1, -1 do
        local dot = e.dots[k]
        dot.t, dot.tick = dot.t - dt, dot.tick - dt
        if dot.tick <= 0 then dot.tick = 0.3; damageEnemy(e, dot.dps * 0.3, nil, {color = COL.purple}) end
        if dot.t <= 0 then table.remove(e.dots, k) end
      end
    end
    if not e.dead then
      local t, td = nearestUnit(e.x, e.y)
      local dx, dy, acc = 0, 0, 4
      if e.stun > 0 then
        e.stun = e.stun - dt
      elseif t then
        local nx, ny = norm(t.x - e.x, t.y - e.y)
        local tp = e.type
        if tp == 'shooter' then
          if td > 200 then dx, dy = nx * e.speed, ny * e.speed
          elseif td < 130 then dx, dy = -nx * e.speed, -ny * e.speed
          else dx, dy = -ny * e.speed * 0.6, nx * e.speed * 0.6 end
          e.st = e.st - dt
          if e.st <= 0 and td < 380 then
            e.st = rr(2.2, 3.2)
            enemyShoot(e.x, e.y, math.atan2(ny, nx), 150, e.dmg)
          end
        elseif tp == 'kamikaze' then
          if e.cs == 'arm' then
            dx, dy = nx * e.speed * 0.3, ny * e.speed * 0.3
            e.ct = e.ct - dt
            if e.ct <= 0 then kamikazeBoom(e) end
          else
            dx, dy = nx * e.speed, ny * e.speed
            if td < 45 then e.cs, e.ct = 'arm', 0.45 end
          end
        elseif tp == 'repulsor' then
          if td > 120 then dx, dy = nx * e.speed, ny * e.speed end
          if td < 200 then
            e.st = e.st - dt
            if e.st <= 0 then e.st = rr(2.8, 3.6); repulse(e) end
          end
        elseif tp == 'sniper' then
          if e.cs == 'aim' then
            e.ct = e.ct - dt
            if e.ct <= 0 then
              enemyShoot(e.x, e.y, e.ca, 430, e.dmg)
              play('shoot', 0.6)
              e.cs, e.st = 'walk', rr(3, 4)
            end
          else
            if td > 330 then dx, dy = nx * e.speed, ny * e.speed
            elseif td < 240 then dx, dy = -nx * e.speed, -ny * e.speed end
            e.st = e.st - dt
            if e.st <= 0 and td < 430 then e.cs, e.ct, e.ca = 'aim', 0.9, math.atan2(ny, nx) end
          end
        elseif tp == 'charger' or tp == 'boss' then
          if e.cs == 'wind' then
            e.ct = e.ct - dt
            if e.ct <= 0 then e.cs, e.ct = 'dash', tp == 'boss' and 0.7 or 0.45 end
          elseif e.cs == 'dash' then
            local sp = tp == 'boss' and 330 or 360
            dx, dy, acc = math.cos(e.ca) * sp, math.sin(e.ca) * sp, 20
            e.ct = e.ct - dt
            if e.ct <= 0 then e.cs, e.ct = 'walk', rr(2, 3.5) end
          else
            dx, dy = nx * e.speed, ny * e.speed
            if tp == 'charger' then
              e.ct = e.ct - dt
              if e.ct <= 0 then
                if td < 320 then e.cs, e.ct, e.ca = 'wind', 0.6, math.atan2(ny, nx) else e.ct = 0.5 end
              end
            else
              bossAI(e, nx, ny, dt)
            end
          end
        else
          dx, dy = nx * e.speed, ny * e.speed
        end
      end
      local f = math.min(1, dt * acc)
      e.vx, e.vy = e.vx + (dx - e.vx) * f, e.vy + (dy - e.vy) * f
      e.x, e.y = e.x + (e.vx + e.kx) * dt, e.y + (e.vy + e.ky) * dt
      local kd = math.max(0, 1 - dt * 5)
      e.kx, e.ky = e.kx * kd, e.ky * kd
      if e.cs == 'wind' or e.cs == 'aim' then
        e.a = e.ca
      elseif e.vx * e.vx + e.vy * e.vy > 4 then
        e.a = math.atan2(e.vy, e.vx)
      end
      e.x, e.y = clamp(e.x, AR.x1 + e.r, AR.x2 - e.r), clamp(e.y, AR.y1 + e.r, AR.y2 - e.r)

      if e.spawnT <= 0 and not e.dead then
        for _, u in ipairs(arena.alive) do
          if dist(e.x, e.y, u.x, u.y) < e.r + UR then
            if e.ccd <= 0 then
              e.ccd = 0.6
              hurtUnit(u, e.dmg * u.contactTaken)
              ramEnemy(e, u)
            end
            local nx, ny = norm(e.x - u.x, e.y - u.y)
            local k = e.type == 'boss' and 60 or (e.type == 'tank' and 120 or 240)
            e.kx, e.ky = nx * k, ny * k
            if e.type == 'charger' and e.cs == 'dash' then e.cs, e.ct = 'walk', rr(2, 3) end
            break
          end
        end
      end
    end
  end

  -- separation
  for i = 1, #es do
    local a = es[i]
    for j = i + 1, #es do
      local b = es[j]
      local dx, dy = b.x - a.x, b.y - a.y
      local rs = a.r + b.r
      local d2 = dx * dx + dy * dy
      if d2 < rs * rs and d2 > 1e-4 then
        local d = math.sqrt(d2)
        local push, nx, ny = (rs - d) * 0.5, dx / d, dy / d
        local wa, wb = a.type == 'boss' and 0.1 or 1, b.type == 'boss' and 0.1 or 1
        a.x, a.y = a.x - nx * push * wa, a.y - ny * push * wa
        b.x, b.y = b.x + nx * push * wb, b.y + ny * push * wb
      end
    end
  end

  for i = #es, 1, -1 do if es[i].dead then table.remove(es, i) end end
end

local function updateArena(dt)
  arena.t = arena.t + dt
  arena.alive = {}
  for _, u in ipairs(arena.units) do if not u.dead then arena.alive[#arena.alive + 1] = u end end

  if #arena.alive > 0 then updateWorm(dt) end
  updateUnits(dt)
  updateProjectiles(dt)
  updateAreas(dt)
  updateSummons(dt)
  updateEnemies(dt)

  -- coins drift toward the head and are picked up by any segment
  local head = arena.alive[1]
  for i = #arena.coins, 1, -1 do
    local c = arena.coins[i]
    c.life = c.life - dt
    if head and dist(c.x, c.y, head.x, head.y) < 90 then
      local nx, ny = norm(head.x - c.x, head.y - c.y)
      c.x, c.y = c.x + nx * 240 * dt, c.y + ny * 240 * dt
    end
    local got = false
    for _, u in ipairs(arena.alive) do
      if dist(c.x, c.y, u.x, u.y) < UR + 7 then got = true; break end
    end
    if got then
      run.gold = run.gold + c.value
      addText(c.x, c.y - 10, '+$' .. c.value, COL.coin, true)
      play('buy', 1.6)
      table.remove(arena.coins, i)
    elseif c.life <= 0 then
      table.remove(arena.coins, i)
    end
  end

  for i = #arena.spawns, 1, -1 do
    local s = arena.spawns[i]
    s.t = s.t - dt
    if s.t <= 0 then
      for k, tp in ipairs(s.list) do
        local a, rad = rr(0, 6.28), 10 * math.sqrt(k)
        spawnEnemy(tp, s.x + math.cos(a) * rad, s.y + math.sin(a) * rad)
      end
      burst(s.x, s.y, COL.pink, 12, 160)
      table.remove(arena.spawns, i)
    end
  end

  for i = #arena.parts, 1, -1 do
    local p = arena.parts[i]
    p.x, p.y, p.life = p.x + p.vx * dt, p.y + p.vy * dt, p.life - dt
    p.vx, p.vy = p.vx * (1 - dt * 3), p.vy * (1 - dt * 3)
    if p.life <= 0 then table.remove(arena.parts, i) end
  end
  for i = #arena.texts, 1, -1 do
    local t = arena.texts[i]
    t.life = t.life - dt
    if t.life <= 0 then table.remove(arena.texts, i) end
  end
  if arena.banner then
    arena.banner.t = arena.banner.t - dt
    if arena.banner.t <= 0 then arena.banner = nil end
  end
  arena.shake = arena.shake * math.max(0, 1 - dt * 10)
  if arena.shake < 0.2 then arena.shake = 0 end

  -- waves / end conditions
  if arena.done or arena.lost then
    arena.endT = arena.endT - dt
    if arena.endT <= 0 then
      if arena.lost then state = 'gameover' else finishLevel() end
    end
    return
  end
  if #arena.alive == 0 then
    arena.lost, arena.endT = true, 2
    banner('KERNEL PANIC', 'not syncing: all units terminated', COL.red)
    return
  end
  if arena.wave < arena.waves then
    if #arena.spawns == 0 then
      arena.nextWave = arena.nextWave - dt
      if arena.wave > 0 and #arena.enemies <= math.max(2, math.floor(arena.perWave * 0.25)) then
        arena.nextWave = math.min(arena.nextWave, 0.8)
      end
      if arena.nextWave <= 0 then startWave(); arena.nextWave = 15 end
    end
  elseif #arena.spawns == 0 and #arena.enemies == 0 then
    arena.done, arena.endT = true, 2
    for _, c in ipairs(arena.coins) do run.gold = run.gold + c.value end
    arena.coins = {}
    banner(run.level >= MAX_LEVEL and 'EXIT 0' or 'LEVEL CLEARED', '[  OK  ] all hostile processes killed', COL.green)
    play('buy')
  end
end

---------------------------------------------------------------------------
-- drawing helpers (terminal look: bordered panels, monospace, phosphor green, CRT scanlines)
---------------------------------------------------------------------------
local function fontH(f) return fonts[f or 'm']:getHeight() / scale end

local function poly(mode, x, y, r, n, rot)
  local pts = {}
  for i = 0, n - 1 do
    local a = rot + i / n * math.pi * 2
    pts[#pts + 1] = x + math.cos(a) * r
    pts[#pts + 1] = y + math.sin(a) * r
  end
  lg.polygon(mode, pts)
end

-- terminal panel: dark fill, thin border, bright corner ticks
local function card(x, y, w, h)
  setc(COL.card)
  lg.rectangle('fill', x, y, w, h)
  lg.setLineWidth(1)
  setc(COL.line)
  lg.rectangle('line', x + 0.5, y + 0.5, w - 1, h - 1)
  setc(COL.mid)
  local t = 6
  lg.line(x, y + t, x, y, x + t, y)
  lg.line(x + w - t, y, x + w, y, x + w, y + t)
  lg.line(x, y + h - t, x, y + h, x + t, y + h)
  lg.line(x + w - t, y + h, x + w, y + h, x + w, y + h - t)
end

-- small rounded tag, returns its width
local function pill(label, x, y, fg, bg, f)
  f = f or 's'
  local h = fontH(f) + 4
  local w = textW(label, f) + 14
  setc(bg)
  lg.rectangle('fill', x, y, w, h, 2, 2)
  setc(fg)
  text(label, x + 7, y + 2, f)
  return w
end
local function pillW(label, f) return textW(label, f or 's') + 14 end

local function dashedCircle(x, y, r, n, rot)
  for i = 0, n - 1 do
    local a = rot + i / n * math.pi * 2
    lg.arc('line', 'open', x, y, r, a, a + math.pi / n)
  end
end

-- one symbol per class, drawn inside the point markers
local function glyph(cl, x, y, s)
  if cl == 'warrior' then
    lg.rectangle('fill', x - s * 0.8, y - s * 0.8, s * 1.6, s * 1.6, 1.5, 1.5)
  elseif cl == 'ranger' then
    poly('fill', x, y + s * 0.15, s * 1.15, 3, -math.pi / 2)
  elseif cl == 'mage' then
    poly('fill', x, y, s * 1.15, 4, 0)
  elseif cl == 'rogue' then
    lg.setLineWidth(math.max(1.5, s * 0.45))
    lg.line(x - s * 0.8, y - s * 0.8, x + s * 0.8, y + s * 0.8)
    lg.line(x - s * 0.8, y + s * 0.8, x + s * 0.8, y - s * 0.8)
  elseif cl == 'healer' then
    lg.rectangle('fill', x - s * 0.3, y - s, s * 0.6, s * 2)
    lg.rectangle('fill', x - s, y - s * 0.3, s * 2, s * 0.6)
  elseif cl == 'nuker' then
    lg.circle('fill', x, y, s)
  elseif cl == 'conjurer' then
    lg.setLineWidth(math.max(1.5, s * 0.4))
    lg.circle('line', x, y, s * 0.8)
  elseif cl == 'voider' then
    lg.arc('fill', x, y, s, math.pi / 2, math.pi * 1.5)
  elseif cl == 'merchant' then
    lg.rectangle('fill', x - s, y - s * 0.85, s * 2, s * 0.65, 1, 1)
    lg.rectangle('fill', x - s, y + s * 0.2, s * 2, s * 0.65, 1, 1)
  elseif cl == 'rammer' then
    lg.setLineWidth(math.max(1.5, s * 0.5))
    lg.line(x - s * 0.7, y - s * 0.9, x + s * 0.5, y, x - s * 0.7, y + s * 0.9)
  else
    lg.rectangle('fill', x - s, y - s * 0.4, s * 2, s * 0.8, 1, 1)
  end
end

-- worm segment: rounded block in class colour with its class symbol
local function marker(x, y, r, what, fill, lv, a, noGlyph)
  -- `what` is a unit definition (its own shade) or a class key (the class colour)
  local cl, color
  if type(what) == 'table' then cl, color = what.classes[1], what.color else cl, color = what, CLASSES[what].color end
  local w, h = r * 2.2, r * 1.7
  lg.push()
  lg.translate(x, y)
  lg.rotate(a or 0)
  if lv and lv >= 2 then
    lg.setLineWidth(2)
    setc(lv == 3 and COL.gold or COL.ink, 0.85)
    lg.rectangle('line', -w / 2 - 3, -h / 2 - 3, w + 6, h + 6, 4, 4)
  end
  setc(fill or color)
  lg.rectangle('fill', -w / 2, -h / 2, w, h, 3, 3)
  lg.pop()
  if not noGlyph then
    setc(lum(color) > 0.5 and COL.bg or COL.ink)
    glyph(cl, x, y, r * 0.38)
  end
end

local function classLine(classes)
  local t = {}
  for i, cl in ipairs(classes) do t[i] = CLASSES[cl].name end
  return table.concat(t, '/')
end

---------------------------------------------------------------------------
-- drawing: arena
---------------------------------------------------------------------------
local function drawEnemy(e)
  local s = 1 - clamp(e.spawnT / 0.4, 0, 1)
  local r = e.r * (0.3 + 0.7 * s)
  local c = e.flash > 0 and COL.ink or e.d.color
  local alpha = e.stun > 0 and 0.4 or 1
  local tp = e.type
  if (tp == 'charger' or tp == 'boss') and e.cs == 'wind' then
    setc(COL.pink, 0.15 + 0.1 * math.sin(time * 40))
    lg.setLineWidth(e.r * (tp == 'boss' and 2 or 1.6))
    local len = tp == 'boss' and 240 or 170
    lg.line(e.x, e.y, e.x + math.cos(e.ca) * len, e.y + math.sin(e.ca) * len)
  end
  if tp == 'sniper' and e.cs == 'aim' then
    setc(COL.pink, 0.35 + 0.35 * (1 - e.ct / 0.9))
    lg.setLineWidth(1.5)
    lg.line(e.x, e.y, e.x + math.cos(e.ca) * 430, e.y + math.sin(e.ca) * 430)
  end
  if tp == 'repulsor' and e.st < 0.8 and e.stun <= 0 then
    local p = 1 - e.st / 0.8
    setc(COL.pink, 0.5)
    lg.setLineWidth(1.5)
    dashedCircle(e.x, e.y, REPULSE_R * p, 14, time * 3)
  end
  if tp == 'kamikaze' and e.cs == 'arm' and math.floor(time * 20) % 2 == 0 then c = COL.ink end
  setc(c, alpha)
  lg.push()
  lg.translate(e.x, e.y)
  lg.rotate(e.a)
  if tp == 'seeker' then
    lg.rectangle('fill', -r, -r, r * 2, r * 2, 3, 3)
  elseif tp == 'shooter' then
    poly('fill', 0, 0, r * 1.25, 3, 0)
  elseif tp == 'charger' then
    poly('fill', 0, 0, r * 1.3, 4, 0)
  elseif tp == 'tank' then
    lg.rectangle('fill', -r, -r, r * 2, r * 2, 4, 4)
    setc(COL.card, 0.45)
    lg.rectangle('fill', -r * 0.5, -r * 0.5, r, r, 2, 2)
  elseif tp == 'splitter' or tp == 'mini' then
    lg.circle('fill', 0, 0, r)
    if tp == 'splitter' then setc(COL.card, 0.6); lg.setLineWidth(2); lg.line(-r * 0.7, 0, r * 0.7, 0) end
  elseif tp == 'kamikaze' then
    if e.cs == 'arm' then r = r * 1.3 end
    -- arrowhead (two triangles, since filled polygons must be convex)
    lg.polygon('fill', r * 1.4, 0, -r, -r, -r * 0.3, 0)
    lg.polygon('fill', r * 1.4, 0, -r * 0.3, 0, -r, r)
  elseif tp == 'repulsor' then
    lg.circle('fill', 0, 0, r * 0.75)
    lg.setLineWidth(2.5)
    lg.circle('line', 0, 0, r * 1.15)
  elseif tp == 'sniper' then
    lg.rectangle('fill', -r * 1.2, -r * 0.45, r * 2.4, r * 0.9, 2, 2)
    lg.rectangle('fill', -r * 0.5, -r * 0.8, r, r * 1.6, 2, 2)
  elseif tp == 'boss' then
    lg.rotate(time * 0.8)
    poly('fill', 0, 0, r, 6, 0)
    setc(COL.ink, 0.85)
    poly('fill', 0, 0, r * 0.5, 6, 0)
  end
  lg.pop()
  if e.hp < e.maxhp and tp ~= 'boss' then
    local w = e.r * 2.2
    setc(COL.grid)
    lg.rectangle('fill', e.x - w / 2, e.y - e.r - 8, w, 3, 1.5, 1.5)
    setc(COL.pink)
    lg.rectangle('fill', e.x - w / 2, e.y - e.r - 8, w * math.max(0, e.hp / e.maxhp), 3, 1.5, 1.5)
  end
end

local function drawWorm()
  for i = #arena.alive, 1, -1 do
    local u = arena.alive[i]
    local head = i == 1
    marker(u.x, u.y, 8.5, u.def, u.flash > 0 and COL.red or nil, u.lv, u.a, head)
    if head then
      local ca, sa = math.cos(u.a), math.sin(u.a)
      setc(lum(u.color) > 0.5 and COL.bg or COL.ink)
      lg.circle('fill', u.x + ca * 4 - sa * 3.5, u.y + sa * 4 + ca * 3.5, 1.9)
      lg.circle('fill', u.x + ca * 4 + sa * 3.5, u.y + sa * 4 - ca * 3.5, 1.9)
    end
    if u.hp < u.maxhp then
      local f = u.hp / u.maxhp
      setc(COL.grid)
      lg.rectangle('fill', u.x - 10, u.y - 18, 20, 3, 1.5, 1.5)
      setc(f < 0.3 and COL.red or COL.green)
      lg.rectangle('fill', u.x - 10, u.y - 18, 20 * f, 3, 1.5, 1.5)
    end
  end
end

-- first-level tutorial, written as the operator's notes while the worm installs
local BRIEFING = {
  '> worm.ko injected into /dev/arena0. it never stops moving.',
  '> steer it with [A]/[D] or [Left]/[Right]. kernel walls hurt the head.',
  '> your modules fire on their own. your only job: keep them alive.',
  '> red shapes are hostile processes. ramming one hurts you both.',
  '> kill every wave to escalate. spend the loot at the darkmarket.',
}
-- from level 2 on, the kernel's defences announce what they just upgraded
local SECURITY = {
  [2] = 'ids: anomaly detected in /dev/arena0. monitoring enabled.',
  [3] = 'firewall: turret processes deployed. they shoot back now.',
  [4] = 'edr: kamikaze processes armed. they detonate on contact.',
  [5] = 'edr: charger processes now dash at known worm signatures.',
  [6] = 'ANTIVIRUS v1 online. scanning memory for worm.ko...',
  [7] = 'kernel: repulsor daemons pulse to shove the worm off course.',
  [8] = 'hardening: armoured tank processes deployed.',
  [9] = 'audit: more hostile processes in every wave from now on.',
  [10] = 'sandbox: splitter processes fork in two when killed.',
  [11] = 'honeypot: laser-sighted snipers are watching the worm.',
  [12] = 'ANTIVIRUS v2 online. signatures updated.',
  [13] = 'siem: every wave now correlated. expect larger swarms.',
  [14] = 'patch tuesday: tanks, chargers and turrets doubled.',
  [16] = 'zero-trust mode: kamikazes, repulsors and snipers doubled.',
  [18] = 'ANTIVIRUS v3 online. heuristics enabled.',
  [20] = 'soc on high alert: analysts hunting the worm manually.',
  [22] = 'secure boot: integrity checks on every process.',
  [24] = 'ANTIVIRUS v4 online. last line before the core.',
  [25] = 'KERNEL SELF-DEFENSE ENGAGED. this is the final boss.',
}
local function securityLog(l)
  if l < 2 or not (SECURITY[l] or l % 2 == 0) then return nil end
  local lines = {('[!] security update - threat level %02d, process integrity x%.1f'):format(l, hpScale(l))}
  if SECURITY[l] then lines[2] = '> ' .. SECURITY[l] end
  return lines
end

-- a log that types itself out in the bottom-left corner of the arena, then fades
local function drawTypedLog(lines, duration, color, lastColor)
  local t = arena.t
  local alpha = math.min(1, (duration - t) / 1.5)
  if alpha <= 0 then return end
  local x, y = AR.x1 + 64, AR.y2 - 18 - #lines * 16
  local w = 0
  for _, line in ipairs(lines) do w = math.max(w, textW(line, 's')) end
  setc(COL.bg, 0.8 * alpha)
  lg.rectangle('fill', x - 8, y - 8, w + 16, #lines * 16 + 12)
  setc(color, 0.6 * alpha)
  lg.rectangle('fill', x - 8, y - 8, 2, #lines * 16 + 12)
  local chars = math.floor(t * 38)
  for i, line in ipairs(lines) do
    if chars <= 0 then break end
    setc(i == #lines and lastColor or color, alpha)
    text(line:sub(1, chars), x, y + (i - 1) * 16, 's')
    chars = chars - #line - 12
  end
end

local function drawBriefing()
  if run.level == 1 then
    drawTypedLog(BRIEFING, 24, COL.green, COL.ink)
  else
    local lines = securityLog(run.level)
    if lines then drawTypedLog(lines, 10, COL.red, COL.gold) end
  end
end

local function drawArena()
  local sx, sy = 0, 0
  if arena.shake > 0 then sx, sy = rr(-1, 1) * arena.shake, rr(-1, 1) * arena.shake end
  lg.push()
  lg.translate(sx, sy)

  card(AR.x1, AR.y1, AR.x2 - AR.x1, AR.y2 - AR.y1)
  lg.setScissor(ox + AR.x1 * scale, oy + AR.y1 * scale, (AR.x2 - AR.x1) * scale, (AR.y2 - AR.y1) * scale)
  -- memory map: dotted grid with hex addresses down the left edge
  setc(COL.grid)
  for y = AR.y1 + 28, AR.y2 - 10, 32 do
    for x = AR.x1 + 64, AR.x2 - 12, 32 do lg.rectangle('fill', x, y, 1.5, 1.5) end
  end
  for i, y in ipairs({AR.y1 + 22, AR.y1 + 118, AR.y1 + 214, AR.y1 + 310, AR.y1 + 406}) do
    setc(COL.light)
    text(('0x%04X'):format(0xA000 + (i - 1) * 0x0C00), AR.x1 + 8, y, 's')
  end
  setc(COL.light)
  text('/dev/arena0', AR.x2 - 210, AR.y2 - 18, 's', 'right', 200)

  for _, s in ipairs(arena.spawns) do
    local p = 1 - s.t / s.max
    setc(COL.pink, 0.15 + 0.1 * math.sin(time * 20))
    lg.circle('fill', s.x, s.y, 4 + 14 * p)
    setc(COL.pink, 0.9)
    lg.setLineWidth(1.5)
    dashedCircle(s.x, s.y, 26 - 12 * p, 10, time * 2)
    setc(COL.pink, 0.7)
    ctext('fork()', s.x, s.y - 40, 's')
  end

  for _, a in ipairs(arena.areas) do
    if a.delay > 0 then
      local p = 1 - a.delay / math.max(0.01, a.maxdelay)
      setc(COL.cyan, 0.1)
      lg.circle('fill', a.x, a.y, a.r * p)
      setc(COL.cyan, 0.7)
      lg.setLineWidth(1.5)
      dashedCircle(a.x, a.y, a.r, 12, time)
    elseif a.ling then
      local alpha = math.min(1, a.dur * 2)
      setc(COL.purple, 0.10 * alpha)
      lg.circle('fill', a.x, a.y, a.r)
      setc(COL.purple, 0.6 * alpha)
      lg.setLineWidth(1.5)
      dashedCircle(a.x, a.y, a.r, 14, time * 0.8)
    else
      local p = a.age / 0.3
      local alpha = (1 - p) * (a.faint and 0.35 or 1)
      local rad = a.r * (0.6 + 0.4 * p)
      local ac = a.visual and COL.pink or (a.src and a.src.color or COL.ink)
      setc(ac, alpha * 0.15)
      lg.circle('fill', a.x, a.y, rad)
      setc(ac, alpha * 0.8)
      lg.setLineWidth(2)
      lg.circle('line', a.x, a.y, rad)
    end
  end

  for _, c in ipairs(arena.coins) do
    if c.life > 2 or math.floor(c.life * 8) % 2 == 0 then
      setc(COL.coin)
      lg.circle('fill', c.x, c.y, 6)
      setc(COL.card, 0.8)
      lg.setLineWidth(1.5)
      lg.circle('line', c.x, c.y, 3.5)
    end
  end

  for _, s in ipairs(arena.summons) do
    if s.kind == 'turret' then
      lg.push()
      lg.translate(s.x, s.y)
      lg.rotate(s.a)
      setc(COL.ink)
      lg.rectangle('fill', -6, -6, 12, 12, 3, 3)
      lg.rectangle('fill', 0, -2, 11, 4, 1, 1)
      setc(COL.card)
      lg.circle('fill', 0, 0, 2.5)
      lg.pop()
    else
      setc(COL.ink)
      lg.circle('fill', s.x, s.y, 5)
      setc(COL.green)
      lg.setLineWidth(1.5)
      lg.circle('line', s.x, s.y, 5)
    end
  end

  for _, e in ipairs(arena.enemies) do drawEnemy(e) end
  drawWorm()

  setc(COL.ink)
  for _, p in ipairs(arena.projs) do
    if p.shape then
      local nx, ny = norm(p.vx, p.vy)
      local len = p.shape == 'arrow' and 12 or 8
      lg.setLineWidth(2.5)
      lg.line(p.x - nx * len, p.y - ny * len, p.x, p.y)
    else
      lg.circle('fill', p.x, p.y, p.r)
    end
  end
  lg.setLineWidth(2)
  for _, p in ipairs(arena.eprojs) do
    setc(COL.pink)
    lg.circle('fill', p.x, p.y, p.r)
    setc(COL.bg)
    lg.circle('fill', p.x, p.y, p.r * 0.4)
  end

  for _, p in ipairs(arena.parts) do
    setc(p.c, p.life / p.max)
    local s = p.s * (p.life / p.max)
    lg.rectangle('fill', p.x - s / 2, p.y - s / 2, s, s, 1, 1)
  end
  for _, t in ipairs(arena.texts) do
    local p = 1 - t.life / t.max
    setc(t.c, math.min(1, t.life / t.max * 2))
    ctext(t.s, t.x, t.y - p * 18, t.big and 'm' or 's')
  end
  lg.setScissor()
  lg.pop()

  drawBriefing()

  -- HUD
  setc(COL.dim)
  text('root@networm:~/arena#', 24, 4, 's')
  local ls = ('level %02d/%d'):format(run.level, MAX_LEVEL)
  setc(COL.ink)
  text(ls, 24, 17, 'l')
  local px = 24 + textW(ls, 'l') + 12
  local boss
  for _, e in ipairs(arena.enemies) do if e.type == 'boss' then boss = e end end
  if arena.boss then
    px = px + pill(run.level == MAX_LEVEL and 'FINAL BOSS' or 'BOSS', px, 24, COL.bg, COL.red) + 6
  else
    px = px + pill(('wave %d/%d'):format(math.max(1, arena.wave), arena.waves), px, 24, COL.mintText, COL.mintSoft) + 6
  end
  pill(#arena.enemies .. ' hostile procs', px, 24, COL.red, COL.pinkSoft)
  setc(COL.dim)
  text('gold', W - 224, 4, 's', 'right', 200)
  setc(COL.gold)
  text('$' .. run.gold, W - 224, 17, 'l', 'right', 200)
  if boss then
    setc(COL.grid)
    lg.rectangle('fill', W / 2 + 10, 26, 240, 9)
    setc(COL.red)
    lg.rectangle('fill', W / 2 + 10, 26, 240 * math.max(0, boss.hp / boss.maxhp), 9)
  end

  if arena.banner then
    local b = arena.banner
    local p = b.t / b.max
    local alpha = math.min(1, p * 3, (1 - p) * 8)
    setc(b.c, alpha)
    ctext(b.s, W / 2, 200, 'xl')
    if b.sub then setc(COL.mid, alpha); ctext(b.sub, W / 2, 280, 'l') end
  end

  if paused then
    setc(COL.bg, 0.85)
    lg.rectangle('fill', 0, 0, W, H)
    setc(COL.ink)
    ctext('SIGSTOP', W / 2, 200, 'xl')
    setc(COL.mid)
    ctext('[P] / [Esc] resume (SIGCONT)     [Q] quit to menu', W / 2, 280, 'm')
  end
end

---------------------------------------------------------------------------
-- drawing: shop
---------------------------------------------------------------------------
local SH = {px = 24, py = 92, pw = 312, rowH = 46}
local function cardRect(i) return {x = 360 + (i - 1) * 148, y = 92, w = 136, h = 190} end
local function rowRect(i) return {x = SH.px, y = SH.py + (i - 1) * SH.rowH, w = SH.pw, h = SH.rowH - 6} end
local function sellRect(i) local r = rowRect(i); return {x = r.x + r.w - 58, y = r.y + 9, w = 52, h = 22} end
local function upRect(i) local r = rowRect(i); return {x = r.x + r.w - 84, y = r.y + 3, w = 20, h = 16} end
local function downRect(i) local r = rowRect(i); return {x = r.x + r.w - 84, y = r.y + 21, w = 20, h = 16} end
local REROLL_BTN = {x = 360, y = 292, w = 200, h = 40}
local SHOPUP_BTN = {x = 568, y = 292, w = 152, h = 40}
local START_BTN = {x = 728, y = 292, w = 208, h = 40}
local CATALOG_BTN = {x = W - 24 - 118, y = 12, w = 118, h = 30}
local CAT = {x = 40, y = 30, w = 880, h = 480}
local CAT_CLOSE = {x = CAT.x + CAT.w - 120, y = CAT.y + 16, w = 100, h = 28}
local TIER_COL = {{COL.mid, COL.grid}, {COL.mintText, COL.mintSoft}, {COL.bg, COL.cyan}, {COL.bg, COL.gold}}

local function button(r, label, enabled, hover, primary)
  if primary then
    -- inverted video, like a selected terminal line
    setc(not enabled and COL.light or (hover and COL.ink or COL.green))
    lg.rectangle('fill', r.x, r.y, r.w, r.h)
    setc(COL.bg)
  else
    setc((hover and enabled) and COL.hover or COL.card)
    lg.rectangle('fill', r.x, r.y, r.w, r.h)
    lg.setLineWidth(1)
    setc((hover and enabled) and COL.green or COL.line)
    lg.rectangle('line', r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1)
    setc(enabled and COL.ink or COL.dim)
  end
  local f = r.h >= 30 and 'm' or 's'
  text(label, r.x, r.y + (r.h - fontH(f)) / 2, f, 'center', r.w)
end

-- every unit the shop can roll, grouped by tier, with the odds for the current shop level
local function drawCatalogue(mx, my)
  setc(COL.bg, 0.8)
  lg.rectangle('fill', 0, 0, W, H)
  card(CAT.x, CAT.y, CAT.w, CAT.h)
  setc(COL.dim)
  text('$ man worm-modules', CAT.x + 20, CAT.y + 8, 's')
  setc(COL.ink)
  text('Catalogue', CAT.x + 20, CAT.y + 20, 'l')
  setc(COL.dim)
  text(('Every module the market can sell. Odds shown for market level %d; upgrade it to unlock higher tiers.'):format(run.shopLevel),
    CAT.x + 20, CAT.y + 46, 's')
  button(CAT_CLOSE, '[Esc] close', true, inRect(mx, my, CAT_CLOSE))

  local odds, hovered = SHOP_ODDS[run.shopLevel], nil
  local colW = (CAT.w - 40 - 3 * 14) / 4
  for tier = 1, 4 do
    local cx, cy = CAT.x + 20 + (tier - 1) * (colW + 14), CAT.y + 72
    local avail = odds[tier] > 0
    local label = 'Tier ' .. tier
    pill(label, cx, cy, TIER_COL[tier][1], TIER_COL[tier][2])
    setc(avail and COL.mid or COL.light)
    text(('$%d  %3d%%'):format(COST[tier], math.floor(odds[tier] * 100 + 0.5)), cx + pillW(label) + 8, cy + 2, 's')
    for i, key in ipairs(UNIT_TIERS[tier]) do
      local def = UNITS[key]
      local r = {x = cx, y = cy + 24 + (i - 1) * 26, w = colW, h = 25}
      if inRect(mx, my, r) then
        hovered = def
        setc(COL.hover)
        lg.rectangle('fill', r.x - 4, r.y, r.w + 8, r.h)
      end
      marker(r.x + 11, r.y + 13, 7.5, def)
      setc(avail and COL.ink or COL.dim)
      text(def.name, r.x + 28, r.y - 1, 'm')
      setc(COL.dim)
      text(classLine(def.classes), r.x + 28, r.y + 13, 's')
      local m = findMember(key)
      if m then
        local s = 'Lv' .. memberLevel(m)
        pill(s, r.x + r.w - pillW(s), r.y + 4, COL.mintText, COL.mintSoft)
      end
    end
  end

  local fy = CAT.y + CAT.h - 52
  setc(COL.grid)
  lg.setLineWidth(1)
  lg.line(CAT.x + 20, fy - 8, CAT.x + CAT.w - 20, fy - 8)
  if hovered then
    setc(COL.ink)
    text(hovered.name, CAT.x + 20, fy, 'm')
    setc(COL.mid)
    text(hovered.desc, CAT.x + 20, fy + 20, 's')
    local stats = {'HP ' .. math.floor(hovered.hp * HP_SCALE)}
    if hovered.dmg > 0 then stats[#stats + 1] = 'DMG ' .. hovered.dmg end
    if hovered.ram then stats[#stats + 1] = 'RAM ' .. hovered.ram end
    if not hovered.noAttack then stats[#stats + 1] = ('every %.1fs'):format(hovered.cd) end
    setc(COL.dim)
    text(table.concat(stats, '  ·  ') .. '  (at Lv1)', CAT.x + CAT.w - 420, fy + 2, 's', 'right', 400)
  else
    setc(COL.dim)
    text('Hover a module to read its exploit. Modules already in your worm show their level.', CAT.x + 20, fy + 8, 's')
  end
end

local function drawShop()
  local mx, my = getMouse()
  local l = run.level

  -- header
  local ls = ('level %02d/%d'):format(l, MAX_LEVEL)
  setc(COL.dim)
  text('root@networm:~/darkmarket#', 24, 6, 's')
  setc(COL.ink)
  text(ls, 24, 19, 'l')
  if isBoss(l) then pill('BOSS', 24 + textW(ls, 'l') + 12, 26, COL.bg, COL.red) end
  -- gold sits left of the catalogue button in the top-right corner
  local gs, gx = '$' .. run.gold, CATALOG_BTN.x - 16
  setc(COL.dim)
  text('gold', gx - 200, 6, 's', 'right', 200)
  setc(COL.gold)
  text(gs, gx - 200, 19, 'l', 'right', 200)
  if run.lastIncome then
    local s = '+' .. run.lastIncome
    pill(s, gx - textW(gs, 'l') - pillW(s) - 10, 26, COL.mintText, COL.mintSoft)
  end
  button(CATALOG_BTN, '[C] catalog', true, inRect(mx, my, CATALOG_BTN))

  -- shop level and the tier odds it gives
  local hx = 312
  setc(COL.dim)
  text(('market lv%d/%d  ·  tier odds'):format(run.shopLevel, SHOP_MAX), hx, 6, 's')
  local odds = SHOP_ODDS[run.shopLevel]
  for k = 1, 4 do
    local s = ('T%d  %d%%'):format(k, math.floor(odds[k] * 100 + 0.5))
    if odds[k] > 0 then
      hx = hx + pill(s, hx, 24, TIER_COL[k][1], TIER_COL[k][2]) + 6
    else
      hx = hx + pill(s, hx, 24, COL.light, COL.card) + 6
    end
  end

  -- party
  card(SH.px - 8, 56, SH.pw + 16, 444)
  setc(COL.ink)
  text('party/', SH.px + 4, 64, 'm')
  pill(('%d/%d'):format(#run.party, maxUnits(l)), SH.px + 14 + textW('party/', 'm'), 65, COL.mid, COL.grid)
  local ns = nextSlotLevel(l)
  local slotTxt = ns and ('+1 slot @ lvl ' .. ns) or 'all slots open'
  pill(slotTxt, SH.px + SH.pw - pillW(slotTxt) - 2, 65, ns and COL.mintText or COL.mid, ns and COL.mintSoft or COL.grid)
  for i, m in ipairs(run.party) do
    local r = rowRect(i)
    local lv = memberLevel(m)
    if inRect(mx, my, r) then
      setc(COL.hover)
      lg.rectangle('fill', r.x - 2, r.y - 2, r.w + 4, r.h + 4)
    end
    if i < #run.party then
      setc(COL.grid)
      lg.setLineWidth(1)
      lg.line(r.x + 4, r.y + r.h + 3, r.x + r.w - 4, r.y + r.h + 3)
    end
    marker(r.x + 18, r.y + 20, 9, m.def, nil, lv)
    setc(COL.ink)
    text(m.def.name, r.x + 38, r.y + 3, 'm')
    setc(COL.dim)
    text(classLine(m.def.classes), r.x + 38, r.y + 22, 's')
    local tag = lv == 3 and 'Lv3 max' or ('Lv%d %d/%d'):format(lv, m.copies, lv == 1 and 3 or 9)
    pill(tag, r.x + 46 + textW(m.def.name, 'm'), r.y + 4, lv == 3 and COL.bg or COL.mintText, lv == 3 and COL.gold or COL.mintSoft)
    if i > 1 then button(upRect(i), '^', true, inRect(mx, my, upRect(i))) end
    if i < #run.party then button(downRect(i), 'v', true, inRect(mx, my, downRect(i))) end
    button(sellRect(i), 'kill $' .. sellValue(m), true, inRect(mx, my, sellRect(i)))
  end
  setc(COL.dim)
  if #run.party == 0 then text('the worm has no modules.\nbuy one from the market ->', SH.px + 4, SH.py + 4, 'm') end
  text('# first unit = head of the worm\n# 3 copies -> Lv2, 9 copies -> Lv3', SH.px + 4, 466, 's')

  -- recruit cards
  for i = 1, 4 do
    local r = cardRect(i)
    local key = run.offers[i]
    local hover = inRect(mx, my, r)
    if key then
      local def = UNITS[key]
      local owned = findMember(key)
      local cost = COST[def.tier]
      local can = run.gold >= cost and (owned and owned.copies < 9 or (not owned and #run.party < maxUnits(l)))
      card(r.x, r.y, r.w, r.h)
      if hover then
        lg.setLineWidth(1)
        setc(COL.green)
        lg.rectangle('line', r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1)
      end
      pill('Tier ' .. def.tier, r.x + 8, r.y + 8, TIER_COL[def.tier][1], TIER_COL[def.tier][2])
      local cs = '$' .. cost
      pill(cs, r.x + r.w - 10 - pillW(cs), r.y + 8, can and COL.bg or COL.dim, can and COL.gold or COL.grid)
      marker(r.x + r.w / 2, r.y + 46, 12, def)
      setc(COL.ink)
      text(def.name, r.x, r.y + 66, 'm', 'center', r.w)
      setc(COL.mid)
      text(classLine(def.classes), r.x, r.y + 86, 's', 'center', r.w)
      setc(COL.dim)
      text(def.desc, r.x + 8, r.y + 104, 's', 'center', r.w - 16)
      local status, fg, bg = 'new', COL.mid, COL.grid
      if owned then status, fg, bg = ('owned · Lv%d'):format(memberLevel(owned)), COL.mintText, COL.mintSoft
      elseif #run.party >= maxUnits(l) then status = 'party full' end
      pill(status, r.x + (r.w - pillW(status)) / 2, r.y + r.h - 24, fg, bg)
    else
      setc(COL.line)
      lg.setLineWidth(1)
      lg.rectangle('line', r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1)
      setc(COL.light)
      text('[ sold ]', r.x, r.y + r.h / 2 - 9, 'm', 'center', r.w)
    end
  end

  button(REROLL_BTN, '[R] reroll $' .. REROLL_COST, run.gold >= REROLL_COST, inRect(mx, my, REROLL_BTN))
  local maxed = run.shopLevel >= SHOP_MAX
  local upCost = SHOP_UP_COST[run.shopLevel]
  button(SHOPUP_BTN, maxed and 'market maxed' or ('[U] upgrade $' .. upCost), not maxed and run.gold >= upCost, inRect(mx, my, SHOPUP_BTN))
  button(START_BTN, '[Space] inject lvl ' .. l, #run.party > 0, inRect(mx, my, START_BTN), true)

  -- class bonuses as a horizontal bar chart
  card(360, 340, 576, 184)
  setc(COL.ink)
  text('class bonuses', 376, 345, 'm')
  local counts = classCounts()
  for i, cl in ipairs(CLASS_ORDER) do
    local c = CLASSES[cl]
    local y = 368 + (i - 1) * 14
    local n, tier = counts[cl] or 0, classTier(counts, cl)
    setc(c.color, n > 0 and 1 or 0.35)
    glyph(cl, 380, y + 7, 3.5)
    setc(n > 0 and COL.ink or COL.dim)
    text(c.name, 392, y, 's')
    local bx, bw = 470, 150
    setc(COL.grid)
    lg.rectangle('fill', bx, y + 4, bw, 7)
    local f = math.min(1, n / c.tiers[2])
    if f > 0 then
      setc(tier > 0 and COL.green or COL.mid, tier > 0 and 1 or 0.6)
      lg.rectangle('fill', bx, y + 4, math.max(7, bw * f), 7)
    end
    setc(COL.bg)
    lg.setLineWidth(2)
    local tx = bx + bw * c.tiers[1] / c.tiers[2]
    lg.line(tx, y + 3, tx, y + 12)
    setc(tier > 0 and COL.green or COL.dim)
    text(('%d  (%d/%d)'):format(n, c.tiers[1], c.tiers[2]), 628, y, 's')
    if tier > 0 then
      setc(COL.ink)
      text(c.desc[tier], 700, y, 's')
    else
      setc(COL.dim)
      text(c.desc[1], 700, y, 's')
    end
  end

  if run.msg and run.msg.t > 0 then
    setc(run.msg.c, math.min(1, run.msg.t))
    ctext(run.msg.s, 648, 64, 'm')
  end

  setc(COL.dim)
  text('right-click: kill unit  ·  [Esc] menu', SH.px, H - 26, 's')

  if run.catalog then drawCatalogue(mx, my) end
end

---------------------------------------------------------------------------
-- drawing: menus
---------------------------------------------------------------------------
local MENU_BTN = {x = 182, y = 290, w = 220, h = 38}
local BOOT_LOG = {
  'ssh root@kernel ... access granted',
  'scp worm.ko /lib/modules/ ... 40 modules, 11 classes',
  'scan: hostile processes on /dev/arena0 (25 levels deep)',
  'hint: steer with [A]/[D]; modules fire on their own',
  'worm: awaiting operator...',
}

local function drawMenu()
  local mx, my = getMouse()
  card(150, 36, 660, 446)
  setc(COL.grid)
  lg.rectangle('fill', 151, 37, 658, 20)
  setc(COL.dim)
  text('tty1 - networm', 162, 40, 's')
  setc(COL.red); lg.circle('fill', 786, 47, 4)
  setc(COL.gold); lg.circle('fill', 772, 47, 4)
  setc(COL.green); lg.circle('fill', 758, 47, 4)

  -- dmesg-style boot log, typed out one line at a time
  local shown = math.min(#BOOT_LOG, math.floor(time / 0.35) + 1)
  for i = 1, shown do
    setc(COL.dim)
    text(('[%12.6f]'):format((i - 1) * 0.004211 + 0.000001), 172, 66 + (i - 1) * 16, 's')
    setc(i == #BOOT_LOG and COL.ink or COL.mid)
    text(BOOT_LOG[i], 282, 66 + (i - 1) * 16, 's')
  end

  setc(COL.green)
  text('NETWORM', 180, 160, 'xl')
  if math.floor(time * 2) % 2 == 0 then
    lg.rectangle('fill', 184 + textW('NETWORM', 'xl'), 172, 26, 52)
  end
  setc(COL.mid)
  text('you are the operator. steer the worm; its modules kill every process in reach.', 182, 240, 's')
  setc(COL.dim)
  text('25 levels  ·  40 modules  ·  11 classes  ·  5 market tiers', 182, 258, 's')
  button(MENU_BTN, '[Space] insmod worm.ko', true, inRect(mx, my, MENU_BTN), true)

  -- a little worm chasing processes around the bottom of the window
  for k = 0, 4 do
    local t = time * 0.7 + k * 1.3
    setc(COL.red)
    lg.push()
    lg.translate(W / 2 + math.cos(t * 1.1 + k) * 150, 410 + math.sin(t * 1.7) * 35)
    lg.rotate(t * 2)
    lg.rectangle('fill', -7, -7, 14, 14)
    lg.pop()
  end
  for i = 9, 0, -1 do
    local t = time * 1.3 - i * 0.11
    local x, y = W / 2 + math.cos(t) * 250, 410 + math.sin(t * 2) * 42
    local a = math.atan2(math.cos(t * 2) * 84, -math.sin(t) * 250)
    marker(x, y, 9, CLASS_ORDER[i % #CLASS_ORDER + 1], nil, nil, a, i == 0)
  end

  setc(COL.mid)
  ctext('steer the worm: [A]/[D] or [Left]/[Right]   ·   modules attack on their own', W / 2, 494, 's')
  setc(COL.dim)
  ctext('the kernel walls hurt. ramming a process hurts both sides. [P] pause  [M] music', W / 2, 512, 's')
end

local function drawEnd(title, c, sub)
  card(200, 110, 560, 300)
  setc(COL.dim)
  text('$ dmesg | tail -n 3', 222, 124, 's')
  setc(c)
  ctext(title, W / 2, 150, 'xl')
  setc(COL.ink)
  ctext(sub, W / 2, 232, 'm')
  local x = W / 2 - (#run.party - 1) * 15
  for i, m in ipairs(run.party) do marker(x + (i - 1) * 30, 290, 9, m.def, nil, memberLevel(m)) end
  setc(COL.dim)
  ctext('[Space] or click to reboot', W / 2, 350, 's')
end

---------------------------------------------------------------------------
-- LOVE callbacks
---------------------------------------------------------------------------
-- background music (desktop build). The web build leaves the track out of the
-- game package and plays it from the page instead, so this simply finds no file there.
local MUSIC_FILE = 'music/memory.mp3'
local music, musicOn = nil, true

function love.load()
  lg.setLineStyle('smooth')
  lg.setLineJoin('bevel')
  resize(lg.getDimensions())
  local ok = pcall(initSounds)
  if not ok then sfx = {} end
  if love.filesystem.getInfo(MUSIC_FILE) then
    local loaded, src = pcall(love.audio.newSource, MUSIC_FILE, 'stream')
    if loaded then
      music = src
      music:setLooping(true)
      music:setVolume(0.35)
      music:play()
    end
  end
end

function love.resize(w, h) resize(w, h) end

function love.update(dt)
  dt = math.min(dt, 1 / 30)
  time = time + dt
  if state == 'arena' and not paused then updateArena(dt) end
  if state == 'shop' and run.msg then run.msg.t = run.msg.t - dt end
end

function love.draw()
  lg.clear(COL.bg)
  lg.push()
  lg.translate(ox, oy)
  lg.scale(scale)
  setc(COL.bg)
  lg.rectangle('fill', 0, 0, W, H)
  if state == 'menu' then drawMenu()
  elseif state == 'shop' then drawShop()
  elseif state == 'arena' then drawArena()
  elseif state == 'gameover' then drawEnd('KERNEL PANIC', COL.red, 'not syncing: worm purged on level ' .. run.level)
  elseif state == 'win' then drawEnd('EXIT 0', COL.green, 'root obtained: all ' .. MAX_LEVEL .. ' levels cleared. the kernel is yours.')
  end
  -- CRT scanlines
  lg.setColor(0, 0, 0, 0.22)
  for y = 0, H, 3 do lg.rectangle('fill', 0, y, W, 1) end
  lg.pop()
end

local function reroll()
  if run.gold < REROLL_COST then play('error'); return end
  run.gold = run.gold - REROLL_COST
  rollOffers()
  play('click')
end

local function upgradeShop()
  if run.shopLevel >= SHOP_MAX then play('error'); shopMsg('The market is already max level', COL.red); return end
  local cost = SHOP_UP_COST[run.shopLevel]
  if run.gold < cost then play('error'); shopMsg('Upgrading the market costs $' .. cost, COL.red); return end
  run.gold = run.gold - cost
  run.shopLevel = run.shopLevel + 1
  play('buy')
  shopMsg('Market upgraded to level ' .. run.shopLevel .. ' - better odds from the next roll', COL.green)
end

local function tryStart()
  if #run.party == 0 then play('error'); shopMsg('The worm needs at least one module!', COL.red); return end
  play('click')
  startLevel()
end

function love.keypressed(key)
  if key == 'm' then
    musicOn = not musicOn
    if music then
      if musicOn then music:play() else music:pause() end
    end
    return
  end
  if state == 'menu' then
    if key == 'space' or key == 'return' then newRun()
    elseif key == 'escape' then love.event.quit() end
  elseif state == 'shop' then
    if run.catalog then
      if key == 'escape' or key == 'c' then run.catalog = false; play('click') end
    elseif key == 'space' or key == 'return' then tryStart()
    elseif key == 'r' then reroll()
    elseif key == 'u' then upgradeShop()
    elseif key == 'c' then run.catalog = true; play('click')
    elseif key == 'escape' then state = 'menu' end
  elseif state == 'arena' then
    if key == 'p' or key == 'escape' then paused = not paused
    elseif key == 'q' and paused then paused = false; state = 'menu' end
  elseif state == 'gameover' or state == 'win' then
    if key == 'space' or key == 'return' or key == 'escape' then state = 'menu' end
  end
end

function love.mousepressed(x, y, b)
  local mx, my = (x - ox) / scale, (y - oy) / scale
  if state == 'menu' then
    if b == 1 then play('click'); newRun() end
  elseif state == 'shop' then
    if run.catalog then
      if inRect(mx, my, CAT_CLOSE) or not inRect(mx, my, CAT) then run.catalog = false; play('click') end
      return
    end
    if inRect(mx, my, CATALOG_BTN) then run.catalog = true; play('click'); return end
    if inRect(mx, my, SHOPUP_BTN) then upgradeShop(); return end
    for i = 1, 4 do
      if inRect(mx, my, cardRect(i)) then buyOffer(i); return end
    end
    for i = #run.party, 1, -1 do
      if inRect(mx, my, sellRect(i)) then sellMember(i); return end
      if i > 1 and inRect(mx, my, upRect(i)) then moveMember(i, -1); return end
      if i < #run.party and inRect(mx, my, downRect(i)) then moveMember(i, 1); return end
      if b == 2 and inRect(mx, my, rowRect(i)) then sellMember(i); return end
    end
    if inRect(mx, my, REROLL_BTN) then reroll()
    elseif inRect(mx, my, START_BTN) then tryStart() end
  elseif state == 'gameover' or state == 'win' then
    if b == 1 then state = 'menu' end
  end
end
