--!strict
-- FighterState: состояние одного бойца на сервере (авторитет).
-- Сервер гоняет это в fixed-timestep цикле; клиент держит зеркальную копию
-- и сверяется (реконсиляция) - см. src/client/Prediction.luau

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
	grounded: boolean,
	getupFrames: number,
	invulnFrames: number,

	-- буфер ввода (как в файтингах: ввод запоминается и исполняется в ближайшем окне)
	inputBuffer: { { moveId: string, atFrame: number, dir: Vector3 } },

	-- намерение движения (задаётся клиентом/ботом, применяется сервером)
	moveIntent: Vector3?,

	-- один мув = максимум одно попадание; сбрасывается при выходе из активных кадров
	hitConsumed: boolean,

	-- сетка
	tick: number,

	beginMove: ((self: any, moveId: string, dir: Vector3?) -> boolean),
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

M.STATES = { "idle", "startup", "active", "recovery", "blocking", "stunned", "knockdown", "getup", "ground", "finished" }

local BUFFER_WINDOW_FRAMES = 10

function M.new(id: string, stats: FighterStats?, player: Player?): FighterState
	local st = stats or M.DEFAULT_STATS
	local cfg = table.clone(StaminaSystem.DEFAULT_CONFIG)
	cfg.max = 100 + (st.staminaPool - 50) * 0.6 -- стата стамины увеличивает бак
	cfg.regenPerSecondIdle = 5.0 + (st.staminaPool / 100) * 4

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
		grounded = false,
		getupFrames = 0,
		invulnFrames = 0,

		inputBuffer = {},
		tick = 0,
	} :: any

	self.canAct = function(s: FighterState): boolean
		if s.stunFrames > 0 or s.grounded or s.getupFrames > 0 then
			return false
		end
		if s.move and s.phase ~= "none" then
			-- разрешаем только в окне отмены
			return FrameData.canCancel(s.move, s.moveFrame)
		end
		return true
	end

	self.beginMove = function(s: FighterState, moveId: string, dir: Vector3?): boolean
		local move = Moves.get(moveId)
		if not move then
			return false
		end
		if not s:canAct() then
			-- не прошло сейчас -> кладём в буфер, файтинги так и делают
			if #s.inputBuffer < 3 then
				table.insert(s.inputBuffer, { moveId = moveId, atFrame = s.tick, dir = dir or Vector3.zero })
			end
			return false
		end
		if move.props.onGroundOnly and not s.grounded then
			return false
		end
		if move.props.standingOnly and s.grounded then
			return false
		end
		if not s.stamina:spend(FrameData.staminaCost(move, 0) * 0.35) then
			-- старт мува стоит часть стамины; остальное спишется в активных кадрах
			s.stamina:spend(s.stamina.value)
			s.stunFrames = math.max(s.stunFrames, 12)
			return false
		end
		s.move = move
		s.moveFrame = 1
		s.phase = "startup"
		s.blocked = false
		return true
	end

	self.applyKnockdown = function(s: FighterState)
		s.move = nil
		s.moveFrame = 0
		s.phase = "none"
		s.grounded = true
		s.getupFrames = 0
		s.stunFrames = 0
	end

	self.consumeHit = function(s: FighterState, result: FrameData.HitResult)
		local chinMul = FightMath.remap(s.stats.chin, 0, 100, 1.15, 0.85)
		local dmg = result.healthDamage * chinMul
		if result.knockdown then
			dmg *= 0.85
		end
		s.health = math.max(0, s.health - dmg)
		s.stamina:takeDamage(result.staminaDamage)

		if result.knockdown and not s.blocked then
			s:applyKnockdown()
			s.getupFrames = 90 -- ~1.5 сек лежим, потом встаём
			s.invulnFrames = 30
			return
		end

		if result.stunFrames > 0 and not s.blocked then
			s.stunFrames = math.max(s.stunFrames, result.stunFrames)
			s.move = nil
			s.moveFrame = 0
			s.phase = "none"
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
		elseif s.grounded then
			activity = "grappling"
		elseif opponent and s.humanoidRootPart and opponent.humanoidRootPart then
			activity = "moving"
		end
		s.stamina:regen(dt, activity, nil)

		-- нокдаун/вставание
		if s.grounded and s.getupFrames > 0 then
			s.getupFrames -= 1
			if s.getupFrames <= 0 then
				s.grounded = false
				s.invulnFrames = 12
			end
			s.blockHeldFrames = 0
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
			if now - entry.atFrame <= BUFFER_WINDOW_FRAMES then
				table.insert(kept, entry)
			end
		end
		s.inputBuffer = kept
		if #s.inputBuffer > 0 and s:canAct() then
			local entry = table.remove(s.inputBuffer, 1)
			s:beginMove(entry.moveId, entry.dir)
		end

		if s.health <= 0 then
			s.grounded = true
			s.getupFrames = 10 ^ 6
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
			grounded = s.grounded,
			tick = s.tick,
		}
	end

	return self
end

return M
