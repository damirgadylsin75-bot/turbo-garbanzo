--!strict
-- Серверная точка входа: поднимает бой, манекен и дебаг-команды.
-- Тестовая сборка: только стойка, соперник - неподвижный манекен
-- (DummyController, режимы через workspace-атрибут "FightDummyMode").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FrameData = require(Shared:WaitForChild("FrameData"))

local Server = script.Parent
local MatchServer = require(Server:WaitForChild("MatchServer"))
local DummyController = require(Server:WaitForChild("DummyController"))
local FighterState = require(Server:WaitForChild("FighterState"))
local HitboxSystem = require(Server:WaitForChild("HitboxSystem"))

-- 1. Собираем статистику бойцов из data/fighters.json
local function loadFighterStats(): { [string]: FighterState.FighterStats }
	local ok, asset = pcall(function()
		return ReplicatedStorage:WaitForChild("FightData"):WaitForChild("fighters", 5)
	end)
	if not ok or not asset or not asset:IsA("JsonStringValue") then
		return { default = FighterState.DEFAULT_STATS }
	end
	local decoded = game:GetService("HttpService"):JSONDecode((asset :: JsonStringValue).Value)
	return decoded.fighters or { default = FighterState.DEFAULT_STATS }
end

local statsTable = loadFighterStats()

-- 2. Спавним манекен, чтобы можно было тестить в одиночку
local function spawnDummyIfSolo()
	local fighters = MatchServer.getFighters()
	if #fighters >= 2 then
		return
	end
	local dummyStats = statsTable.dummy or statsTable.default or FighterState.DEFAULT_STATS
	local dummy = FighterState.new("DUMMY", dummyStats, nil)
	MatchServer.registerFighter(dummy)

	-- телом манекена делаем копию персонажа первого игрока (R15)
	local first = fighters[1]
	if first and first.character then
		local clone = first.character:Clone()
		clone.Name = "FightDummy"
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Transparency = math.min(0.6, d.Transparency)
			end
		end
		clone.Parent = workspace
		local hrp = clone:FindFirstChild("HumanoidRootPart")
		if hrp and first.humanoidRootPart then
			clone:PivotTo(first.humanoidRootPart.CFrame * CFrame.new(0, 0, -8))
		end
		dummy.character = clone
		dummy.humanoidRootPart = clone:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = clone:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.MaxHealth = 100000
			hum.Health = 100000
			hum.AutoRotate = false
		end
		HitboxSystem.buildHurtboxes(clone)
	end

	DummyController.attach(dummy.id)
	print("[Main] манекен создан")
	MatchServer.start()
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Wait()
	local stats = statsTable[player.Name] or statsTable.default or FighterState.DEFAULT_STATS
	MatchServer.addFighter(player, stats)
	task.wait(1)
	spawnDummyIfSolo()
end)

for _, p in ipairs(Players:GetPlayers()) do
	if p.Character then
		MatchServer.addFighter(p, statsTable.default)
	end
end

-- 3. Тик манекена в серверном цикле (тот же шаг, что и симуляция)
local dummyAccumulator = 0
RunService.Heartbeat:Connect(function(dt)
	dummyAccumulator += dt
	local step = FrameData.FRAME
	local guard = 0
	while dummyAccumulator >= step and guard < 5 do
		DummyController.tick(step)
		dummyAccumulator -= step
		guard += 1
	end
end)

-- 4. Дебаг-команды (включаются атрибутами workspace)
workspace:GetAttributeChangedSignal("FightDebugHitboxes"):Connect(function()
	local visible = workspace:GetAttribute("FightDebugHitboxes") == true
	for _, f in ipairs(MatchServer.getFighters()) do
		if f.character then
			HitboxSystem.setDebugVisible(f.character, visible)
		end
	end
end)

print("[turbo-garbanzo] server ready (test build: standing only)")
