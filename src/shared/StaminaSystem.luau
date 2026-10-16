--!strict
-- StaminaSystem: стамина - главный ресурс в UFC 4.
-- Наблюдения из игры:
--   * удар в блок почти не снимает здоровье, но снимает стамину
--   * при нулевой стамине боец "дышит", двигается медленнее, падает от любого хэд-кика
--   * реген зависит от активности
-- Все числа приходят из data/moves.json (секция "stamina") - здесь нет хардкода.

export type StaminaConfig = {
	max: number,
	regenPerSecondIdle: number,      -- стоит на месте
	regenPerSecondMoving: number,    -- ходит
	regenPerSecondBlocking: number,  -- держит блок
	regenDelayAfterSprint: number,   -- задержка регена после спринта, сек
	exhaustedThreshold: number,      -- ниже этого - состояние "выдохся"
	recoveryTo: number,              -- после выдоха восстанавливаемся хотя бы до этого
	speedBase: number,               -- кривая скорости от стамины
	speedSpan: number,
	speedExhausted: number,
	damageBase: number,              -- кривая урона от стамины
	damageSpan: number,
}

export type StaminaModel = {
	value: number,
	max: number,
	exhausted: boolean,
	recoverTimer: number,
	spend: ((self: any, amount: number) -> boolean),
	takeDamage: ((self: any, amount: number) -> ()),
	regen: ((self: any, dt: number, activity: string, config: StaminaConfig?) -> ()),
	ratio: ((self: any, config: StaminaConfig?) -> number),
}

local M = {}

function M.new(config: StaminaConfig): StaminaModel
	local cfg = config
	local model
	model = {
		value = cfg.max,
		max = cfg.max,
		exhausted = false,
		recoverTimer = 0,

		-- Тратит стамину. Возвращает false, если не хватило (мув не выполнится).
		spend = function(self: StaminaModel, amount: number): boolean
			if amount <= 0 then
				return true
			end
			if self.value < amount then
				return false
			end
			self.value -= amount
			if self.value <= cfg.exhaustedThreshold then
				self.exhausted = true
			end
			return true
		end,

		-- Урон по стамине (удары в блок). Может уйти в минус-эффект: выдох.
		takeDamage = function(self: StaminaModel, amount: number)
			self.value = math.max(0, self.value - amount)
			if self.value <= cfg.exhaustedThreshold then
				self.exhausted = true
			end
		end,

		regen = function(self: StaminaModel, dt: number, activity: string, runtimeCfg: StaminaConfig?)
			local c = runtimeCfg or cfg
			if self.recoverTimer > 0 then
				self.recoverTimer -= dt
				return
			end
			local rate
			if activity == "idle" then
				rate = c.regenPerSecondIdle
			elseif activity == "moving" then
				rate = c.regenPerSecondMoving
			elseif activity == "blocking" then
				rate = c.regenPerSecondBlocking
			else
				rate = c.regenPerSecondIdle * 0.5
			end

			-- Выдох: сначала добираемся до recoveryTo по ускоренной кривой
			if self.exhausted then
				self.value += rate * dt * 1.8
				if self.value >= c.recoveryTo then
					self.exhausted = false
				end
			else
				self.value += rate * dt
			end
			self.value = math.min(c.max, self.value)
		end,

		ratio = function(self: StaminaModel, runtimeCfg: StaminaConfig?): number
			local c = runtimeCfg or cfg
			return self.value / math.max(0.001, c.max)
		end,
	} :: any
	return model
end

-- Множитель скорости от усталости. Именно он делает "тяжёлые" 3-е раунды.
function M.speedMultiplier(model: StaminaModel, config: StaminaConfig): number
	if model.exhausted then
		return config.speedExhausted
	end
	local ratio = model.value / config.max
	return config.speedBase + config.speedSpan * math.clamp(ratio, 0, 1)
end

-- Штраф к урону уставшего бойца
function M.damageMultiplier(model: StaminaModel, config: StaminaConfig): number
	local ratio = model.value / config.max
	return config.damageBase + config.damageSpan * math.clamp(ratio, 0, 1)
end

return M
