--!strict
-- Создаёт тренировочную арену один раз при старте сервера и управляет сессиями.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local FighterState = require(script.Parent:WaitForChild("FighterState"))
local MatchServer = require(script.Parent:WaitForChild("MatchServer"))
local HitboxSystem = require(script.Parent:WaitForChild("HitboxSystem"))
local DummyController = require(script.Parent:WaitForChild("DummyController"))

local M = {}
local ORIGIN = Vector3.new(0, 2, 0)
local RING_SIZE = 36
local SESSION_SECONDS = 240
local arenaEvent = Remotes.event("ArenaSession")
local activePlayer: Player? = nil
local dummyModel: Model? = nil
local returnCFrames: { [Player]: CFrame } = {}
local dummyAccumulator = 0

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, transparency: number, color: Color3, collidable: boolean): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Transparency = transparency
	p.Color = color
	p.Anchored = true
	p.CanCollide = collidable
	p.CanTouch = false
	p.CanQuery = false
	p.Parent = parent
	return p
end

function M.build()
	local old = workspace:FindFirstChild("TrainingArena")
	if old then
		return old
	end
	local arena = Instance.new("Folder")
	arena.Name = "TrainingArena"
	arena.Parent = workspace
	part(arena, "BlackMat", Vector3.new(RING_SIZE, 1, RING_SIZE), CFrame.new(ORIGIN), 0, Color3.fromRGB(12, 12, 15), true)
	local height = 9
	local wallSize = Vector3.new(RING_SIZE, height, 1)
	part(arena, "WallNorth", wallSize, CFrame.new(ORIGIN + Vector3.new(0, height / 2, -RING_SIZE / 2)), 1, Color3.new(1, 1, 1), true)
	part(arena, "WallSouth", wallSize, CFrame.new(ORIGIN + Vector3.new(0, height / 2, RING_SIZE / 2)), 1, Color3.new(1, 1, 1), true)
	local sideSize = Vector3.new(1, height, RING_SIZE)
	part(arena, "WallEast", sideSize, CFrame.new(ORIGIN + Vector3.new(RING_SIZE / 2, height / 2, 0)), 1, Color3.new(1, 1, 1), true)
	part(arena, "WallWest", sideSize, CFrame.new(ORIGIN + Vector3.new(-RING_SIZE / 2, height / 2, 0)), 1, Color3.new(1, 1, 1), true)
	local stand = part(arena, "EnterStand", Vector3.new(4, 1, 4), CFrame.new(ORIGIN + Vector3.new(0, 0, RING_SIZE / 2 + 6)), 0, Color3.fromRGB(55, 55, 65), true)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "EnterFightPrompt"
	prompt.ActionText = "Начать бой"
	prompt.ObjectText = "Тренировочный ринг"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.Parent = stand
	return arena
end

local function endSession(player: Player, reason: string)
	if activePlayer ~= player then
		return
	end
	activePlayer = nil
	DummyController.detach()
	local dummy = MatchServer.getFighterById("DUMMY_" .. tostring(player.UserId))
	if dummy then
		MatchServer.removeFighter(dummy.id)
	end
	if dummyModel then
		dummyModel:Destroy()
		dummyModel = nil
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.CFrame = returnCFrames[player] or CFrame.new(0, 6, 0)
	end
	returnCFrames[player] = nil
	arenaEvent:FireClient(player, { active = false, reason = reason })
end

local function startSession(player: Player, statsTable: { [string]: any })
	if activePlayer then
		return
	end
	local fighter = MatchServer.getPlayerFighter(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not fighter or not character or not root or not root:IsA("BasePart") then
		return
	end
	activePlayer = player
	returnCFrames[player] = root.CFrame
	fighter.health = fighter.maxHealth
	fighter.move = nil
	fighter.moveFrame = 0
	fighter.phase = "none"
	fighter.stunFrames = 0
	fighter.knockdownFrames = 0
	fighter.stamina.value = fighter.stamina.max
	root.CFrame = CFrame.lookAt(ORIGIN + Vector3.new(-6, 3.5, 0), ORIGIN)

	local clone = character:Clone()
	clone.Name = "FightDummy"
	for _, item in ipairs(clone:GetDescendants()) do
		if item:IsA("BaseScript") then
			item:Destroy()
		elseif item:IsA("BasePart") then
			item.Transparency = math.min(item.Transparency, 0.35)
		end
	end
	clone.Parent = workspace
	clone:PivotTo(CFrame.lookAt(ORIGIN + Vector3.new(6, 3.5, 0), ORIGIN))
	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.MaxHealth = 100000
		humanoid.Health = 100000
		humanoid.AutoRotate = false
	end
	dummyModel = clone
	local stats = statsTable.dummy or statsTable.default or FighterState.DEFAULT_STATS
	local dummy = FighterState.new("DUMMY_" .. tostring(player.UserId), stats, nil)
	dummy.character = clone
	dummy.humanoidRootPart = clone:FindFirstChild("HumanoidRootPart") :: BasePart?
	MatchServer.registerFighter(dummy)
	HitboxSystem.buildHurtboxes(clone)
	DummyController.attach(dummy.id)
	MatchServer.start()
	arenaEvent:FireClient(player, { active = true, seconds = SESSION_SECONDS })
	task.delay(SESSION_SECONDS, function()
		endSession(player, "time")
	end)
end

function M.start(statsTable: { [string]: any })
	RunService.Heartbeat:Connect(function(dt)
		if not activePlayer then return end
		dummyAccumulator += dt
		local step = 1 / 60
		local guard = 0
		while dummyAccumulator >= step and guard < 5 do
			DummyController.tick(step)
			dummyAccumulator -= step
			guard += 1
		end
	end)
	local arena = M.build()
	local stand = arena:FindFirstChild("EnterStand")	if not stand then return end
	local prompt = stand:FindFirstChildOfClass("ProximityPrompt")	if not prompt then return end
	prompt.Triggered:Connect(function(player)
		startSession(player, statsTable)
	end)
	arenaEvent.OnServerEvent:Connect(function(player, action)
		if action == "leave" then
			endSession(player, "leave")
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		if activePlayer == player then
			endSession(player, "leave")
		end
	end)
end

function M.endSessionFromRequest(player: Player)
	endSession(player, "leave")
end

return M
