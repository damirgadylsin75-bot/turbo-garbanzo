--!strict
-- Основная точка входа сервера: игроки регистрируются, арена создаётся один раз.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local FighterData = require(Shared:WaitForChild("FighterData"))
local Server = script.Parent
local MatchServer = require(Server:WaitForChild("MatchServer"))
local FighterState = require(Server:WaitForChild("FighterState"))
local HitboxSystem = require(Server:WaitForChild("HitboxSystem"))
local RinkArena = require(Server:WaitForChild("RinkArena"))

local statsTable = FighterData.fighters or {
	default = FighterState.DEFAULT_STATS,
	dummy = FighterState.DEFAULT_STATS,
}
local function registerPlayer(player: Player)
	local character = player.Character or player.CharacterAdded:Wait()
	local stats = statsTable[player.Name] or statsTable.default or FighterState.DEFAULT_STATS
	local state = MatchServer.addFighter(player, stats)
	state.character = character
	local hum = character:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.AutoRotate = false
	end
	HitboxSystem.buildHurtboxes(character)
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(registerPlayer, player)
end)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(registerPlayer, player)
end

RinkArena.start(statsTable)

local debugSignal = workspace:GetAttributeChangedSignal("FightDebugHitboxes")
debugSignal:Connect(function()
	local visible = workspace:GetAttribute("FightDebugHitboxes") == true
	for _, fighter in ipairs(MatchServer.getFighters()) do
		if fighter.character then
			HitboxSystem.setDebugVisible(fighter.character, visible)
		end
	end
end)

-- DummyController ticks as part of the fixed 60 Hz match simulation.
print("[Main] тренировочная арена создана; подойди к стойке и нажми E")
