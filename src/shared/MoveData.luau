--!strict
-- GENERATED from data/moves.json by tools/generate_move_module.py. Do not edit by hand.
local HttpService = game:GetService("HttpService")
local JSON = [====[
{
  "$comment": "Тестовая сборка: ТОЛЬКО стойка, 12 приёмов. Фреймдата в стиле UFC 4, 60 fps: startup/active/recovery - в кадрах. ВСЕ числа боя живут здесь: timing/stamina/damage/reaction - по приёмам, combat/balance/stamina/hurtboxes/dummy - общие правила. Код не хардкодит баланс. health - урон 0..100 по полоске здоровья, stamina - урон по выносливости, chipRatio - сколько проходит сквозь блок, knockback - импульс студах/сек.",
  "version": 4,
  "fps": 60,
  "combat": {
    "$comment": "правила боя: буфер ввода, нокдаун, стамина от статов, поворот бойца",
    "inputBufferWindowFrames": 10,
    "inputBufferMaxEntries": 3,
    "moveStartStaminaFraction": 0.35,
    "exhaustStunFrames": 12,
    "knockdownFrames": 90,
    "knockdownInvulnFrames": 30,
    "getupInvulnFrames": 12,
    "koKnockdownFrames": 1000000,
    "turnDegreesPerSecond": 720,
    "staminaPoolMid": 50,
    "staminaPerPoolPoint": 0.6,
    "regenPoolBase": 5.0,
    "regenPoolSpan": 4.0
  },
  "balance": {
    "$comment": "коэффициенты resolveHit/consumeHit: урон, блок, стаггер, нокдауны",
    "powerMin": 0.85,
    "powerSpan": 0.3,
    "chinWorst": 1.15,
    "chinBest": 0.85,
    "blockStaminaMul": 1.35,
    "blockStunMul": 0.35,
    "blockHoldGraceFrames": 30,
    "blockHoldMaxBonus": 0.5,
    "blockHoldBonusFrames": 120,
    "stunnedStunMul": 1.25,
    "blockedKnockdownMul": 0.15,
    "fatigueKnockdownBonus": 0.45,
    "knockdownMinStunFrames": 40,
    "knockdownDamageMul": 0.85,
    "knockdownKnockbackMul": 1.6
  },
  "stamina": {
    "$comment": "модель выносливости и кривые скорости/урона от усталости",
    "max": 100,
    "regenPerSecondIdle": 6.5,
    "regenPerSecondMoving": 3.2,
    "regenPerSecondBlocking": 1.4,
    "regenDelayAfterSprint": 1.6,
    "exhaustedThreshold": 8,
    "recoveryTo": 25,
    "speedBase": 0.7,
    "speedSpan": 0.3,
    "speedExhausted": 0.55,
    "damageBase": 0.75,
    "damageSpan": 0.25
  },
  "hurtboxes": [
    { "name": "head", "bone": "Head", "size": [1.6, 1.6, 1.6], "level": "high" },
    { "name": "torso", "bone": "UpperTorso", "size": [2.6, 2.4, 1.6], "level": "mid" },
    { "name": "legs", "bone": "LowerTorso", "size": [2.2, 2.6, 1.6], "level": "low" }
  ],
  "dummy": {
    "$comment": "настройки манекена (DummyController): режимы static/blocks/fights",
    "blockRange": 8,
    "maxAttackDistance": 10,
    "minStaminaRatio": 0.25,
    "reachPadding": 2,
    "strikeCooldownFrames": 24,
    "strikeCooldownRandomFrames": 20
  },
  "moves": [
    {
      "id": "jab",
      "name": "Jab (lead hand)",
      "category": "strike",
      "timing": { "startup": 7, "active": 3, "recovery": 9 },
      "stamina": { "cost": 4, "costPerActiveFrame": 0.4 },
      "damage": { "health": 5.5, "stamina": 6, "chipRatio": 0.08 },
      "reaction": { "stunFrames": 10, "knockdownChance": 0.0, "floorStamina": 0.15, "knockback": 3 },
      "hitbox": { "bone": "RightHand", "size": [1.6, 1.6, 1.6], "offset": [0, 0, -0.6], "reach": 5.2 },
      "hitLevel": "high",
      "cancel": ["cross", "hook_left", "kick_low"],
      "props": { "movesCharacter": false }
    },
    {
      "id": "cross",
      "name": "Cross (rear hand)",
      "category": "strike",
      "timing": { "startup": 12, "active": 4, "recovery": 16 },
      "stamina": { "cost": 8, "costPerActiveFrame": 0.5 },
      "damage": { "health": 11, "stamina": 10, "chipRatio": 0.07 },
      "reaction": { "stunFrames": 18, "knockdownChance": 0.05, "floorStamina": 0.3, "knockback": 8 },
      "hitbox": { "bone": "LeftHand", "size": [1.7, 1.7, 1.7], "offset": [0, 0, -0.7], "reach": 5.6 },
      "hitLevel": "high",
      "cancel": ["hook_right", "kick_body"],
      "props": { "movesCharacter": true }
    },
    {
      "id": "hook_left",
      "name": "Hook (lead)",
      "category": "strike",
      "timing": { "startup": 13, "active": 4, "recovery": 18 },
      "stamina": { "cost": 9, "costPerActiveFrame": 0.5 },
      "damage": { "health": 12, "stamina": 11, "chipRatio": 0.06 },
      "reaction": { "stunFrames": 20, "knockdownChance": 0.07, "floorStamina": 0.35, "knockback": 10 },
      "hitbox": { "bone": "RightHand", "size": [1.8, 1.8, 1.8], "offset": [0.4, 0, -0.5], "reach": 4.6 },
      "hitLevel": "high",
      "props": { "movesCharacter": true }
    },
    {
      "id": "hook_right",
      "name": "Hook (rear)",
      "category": "strike",
      "timing": { "startup": 16, "active": 4, "recovery": 22 },
      "stamina": { "cost": 12, "costPerActiveFrame": 0.6 },
      "damage": { "health": 15, "stamina": 14, "chipRatio": 0.05 },
      "reaction": { "stunFrames": 24, "knockdownChance": 0.12, "floorStamina": 0.35, "knockback": 14 },
      "hitbox": { "bone": "LeftHand", "size": [1.8, 1.8, 1.8], "offset": [-0.4, 0, -0.5], "reach": 4.6 },
      "hitLevel": "high",
      "props": { "movesCharacter": true }
    },
    {
      "id": "uppercut_right",
      "name": "Uppercut",
      "category": "strike",
      "timing": { "startup": 14, "active": 3, "recovery": 20 },
      "stamina": { "cost": 10 },
      "damage": { "health": 13, "stamina": 12, "chipRatio": 0.05 },
      "reaction": { "stunFrames": 22, "knockdownChance": 0.1, "floorStamina": 0.3, "knockback": 9 },
      "hitbox": { "bone": "LeftHand", "size": [1.6, 2.0, 1.6], "offset": [0, 0.5, -0.6], "reach": 4.2 },
      "hitLevel": "high",
      "props": {}
    },
    {
      "id": "overhand_right",
      "name": "Overhand right",
      "category": "strike",
      "timing": { "startup": 22, "active": 4, "recovery": 28 },
      "stamina": { "cost": 16 },
      "damage": { "health": 22, "stamina": 18, "chipRatio": 0.04 },
      "reaction": { "stunFrames": 30, "knockdownChance": 0.2, "floorStamina": 0.4, "knockback": 22 },
      "hitbox": { "bone": "LeftHand", "size": [1.9, 1.9, 1.9], "offset": [0, 0.3, -0.8], "reach": 5.4 },
      "hitLevel": "high",
      "props": { "movesCharacter": true, "armorFrames": [22, 26] }
    },
    {
      "id": "kick_low",
      "name": "Low kick / calf kick",
      "category": "strike",
      "timing": { "startup": 14, "active": 5, "recovery": 20 },
      "stamina": { "cost": 10 },
      "damage": { "health": 8, "stamina": 16, "chipRatio": 0.1 },
      "reaction": { "stunFrames": 16, "knockdownChance": 0.03, "floorStamina": 0.2, "knockback": 6 },
      "hitbox": { "bone": "RightFoot", "size": [1.6, 1.4, 2.2], "offset": [0, 0, -0.4], "reach": 6.4 },
      "hitLevel": "low",
      "props": {}
    },
    {
      "id": "kick_body",
      "name": "Body kick",
      "category": "strike",
      "timing": { "startup": 17, "active": 5, "recovery": 24 },
      "stamina": { "cost": 14 },
      "damage": { "health": 14, "stamina": 20, "chipRatio": 0.08 },
      "reaction": { "stunFrames": 24, "knockdownChance": 0.08, "floorStamina": 0.3, "knockback": 12 },
      "hitbox": { "bone": "RightFoot", "size": [1.6, 1.6, 2.4], "offset": [0, 0, -0.4], "reach": 7.2 },
      "hitLevel": "mid",
      "props": { "movesCharacter": true }
    },
    {
      "id": "kick_head",
      "name": "Head kick",
      "category": "strike",
      "timing": { "startup": 19, "active": 4, "recovery": 28 },
      "stamina": { "cost": 18 },
      "damage": { "health": 24, "stamina": 18, "chipRatio": 0.05 },
      "reaction": { "stunFrames": 32, "knockdownChance": 0.3, "floorStamina": 0.45, "knockback": 26 },
      "hitbox": { "bone": "RightFoot", "size": [1.5, 1.5, 2.6], "offset": [0, 0.8, -0.4], "reach": 7.6 },
      "hitLevel": "high",
      "props": { "movesCharacter": true }
    },
    {
      "id": "block",
      "name": "Block / guard",
      "category": "defense",
      "timing": { "startup": 3, "active": 9999, "recovery": 6 },
      "stamina": { "cost": 1, "costPerActiveFrame": 0.12 },
      "damage": { "health": 0, "stamina": 0, "chipRatio": 0 },
      "reaction": { "stunFrames": 0, "knockdownChance": 0, "floorStamina": 0, "knockback": 0 },
      "props": { "holdToCharge": true }
    },
    {
      "id": "slip",
      "name": "Slip (head movement)",
      "category": "defense",
      "timing": { "startup": 4, "active": 8, "recovery": 10 },
      "stamina": { "cost": 6 },
      "damage": { "health": 0, "stamina": 0, "chipRatio": 0 },
      "reaction": { "stunFrames": 0, "knockdownChance": 0, "floorStamina": 0, "knockback": 0 },
      "cancel": ["cross", "hook_right", "uppercut_right"],
      "props": {}
    },
    {
      "id": "duck",
      "name": "Duck / roll under",
      "category": "defense",
      "timing": { "startup": 5, "active": 10, "recovery": 12 },
      "stamina": { "cost": 8 },
      "damage": { "health": 0, "stamina": 0, "chipRatio": 0 },
      "reaction": { "stunFrames": 0, "knockdownChance": 0, "floorStamina": 0, "knockback": 0 },
      "cancel": ["hook_left"],
      "props": {}
    }
  ]
}

]====]
return HttpService:JSONDecode(JSON)
