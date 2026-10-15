--!strict
-- VFX: клиентские эффекты попаданий (искры/брызги пота, звук, hitstop).
-- Hitstop - микро-пауза на 2-4 кадра при сильном попадании. Именно она даёт
-- "вес" ударам в UFC 4 и её чаще всего забывают в самописных файтингах.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local M = {}

local evHit = Remotes.event("HitFX")
local evKnockdown = Remotes.event("KnockdownFX")

M.CONFIG = {
	hitstopFrames = 3,          -- кадров паузы на обычном попадании
	heavyHitstopFrames = 6,     -- на нокауте
	impactSoundId = "rbxassetid://0", -- поставь свой id
	sweatEnabled = true,
}

local hitstopUntil = 0

local function spawnImpact(position: Vector3, direction: Vector3, blocked: boolean, knockdown: boolean)
	local att = Instance.new("Attachment")
	att.Name = "ImpactAtt"

	local part = Instance.new("Part")
	part.Name = "ImpactFX"
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false
	part.Anchored = true
	part.CFrame = CFrame.lookAt(position, position + direction)
	part.Parent = workspace

	att.Parent = part

	-- вспышка
	local light = Instance.new("PointLight")
	light.Brightness = knockdown and 6 or 2.5
	light.Range = knockdown and 14 or 8
	light.Color = blocked and Color3.fromRGB(140, 190, 255) or Color3.fromRGB(255, 210, 170)
	light.Parent = part
	TweenService:Create(light, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 }):Play()
	game:GetService("Debris"):AddItem(light, 0.4)

	-- брызги пота
	if M.CONFIG.sweatEnabled and not blocked then
		local particles = Instance.new("ParticleEmitter")
		particles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		particles.Color = ColorSequence.new(Color3.fromRGB(230, 240, 255))
		particles.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(1, 0),
		})
		particles.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		particles.Lifetime = NumberRange.new(0.18, 0.4)
		particles.Speed = NumberRange.new(6, 16)
		particles.SpreadAngle = Vector2.new(35, 35)
		particles.Rate = 0
		particles.Acceleration = Vector3.new(0, -25, 0)
		particles.Parent = att
		particles:Emit(knockdown and 40 or 18)
	end

	if M.CONFIG.impactSoundId ~= "rbxassetid://0" then
		local sound = Instance.new("Sound")
		sound.SoundId = M.CONFIG.impactSoundId
		sound.Volume = knockdown and 1.6 or (blocked and 0.5 or 1.0)
		sound.PlaybackSpeed = knockdown and 0.85 or 1.0
		sound.Parent = part
		sound:Play()
		game:GetService("Debris"):AddItem(sound, 1.2)
	end

	game:GetService("Debris"):AddItem(part, 1.0)
end

function M.start()
	evHit.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end
		local pos = payload.position
		if typeof(pos) ~= "Vector3" then
			return
		end
		local dir = Vector3.new(0, 0, 1)
		if typeof(payload.direction) == "table" then
			dir = Vector3.new(payload.direction[1] or 0, payload.direction[2] or 0, payload.direction[3] or 1)
		end
		spawnImpact(pos, dir, payload.blocked == true, payload.knockdown == true)

		-- hitstop: замедляем анимации на пару кадров
		local frames = payload.knockdown and M.CONFIG.heavyHitstopFrames or M.CONFIG.hitstopFrames
		hitstopUntil = os.clock() + frames / 60
	end)

	-- во время hitstop слегка тормозим время анимаций.
	-- глобальный таймскейл менять нельзя (сломает физику), поэтому тормозим только треки.
	RunService.RenderStepped:Connect(function()
		local slow = os.clock() < hitstopUntil
		local AnimDriver = require(script.Parent:WaitForChild("AnimDriver"))
		AnimDriver.setSpeedMultiplier(slow and 0.25 or 1.0)
	end)

	evKnockdown.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end
		local pos = payload.position
		if typeof(pos) == "Vector3" then
			spawnImpact(pos, Vector3.new(0, 1, 0), false, true)
		end
	end)
end

return M
