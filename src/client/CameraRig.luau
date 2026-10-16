--!strict
-- CameraRig: телевизионная камера октагона как в UFC 4.
-- Камера держит середину между бойцами, отъезжает при разрыве дистанции,
-- слегка "дышит" и трясётся на попаданиях.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local FightMath = require(Shared:WaitForChild("FightMath"))

local M = {}

local camera = workspace.CurrentCamera
local evHit = Remotes.event("HitFX")
local evKnockdown = Remotes.event("KnockdownFX")

local shakeAmount = 0
local shakeDecay = 6

M.CONFIG = {
	sideOffset = 9,      -- отлет камеры вбок (вид "с угла ринга")
	heightOffset = 5.5,
	minDistance = 8,
	maxDistance = 22,
	fovBase = 55,
	fovMax = 72,
	lerpSpeed = 6,
}

function M.start()
	if not camera then
		camera = workspace.CurrentCamera or Instance.new("Camera")
	end
	camera.CameraType = Enum.CameraType.Scriptable

	local targets: { BasePart } = {}

	RunService.RenderStepped:Connect(function(dt)
		-- собираем бойцов
		targets = {}
		for _, p in ipairs(Players:GetPlayers()) do
			local char = p.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp and hrp:IsA("BasePart") then
				table.insert(targets, hrp :: BasePart)
			end
		end
		if #targets == 0 then
			return
		end

		local center = targets[1].Position
		if #targets > 1 then
			center = targets[1].Position:Lerp(targets[2].Position, 0.5)
		end

		local spread = 0
		if #targets > 1 then
			spread = (targets[1].Position - targets[2].Position).Magnitude
		end

		local distance = FightMath.clamp(spread * 1.6 + M.CONFIG.minDistance, M.CONFIG.minDistance, M.CONFIG.maxDistance)
		local side = Vector3.new(center.Z, 0, -center.X)
		if side.Magnitude < 0.001 then
			side = Vector3.new(1, 0, 0)
		end
		side = side.Unit

		local desiredPos = center + side * M.CONFIG.sideOffset + Vector3.new(0, M.CONFIG.heightOffset + spread * 0.15, 0)
		local targetCF = CFrame.lookAt(desiredPos, center)

		-- тряска
		if shakeAmount > 0.001 then
			local jitter = CFrame.new(
				(math.random() * 2 - 1) * shakeAmount,
				(math.random() * 2 - 1) * shakeAmount,
				0
			)
			targetCF = targetCF * jitter
			shakeAmount = math.max(0, shakeAmount - shakeDecay * dt * shakeAmount)
		end

		camera.CFrame = camera.CFrame:Lerp(targetCF, FightMath.clamp(M.CONFIG.lerpSpeed * dt, 0, 1))
		camera.FieldOfView = FightMath.remap(spread, 4, 20, M.CONFIG.fovBase, M.CONFIG.fovMax)
	end)

	evHit.OnClientEvent:Connect(function(payload)
		local mag = typeof(payload.magnitude) == "number" and payload.magnitude or 6
		local blocked = payload.blocked == true
		shakeAmount = math.min(1.2, shakeAmount + (blocked and mag * 0.02 or mag * 0.06))
	end)

	evKnockdown.OnClientEvent:Connect(function()
		shakeAmount = math.min(2.0, shakeAmount + 0.9)
	end)
end

function M.shake(amount: number)
	shakeAmount = math.min(2.0, shakeAmount + amount)
end

return M
