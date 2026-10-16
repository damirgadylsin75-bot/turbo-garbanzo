--!strict
-- HUD: полоски здоровья/стамины как в UFC 4 (две сверху, имена по центру, таймер раунда).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local M = {}

local evSnapshot = Remotes.event("FightSnapshot")
local player = Players.LocalPlayer

local gui: ScreenGui? = nil
local bars: { [string]: { health: Frame, stamina: Frame, name: TextLabel } } = {}
local latest: { [string]: any } = {}

local function bar(parent: Instance, name: string, color: Color3, sizeY: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Size = UDim2.new(1, 0, 0, sizeY)
	f.AnchorPoint = Vector2.new(1, 0)
	f.Position = UDim2.new(1, 0, 0, 0)
	f.Parent = parent
	return f
end

local function buildSide(side: string, index: number)
	assert(gui)
	local holder = Instance.new("Frame")
	holder.Name = "Side_" .. side
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(0.42, 0, 0, 46)
	holder.Position = UDim2.new(side == "L" and 0.03 or 0.55, 0, 0.03, 0)
	holder.Parent = gui

	local bg = Instance.new("Frame")
	bg.Name = "BG"
	bg.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
	bg.BackgroundTransparency = 0.25
	bg.BorderSizePixel = 0
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.Parent = holder

	local health = bar(holder, "Health", Color3.fromRGB(200, 40, 45), 20)
	local stamina = Instance.new("Frame")
	stamina.Name = "Stamina"
	stamina.BackgroundColor3 = Color3.fromRGB(60, 190, 120)
	stamina.BorderSizePixel = 0
	stamina.Size = UDim2.new(1, 0, 0, 10)
	stamina.AnchorPoint = Vector2.new(1, 0)
	stamina.Position = UDim2.new(1, 0, 0, 24)
	stamina.Parent = holder

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.new(1, 0, 0, 14)
	nameLabel.Position = UDim2.new(0, 0, 1, 2)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 13
	nameLabel.TextColor3 = Color3.fromRGB(230, 230, 235)
	nameLabel.Text = side == "L" and "FIGHTER 1" or "FIGHTER 2"
	nameLabel.TextXAlignment = side == "L" and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right
	nameLabel.Parent = holder

	bars[index == 1 and "1" or "2"] = { health = health, stamina = stamina, name = nameLabel }
end

function M.start()
	local pg = player:WaitForChild("PlayerGui")
	gui = Instance.new("ScreenGui")
	gui.Name = "FightHUD"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = pg

	buildSide("L", 1)
	buildSide("R", 2)

	evSnapshot.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" or typeof(payload.fighters) ~= "table" then
			return
		end
		latest = {}
		for i, snap in ipairs(payload.fighters) do
			latest[tostring(i)] = snap
		end
	end)

	RunService.RenderStepped:Connect(function()
		for key, set in pairs(bars) do
			local snap = latest[key]
			if snap then
				set.health.Size = UDim2.fromScale(math.clamp((snap.health or 0) / 100, 0, 1), 1)
				set.stamina.Size = UDim2.fromScale(math.clamp((snap.stamina or 0) / 100, 0, 1), 1)
				set.stamina.BackgroundColor3 = snap.exhausted and Color3.fromRGB(220, 90, 60)
					or Color3.fromRGB(60, 190, 120)
				set.name.Text = string.upper(tostring(snap.id))
			end
		end
	end)
end

return M
