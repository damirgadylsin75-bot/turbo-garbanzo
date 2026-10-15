--!strict
-- InputBuffer (клиент): считывает ввод игрока и превращает его в НАМЕРЕНИЯ,
-- которые уходят на сервер. Ничего локального урона - только запросы.
--
-- Раскладка в стиле UFC 4 (геймпад/клавиатура):
--   ЛКМ / R2      - джеб (правая рука)
--   ПКМ / L2      - блок
--   Q / Square    - кик
--   E / Triangle  - тейкдаун / граппл
--   1..4          - удары по уровню (голова/корпус/ноги)
--   Space         - движение вперёд, Shift - назад
--   Двойной тап направления - тейкдаун (как в UFC 4: вперёд+вперёд)

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local M = {}

local evInput = Remotes.event("FighterInput")

M.KEYBINDS = {
	[Enum.KeyCode.E] = { action = "strike", moveId = "jab" },
	[Enum.KeyCode.R] = { action = "strike", moveId = "cross" },
	[Enum.KeyCode.F] = { action = "strike", moveId = "hook_left" },
	[Enum.KeyCode.G] = { action = "strike", moveId = "uppercut_right" },
	[Enum.KeyCode.Q] = { action = "strike", moveId = "kick_low" },
	[Enum.KeyCode.T] = { action = "strike", moveId = "kick_body" },
	[Enum.KeyCode.Y] = { action = "strike", moveId = "kick_head" },
	[Enum.KeyCode.C] = { action = "strike", moveId = "knee_clinch" },
	[Enum.KeyCode.X] = { action = "grapple", moveId = "double_leg" },
	[Enum.KeyCode.V] = { action = "grapple", moveId = "single_leg" },
	[Enum.KeyCode.B] = { action = "defense", moveId = "slip" },
	[Enum.KeyCode.N] = { action = "defense", moveId = "duck" },
}

M.GAMEPAD_BINDS = {
	[Enum.KeyCode.ButtonA] = { action = "strike", moveId = "jab" },
	[Enum.KeyCode.ButtonB] = { action = "strike", moveId = "hook_left" },
	[Enum.KeyCode.ButtonX] = { action = "strike", moveId = "kick_low" },
	[Enum.KeyCode.ButtonY] = { action = "grapple", moveId = "double_leg" },
	[Enum.KeyCode.ButtonR2] = { action = "strike", moveId = "cross" },
	[Enum.KeyCode.ButtonL2] = { action = "block", held = true },
	[Enum.KeyCode.ButtonR1] = { action = "strike", moveId = "kick_head" },
	[Enum.KeyCode.ButtonL1] = { action = "defense", moveId = "slip" },
}

local DOUBLE_TAP_WINDOW = 0.26
local lastTap: { [string]: number } = {}

local function send(payload: { [string]: any })
	evInput:FireServer(payload)
end

function M.start()
	local player = Players.LocalPlayer

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local bind = M.KEYBINDS[input.KeyCode]
		if bind then
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local dir = Vector3.zero
			if hrp then
				dir = hrp.CFrame.LookVector
			end
			send({ action = bind.action, moveId = bind.moveId, dir = { dir.X, dir.Y, dir.Z } })
			return
		end

		if input.KeyCode == Enum.KeyCode.Space or input.UserInputType == Enum.UserInputType.MouseButton2 then
			send({ action = "block", held = true })
			return
		end

		-- двойной тап W = рывок/тейкдаун
		if input.KeyCode == Enum.KeyCode.W then
			local now = os.clock()
			if lastTap.W and now - lastTap.W < DOUBLE_TAP_WINDOW then
				send({ action = "grapple", moveId = "double_leg" })
				lastTap.W = nil
			else
				lastTap.W = now
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Space or input.UserInputType == Enum.UserInputType.MouseButton2 then
			send({ action = "block", held = false })
		end
	end)

	-- геймпад
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local gp = M.GAMEPAD_BINDS[input.KeyCode]
		if gp then
			send(gp)
		end
	end)
end

return M
