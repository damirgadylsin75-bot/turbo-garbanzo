--!strict
-- BotController: простой ИИ-соперник. Он шлёт те же "намерения", что и игрок,
-- поэтому его легко заменить на нейросеть (RL-агент), не меняя архитектуру.
-- Логика - классическая для файтингов: контроль дистанции -> выбор окна -> атака.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Moves = require(Shared:WaitForChild("Moves"))
local FightMath = require(Shared:WaitForChild("FightMath"))

local Server = script.Parent
local MatchServer = require(Server:WaitForChild("MatchServer"))

local M = {}

export type BotConfig = {
	aggression: number,     -- 0..1
	reactionTicks: number,  -- задержка "человеческой" реакции
	preferredRange: number, -- студы
	blockChance: number,    -- 0..1
	takedownChance: number,
}

M.DEFAULT_CONFIG = {
	aggression = 0.55,
	reactionTicks = 12,
	preferredRange = 5.0,
	blockChance = 0.35,
	takedownChance = 0.08,
} :: BotConfig

local botState: {
	id: string?,
	cooldown: number,
	targetMoveId: string?,
} = { id = nil, cooldown = 0, targetMoveId = nil }

function M.attach(fighterId: string, config: BotConfig?)
	botState.id = fighterId
	M.config = config or M.DEFAULT_CONFIG
end

local function pickStrike(distance: number, staminaRatio: number, aggression: number): string?
	local pool = Moves.standingStrikes()
	if #pool == 0 then
		return nil
	end
	local best, bestScore = nil, -1e9
	for _, move in ipairs(pool) do
		local reach = move.hitbox and move.hitbox.reach or 4
		local rangeErr = math.abs(distance - reach)
		if rangeErr > 1.5 then
			continue -- не дотянемся
		end
		local cost = move.stamina.cost
		if cost > staminaRatio * 100 then
			continue -- нет стамины
		end
		-- Скоринг (должен совпадать с tools/simulate.py, иначе автобаланс врёт):
		--   урон нормирован на «цену окна» startup+recovery, как в UFC 4,
		--   плюс бонус быстрым мувам — они прерывают медленные (см. resolveCollisions).
		-- Без нормировки бот всегда берёт самый сильный и самый медленный приём.
		local commitment = move.timing.startup + move.timing.recovery
		local speedBonus = math.max(0, 26 - move.timing.startup) * 0.22 * aggression
		local score = (move.damage.health + move.reaction.knockdownChance * 12)
				* (36 / math.max(12, commitment))
			- commitment * 0.045 * (1.4 - aggression)
			+ speedBonus
			- rangeErr * 2
			- cost * 0.06
			+ (math.random() * 5 - 2.5)
		if score > bestScore then
			bestScore, best = score, move.id
		end
	end
	return best
end

function M.tick(dt: number)
	if not botState.id then
		return
	end
	local fighters = MatchServer.getFighters()
	local self, opp
	for _, f in ipairs(fighters) do
		if f.id == botState.id then
			self = f
		else
			opp = opp or f
		end
	end
	if not self or not opp or not self.humanoidRootPart or not opp.humanoidRootPart then
		return
	end

	local cfg = M.config or M.DEFAULT_CONFIG
	botState.cooldown -= dt * 60

	local distance = (self.humanoidRootPart.Position - opp.humanoidRootPart.Position).Magnitude

	-- защита: если соперник в startup/active - иногда блокируем
	local threat = opp.move and (opp.phase == "startup" or opp.phase == "active")
	self.blocked = threat and (math.random() < cfg.blockChance) and distance < 7

	-- движение к идеальной дистанции
	if not threat and not self.blocked then
		local dirTo = (opp.humanoidRootPart.Position - self.humanoidRootPart.Position)
		dirTo = Vector3.new(dirTo.X, 0, dirTo.Z)
		if dirTo.Magnitude > 0.01 then
			dirTo = dirTo.Unit
		end
		-- держим идеальную дистанцию: ближе/дальше/стоять
		local want = Vector3.zero
		if distance > cfg.preferredRange then
			want = dirTo
		elseif distance < cfg.preferredRange * 0.6 then
			want = -dirTo
		end
		self.moveIntent = want
	end

	if botState.cooldown > 0 then
		return
	end

	-- атака
	if distance <= cfg.preferredRange + 2 and self.stamina:ratio() > 0.25 then
		if math.random() < cfg.takedownChance and distance < 4.5 then
			local tds = Moves.takedowns()
			if #tds > 0 then
				local move = tds[math.random(1, #tds)]
				MatchServer.handleInputBot(botState.id, { action = "grapple", moveId = move.id })
				botState.cooldown = cfg.reactionTicks + math.random(0, 20)
				return
			end
		end
		if math.random() < cfg.aggression then
			local moveId = pickStrike(distance, self.stamina:ratio(), cfg.aggression)
			if moveId then
				MatchServer.handleInputBot(botState.id, { action = "strike", moveId = moveId })
				botState.cooldown = cfg.reactionTicks + math.random(0, 15)
			end
		end
	end
end

return M
