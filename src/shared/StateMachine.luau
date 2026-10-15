--!strict
-- StateMachine: универсальный конечный автомат.
-- Один и тот же код используется для:
--   1. фазы боя (standing / clinch / ground / knockdown / finished)
--   2. фазы конкретного мува (startup / active / recovery)
-- Сервер и клиент держат ПО ОДНОЙ копии автомата, поэтому клиент может
-- предсказывать анимацию мгновенно, а сервер остаётся авторитетным.

export type State = {
	name: string,
	frame: number, -- сколько кадров (тиков) мы в этом состоянии
}

export type StateMachine = {
	states: { [string]: State },
	current: State,
	stack: { State },
	changed: boolean,
	enter: ((self: any, name: string, params: { [string]: any }?) -> boolean),
	leave: ((self: any) -> ()),
	update: ((self: any) -> ()),
	is: ((self: any, name: string) -> boolean),
	any: ((self: any, names: { string }) -> boolean),
	ticksIn: ((self: any) -> number),
}

local StateMachine = {}
StateMachine.__index = StateMachine

function StateMachine.new(states: { string }, initial: string)
	assert(states[1] ~= nil, "StateMachine.new: нужен хотя бы один стейт")
	local dict: { [string]: State } = {}
	for _, name in states do
		dict[name] = { name = name, frame = 0 }
	end
	assert(dict[initial] ~= nil, "StateMachine.new: нет стейта " .. tostring(initial))

	return setmetatable({
		states = dict,
		current = dict[initial],
		stack = {},
		changed = false,
	}, StateMachine) :: any
end

function StateMachine:enter(name: string, _params: { [string]: any }?): boolean
	local next = self.states[name]
	if not next or next == self.current then
		return false
	end
	table.insert(self.stack, self.current)
	self.current = next
	next.frame = 0
	self.changed = true
	return true
end

function StateMachine:leave()
	local prev = table.remove(self.stack)
	if prev then
		self.current = prev
		self.current.frame = 0
		self.changed = true
	end
end

function StateMachine:update()
	self.current.frame += 1
end

function StateMachine:is(name: string): boolean
	return self.current.name == name
end

function StateMachine:any(names: { string }): boolean
	for _, n in names do
		if self.current.name == n then
			return true
		end
	end
	return false
end

function StateMachine:ticksIn(): number
	return self.current.frame
end

return StateMachine
