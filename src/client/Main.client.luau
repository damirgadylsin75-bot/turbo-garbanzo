--!strict
-- Клиентская точка входа. Порядок важен: сначала модули, потом старт.

local Client = script.Parent

local InputBuffer = require(Client:WaitForChild("InputBuffer"))
local Prediction = require(Client:WaitForChild("Prediction"))
local CameraRig = require(Client:WaitForChild("CameraRig"))
local VFX = require(Client:WaitForChild("VFX"))
local HUD = require(Client:WaitForChild("HUD"))

HUD.start()
VFX.start()
Prediction.start()
CameraRig.start()
InputBuffer.start()

print("[turbo-garbanzo] client ready")
