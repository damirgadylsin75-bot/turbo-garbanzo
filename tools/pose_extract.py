#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
pose_extract.py — видео -> CSV координат скелета, для замера фреймдаты UFC 4.

Ставит MediaPipe (один раз):
    pip install mediapipe opencv-python

Запуск:
    python3 tools/pose_extract.py clip_jab.mp4 --out jab.csv --fps 60

Потом:
    python3 tools/calibrate.py --measure jab.csv --point wrist_r --id jab --recovery 9

CSV-колонки: frame, t, <landmark>_x, <landmark>_y для ключевых точек:
    wrist_l, wrist_r, ankle_l, ankle_r, shoulder_l, shoulder_r, hip_l, hip_r
Координаты нормализованы 0..1 (доля ширины/высоты кадра).

Важно: пиши видео с постоянной частотой кадров (OBS: 60 fps, CFR),
иначе тайминги «поедут». Для точности снимай тренировочный режим UFC 4
с неподвижным соперником и одним приёмом за клип (3-5 сек).
"""

import argparse
import csv
import sys

POINTS = {
    "wrist_l": 15,
    "wrist_r": 16,
    "ankle_l": 27,
    "ankle_r": 28,
    "shoulder_l": 11,
    "shoulder_r": 12,
    "hip_l": 23,
    "hip_r": 24,
}


def extract(video_path, out_path, fps_override=None):
    try:
        import cv2
        import mediapipe as mp
    except ImportError as e:
        print(
            "Не хватает зависимостей. Установи: pip install mediapipe opencv-python",
            file=sys.stderr,
        )
        raise SystemExit(1) from e

    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise SystemExit(f"не удалось открыть видео: {video_path}")

    fps = fps_override or cap.get(cv2.CAP_PROP_FPS) or 60
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)

    pose = mp.solutions.pose.Pose(
        static_image_mode=False,
        model_complexity=2,
        smooth_landmarks=False,  # сглаживание выключено: нам нужны честные пики скорости
        min_detection_confidence=0.5,
        min_tracking_confidence=0.5,
    )

    fieldnames = ["frame", "t"]
    for name in POINTS:
        fieldnames += [f"{name}_x", f"{name}_y"]

    frame_idx = 0
    written = 0
    with open(out_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()

        while True:
            ok, bgr = cap.read()
            if not ok:
                break
            rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
            rgb.flags.writeable = False
            res = pose.process(rgb)

            row = {"frame": frame_idx, "t": round(frame_idx / fps, 4)}
            if res.pose_landmarks:
                lm = res.pose_landmarks.landmark
                for name, idx in POINTS.items():
                    row[f"{name}_x"] = round(lm[idx].x, 5)
                    row[f"{name}_y"] = round(lm[idx].y, 5)
            else:
                for name in POINTS:
                    row[f"{name}_x"] = ""
                    row[f"{name}_y"] = ""
            writer.writerow(row)
            written += 1
            frame_idx += 1

            if frame_idx % 60 == 0:
                print(f"\rкадров: {frame_idx}/{total or '?'}", end="", file=sys.stderr)

    cap.release()
    pose.close()
    print(f"\n✅ {out_path}: строк {written}, fps {fps:.2f}", file=sys.stderr)
    print(
        "\nДальше: python3 tools/calibrate.py --measure "
        f"{out_path} --point wrist_r --fps {int(fps)} --id <move_id> --recovery <n>",
        file=sys.stderr,
    )
    return 0


def main():
    p = argparse.ArgumentParser(description="Видео -> CSV координат скелета (MediaPipe)")
    p.add_argument("video")
    p.add_argument("--out", default="pose.csv")
    p.add_argument("--fps", type=float, default=None, help="принудительно указать fps (например 60)")
    args = p.parse_args()
    return extract(args.video, args.out, args.fps)


if __name__ == "__main__":
    sys.exit(main())
