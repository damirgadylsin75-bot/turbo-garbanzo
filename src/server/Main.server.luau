--!strict
-- Серверная точка входа: поднимает бой, бота и дебаг-команды.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FrameData = require(Shared:WaitForChild("FrameData"))

local Server = script.Parent
local MatchServer = require(Server:WaitForChild("MatchServer"))
local BotController = require(Server:WaitForChild("BotController"))
local FighterState = require(Server:WaitForChild("FighterState"))

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

-- 2. Подключаем игрока + бота, чтобы можно было тестить в одиночку
local function spawnBotIfSolo()
	local fighters = MatchServer.getFighters()
	if #fighters >= 2 then
		return
	end
	local botStats = statsTable.bot or statsTable.default or FighterState.DEFAULT_STATS
	local bot = FighterState.new("BOT", botStats, nil)
	MatchServer.registerFighter(bot)

	-- телом бота делаем копию персонажа первого игрока (или простой R15 из Studio)
	local first = fighters[1]
	if first and first.character then
		local clone = first.character:Clone()
		clone.Name = "BotCharacter"
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
		bot.character = clone
		bot.humanoidRootPart = clone:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = clone:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.MaxHealth = 100000
			hum.Health = 100000
		end
		local HitboxSystem = require(Server:WaitForChild("HitboxSystem"))
		HitboxSystem.buildHurtboxes(clone)
	end

	BotController.attach(bot.id, BotController.DEFAULT_CONFIG)
	MatchServer.start()
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Wait()
	local stats = statsTable[player.Name] or statsTable.default or FighterState.DEFAULT_STATS
	MatchServer.addFighter(player, stats)
	task.wait(1)
	spawnBotIfSolo()
end)

for _, p in ipairs(Players:GetPlayers()) do
	if p.Character then
		MatchServer.addFighter(p, statsTable.default)
	end
end

-- 3. Тик бота в серверном цикле (тот же шаг, что и симуляция)
local botAccumulator = 0
RunService.Heartbeat:Connect(function(dt)
	botAccumulator += dt
	local step = FrameData.FRAME
	local guard = 0
	while botAccumulator >= step and guard < 5 do
		BotController.tick(step)
		botAccumulator -= step
		guard += 1
	end
end)

-- 4. Дебаг-команды (включаются атрибутами workspace)
workspace:GetAttributeChangedSignal("FightDebugHitboxes"):Connect(function()
	local visible = workspace:GetAttribute("FightDebugHitboxes") == true
	for _, f in ipairs(MatchServer.getFighters()) do
		if f.character then
			require(Server:WaitForChild("HitboxSystem")).setDebugVisible(f.character, visible)
		end
	end
end)

print("[turbo-garbanzo] server ready")
