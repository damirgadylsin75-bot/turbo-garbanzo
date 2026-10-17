--!strict
-- Клиентская точка входа (тестовая сборка: только стойка).
-- Порядок важен: сначала модули, потом старт.

local Client = script.Parent

local InputBuffer = require(Client:WaitForChild("InputBuffer"))
local CharacterControl = require(Client:WaitForChild("CharacterControl"))
local CameraRig = require(Client:WaitForChild("CameraRig"))
local VFX = require(Client:WaitForChild("VFX"))
local HUD = require(Client:WaitForChild("HUD"))
local AnimDriver = require(Client:WaitForChild("AnimDriver"))
local ArenaUI = require(Client:WaitForChild("ArenaUI"))

HUD.start()
VFX.start()
CameraRig.start()
CharacterControl.start()
AnimDriver.start()
AnimDriver.reportMissing()
InputBuffer.start()
ArenaUI.start()

print("[turbo-garbanzo] client ready (test build: standing only)")
