#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
calibrate.py — помощник калибровки фреймдаты под UFC 4.

Две задачи:
  1) --check   : валидирует data/moves.json (схема, инварианты, ссылки на позиции)
  2) --measure : считает startup/active/recovery из CSV, который ты получаешь
                 покадровым трекингом (MediaPipe/OpenCV), и печатает готовый JSON-кусок

Формат CSV для --measure:
  frame,wrist_r_x,wrist_r_y,ankle_r_x,ankle_r_y
  0,0.51,0.42,...
Модель ищет пик скорости выбранной точки: это кадр контакта (F1).

Примеры:
  python3 tools/calibrate.py --check data/moves.json
  python3 tools/calibrate.py --measure clip_jab.csv --point wrist_r --fps 60 --id jab --recovery 9
"""

import argparse
import csv
import json
import math
import sys

GROUND_POSITIONS = {
    "standing", "clinch",
    "guard_top", "guard_bottom",
    "side_top", "side_bottom",
    "mount_top", "mount_bottom",
    "back_top", "back_bottom",
}

REQUIRED_TIMING = ("startup", "active", "recovery")
STRIKE_CATEGORIES = {"strike", "ground_strike"}


def load_moves(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def check(path):
    data = load_moves(path)
    moves = data.get("moves", [])
    errors = []
    ids = set()

    if not moves:
        errors.append("нет ни одного мува")

    for i, m in enumerate(moves):
        tag = m.get("id", f"#{i}")
        if tag in ids:
            errors.append(f"{tag}: дублирующийся id")
        ids.add(tag)

        timing = m.get("timing") or {}
        for key in REQUIRED_TIMING:
            if key not in timing:
                errors.append(f"{tag}: нет timing.{key}")
            elif not isinstance(timing[key], (int, float)) or timing[key] < 0:
                errors.append(f"{tag}: timing.{key} должен быть числом >= 0")

        cat = m.get("category")
        if cat in STRIKE_CATEGORIES:
            hb = m.get("hitbox")
            if not hb:
                errors.append(f"{tag}: страйк без hitbox")
            else:
                for key in ("bone", "size", "offset", "reach"):
                    if key not in hb:
                        errors.append(f"{tag}: hitbox без {key}")
                if isinstance(hb.get("reach"), (int, float)) and hb["reach"] <= 0:
                    errors.append(f"{tag}: hitbox.reach должен быть > 0")

        gr = m.get("grapple")
        if gr:
            to = gr.get("to")
            if to and to not in GROUND_POSITIONS:
                errors.append(f"{tag}: grapple.to '{to}' — неизвестная позиция")
            for frm in gr.get("from", []) or []:
                if frm not in GROUND_POSITIONS:
                    errors.append(f"{tag}: grapple.from '{frm}' — неизвестная позиция")

        dmg = m.get("damage") or {}
        for key in ("health", "stamina", "chipRatio"):
            if key not in dmg:
                errors.append(f"{tag}: нет damage.{key}")

        for cid in m.get("cancel", []) or []:
            if cid not in {x.get("id") for x in moves}:
                errors.append(f"{tag}: cancel ссылается на несуществующий мув '{cid}'")

        total = sum(timing.get(k, 0) for k in REQUIRED_TIMING)
        if cat in STRIKE_CATEGORIES and total > 90:
            errors.append(f"{tag}: суммарно {total} кадров (>1.5 сек) — подозрительно долго")

    if errors:
        print(f"❌ найдено проблем: {len(errors)}")
        for e in errors:
            print("  -", e)
        return 1

    print(f"✅ data ok: мувов {len(moves)}, fps {data.get('fps')}")
    # сводка по категориям
    cats = {}
    for m in moves:
        cats[m.get("category", "?")] = cats.get(m.get("category", "?"), 0) + 1
    for k in sorted(cats):
        print(f"   {k}: {cats[k]}")
    return 0


def speed_profile(rows, point):
    xs = point + "_x"
    ys = point + "_y"
    if xs not in rows[0] or ys not in rows[0]:
        raise SystemExit(f"в CSV нет колонок {xs}/{ys}")
    prof = []
    for a, b in zip(rows, rows[1:]):
        dx = float(b[xs]) - float(a[xs])
        dy = float(b[ys]) - float(a[ys])
        prof.append((int(b["frame"]), math.hypot(dx, dy)))
    return prof


def measure(csv_path, point, fps, move_id, recovery, threshold=0.55):
    with open(csv_path, "r", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    if len(rows) < 5:
        raise SystemExit("CSV слишком короткий")

    prof = speed_profile(rows, point)
    peak_val = max(v for _, v in prof)
    peak_frame = max(prof, key=lambda t: t[1])[0]

    # границы активного окна: где скорость выше threshold от пика
    limit = peak_val * threshold
    active_frames = [fr for fr, v in prof if v >= limit]
    f1 = min(active_frames)
    f2 = max(active_frames)
    f0 = min(int(r["frame"]) for r in rows)

    startup = max(1, f1 - f0)
    active = max(1, f2 - f1 + 1)

    result = {
        "id": move_id,
        "measured": {
            "f0": f0,
            "f1": f1,
            "f2": f2,
            "peak_speed_px": round(peak_val, 3),
            "fps": fps,
            "startup_frames": startup,
            "startup_ms": round(startup / fps * 1000, 1),
            "active_frames": active,
            "recovery_frames": recovery,
            "total_frames": startup + active + recovery,
            "total_ms": round((startup + active + recovery) / fps * 1000, 1),
        },
        "timing": {"startup": startup, "active": active, "recovery": recovery},
    }
    print(json.dumps(result, ensure_ascii=False, indent=2))
    print(
        "\n# Вставь 'timing' в запись мува в data/moves.json, затем: "
        "python3 tools/calibrate.py --check data/moves.json",
        file=sys.stderr,
    )
    return 0


def main():
    p = argparse.ArgumentParser(description="Калибровка фреймдаты под UFC 4")
    p.add_argument("file", nargs="?", default="data/moves.json")
    p.add_argument("--check", action="store_true", help="валидировать moves.json")
    p.add_argument("--measure", metavar="CSV", help="посчитать тайминги из CSV трекинга")
    p.add_argument("--point", default="wrist_r", help="колонка трекинга (wrist_r / ankle_r / ...)")
    p.add_argument("--fps", type=int, default=60)
    p.add_argument("--id", default="measured_move")
    p.add_argument("--recovery", type=int, default=12)
    p.add_argument("--threshold", type=float, default=0.55)
    args = p.parse_args()

    if args.measure:
        return measure(args.measure, args.point, args.fps, args.id, args.recovery, args.threshold)
    return check(args.file)


if __name__ == "__main__":
    sys.exit(main())
