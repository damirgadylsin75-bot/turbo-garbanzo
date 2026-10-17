--!strict
-- Кнопка выхода и локальный четырёхминутный таймер тренировочной сессии.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local event = Remotes.event("ArenaSession")
local M = {}

function M.start()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "ArenaSessionGui"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")
	local timer = Instance.new("TextLabel")
	timer.Name = "FightTimer"
	timer.Size = UDim2.fromOffset(220, 48)
	timer.Position = UDim2.new(0.5, -110, 0, 24)
	timer.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	timer.BackgroundTransparency = 0.15
	timer.TextColor3 = Color3.new(1, 1, 1)
	timer.TextScaled = true
	timer.Font = Enum.Font.GothamBold
	timer.Parent = gui
	local leave = Instance.new("TextButton")
	leave.Name = "RunForYourLife"
	leave.Size = UDim2.fromOffset(220, 54)
	leave.Position = UDim2.new(1, -242, 1, -82)
	leave.BackgroundColor3 = Color3.fromRGB(150, 35, 35)
	leave.TextColor3 = Color3.new(1, 1, 1)
	leave.TextScaled = true
	leave.Font = Enum.Font.GothamBold
	leave.Text = "RUN FOR YOUR LIFE"
	leave.Parent = gui
	leave.Activated:Connect(function()
		event:FireServer("leave")
	end)

	event.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then return end
		gui.Enabled = payload.active == true
		if not payload.active then return end
		local deadline = os.clock() + (tonumber(payload.seconds) or 240)
		task.spawn(function()
			while gui.Enabled and os.clock() < deadline do
				local remaining = math.max(0, math.ceil(deadline - os.clock()))
				timer.Text = string.format("%d:%02d", math.floor(remaining / 60), remaining % 60)
				RunService.Heartbeat:Wait()
			end
		end)
	end)
end

return M
