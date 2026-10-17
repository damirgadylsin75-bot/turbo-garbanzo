--!strict
-- GENERATED from data/fighters.json by tools/generate_move_module.py. Do not edit by hand.
local HttpService = game:GetService("HttpService")
local JSON = [====[
{
  "$comment": "Статы 0..100. default — игрок, dummy — манекен тестовой сборки.",
  "fighters": {
    "default": { "punchPower": 70, "kickPower": 65, "speed": 68, "chin": 65, "staminaPool": 70 },
    "dummy": { "punchPower": 64, "kickPower": 60, "speed": 62, "chin": 70, "staminaPool": 65 }
  },
  "dummy": {
    "defaultMode": "static",
    "modes": ["static", "blocks", "fights"]
  }
}

]====]
return HttpService:JSONDecode(JSON)
