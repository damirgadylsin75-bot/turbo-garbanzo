#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
simulate.py — headless-симулятор боёв для автобаланса фреймдаты.

Зачем: чтобы не подбирать числа «на глаз» в Studio, гоняем тысячи боёв
бот-vs-бот на тех же формулах, что и в Luau (FrameData.resolveHit,
StaminaSystem), собираем CSV и скармливаем нейросети на анализ
(см. docs/ai-workflow.md, промпт «Автобаланс»).

Запуск:
    python3 tools/simulate.py                        # 2000 боёв -> build/sim/
    python3 tools/simulate.py --fights 10000 --seed 7
    python3 tools/simulate.py --report               # только показать отчёт из CSV

Результат:
    build/sim/moves_stats.csv   — по каждому муву: использования, попадания, урон, нокдауны
    build/sim/fights.csv        — по каждому бою: победитель, длительность, KO/решение
    build/sim/report.txt        — человекочитаемый отчёт + флаги для балансировки

Важно: формулы здесь обязаны совпадать с src/shared/FrameData.luau и
src/shared/StaminaSystem.luau. Меняешь одно — меняй и другое
(проверка: tools/luau_syntax_check.py + тесты TestEZ).
"""

import argparse
import csv
import json
import math
import os
import random
import sys
from collections import defaultdict

DATA_PATH = os.path.join("data", "moves.json")
FIGHTERS_PATH = os.path.join("data", "fighters.json")
OUT_DIR = os.path.join("build", "sim")

FPS = 60
FRAME = 1.0 / FPS


# ---------------------------------------------------------------- данные

def load_moves(path=DATA_PATH):
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    moves = {}
    for m in data.get("moves", []):
        moves[m["id"]] = m
    return data, moves


def load_fighters(path=FIGHTERS_PATH):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f).get("fighters", {})
    except OSError:
        return {}


# ---------------------------------------------------------------- стамина (порт StaminaSystem.luau)

DEFAULT_STAMINA = {
    "max": 100.0,
    "regenPerSecondIdle": 6.5,
    "regenPerSecondMoving": 3.2,
    "regenPerSecondBlocking": 1.4,
    "regenPerSecondGrappling": 0.4,
    "regenDelayAfterSprint": 1.6,
    "exhaustedThreshold": 8.0,
    "recoveryTo": 25.0,
}

REGEN_BY_ACTIVITY = {
    "idle": "regenPerSecondIdle",
    "moving": "regenPerSecondMoving",
    "blocking": "regenPerSecondBlocking",
    "grappling": "regenPerSecondGrappling",
    "attacking": "regenPerSecondIdle",
}


class Stamina:
    def __init__(self, cfg, pool_stat=50):
        self.cfg = dict(cfg)
        self.cfg["max"] = cfg["max"] + (pool_stat - 50) * 0.6
        self.cfg["regenPerSecondIdle"] = 5.0 + (pool_stat / 100.0) * 4.0
        self.value = self.cfg["max"]
        self.exhausted = False

    def spend(self, amount):
        if amount <= 0:
            return True
        if self.value < amount:
            return False
        self.value -= amount
        if self.value <= self.cfg["exhaustedThreshold"]:
            self.exhausted = True
        return True

    def take_damage(self, amount):
        self.value = max(0.0, self.value - amount)
        if self.value <= self.cfg["exhaustedThreshold"]:
            self.exhausted = True

    def regen(self, dt, activity):
        key = REGEN_BY_ACTIVITY.get(activity, "regenPerSecondIdle")
        rate = self.cfg[key] if activity != "attacking" else self.cfg["regenPerSecondIdle"] * 0.5
        if self.exhausted:
            self.value += rate * dt * 1.8
            if self.value >= self.cfg["recoveryTo"]:
                self.exhausted = False
        else:
            self.value += rate * dt
        self.value = min(self.cfg["max"], self.value)

    def ratio(self):
        return self.value / max(1e-6, self.cfg["max"])

    def speed_multiplier(self):
        if self.exhausted:
            return 0.55
        return 0.70 + 0.30 * max(0.0, min(1.0, self.ratio()))


# ---------------------------------------------------------------- математика (порт FightMath.luau)

def clamp(v, lo, hi):
    return lo if v < lo else (hi if v > hi else v)


def remap(v, in_min, in_max, out_min, out_max):
    t = (v - in_min) / max(1e-6, in_max - in_min)
    t = clamp(t, 0.0, 1.0)
    return out_min + (out_max - out_min) * t


def stat_to_multiplier(stat):
    return remap(stat, 0, 100, 0.85, 1.15)


def contest_chance(attack, defense, attack_stamina, defense_stamina):
    a = attack * (0.6 + 0.4 * clamp(attack_stamina, 0, 1))
    d = defense * (0.6 + 0.4 * clamp(defense_stamina, 0, 1))
    return clamp(a / max(1e-6, a + d), 0.05, 0.95)


def total_frames(move):
    t = move["timing"]
    return t["startup"] + t["active"] + t["recovery"]


def cancel_window(move):
    t = move["timing"]
    return max(1, t["startup"] - 4), min(t["startup"] + t["active"] + 3, total_frames(move))


# ---------------------------------------------------------------- resolveHit (порт FrameData.luau)

def resolve_hit(move, attacker_power, defender, rng):
    blocked = defender.blocking and not defender.stunned
    dmg = move.get("damage", {})
    react = move.get("reaction", {})

    power_mul = 0.85 + (attacker_power / 100.0) * 0.30
    health_damage = dmg.get("health", 0) * power_mul
    stamina_damage = dmg.get("stamina", 0) * power_mul

    if blocked:
        health_damage *= dmg.get("chipRatio", 0.08)
        stamina_damage *= 1.35
        if defender.block_held_frames > 30:
            stamina_damage *= 1.0 + min(0.5, (defender.block_held_frames - 30) / 120.0)

    stun = react.get("stunFrames", 8)
    if blocked:
        stun = int(stun * 0.35)
    elif defender.stunned:
        stun = int(stun * 1.25)

    knockdown = False
    ratio = defender.stamina.ratio()
    floor = react.get("floorStamina", 0.2)
    chance = react.get("knockdownChance", 0.0) * power_mul
    if ratio <= floor:
        fatigue = 1.0 - (ratio / max(0.001, floor))
        chance += fatigue * 0.45
    if blocked or defender.grounded:
        chance *= 0.15
    if not blocked and rng.random() < chance:
        knockdown = True
        stun = max(stun, 40)

    return {
        "blocked": blocked,
        "health_damage": health_damage,
        "stamina_damage": stamina_damage,
        "stun": stun,
        "knockdown": knockdown,
        "knockback": react.get("knockback", 0) * (1.6 if knockdown else 1.0),
    }


# ---------------------------------------------------------------- боец

class Fighter:
    def __init__(self, name, stats, rng, archetype="balanced"):
        self.name = name
        self.stats = stats
        self.rng = rng
        self.archetype = archetype
        self.health = 100.0
        self.stamina = Stamina(DEFAULT_STAMINA, stats.get("staminaPool", 50))
        self.move = None
        self.move_frame = 0
        self.stun_frames = 0
        self.blocking = False
        self.block_held_frames = 0
        self.grounded = False
        self.getup_frames = 0
        self.distance = 8.0
        self.knockdowns_taken = 0
        self.decision_loss = False
        # один мув = максимум одно попадание (аналог hitConsumed в MatchServer.luau)
        self.hit_done = False

    @property
    def stunned(self):
        return self.stun_frames > 0

    @property
    def phase(self):
        if not self.move:
            return "none"
        t = self.move["timing"]
        if self.move_frame <= t["startup"]:
            return "startup"
        if self.move_frame <= t["startup"] + t["active"]:
            return "active"
        if self.move_frame <= total_frames(self.move):
            return "recovery"
        return "none"

    def can_act(self):
        if self.stun_frames > 0 or self.grounded or self.getup_frames > 0:
            return False
        if self.move:
            s, e = cancel_window(self.move)
            return s <= self.move_frame <= e
        return True

    def begin_move(self, move):
        if not self.can_act():
            return False
        if move.get("props", {}).get("onGroundOnly") and not self.grounded:
            return False
        if move.get("props", {}).get("standingOnly") and self.grounded:
            return False
        if not self.stamina.spend(move.get("stamina", {}).get("cost", 5) * 0.35):
            self.stun_frames = max(self.stun_frames, 12)
            return False
        self.move = move
        self.move_frame = 1
        self.blocking = False
        self.hit_done = False
        return True

    def consume_hit(self, result):
        chin_mul = remap(self.stats.get("chin", 50), 0, 100, 1.15, 0.85)
        dmg = result["health_damage"] * chin_mul
        if result["knockdown"]:
            dmg *= 0.85
        self.health = max(0.0, self.health - dmg)
        self.stamina.take_damage(result["stamina_damage"])

        was_in_startup = self.move is not None and self.phase == "startup"

        if result["knockdown"] and not result["blocked"]:
            self.move = None
            self.move_frame = 0
            self.grounded = True
            self.getup_frames = 90
            self.stun_frames = 0
            self.knockdowns_taken += 1
            return

        # Прерывание: попадание в замах ломает мув. Именно это делает быстрые
        # удары (джеб 7f) ценными против медленных (spinning_back_kick 26f) —
        # без прерывания бот всегда выгодно размениваться самым сильным мувом.
        if result["stun"] > 0:
            self.stun_frames = max(self.stun_frames, result["stun"])
            if was_in_startup and not result["blocked"]:
                self.move = None
                self.move_frame = 0

    def update(self, dt):
        if self.getup_frames > 0:
            self.getup_frames -= 1
            if self.getup_frames <= 0:
                self.grounded = False
            self.block_held_frames = 0
            return

        activity = "idle"
        if self.blocking:
            activity = "blocking"
            self.block_held_frames += 1
        elif self.move:
            activity = "attacking"
        elif self.grounded:
            activity = "grappling"
        else:
            activity = "moving"
        self.stamina.regen(dt, activity)

        if self.stun_frames > 0:
            self.stun_frames -= 1
            return

        if self.move:
            self.move_frame += 1
            per = self.move.get("stamina", {}).get("costPerActiveFrame", 0)
            if self.phase == "active" and per:
                self.stamina.take_damage(per)
            if self.move_frame > total_frames(self.move):
                self.move = None
                self.move_frame = 0


# ---------------------------------------------------------------- стратегии ботов

ARCHETYPES = {
    "aggressive": {
        "preferred_range": 4.2,
        "block_chance": 0.15,
        "attack_bias": 0.85,
        "power_stat": "punchPower",
        "cooldown": 14,
    },
    "counter": {
        "preferred_range": 6.0,
        "block_chance": 0.6,
        "attack_bias": 0.45,
        "power_stat": "punchPower",
        "cooldown": 22,
    },
    "kicker": {
        "preferred_range": 7.0,
        "block_chance": 0.3,
        "attack_bias": 0.6,
        "power_stat": "kickPower",
        "cooldown": 20,
    },
    "grappler": {
        "preferred_range": 3.6,
        "block_chance": 0.25,
        "attack_bias": 0.7,
        "power_stat": "groundPound",
        "cooldown": 16,
    },
}


class BotBrain:
    def __init__(self, fighter, archetype, rng):
        self.f = fighter
        self.cfg = ARCHETYPES[archetype]
        self.rng = rng
        self.cooldown = 0

    def choose(self, moves, opponent):
        f = self.f
        self.cooldown -= 1

        # движение к идеальной дистанции
        speed = 0.06 * f.stamina.speed_multiplier()
        if f.distance > self.cfg["preferred_range"]:
            f.distance = max(self.cfg["preferred_range"], f.distance - speed)
        elif f.distance < self.cfg["preferred_range"] * 0.6:
            f.distance += speed

        # защита
        threat = opponent.move and opponent.phase in ("startup", "active")
        f.blocking = bool(threat and self.rng.random() < self.cfg["block_chance"] and f.distance < 8)
        if f.blocking or threat:
            return None

        if self.cooldown > 0 or f.stamina.ratio() < 0.18:
            return None

        # выбор мува по скорингу (та же логика, что в BotController.luau)
        candidates = []
        for m in moves.values():
            if m.get("category") not in ("strike",):
                continue
            if m.get("props", {}).get("standingOnly") and f.grounded:
                continue
            hb = m.get("hitbox") or {}
            reach = hb.get("reach", 4.0)
            if abs(f.distance - reach) > 1.6:
                continue
            cost = m.get("stamina", {}).get("cost", 5)
            if cost > f.stamina.value:
                continue
            aggression = self.cfg["attack_bias"]
            commitment = m["timing"]["startup"] + m["timing"]["recovery"]
            raw = m.get("damage", {}).get("health", 0)
            kd = m.get("reaction", {}).get("knockdownChance", 0.0)

            # Нормируем урон на «цену окна» (как в UFC 4: риск наказания)
            # и даём бонус быстрым мувам — они прерывают медленные.
            speed_bonus = max(0.0, (26 - m["timing"]["startup"])) * 0.22 * aggression
            score = (
                (raw + kd * 12) * (36.0 / max(12.0, commitment))
                - commitment * 0.045 * (1.4 - aggression)
                + speed_bonus
                - abs(f.distance - reach) * 2.0
                - cost * 0.06
                + self.rng.uniform(-2.5, 2.5)
            )
            candidates.append((score, m))

        if not candidates:
            return None
        candidates.sort(key=lambda x: x[0], reverse=True)
        if self.rng.random() > self.cfg["attack_bias"]:
            return None
        self.cooldown = self.cfg["cooldown"] + self.rng.randint(0, 12)
        return candidates[0][1]


# ---------------------------------------------------------------- бой

def simulate_fight(moves, fighters_cfg, rng, max_seconds=300):
    names = list(fighters_cfg.keys())[:2]
    if len(names) < 2:
        names = ["default", "bot"]
        fighters_cfg = {
            "default": fighters_cfg.get("default", {}),
            "bot": fighters_cfg.get("bot", {}),
        }
    archetypes = list(ARCHETYPES.keys())
    a_arch = rng.choice(archetypes)
    b_arch = rng.choice(archetypes)

    a = Fighter(names[0], fighters_cfg[names[0]], rng, a_arch)
    b = Fighter(names[1], fighters_cfg[names[1]], rng, b_arch)
    brain_a = BotBrain(a, a_arch, rng)
    brain_b = BotBrain(b, b_arch, rng)

    move_stats = defaultdict(lambda: {
        "uses": 0, "hits": 0, "blocked_hits": 0, "damage": 0.0,
        "stamina_damage": 0.0, "knockdowns": 0, "stamina_spent": 0.0,
    })

    tick = 0
    max_ticks = int(max_seconds * FPS)
    winner = None
    finish = "timeout"

    while tick < max_ticks:
        tick += 1

        for f, brain, opp in ((a, brain_a, b), (b, brain_b, a)):
            f.update(FRAME)
            if f.health <= 0:
                continue
            chosen = brain.choose(moves, opp)
            if chosen and f.begin_move(chosen):
                move_stats[chosen["id"]]["uses"] += 1
                move_stats[chosen["id"]]["stamina_spent"] += chosen.get("stamina", {}).get("cost", 5) * 0.35

        # разрешение попаданий
        for attacker, defender in ((a, b), (b, a)):
            if not attacker.move or attacker.phase != "active" or attacker.hit_done:
                continue
            hb = attacker.move.get("hitbox") or {}
            reach = hb.get("reach", 4.0)
            if defender.distance > reach + 0.5:
                continue
            # шанс попасть зависит от того, защищается ли соперник
            hit_chance = 0.85 if not defender.blocking else 0.45
            if defender.stun_frames > 0:
                hit_chance = 0.95
            if rng.random() > hit_chance:
                continue

            power_stat = attacker.stats.get("punchPower", 60)
            if attacker.move["id"].startswith("kick") or attacker.move["id"].endswith("kick"):
                power_stat = attacker.stats.get("kickPower", power_stat)
            result = resolve_hit(attacker.move, power_stat, defender, rng)
            defender.consume_hit(result)
            attacker.hit_done = True

            st = move_stats[attacker.move["id"]]
            st["hits"] += 1
            if result["blocked"]:
                st["blocked_hits"] += 1
            st["damage"] += result["health_damage"]
            st["stamina_damage"] += result["stamina_damage"]
            if result["knockdown"]:
                st["knockdowns"] += 1

        if a.health <= 0 or b.health <= 0:
            winner = names[0] if b.health <= 0 else names[1]
            finish = "KO"
            break

    if winner is None:
        winner = names[0] if a.health > b.health else names[1]
        finish = "decision"

    return {
        "winner": winner,
        "finish": finish,
        "ticks": tick,
        "seconds": round(tick * FRAME, 2),
        "health_a": round(a.health, 2),
        "health_b": round(b.health, 2),
        "arch_a": a_arch,
        "arch_b": b_arch,
        "knockdowns_a": a.knockdowns_taken,
        "knockdowns_b": b.knockdowns_taken,
    }, move_stats


# ---------------------------------------------------------------- отчёт

def aggregate(fights, n):
    wins = defaultdict(int)
    finishes = defaultdict(int)
    total_seconds = 0.0
    for f in fights:
        wins[f["winner"]] += 1
        finishes[f["finish"]] += 1
        total_seconds += f["seconds"]
    return wins, finishes, total_seconds / max(1, n)


def flag_moves(move_stats):
    """Флаги для балансировки: что явно пере- или недо-тюнено."""
    flags = []
    for mid, s in sorted(move_stats.items()):
        uses = s["uses"]
        if uses < 20:
            flags.append((mid, "низкое использование", f"uses={uses}"))
            continue
        acc = s["hits"] / uses
        dmg_per_hit = s["damage"] / max(1, s["hits"])
        dmg_per_use = s["damage"] / uses
        kd_rate = s["knockdowns"] / max(1, s["hits"])
        if acc > 0.75:
            flags.append((mid, "слишком точный", f"accuracy={acc:.2f}"))
        if acc < 0.15:
            flags.append((mid, "почти не попадает", f"accuracy={acc:.2f}"))
        if dmg_per_use > 9:
            flags.append((mid, "пере-урон на использование", f"dmg/use={dmg_per_use:.2f}"))
        if dmg_per_use < 0.8 and uses > 100:
            flags.append((mid, "недо-урон (спамится впустую)", f"dmg/use={dmg_per_use:.2f}"))
        if kd_rate > 0.25:
            flags.append((mid, "слишком часто роняет", f"kd/hit={kd_rate:.2f}"))
    return flags


def write_outputs(fights, move_stats, n, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    fights_path = os.path.join(out_dir, "fights.csv")
    moves_path = os.path.join(out_dir, "moves_stats.csv")
    report_path = os.path.join(out_dir, "report.txt")

    if fights:
        with open(fights_path, "w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=list(fights[0].keys()))
            w.writeheader()
            w.writerows(fights)

    with open(moves_path, "w", newline="", encoding="utf-8") as f:
        fields = ["move_id", "uses", "hits", "accuracy", "blocked_hits", "damage",
                  "damage_per_use", "damage_per_hit", "stamina_damage", "knockdowns",
                  "knockdown_rate", "stamina_spent"]
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for mid, s in sorted(move_stats.items(), key=lambda kv: -kv[1]["uses"]):
            uses = s["uses"]
            hits = s["hits"]
            w.writerow({
                "move_id": mid,
                "uses": uses,
                "hits": hits,
                "accuracy": round(hits / uses, 4) if uses else 0,
                "blocked_hits": s["blocked_hits"],
                "damage": round(s["damage"], 1),
                "damage_per_use": round(s["damage"] / uses, 3) if uses else 0,
                "damage_per_hit": round(s["damage"] / hits, 3) if hits else 0,
                "stamina_damage": round(s["stamina_damage"], 1),
                "knockdowns": s["knockdowns"],
                "knockdown_rate": round(s["knockdowns"] / hits, 4) if hits else 0,
                "stamina_spent": round(s["stamina_spent"], 1),
            })

    wins, finishes, avg_seconds = aggregate(fights, n)
    flags = flag_moves(move_stats)

    lines = []
    lines.append(f"Симуляция: {n} боёв, средняя длительность {avg_seconds:.1f} сек")
    lines.append("")
    lines.append("Исходы:")
    for k, v in sorted(finishes.items(), key=lambda kv: -kv[1]):
        lines.append(f"  {k}: {v} ({v / max(1, n) * 100:.1f}%)")
    lines.append("")
    lines.append("Победы по бойцам:")
    for k, v in sorted(wins.items(), key=lambda kv: -kv[1]):
        lines.append(f"  {k}: {v} ({v / max(1, n) * 100:.1f}%)")
    lines.append("")
    lines.append("Топ мувов по использованиям:")
    top = sorted(move_stats.items(), key=lambda kv: -kv[1]["uses"])[:12]
    for mid, s in top:
        acc = s["hits"] / s["uses"] if s["uses"] else 0
        dpu = s["damage"] / s["uses"] if s["uses"] else 0
        lines.append(
            f"  {mid:<24} uses={s['uses']:<6} acc={acc:.2f} dmg/use={dpu:.2f} kd={s['knockdowns']}"
        )
    lines.append("")
    lines.append(f"Флаги для балансировки ({len(flags)}):")
    for mid, reason, detail in flags:
        lines.append(f"  - {mid}: {reason} ({detail})")
    lines.append("")
    lines.append("Что дальше: скорми moves_stats.csv нейросети с промптом «Автобаланс»")
    lines.append("из docs/ai-workflow.md — получишь diff к data/moves.json.")

    report = "\n".join(lines)
    with open(report_path, "w", encoding="utf-8") as f:
        f.write(report + "\n")

    return report, fights_path, moves_path, report_path


def main():
    ap = argparse.ArgumentParser(description="Headless-симулятор боёв для автобаланса")
    ap.add_argument("--fights", type=int, default=2000)
    ap.add_argument("--seed", type=int, default=None)
    ap.add_argument("--max-seconds", type=float, default=300.0)
    ap.add_argument("--out", default=OUT_DIR)
    ap.add_argument("--moves", default=DATA_PATH)
    ap.add_argument("--fighters", default=FIGHTERS_PATH)
    ap.add_argument("--report", action="store_true", help="только показать существующий отчёт")
    args = ap.parse_args()

    if args.report:
        path = os.path.join(args.out, "report.txt")
        if not os.path.exists(path):
            print(f"нет отчёта: {path}. Сначала запусти симуляцию.", file=sys.stderr)
            return 1
        print(open(path, encoding="utf-8").read())
        return 0

    data, moves = load_moves(args.moves)
    fighters_cfg = load_fighters(args.fighters)
    if not fighters_cfg:
        fighters_cfg = {"default": {}, "bot": {}}

    rng = random.Random(args.seed)
    all_fights = []
    totals = defaultdict(lambda: {
        "uses": 0, "hits": 0, "blocked_hits": 0, "damage": 0.0,
        "stamina_damage": 0.0, "knockdowns": 0, "stamina_spent": 0.0,
    })

    for i in range(args.fights):
        result, stats = simulate_fight(moves, fighters_cfg, rng, args.max_seconds)
        all_fights.append(result)
        for mid, s in stats.items():
            for k, v in s.items():
                totals[mid][k] += v
        if (i + 1) % 500 == 0:
            print(f"\rбоёв: {i + 1}/{args.fights}", end="", file=sys.stderr)

    print("", file=sys.stderr)
    report, fp, mp, rp = write_outputs(all_fights, totals, args.fights, args.out)
    print(report)
    print()
    print(f"CSV боёв:  {fp}")
    print(f"CSV мувов: {mp}")
    print(f"Отчёт:     {rp}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
