--!strict
-- CharacterControl (клиент): автоповорот бойца к сопернику.
-- Humanoid.AutoRotate = false: стандартный поворот Roblox дёргает стойку;
-- мы крутим сами с ограниченной скоростью (~720 град/сек, число - в
-- data/moves.json, combat.turnDegreesPerSecond). Работает и против манекена.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Moves = require(Shared:WaitForChild("Moves"))
local FightMath = require(Shared:WaitForChild("FightMath"))

local M = {}

local player = Players.LocalPlayer

local function applySetup(character: Model)
	local hum = character:WaitForChild("Humanoid", 5)
	if hum and hum:IsA("Humanoid") then
		hum.AutoRotate = false
	end
end

-- Ближайший живой соперник: другой игрок или манекен (модель с Humanoid)
local function findOpponentRoot(myCharacter: Model): BasePart?
	local myRoot = myCharacter:FindFirstChild("HumanoidRootPart")
	if not myRoot or not myRoot:IsA("BasePart") then
		return nil
	end
	local best: BasePart? = nil
	local bestDist = math.huge
	for _, inst in ipairs(workspace:GetChildren()) do
		if inst:IsA("Model") and inst ~= myCharacter then
			local hum = inst:FindFirstChildOfClass("Humanoid")
			local root = inst:FindFirstChild("HumanoidRootPart")
			if hum and root and root:IsA("BasePart") and hum.Health > 0 then
				local dist = (root.Position - myRoot.Position).Magnitude
				if dist < bestDist then
					bestDist = dist
					best = root
				end
			end
		end
	end
	return best
end

function M.start()
	if player.Character then
		applySetup(player.Character)
	end
	player.CharacterAdded:Connect(applySetup)

	RunService.RenderStepped:Connect(function(dt)
		local character = player.Character
		if not character then
			return
		end
		local root = character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			return
		end
		local hum = character:FindFirstChildOfClass("Humanoid")
		if hum and hum.PlatformStand then
			return -- лежим в нокдауне, не крутимся
		end
		local opponent = findOpponentRoot(character)
		if not opponent then
			return
		end
		local combat = Moves.combat()
		local degreesPerSecond = combat.turnDegreesPerSecond
		local radiansPerSecond = math.rad(degreesPerSecond)
		root.CFrame = FightMath.turnToward(root.CFrame, opponent.Position, radiansPerSecond, dt)
	end)
end

return M
