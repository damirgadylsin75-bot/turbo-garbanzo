--!strict
-- FightMath: маленькие чистые функции, которые повторяются везде.
-- Держим их отдельно, чтобы их можно было прогнать в тестах и скормить
-- нейросети для автобаланса (см. docs/ai-workflow.md, шаг "сидентификация параметров").

local M = {}

function M.clamp(v: number, lo: number, hi: number): number
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

function M.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function M.remap(v: number, inMin: number, inMax: number, outMin: number, outMax: number): number
	local t = (v - inMin) / math.max(1e-6, inMax - inMin)
	return M.lerp(outMin, outMax, M.clamp(t, 0, 1))
end

-- Стата 0..100 -> множитель 0.85..1.15
function M.statToMultiplier(stat: number): number
	return M.remap(stat, 0, 100, 0.85, 1.15)
end

-- Шанс успеха греппл-действия: классическое противостояние аттак/деф + стамина
function M.contestChance(attack: number, defense: number, attackStamina: number, defenseStamina: number): number
	local a = attack * (0.6 + 0.4 * M.clamp(attackStamina, 0, 1))
	local d = defense * (0.6 + 0.4 * M.clamp(defenseStamina, 0, 1))
	local raw = a / math.max(1e-6, a + d)
	return M.clamp(raw, 0.05, 0.95)
end

-- Пружинно-демпферная модель "отскока" после нокдауна.
-- Подбирается под видео: снимаем траекторию падения бойца в UFC 4 и фитируем k/c.
function M.springDamp(x: number, v: number, target: number, k: number, c: number, dt: number): (number, number)
	local a = -k * (x - target) - c * v
	return x + v * dt, v + a * dt
end

-- Случайный разброс вокруг значения (для "живого" урона)
function M.jitter(v: number, pct: number): number
	return v * (1 + (math.random() * 2 - 1) * pct)
end

-- Поворот к цели вокруг Y с ограничением скорости (бойцы в UFC 4 не крутятся мгновенно)
function M.turnToward(current: CFrame, targetPos: Vector3, maxRadiansPerSecond: number, dt: number): CFrame
	local look = targetPos - current.Position
	look = Vector3.new(look.X, 0, look.Z)
	if look.Magnitude < 1e-4 then
		return current
	end
	local goal = CFrame.lookAt(current.Position, current.Position + look.Unit)
	return current:Lerp(goal, M.clamp(maxRadiansPerSecond * dt, 0, 1))
end

return M
