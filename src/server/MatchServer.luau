--!strict
-- MatchServer: авторитетный симулятор боя с фиксированным шагом (только стойка).
--
-- Почему фиксированный шаг обязателен: весь файтинг построен на кадрах.
-- Если гонять логику в Heartbeat с плавающим dt, комбо и окна отмены "поплывут"
-- на разных машинах. Поэтому: сервер считает 60 тиков в секунду, а визуал
-- клиента интерполируется между снапшотами.
--
-- Клиент шлёт ТОЛЬКО {action, moveId}. Урон, тайминги и позиции считаются здесь.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local FrameData = require(Shared:WaitForChild("FrameData"))
local Moves = require(Shared:WaitForChild("Moves"))

local Server = script.Parent
local FighterState = require(Server:WaitForChild("FighterState"))
local HitboxSystem = require(Server:WaitForChild("HitboxSystem"))

local M = {}

local fighters: { [string]: FighterState.FighterState } = {}
local order: { string } = {}
local accumulator = 0
local started = false
local snapshotTimer = 0
local SNAPSHOT_INTERVAL = 1 / 30 -- 30 Гц снапшотов на клиентов
local MIN_INTENT_INTERVAL = 1 / 40 -- античит: ограничение около 40 намерений в секунду
local rate: { [Player]: number } = {}

local evInput = Remotes.event("FighterInput")
local evSnapshot = Remotes.event("FightSnapshot")
local evHit = Remotes.event("HitFX")
local evKnockdown = Remotes.event("KnockdownFX")

function M.addFighter(player: Player, stats: FighterState.FighterStats?)
	local state = FighterState.new(player.UserId and tostring(player.UserId) or player.Name, stats, player)
	fighters[state.id] = state
	table.insert(order, state.id)

	player.CharacterAdded:Connect(function(character)
		state.character = character
		state.humanoidRootPart = character:WaitForChild("HumanoidRootPart") :: BasePart?
		HitboxSystem.buildHurtboxes(character)
		if workspace:GetAttribute("FightDebugHitboxes") then
			HitboxSystem.setDebugVisible(character, true)
		end
	end)
	if player.Character then
		state.character = player.Character
		state.humanoidRootPart = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		HitboxSystem.buildHurtboxes(player.Character)
	end

	-- Отключаем стандартный Humanoid-урон: всё считаем сами
	if player.Character then
		local hum = player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.MaxHealth = 10000
			hum.Health = 10000
			hum.DisplayName = state.id
		end
	end

	return state
end

-- Регистрация уже собранного FighterState (используется для манекена)
function M.registerFighter(state: FighterState.FighterState)
	if fighters[state.id] then
		return state
	end
	fighters[state.id] = state
	table.insert(order, state.id)
	return state
end

-- Ввод от манекена идёт по тому же пути, что и от игрока: никаких привилегий.
function M.handleInputBot(fighterId: string, payload: { [string]: any })
	local state = fighters[fighterId]
	if not state then
		return
	end
	M.applyIntent(state, payload)
end

function M.getFighters(): { FighterState.FighterState }
	local out = {}
	for _, id in ipairs(order) do
		local f = fighters[id]
		if f then
			table.insert(out, f)
		end
	end
	return out
end

local function resolveCollisions()
	local list = M.getFighters()
	if #list < 2 then
		return
	end
	local balance = Moves.balance()
	for i = 1, #list do
		local a = list[i]
		for j = i + 1, #list do
			local b = list[j]
			if not a.character or not b.character or not a.humanoidRootPart or not b.humanoidRootPart then
				continue
			end
			if a.invulnFrames > 0 or b.invulnFrames > 0 then
				continue
			end

			-- хитбокс A -> хуртбокс B
			local hitA = HitboxSystem.syncHitbox(a.character, a.move, a.moveFrame)
			local hitB = HitboxSystem.syncHitbox(b.character, b.move, b.moveFrame)

			if hitA and a.move and not a.hitConsumed then
				local level = HitboxSystem.queryHit(hitA, b.character)
				if level then
					local dir = (b.humanoidRootPart.Position - a.humanoidRootPart.Position).Unit
					local result = FrameData.resolveHit(a.move, a.stats.punchPower, {
						blocked = b.blocked,
						blockHeldFrames = b.blockHeldFrames,
						stamina = b.stamina.value,
						maxStamina = b.stamina.max,
						stunned = b.stunFrames > 0,
						directionToDefender = dir,
					}, balance)
					b:consumeHit(result)
					a.hitConsumed = true

					evHit:FireAllClients({
						attackerId = a.id,
						victimId = b.id,
						moveId = a.move.id,
						level = level,
						blocked = result.blocked,
						knockdown = result.knockdown,
						position = hitA.Position,
						direction = { dir.X, dir.Y, dir.Z },
						magnitude = result.knockback,
					})

					if result.knockdown then
						evKnockdown:FireAllClients({ victimId = b.id, position = b.humanoidRootPart.Position })
					elseif result.knockback > 0 and b.humanoidRootPart then
						b.humanoidRootPart.AssemblyLinearVelocity = dir * result.knockback + Vector3.new(0, result.knockback * 0.15, 0)
					end
				end
			end

			-- симметрично для B
			if hitB and b.move and not b.hitConsumed then
				local level = HitboxSystem.queryHit(hitB, a.character)
				if level then
					local dir = (a.humanoidRootPart.Position - b.humanoidRootPart.Position).Unit
					local result = FrameData.resolveHit(b.move, b.stats.punchPower, {
						blocked = a.blocked,
						blockHeldFrames = a.blockHeldFrames,
						stamina = a.stamina.value,
						maxStamina = a.stamina.max,
						stunned = a.stunFrames > 0,
						directionToDefender = dir,
					}, balance)
					a:consumeHit(result)
					b.hitConsumed = true

					evHit:FireAllClients({
						attackerId = b.id,
						victimId = a.id,
						moveId = b.move.id,
						level = level,
						blocked = result.blocked,
						knockdown = result.knockdown,
						position = hitB.Position,
						direction = { dir.X, dir.Y, dir.Z },
						magnitude = result.knockback,
					})

					if result.knockdown then
						evKnockdown:FireAllClients({ victimId = a.id, position = a.humanoidRootPart.Position })
					elseif result.knockback > 0 and a.humanoidRootPart then
						a.humanoidRootPart.AssemblyLinearVelocity = dir * result.knockback + Vector3.new(0, result.knockback * 0.15, 0)
					end
				end
			end
		end
	end

	-- сброс флага "попал" при выходе из активных кадров:
	-- один мув = одно попадание
	for _, f in ipairs(list) do
		if f.move and f.phase ~= "active" then
			f.hitConsumed = false
		elseif not f.move then
			f.hitConsumed = false
		end
		if f.move and f.phase == "active" and f.moveFrame == f.move.timing.startup + 1 then
			f.hitConsumed = false
		end
	end
end

local function simulate(dt: number)
	local list = M.getFighters()
	for i, f in ipairs(list) do
		local opp = list[((i) % #list) + 1]
		f:update(dt, opp)
	end
	resolveCollisions()

	-- снапшот клиентам (30 Гц достаточно для визуала)
	snapshotTimer += dt
	if snapshotTimer >= SNAPSHOT_INTERVAL then
		snapshotTimer = 0
		local snap = {}
		for _, f in ipairs(list) do
			table.insert(snap, f:snapshot())
		end
		evSnapshot:FireAllClients({ fighters = snap })
	end
end

function M.start()
	if started then
		return
	end
	started = true
	print("[MatchServer] симуляция запущена (60 Гц)")
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		local step = FrameData.FRAME
		local guard = 0
		while accumulator >= step and guard < 5 do
			simulate(step)
			accumulator -= step
			guard += 1
		end
	end)
end

-- Единственная точка применения "намерения" (от игрока или от манекена).
-- Клиент шлёт ТОЛЬКО {action, moveId}: урон, позиции и тайминги считаются
-- только здесь. moveId валидируется через Moves.isValid.
function M.applyIntent(state: FighterState.FighterState, payload: { [string]: any })
	local action = payload.action
	local moveId = payload.moveId
	if typeof(action) ~= "string" then
		return
	end
	if not Moves.isValid(moveId) then
		return
	end

	if action == "block" then
		state.blocked = true
		return
	end

	if action == "unblock" then
		state.blocked = false
		state.blockHeldFrames = 0
		return
	end

	if action == "strike" or action == "defense" then
		state:beginMove(moveId)
	end
end

function M.handleInput(player: Player, payload: { [string]: any })
	local state = fighters[tostring(player.UserId)]
	if not state then
		return
	end
	M.applyIntent(state, payload)
end

evInput.OnServerEvent:Connect(function(player, payload)
	if typeof(payload) ~= "table" then
		return
	end
	if typeof(payload.action) ~= "string" then
		return
	end
	-- простейший античит: около 40 намерений в секунду
	local now = os.clock()
	local last = rate[player] or 0
	if now - last < MIN_INTENT_INTERVAL then
		return
	end
	rate[player] = now
	M.handleInput(player, payload)
end)

return M
