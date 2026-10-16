--!strict
-- GrappleSystem: граппл - это НЕ физика, а направленный граф состояний + контесты.
-- В UFC 4 переводы работают так:
--   standing -> clinch -> takedown attempt -> ground position (guard / side / mount / back)
-- каждая попытка = мини-контест "атака vs защита", модифицированный стаминой.
-- Тайминги (секунды на реакцию, окна защиты) берутся из видео-замеров.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local FightMath = require(Shared:WaitForChild("FightMath"))
local FrameData = require(Shared:WaitForChild("FrameData"))
local Moves = require(Shared:WaitForChild("Moves"))

export type GroundPosition = "standing" | "clinch" | "guard_top" | "guard_bottom" | "side_top" | "side_bottom" | "mount_top" | "mount_bottom" | "back_top" | "back_bottom"

export type GrappleConfig = {
	clinchEnterRange: number,   -- студы
	takedownRange: number,
	escapeWindow: number,       -- сек на защиту от тейкдауна
	submissionDuration: number, -- сек удержания сабмишена
	positionAdvanceChance: number,
}

export type GrappleSession = {
	position: GroundPosition,
	topId: string?,
	bottomId: string?,
	timer: number,
	pending: { moveId: string, attackerId: string, timer: number, defenderId: string }?,
	-- результат броска кубика на успех контеста, снимается когда pending разрешается
	pendingRoll: boolean?,
	transition: ((self: any, pos: GroundPosition, topId: string?) -> ()),
	attempt: ((self: any, attacker: any, defender: any, move: FrameData.MoveDef) -> boolean),
	update: ((self: any, dt: number, attacker: any, defender: any) -> ()),
	isGround: ((self: any) -> boolean),
}

local M = {}

M.DEFAULT_CONFIG = {
	clinchEnterRange = 3.2,
	takedownRange = 4.5,
	escapeWindow = 0.42,
	submissionDuration = 3.0,
	positionAdvanceChance = 0.22,
} :: GrappleConfig

M.POSITIONS = {
	standing = { ground = false },
	clinch = { ground = false },
	guard_top = { ground = true },
	guard_bottom = { ground = true },
	side_top = { ground = true },
	side_bottom = { ground = true },
	mount_top = { ground = true },
	mount_bottom = { ground = true },
	back_top = { ground = true },
	back_bottom = { ground = true },
}

-- Пары "кто сверху / кто снизу" для одной позиции
M.PAIRS = {
	guard_top = "guard_bottom",
	side_top = "side_bottom",
	mount_top = "mount_bottom",
	back_top = "back_bottom",
}

function M.mirror(position: GroundPosition): GroundPosition
	return (M.PAIRS[position] or position) :: GroundPosition
end

function M.isGround(position: GroundPosition): boolean
	local def = M.POSITIONS[position]
	return def ~= nil and def.ground == true
end

function M.new(config: GrappleConfig?): GrappleSession
	local cfg = config or M.DEFAULT_CONFIG
	local self
	self = {
		position = "standing" :: GroundPosition,
		topId = nil,
		bottomId = nil,
		timer = 0,
		pending = nil,
	} :: any

	self.transition = function(s: GrappleSession, pos: GroundPosition, topId: string?)
		s.position = pos
		s.timer = 0
		s.topId = topId
		s.bottomId = nil
		s.pending = nil
	end

	-- Попытка греппл-мува: тейкдаун, перевод позиции, сабмишен, свип, вставание
	self.attempt = function(s: GrappleSession, attacker, defender, move: FrameData.MoveDef): boolean
		local g = move.grapple
		if not g then
			return false
		end
		if g.from then
			local ok = false
			for _, allowed in ipairs(g.from) do
				if s.position == allowed then
					ok = true
				end
			end
			if not ok then
				return false
			end
		end
		if attacker.stamina:spend(move.stamina.cost) == false then
			return false
		end

		local attackStat = attacker.stats.grappleOffense * (g.power and (0.6 + g.power / 250) or 1)
		local defenseStat = defender.stats.grappleDefense
		local chance = FightMath.contestChance(attackStat, defenseStat, attacker.stamina:ratio(), defender.stamina:ratio())

		-- Защитник получает окно на реакцию (в UFC 4 это QTE/тайминг-защита)
		if defender.blocked then
			chance *= 0.55
		end

		s.pending = {
			moveId = move.id,
			attackerId = attacker.id,
			defenderId = defender.id,
			timer = cfg.escapeWindow,
		}
		s.pendingRoll = math.random() < chance
		return true
	end

	self.update = function(s: GrappleSession, dt: number, attacker, defender)
		s.timer += dt

		local pending = s.pending
		if pending then
			pending.timer -= dt
			if pending.timer <= 0 then
				local move = Moves.get(pending.moveId)
				s.pending = nil
				if move and move.grapple then
					local success = s.pendingRoll
					if success then
						local to = move.grapple.to or s.position
						if move.grapple.kind == "escape" then
							-- встал или засвипил: меняем верх/низ
							s:transition("standing", nil)
							attacker.grounded = false
							defender.grounded = false
						elseif move.grapple.kind == "submit" then
							s:transition("standing", nil)
							defender.health = 0
						else
							s:transition(to :: GroundPosition, pending.attackerId)
							attacker.grounded = M.isGround(s.position)
							defender.grounded = attacker.grounded
						end
					else
						-- защита удалась: защитник тратит стамину, атака отбита
						defender.stamina:takeDamage(6)
					end
				end
			end
			return
		end

		-- Пассивный дрифт позиций на земле: сверху давят, снизу тратят стамину
		if M.isGround(s.position) and s.timer > 4 then
			s.timer = 0
			if math.random() < cfg.positionAdvanceChance and s.topId then
				local order = { "guard_top", "side_top", "mount_top", "back_top" }
				for i, name in ipairs(order) do
					if s.position == name and order[i + 1] then
						s:transition(order[i + 1], s.topId)
						break
					end
				end
			end
			if s.bottomId then
				-- кто снизу - задыхается
			end
		end
	end

	return self
end

-- Расстояние, на котором доступен клинч/тейкдаун
function M.inTakedownRange(a: BasePart, b: BasePart, config: GrappleConfig?): boolean
	local cfg = config or M.DEFAULT_CONFIG
	return (a.Position - b.Position).Magnitude <= cfg.takedownRange
end

return M
