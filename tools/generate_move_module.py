#!/usr/bin/env python3
"""Generate Rojo-safe Luau data modules from canonical JSON files."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def generate(source: str, destination: str) -> None:
    raw = (ROOT / source).read_text(encoding="utf-8")
    level = 4
    while "]" + "=" * level + "]" in raw:
        level += 1
    equals = "=" * level
    output = (
        "--!strict\n"
        f"-- GENERATED from {source} by tools/generate_move_module.py. Do not edit by hand.\n"
        'local HttpService = game:GetService("HttpService")\n'
        f"local JSON = [{equals}[\n{raw}\n]{equals}]\n"
        "return HttpService:JSONDecode(JSON)\n"
    )
    (ROOT / destination).write_text(output, encoding="utf-8")


generate("data/moves.json", "src/shared/MoveData.luau")
generate("data/fighters.json", "src/shared/FighterData.luau")
print("Generated Rojo-safe modules in src/shared/ from data/*.json")
