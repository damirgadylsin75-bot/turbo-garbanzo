--!strict
-- FrameData: ядро боевой системы (тестовая сборка: только стойка).
-- В UFC 4 (и любом файтинге) каждое движение описано КАДРАМИ при 60 fps:
--   startup  -> анимация замаха, хитбокс выключен, ты уязвим
--   active   -> хитбокс включён, можно попасть
--   recovery -> возврат в стойку, нельзя двигаться (окно наказания)
-- Всё остальное (стамина, урон, стаггер, нокдаун) - модификаторы поверх этого.
-- Все игровые числа (включая коэффициенты balance) приходят из data/moves.json.

export type Phase = "startup" | "active" | "recovery" | "none"

export type HitboxSpec = {
	bone: string,          -- имя кости R15, к которой варится хитбокс (RightHand/LeftHand/RightFoot)
	size: Vector3,         -- размер в студах (1 стад ~ 28 см, человек ~ 5 студов)
	offset: Vector3,       -- смещение от кости
	reach: number,         -- доп. дальность для теста дистанции (студы)
}

export type MoveDef = {
	id: string,
	name: string,
	category: string,      -- strike / defense
	timing: {
		startup: number,   -- в кадрах (60 fps)
		active: number,
		recovery: number,
	},
	stamina: { cost: number, costPerActiveFrame: number? },
	-- урон
	damage: {
		health: number,    -- базовый урон по здоровью
		stamina: number,   -- урон по стамине (в UFC 4 удары в блок жрут именно её)
		chipRatio: number, -- сколько проходит через блок (0.08 = 8%)
	},
	-- реакция на попадание
	reaction: {
		stunFrames: number,     -- стаггер
		knockdownChance: number,-- 0..1, шанс уронить
		floorStamina: number,   -- ниже этой стамины шанс нокдауна растёт
		knockback: number,      -- импульс в студах/сек
	},
	hitbox: HitboxSpec?,
	hitLevel: string?,     -- "high" | "mid" | "low"
	cancel: { string }?,   -- во что можно отменить (комбо-окна)
	-- флаги
	props: {
		armorFrames: { number }?, -- кадры супер-армора
		movesCharacter: boolean?, -- движение двигает тело вперёд
		holdToCharge: boolean?,
	},
}

-- Коэффициенты баланса: значения из data/moves.json (секция "balance")
export type Balance = {
	powerMin: number,
	powerSpan: number,
	chinWorst: number,
	chinBest: number,
	blockStaminaMul: number,
	blockStunMul: number,
	blockHoldGraceFrames: number,
	blockHoldMaxBonus: number,
	blockHoldBonusFrames: number,
	stunnedStunMul: number,
	blockedKnockdownMul: number,
	fatigueKnockdownBonus: number,
	knockdownMinStunFrames: number,
	knockdownDamageMul: number,
	knockdownKnockbackMul: number,
}

export type HitResult = {
	moveId: string,
	rawDamage: number,
	blocked: boolean,
	healthDamage: number,
	staminaDamage: number,
	stunFrames: number,
	knockdown: boolean,
	knockback: number,
	direction: Vector3,
}

local M = {}

M.FPS = 60
M.FRAME = 1 / 60

-- Суммарная длина мува в кадрах = окно, в котором боец "занят"
function M.totalFrames(move: MoveDef): number
	local t = move.timing
	return t.startup + t.active + t.recovery
end

-- Кадры, в которые мув можно отменить во что-то другое
function M.cancelWindow(move: MoveDef): (number, number)
	local t = move.timing
	local startFrame = math.max(1, t.startup - 4)          -- буферизация ввода чуть раньше активного кадра
	local endFrame = t.startup + t.active + 3              -- ранний выход в комбо
	return startFrame, math.min(endFrame, M.totalFrames(move))
end

-- Кадры супер-армора (по умолчанию - активные)
function M.armorFrames(move: MoveDef): (number?, number?)
	local armor = move.props.armorFrames
	if not armor then
		return nil
	end
	return armor[1], armor[2]
end

function M.phaseAt(move: MoveDef, frame: number): Phase
	local t = move.timing
	if frame <= 0 or frame > M.totalFrames(move) then
		return "none"
	end
	if frame <= t.startup then
		return "startup"
	end
	if frame <= t.startup + t.active then
		return "active"
	end
	return "recovery"
end

function M.isActive(move: MoveDef, frame: number): boolean
	return M.phaseAt(move, frame) == "active"
end

-- Хитбокс живёт только в активных кадрах
function M.hitboxSpecAt(move: MoveDef, frame: number): HitboxSpec?
	if not move.hitbox then
		return nil
	end
	if M.phaseAt(move, frame) ~= "active" then
		return nil
	end
	return move.hitbox
end

function M.canCancel(move: MoveDef, frame: number): boolean
	local s, e = M.cancelWindow(move)
	return frame >= s and frame <= e
end

function M.staminaCost(move: MoveDef, activeFramesUsed: number?): number
	local cost = move.stamina.cost
	local per = move.stamina.costPerActiveFrame or 0
	return cost + per * (activeFramesUsed or move.timing.active)
end

-- Главная формула разрешения попадания. Чистая функция -> её можно балансировать
-- отдельно от Roblox. Коэффициенты приходят из data/moves.json ("balance").
function M.resolveHit(move: MoveDef, attackerPower: number, defenderState: {
	blocked: boolean,
	blockHeldFrames: number?,
	stamina: number,
	maxStamina: number,
	stunned: boolean,
	directionToDefender: Vector3?,
}, balance: Balance): HitResult
	local blocked = defenderState.blocked and not defenderState.stunned
	local dir = defenderState.directionToDefender or Vector3.new(0, 0, 1)

	-- Урон по здоровью: базовый * сила бойца (стата 0..100 -> множитель)
	local powerMul = balance.powerMin + (attackerPower / 100) * balance.powerSpan
	local healthDamage = move.damage.health * powerMul

	-- Урон по стамине
	local staminaDamage = move.damage.stamina * powerMul
	if blocked then
		-- Блок почти полностью гасит здоровье, но выжигает стамину (как в UFC 4)
		healthDamage *= move.damage.chipRatio
		staminaDamage *= balance.blockStaminaMul
		-- Долгий удержанный блок "пробивается" быстрее
		local held = defenderState.blockHeldFrames or 0
		if held > balance.blockHoldGraceFrames then
			local holdBonus = (held - balance.blockHoldGraceFrames) / balance.blockHoldBonusFrames
			if holdBonus > balance.blockHoldMaxBonus then
				holdBonus = balance.blockHoldMaxBonus
			end
			staminaDamage *= 1 + holdBonus
		end
	end

	-- Стаггер: в блок - минимальный, по ошеломлённому - максимальный
	local stunFrames = move.reaction.stunFrames
	if blocked then
		stunFrames = math.floor(stunFrames * balance.blockStunMul)
	elseif defenderState.stunned then
		stunFrames = math.floor(stunFrames * balance.stunnedStunMul)
	end

	-- Нокдаун: шанс растёт, когда стамина на нуле (устал = упал)
	local knockdown = false
	local staminaRatio = defenderState.stamina / math.max(1, defenderState.maxStamina)
	local knockdownChance = move.reaction.knockdownChance * powerMul
	if staminaRatio <= move.reaction.floorStamina then
		local fatigue = 1 - (staminaRatio / math.max(0.001, move.reaction.floorStamina))
		knockdownChance += fatigue * balance.fatigueKnockdownBonus
	end
	if blocked then
		knockdownChance *= balance.blockedKnockdownMul
	end
	if not blocked and math.random() < knockdownChance then
		knockdown = true
		stunFrames = math.max(stunFrames, balance.knockdownMinStunFrames)
	end

	local knockback = move.reaction.knockback
	if knockdown then
		knockback = move.reaction.knockback * balance.knockdownKnockbackMul
	end

	return {
		moveId = move.id,
		rawDamage = move.damage.health,
		blocked = blocked,
		healthDamage = healthDamage,
		staminaDamage = staminaDamage,
		stunFrames = stunFrames,
		knockdown = knockdown,
		knockback = knockback,
		direction = dir,
	}
end

return M
