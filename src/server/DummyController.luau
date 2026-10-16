--!strict
-- DummyController: неподвижный манекен для тестовой сборки (только стойка).
-- Режимы переключаются атрибутом workspace "FightDummyMode":
--   "static" (по умолчанию) - просто стоит
--   "blocks"                 - держит блок, когда игрок атакует
--   "fights"                 - отвечает ударами стойки
-- Манекен всегда повёрнут к игроку. Его ввод идёт по тому же пути, что и
-- ввод игрока (MatchServer.handleInputBot) - без привилегий.
-- Настройки манекена - в data/moves.json, секция "dummy".

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Moves = require(Shared:WaitForChild("Moves"))

local Server = script.Parent
local MatchServer = require(Server:WaitForChild("MatchServer"))

local M = {}

M.MODE_ATTRIBUTE = "FightDummyMode"
M.MODES = { static = true, blocks = true, fights = true }

local state = {
	id = nil :: string?,
	cooldown = 0,
}

-- Режим манекена: static / blocks / fights (по умолчанию static)
function M.mode(): string
	local raw = workspace:GetAttribute(M.MODE_ATTRIBUTE)
	if typeof(raw) == "string" and M.MODES[raw] then
		return raw
	end
	return "static"
end

function M.attach(fighterId: string)
	state.id = fighterId
end

-- Манекен всегда повёрнут к игроку (только рыскание, позиция не двигается)
local function faceOpponent(selfRoot: BasePart, oppRoot: BasePart)
	local flat = Vector3.new(oppRoot.Position.X - selfRoot.Position.X, 0, oppRoot.Position.Z - selfRoot.Position.Z)
	if flat.Magnitude < 0.01 then
		return
	end
	selfRoot.CFrame = CFrame.lookAt(selfRoot.Position, selfRoot.Position + flat.Unit)
end

function M.tick(_dt: number)
	if not state.id then
		return
	end
	local fighters = MatchServer.getFighters()
	local self, opp
	for _, f in ipairs(fighters) do
		if f.id == state.id then
			self = f
		else
			opp = opp or f
		end
	end
	if not self or not opp or not self.character or not self.humanoidRootPart or not opp.humanoidRootPart then
		return
	end

	local hum = self.character:FindFirstChildOfClass("Humanoid")
	if hum and hum.PlatformStand then
		return -- лежит в нокдауне, не крутим
	end

	faceOpponent(self.humanoidRootPart, opp.humanoidRootPart)

	local mode = M.mode()
	if mode == "static" then
		self.blocked = false
		return
	end

	local cfg = Moves.dummyConfig()
	local distance = (self.humanoidRootPart.Position - opp.humanoidRootPart.Position).Magnitude
	local threat = opp.move ~= nil and (opp.phase == "startup" or opp.phase == "active")

	-- blocks: держим блок под атакой
	self.blocked = threat and distance <= cfg.blockRange
	if mode == "blocks" then
		return
	end

	-- fights: блок + ответные удары стойки
	state.cooldown -= 1
	if state.cooldown > 0 then
		return
	end
	if threat then
		return
	end
	if distance > cfg.maxAttackDistance then
		return
	end
	if self.stamina:ratio() <= cfg.minStaminaRatio then
		return
	end

	local pool = Moves.standingStrikes()
	if #pool == 0 then
		return
	end
	local pick = pool[math.random(1, #pool)]
	local reach = 5
	if pick.hitbox then
		reach = pick.hitbox.reach
	end
	if distance > reach + cfg.reachPadding then
		return
	end

	MatchServer.handleInputBot(state.id, { action = "strike", moveId = pick.id })
	state.cooldown = cfg.strikeCooldownFrames + math.random(0, cfg.strikeCooldownRandomFrames)
end

return M
