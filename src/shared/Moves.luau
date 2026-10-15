--!strict
-- Moves: загрузчик базы приёмов из data/moves.json.
-- Вся "физика UFC 4" живёт в JSON - так её можно править, не трогая код,
-- и генерировать/дополнять нейросетью пачками.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FrameData = require(script.Parent.FrameData)
export type MoveDef = FrameData.MoveDef

local M = {}

local cache: { [string]: MoveDef } = {}
local byCategory: { [string]: { MoveDef } } = {}
local loaded = false

local function load()
	if loaded then
		return
	end
	loaded = true

	local folder = ReplicatedStorage:WaitForChild("FightData")
	local asset = folder:WaitForChild("moves") :: JsonStringValue
	local decoded = game:GetService("HttpService"):JSONDecode(asset.Value)

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
end

function M.get(id: string): MoveDef?
	load()
	return cache[id]
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

-- Быстрые шорткаты для кода и для ИИ-бойца
function M.standingStrikes(): { MoveDef }
	local out = {}
	for _, move in ipairs(M.byCategory("strike")) do
		if not move.props.onGroundOnly then
			table.insert(out, move)
		end
	end
	return out
end

function M.groundStrikes(): { MoveDef }
	local out = {}
	for _, move in ipairs(M.byCategory("ground_strike")) do
		table.insert(out, move)
	end
	return out
end

function M.takedowns(): { MoveDef }
	return M.byCategory("grapple")
end

return M
