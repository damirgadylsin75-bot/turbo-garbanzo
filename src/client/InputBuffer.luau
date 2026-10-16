--!strict
-- InputBuffer (клиент): считывает ввод игрока и превращает его в НАМЕРЕНИЯ,
-- которые уходят на сервер. Клиент шлёт ТОЛЬКО {action, moveId} - никакого
-- урона/позиций/кадров. Урон считает сервер (MatchServer).

-- ===== РАСКЛАДКА КЛАВИАТУРЫ =====
local KEYBOARD = {
	[Enum.KeyCode.E] = { action = "strike", moveId = "jab" },
	[Enum.KeyCode.R] = { action = "strike", moveId = "cross" },
	[Enum.KeyCode.F] = { action = "strike", moveId = "hook_left" },
	[Enum.KeyCode.G] = { action = "strike", moveId = "hook_right" },
	[Enum.KeyCode.T] = { action = "strike", moveId = "uppercut_right" },
	[Enum.KeyCode.Y] = { action = "strike", moveId = "overhand_right" },
	[Enum.KeyCode.Q] = { action = "strike", moveId = "kick_low" },
	[Enum.KeyCode.X] = { action = "strike", moveId = "kick_body" },
	[Enum.KeyCode.C] = { action = "strike", moveId = "kick_head" },
	[Enum.KeyCode.Z] = { action = "defense", moveId = "slip" },
	[Enum.KeyCode.V] = { action = "defense", moveId = "duck" },
	[Enum.KeyCode.Space] = { action = "block", moveId = "block" },
}

-- ===== РАСКЛАДКА ГЕЙМПАДА =====
-- ButtonB НЕ используется: Roblox держит её под меню.
local GAMEPAD = {
	[Enum.KeyCode.ButtonA] = { action = "strike", moveId = "jab" },
	[Enum.KeyCode.ButtonY] = { action = "strike", moveId = "hook_left" },
	[Enum.KeyCode.ButtonX] = { action = "strike", moveId = "kick_low" },
	[Enum.KeyCode.ButtonR2] = { action = "strike", moveId = "cross" },
	[Enum.KeyCode.ButtonL2] = { action = "block", moveId = "block" },
	[Enum.KeyCode.ButtonR1] = { action = "strike", moveId = "kick_head" },
	[Enum.KeyCode.ButtonL1] = { action = "defense", moveId = "slip" },
	[Enum.KeyCode.ButtonR3] = { action = "strike", moveId = "hook_right" },
	[Enum.KeyCode.DPadUp] = { action = "strike", moveId = "uppercut_right" },
	[Enum.KeyCode.DPadRight] = { action = "strike", moveId = "overhand_right" },
	[Enum.KeyCode.DPadLeft] = { action = "strike", moveId = "kick_body" },
	[Enum.KeyCode.DPadDown] = { action = "defense", moveId = "duck" },
}

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local Client = script.Parent
local AnimDriver = require(Client:WaitForChild("AnimDriver"))

local M = {}

local evInput = Remotes.event("FighterInput")

local function send(payload: { [string]: any })
	evInput:FireServer(payload)
end

-- Печатаем раскладку в Output
local function printLayout()
	local function dump(title: string, binds: { [Enum.KeyCode]: any })
		local names = {}
		for code in pairs(binds) do
			table.insert(names, code.Name)
		end
		table.sort(names)
		print("[InputBuffer] " .. title)
		for _, name in ipairs(names) do
			local code = Enum.KeyCode[name] :: Enum.KeyCode
			local bind = binds[code]
			print(string.format("[InputBuffer]   %-12s -> %s %s", name, bind.action, bind.moveId))
		end
	end
	dump("=== раскладка клавиатуры ===", KEYBOARD)
	dump("=== раскладка геймпада (ButtonB не используется - занята меню Roblox) ===", GAMEPAD)
end

-- Отключаем дефолтный прыжок Roblox: он занимает Space
local function disableDefaultJump(player: Player)
	ContextActionService:UnbindAction("jumpAction")
	local function onCharacter(character: Model)
		ContextActionService:UnbindAction("jumpAction")
		local hum = character:WaitForChild("Humanoid", 5)
		if hum and hum:IsA("Humanoid") then
			hum.UseJumpPower = true
			hum.JumpPower = 0
			hum.JumpHeight = 0
		end
	end
	if player.Character then
		onCharacter(player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)
end

function M.start()
	local player = Players.LocalPlayer
	disableDefaultJump(player)
	printLayout()

	-- единая таблица кодов: клавиатура + геймпад
	local byCode: { [Enum.KeyCode]: any } = {}
	for code, bind in pairs(KEYBOARD) do
		byCode[code] = bind
	end
	for code, bind in pairs(GAMEPAD) do
		byCode[code] = bind
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local bind = byCode[input.KeyCode]
		if not bind then
			return
		end
		send({ action = bind.action, moveId = bind.moveId })
		AnimDriver.play(bind.moveId)
	end)

	UserInputService.InputEnded:Connect(function(input, processed)
		if processed then
			return
		end
		local bind = byCode[input.KeyCode]
		if not bind then
			return
		end
		if bind.action == "block" then
			send({ action = "unblock", moveId = bind.moveId })
			AnimDriver.stop()
		end
	end)
end

return M
