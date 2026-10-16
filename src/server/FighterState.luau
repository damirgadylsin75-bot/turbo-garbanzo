--!strict
-- FighterState: состояние одного бойца на сервере (авторитет).
-- Сервер гоняет это в fixed-timestep цикле 60 Гц (см. MatchServer).
-- Тестовая сборка (только стойка): нет grounded/getupFrames - есть knockdownFrames.
-- Нокдаун дёшевый: Humanoid.PlatformStand = true + ChangeState(Physics),
-- при подъёме - ChangeState(GettingUp).
-- Сохранено: буфер ввода, окна отмены, супер-армор, прерывание ТОЛЬКО замаха.
-- Все числа - из data/moves.json (секции combat/balance/stamina).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local FrameData = require(Shared:WaitForChild("FrameData"))
local StaminaSystem = require(Shared:WaitForChild("StaminaSystem"))
local FightMath = require(Shared:WaitForChild("FightMath"))
local Moves = require(Shared:WaitForChild("Moves"))

export type FighterStats = {
	punchPower: number,
	kickPower: number,
	groundPound: number,
	grappleOffense: number,
	grappleDefense: number,
	speed: number,
	chin: number, -- устойчивость к нокдаунам
	staminaPool: number,
}

export type FighterState = {
	id: string,
	player: Player?,
	character: Model?,
	humanoidRootPart: BasePart?,

	stats: FighterStats,
	health: number,
	maxHealth: number,
	stamina: StaminaSystem.StaminaModel,

	-- текущий мув
	move: FrameData.MoveDef?,
	moveFrame: number,
	phase: FrameData.Phase,

	-- модификаторы
	stunFrames: number,
	blocked: boolean,
	blockHeldFrames: number,
	knockdownFrames: number,
	invulnFrames: number,

	-- буфер ввода (как в файтингах: ввод запоминается и исполняется в ближайшем окне)
	inputBuffer: { { moveId: string, atFrame: number } },

	-- один мув = максимум одно попадание; сбрасывается при выходе из активных кадров
	hitConsumed: boolean,

	-- сетка
	tick: number,

	beginMove: ((self: any, moveId: string) -> boolean),
	update: ((self: any, dt: number, opponent: any) -> ()),
	consumeHit: ((self: any, result: FrameData.HitResult) -> ()),
	canAct: ((self: any) -> boolean),
	applyKnockdown: ((self: any) -> ()),
	snapshot: ((self: any) -> { [string]: any }),
}

local M = {}

M.DEFAULT_STATS = {
	punchPower = 65,
	kickPower = 60,
	groundPound = 55,
	grappleOffense = 60,
	grappleDefense = 60,
	speed = 60,
	chin = 60,
	staminaPool = 60,
} :: FighterStats

M.STATES = { "idle", "startup", "active", "recovery", "blocking", "stunned", "knockdown", "finished" }

local function getHumanoid(s: FighterState): Humanoid?
	local char = s.character
	if not char then
		return nil
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		return hum
	end
	return nil
end

function M.new(id: string, stats: FighterStats?, player: Player?): FighterState
	local st = stats or M.DEFAULT_STATS
	local combat = Moves.combat()
	local jsonCfg = Moves.staminaConfig() :: any
	local cfg = table.clone(jsonCfg) :: StaminaSystem.StaminaConfig
	-- стата стамины увеличивает бак и реген (числа масштабирования - в JSON)
	cfg.max = jsonCfg.max + (st.staminaPool - combat.staminaPoolMid) * combat.staminaPerPoolPoint
	cfg.regenPerSecondIdle = combat.regenPoolBase + (st.staminaPool / 100) * combat.regenPoolSpan

	local self
	self = {
		id = id,
		player = player,
		character = player and player.Character or nil,
		humanoidRootPart = nil,

		stats = st,
		health = 100,
		maxHealth = 100,
		stamina = StaminaSystem.new(cfg),

		move = nil,
		moveFrame = 0,
		phase = "none" :: FrameData.Phase,

		stunFrames = 0,
		blocked = false,
		blockHeldFrames = 0,
		knockdownFrames = 0,
		invulnFrames = 0,

		inputBuffer = {},
		hitConsumed = false,
		tick = 0,
	} :: any

	self.canAct = function(s: FighterState): boolean
		if s.stunFrames > 0 or s.knockdownFrames > 0 then
			return false
		end
		if s.move and s.phase ~= "none" then
			-- разрешаем только в окне отмены
			return FrameData.canCancel(s.move, s.moveFrame)
		end
		return true
	end

	self.beginMove = function(s: FighterState, moveId: string): boolean
		local move = Moves.get(moveId)
		if not move then
			return false
		end
		if not s:canAct() then
			-- не прошло сейчас -> кладём в буфер, файтинги так и делают
			if #s.inputBuffer < combat.inputBufferMaxEntries then
				table.insert(s.inputBuffer, { moveId = moveId, atFrame = s.tick })
			end
			return false
		end
		if not s.stamina:spend(FrameData.staminaCost(move, 0) * combat.moveStartStaminaFraction) then
			-- старт мува стоит часть стамины; остальное спишется в активных кадрах
			s.stamina:spend(s.stamina.value)
			s.stunFrames = math.max(s.stunFrames, combat.exhaustStunFrames)
			return false
		end
		s.move = move
		s.moveFrame = 1
		s.phase = "startup"
		s.blocked = false
		return true
	end

	-- Нокдаун: дёшево (PlatformStand + Physics), лежим knockdownFrames кадров
	self.applyKnockdown = function(s: FighterState)
		s.move = nil
		s.moveFrame = 0
		s.phase = "none"
		s.stunFrames = 0
		s.blocked = false
		s.blockHeldFrames = 0
		s.knockdownFrames = combat.knockdownFrames
		if s.health <= 0 then
			s.knockdownFrames = combat.koKnockdownFrames
		end
		s.invulnFrames = combat.knockdownInvulnFrames
		local hum = getHumanoid(s)
		if hum then
			hum.PlatformStand = true
			hum:ChangeState(Enum.HumanoidStateType.Physics)
		end
	end

	self.consumeHit = function(s: FighterState, result: FrameData.HitResult)
		local balance = Moves.balance()
		local chinMul = FightMath.remap(s.stats.chin, 0, 100, balance.chinWorst, balance.chinBest)
		local dmg = result.healthDamage * chinMul
		if result.knockdown then
			dmg *= balance.knockdownDamageMul
		end
		s.health = math.max(0, s.health - dmg)
		s.stamina:takeDamage(result.staminaDamage)

		-- запоминаем фазу ДО обнуления мува: прерывать можно только замах
		local wasStartup = s.move ~= nil and s.phase == "startup"

		if result.knockdown and not s.blocked then
			s:applyKnockdown()
			return
		end

		-- Супер-армор: попадание в кадры армора не стаггерит и не прерывает
		local armored = false
		if s.move and s.phase ~= "none" then
			local armorFrom, armorTo = FrameData.armorFrames(s.move)
			if armorFrom and armorTo then
				if s.moveFrame >= armorFrom and s.moveFrame <= armorTo then
					armored = true
				end
			end
		end

		-- Прерывание: попадание в замах ломает мув. Это ключевая механика
		-- файтинга — именно она делает джеб (7 кадров) ответом на медленный
		-- приём. Без неё выгоднее всегда бить strongest.
		if result.stunFrames > 0 and not armored then
			s.stunFrames = math.max(s.stunFrames, result.stunFrames)
			if wasStartup and not result.blocked then
				s.move = nil
				s.moveFrame = 0
				s.phase = "none"
			end
		end
	end

	self.update = function(s: FighterState, dt: number, opponent: FighterState?)
		s.tick += 1

		if s.character and s.character.Parent then
			s.humanoidRootPart = s.character:FindFirstChild("HumanoidRootPart") :: BasePart?
		end

		if s.invulnFrames > 0 then
			s.invulnFrames -= 1
		end

		-- стамина
		local activity = "idle"
		if s.blocked then
			activity = "blocking"
			s.blockHeldFrames += 1
		elseif s.move then
			activity = "attacking"
		elseif opponent and s.humanoidRootPart and opponent.humanoidRootPart then
			activity = "moving"
		end
		s.stamina:regen(dt, activity, nil)

		-- нокдаун / подъём
		if s.knockdownFrames > 0 then
			s.knockdownFrames -= 1
			s.blockHeldFrames = 0
			if s.knockdownFrames <= 0 and s.health > 0 then
				s.knockdownFrames = 0
				if s.invulnFrames < combat.getupInvulnFrames then
					s.invulnFrames = combat.getupInvulnFrames
				end
				local hum = getHumanoid(s)
				if hum then
					hum.PlatformStand = false
					hum:ChangeState(Enum.HumanoidStateType.GettingUp)
				end
			end
			return
		end

		-- стаггер
		if s.stunFrames > 0 then
			s.stunFrames -= 1
			s.phase = "none"
			if s.stunFrames <= 0 then
				s.blockHeldFrames = 0
			end
			return
		end

		-- активный мув
		if s.move then
			s.moveFrame += 1
			s.phase = FrameData.phaseAt(s.move, s.moveFrame)

			if s.phase == "active" then
				local per = s.move.stamina.costPerActiveFrame or 0
				if per > 0 then
					s.stamina:takeDamage(per)
				end
			end

			if s.moveFrame > FrameData.totalFrames(s.move) then
				s.move = nil
				s.moveFrame = 0
				s.phase = "none"
			end
		end

		-- разбираем буфер ввода
		local now = s.tick
		local kept = {}
		for _, entry in ipairs(s.inputBuffer) do
			if now - entry.atFrame <= combat.inputBufferWindowFrames then
				table.insert(kept, entry)
			end
		end
		s.inputBuffer = kept
		if #s.inputBuffer > 0 and s:canAct() then
			local entry = table.remove(s.inputBuffer, 1)
			s:beginMove(entry.moveId)
		end

		if s.health <= 0 then
			s:applyKnockdown()
		end
	end

	self.snapshot = function(s: FighterState)
		return {
			id = s.id,
			health = s.health,
			stamina = s.stamina.value,
			exhausted = s.stamina.exhausted,
			moveId = s.move and s.move.id or nil,
			moveFrame = s.move and s.moveFrame or 0,
			phase = s.phase,
			stunned = s.stunFrames > 0,
			blocked = s.blocked,
			knockdown = s.knockdownFrames > 0,
			tick = s.tick,
		}
	end

	return self
end

return M
