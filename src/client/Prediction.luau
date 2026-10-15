--!strict
-- Prediction + Reconciliation (клиент).
--
-- Идея: игрок нажимает кнопку -> мы СРАЗУ играем анимацию замаха локально
-- (иначе будет ощущение лага), а сервер независимо считает авторитетный мув.
-- Когда приходит снапшот, клиент сверяет (moveId + moveFrame) и при расхождении
-- плавно возвращает визуал к серверной правде.
--
-- Это "лёгкий rollback": мы не пересчитываем прошлое, а только корректируем
-- отображение - для файтинга с кадрами этого достаточно.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local FrameData = require(Shared:WaitForChild("FrameData"))
local Moves = require(Shared:WaitForChild("Moves"))

local Client = script.Parent
local AnimDriver = require(Client:WaitForChild("AnimDriver"))

local M = {}

local evSnapshot = Remotes.event("FightSnapshot")
local player = Players.LocalPlayer

-- локальная копия состояния своего бойца
local local_state: {
	moveId: string?,
	moveFrame: number,
	phase: FrameData.Phase,
	health: number,
	stamina: number,
	blocked: boolean,
	grounded: boolean,
	stunned: boolean,
	pendingMoveId: string?,
	predictedFrame: number,
} = {
	moveId = nil,
	moveFrame = 0,
	phase = "none" :: FrameData.Phase,
	health = 100,
	stamina = 100,
	blocked = false,
	grounded = false,
	stunned = false,
	pendingMoveId = nil,
	predictedFrame = 0,
}

M.state = local_state

function M.predict(moveId: string)
	local move = Moves.get(moveId)
	if not move then
		return
	end
	local_state.pendingMoveId = moveId
	local_state.moveId = moveId
	local_state.moveFrame = 1
	local_state.phase = "startup"
	AnimDriver.play(moveId)
end

local function reconcile(serverState)
	local_state.health = serverState.health or local_state.health
	local_state.stamina = serverState.stamina or local_state.stamina
	local_state.blocked = serverState.blocked == true
	local_state.grounded = serverState.grounded == true
	local_state.stunned = serverState.stunned == true

	local serverMove = serverState.moveId
	if serverMove ~= local_state.moveId then
		-- расхождение: сервер говорит другое - принимаем сервер
		if serverMove then
			local_state.moveId = serverMove
			AnimDriver.play(serverMove)
		else
			local_state.moveId = nil
			AnimDriver.stop()
		end
		local_state.moveFrame = serverState.moveFrame or 1
	end
	local_state.pendingMoveId = nil
end

function M.start()
	evSnapshot.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" or typeof(payload.fighters) ~= "table" then
			return
		end
		local myId = tostring(player.UserId)
		for _, snap in ipairs(payload.fighters) do
			if snap.id == myId or snap.id == player.Name then
				reconcile(snap)
			end
		end
	end)

	-- локальное продвижение кадров между снапшотами (визуальная непрерывность)
	RunService.RenderStepped:Connect(function(dt)
		if not local_state.moveId then
			return
		end
		local move = Moves.get(local_state.moveId)
		if not move then
			return
		end
		local_state.predictedFrame += dt * FrameData.FPS
		local frame = math.floor(local_state.predictedFrame)
		local_state.moveFrame = frame
		local_state.phase = FrameData.phaseAt(move, frame)
		if frame > FrameData.totalFrames(move) then
			local_state.moveId = nil
			local_state.predictedFrame = 0
			AnimDriver.stop()
		end
	end)
end

return M
