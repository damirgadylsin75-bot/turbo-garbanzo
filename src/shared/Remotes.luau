--!strict
-- Remotes: единая точка создания RemoteEvent'ов.
-- Клиент -> Сервер: только НАМЕРЕНИЯ (какой мув хочу), никогда не урон/позицию.
-- Сервер -> Клиент: снапшоты состояния и визуальные события.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local M = {}

local folder: Folder? = ReplicatedStorage:FindFirstChild("FightRemotes")

local function ensure(): Folder
	if folder then
		return folder
	end
	local found = ReplicatedStorage:FindFirstChild("FightRemotes")
	if found then
		folder = found :: Folder
		return folder
	end
	local created = Instance.new("Folder")
	created.Name = "FightRemotes"
	created.Parent = ReplicatedStorage
	folder = created
	return created
end

function M.event(name: string): RemoteEvent
	local parent = ensure()
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local ev = Instance.new("RemoteEvent")
	ev.Name = name
	ev.Parent = parent
	return ev
end

function M.get(name: string): RemoteEvent
	return M.event(name)
end

return M
