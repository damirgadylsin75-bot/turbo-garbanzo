--!strict
-- Moves: загрузчик базы приёмов из data/moves.json.
-- Вся "физика UFC 4" живёт в JSON - так её можно править, не трогая код.
-- Тестовая сборка: 12 приёмов стойки + общие секции combat/balance/stamina/
-- hurtboxes/dummy. Все игровые числа берутся отсюда, не из кода.

local FrameData = require(script.Parent.FrameData)
local MoveData = require(script.Parent:WaitForChild("MoveData"))
export type MoveDef = FrameData.MoveDef

local M = {}

local cache: { [string]: MoveDef } = {}
local byCategory: { [string]: { MoveDef } } = {}
local settings: { [string]: any } = {
	combat = {},
	balance = {},
	stamina = {},
	hurtboxes = {},
	dummy = {},
}
local loaded = false

local function load()
	if loaded then
		return
	end
	loaded = true

	-- Rojo may interpret raw .json as a Model; the generated Luau module safely carries its JSON text.
	local decoded = MoveData

	-- общие секции настроек (все числа боя - в JSON)
	settings.combat = decoded.combat or settings.combat
	settings.balance = decoded.balance or settings.balance
	settings.stamina = decoded.stamina or settings.stamina
	settings.dummy = decoded.dummy or settings.dummy
	if typeof(decoded.hurtboxes) == "table" then
		settings.hurtboxes = decoded.hurtboxes
	end
	for _, hb in ipairs(settings.hurtboxes) do
		if typeof(hb.size) ~= "Vector3" then
			hb.size = Vector3.new(hb.size[1] or 1, hb.size[2] or 1, hb.size[3] or 1)
		end
	end

	for _, raw in ipairs(decoded.moves) do
		local move = raw :: MoveDef
		-- JSON хранит векторы массивами [x, y, z] -> превращаем в Vector3
		if move.hitbox then
			local hb = move.hitbox :: any
			if typeof(hb.size) ~= "Vector3" then
				hb.size = Vector3.new(hb.size[1] or 1, hb.size[2] or 1, hb.size[3] or 1)
			end
			if typeof(hb.offset) ~= "Vector3" then
				local off = hb.offset
				hb.offset = Vector3.new(off[1] or 0, off[2] or 0, off[3] or 0)
			end
		end
		-- нормализация обязательных полей
		move.props = move.props or ({} :: any)
		move.damage = move.damage or ({ health = 0, stamina = 0, chipRatio = 0.08 } :: any)
		move.reaction = move.reaction or ({ stunFrames = 8, knockdownChance = 0, floorStamina = 0.2, knockback = 0 } :: any)
		move.stamina = move.stamina or ({ cost = 5 } :: any)

		cache[move.id] = move
		local cat = byCategory[move.category]
		if not cat then
			cat = {}
			byCategory[move.category] = cat
		end
		table.insert(cat, move)
	end
	print("[Moves] загружено приёмов: " .. tostring(#decoded.moves))
end

function M.get(id: string): MoveDef?
	load()
	return cache[id]
end

-- Валидация moveId от клиента: только приёмы из JSON проходят на сервер
function M.isValid(id: any): boolean
	if typeof(id) ~= "string" then
		return false
	end
	load()
	return cache[id] ~= nil
end

function M.all(): { MoveDef }
	load()
	local out = {}
	for _, move in pairs(cache) do
		table.insert(out, move)
	end
	return out
end

function M.byCategory(category: string): { MoveDef }
	load()
	return byCategory[category] or {}
end

-- Быстрые шорткаты для кода и для манекена
function M.standingStrikes(): { MoveDef }
	return M.byCategory("strike")
end

function M.defensive(): { MoveDef }
	return M.byCategory("defense")
end

-- Общие настройки боя (все числа - из data/moves.json)
function M.combat(): { [string]: any }
	load()
	return settings.combat
end

function M.balance(): { [string]: any }
	load()
	return settings.balance
end

function M.staminaConfig(): { [string]: any }
	load()
	return settings.stamina
end

function M.hurtboxes(): { [string]: any }
	load()
	return settings.hurtboxes
end

function M.dummyConfig(): { [string]: any }
	load()
	return settings.dummy
end

return M
