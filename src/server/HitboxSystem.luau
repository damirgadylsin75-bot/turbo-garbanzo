--!strict
-- HitboxSystem: хитбоксы/хуртбоксы, привязанные к костям R15.
-- ВАЖНО: в файтинге физика тела НЕ считает урон. Урон считает пересечение
-- "активного хитбокса" (кулак/стопа в активных кадрах) с "хуртбоксом"
-- (капсула корпуса/головы соперника). Roblox-физика нужна только для
-- нокдаунов и инерции тела.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local FrameData = require(Shared:WaitForChild("FrameData"))
local Moves = require(Shared:WaitForChild("Moves"))

local M = {}

-- Части тела, которые считаются "можно бить": хуртбоксы Head/UpperTorso/LowerTorso.
-- Размеры и уровни - в data/moves.json, секция "hurtboxes".
local function hurtboxSpecs(): { { name: string, bone: string, size: Vector3, level: string } }
	return Moves.hurtboxes() :: any
end

M.HITBOX_FOLDER = "FightHitboxes"
M.HURTBOX_FOLDER = "FightHurtboxes"

local function ensureFolder(parent: Instance, name: string): Folder
	local found = parent:FindFirstChild(name)
	if found and found:IsA("Folder") then
		return found
	end
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- Создаёт хуртбоксы бойца один раз (при спавне)
function M.buildHurtboxes(character: Model)
	local folder = ensureFolder(character, M.HURTBOX_FOLDER)
	folder:ClearAllChildren()

	local parts = {}
	for _, spec in ipairs(hurtboxSpecs()) do
		local bone = character:FindFirstChild(spec.bone, true)
		if not bone then
			continue
		end
		local part = Instance.new("Part")
		part.Name = spec.name
		part.Size = spec.size
		part.Transparency = 1
		part.CanCollide = false
		part.CanQuery = true
		part.CanTouch = false
		part.Massless = true
		part.Anchored = true -- важно: не ломает симуляцию тела
		part.CFrame = (bone :: BasePart).CFrame
		part:SetAttribute("level", spec.level)
		part.Parent = folder

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = part
		weld.Part1 = bone :: BasePart
		weld.Parent = part

		part.Anchored = false
		table.insert(parts, part)
	end
	return parts
end

-- Обновляет активный хитбокс бойца под текущий кадр мува
function M.syncHitbox(character: Model, move: FrameData.MoveDef?, moveFrame: number): BasePart?
	local folder = ensureFolder(character, M.HITBOX_FOLDER)
	local spec: FrameData.HitboxSpec? = nil
	if move then
		spec = FrameData.hitboxSpecAt(move, moveFrame)
	end

	if not spec then
		folder:ClearAllChildren()
		return nil
	end

	local bone = character:FindFirstChild(spec.bone, true) :: BasePart?
	if not bone then
		return nil
	end

	local existing = folder:FindFirstChild("Active") :: BasePart?
	if not existing then
		existing = Instance.new("Part")
		existing.Name = "Active"
		existing.Transparency = 1
		existing.CanCollide = false
		existing.CanQuery = true
		existing.CanTouch = false
		existing.Massless = true
		existing.Parent = folder
	end
	existing.Size = spec.size
	local hitCFrame = bone.CFrame * CFrame.new(spec.offset)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") and move and spec.reach then
		-- Server-side extension keeps hits working even when no animation asset is loaded.
		-- Preserve bone-side offset, but place the active box at its JSON reach and strike level.
		local forward = root.CFrame.LookVector
		local right = root.CFrame.RightVector
		local lateral = (hitCFrame.Position - root.Position):Dot(right)
		local height = 0.55
		if move.hitLevel == "high" then
			height = 2.1
		elseif move.hitLevel == "low" then
			height = -0.65
		end
		local center = root.Position + forward * spec.reach + right * lateral + Vector3.new(0, height, 0)
		hitCFrame = CFrame.new(center) * hitCFrame.Rotation
	end
	existing.CFrame = hitCFrame
	existing:SetAttribute("moveId", move and move.id or "")
	existing:SetAttribute("level", move and move.hitLevel or "mid")
	return existing
end

-- Пересечение хитбокса атакующего с хуртбоксами защищающегося.
-- Возвращает уровень попадания ("high"/"mid"/"low") или nil.
function M.queryHit(hitbox: BasePart, targetCharacter: Model): string?
	local hurtFolder = targetCharacter:FindFirstChild(M.HURTBOX_FOLDER)
	if not hurtFolder then
		return nil
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	overlapParams.FilterDescendantsInstances = { hurtFolder }
	overlapParams.MaxParts = 8

	local hits = workspace:GetPartBoundsInBox(hitbox.CFrame, hitbox.Size, overlapParams)
	if #hits == 0 then
		return nil
	end
	return hits[1]:GetAttribute("level") or "mid"
end

-- Визуализация для дебага в Studio (включается атрибутом)
function M.setDebugVisible(character: Model, visible: boolean)
	for _, folderName in { M.HITBOX_FOLDER, M.HURTBOX_FOLDER } do
		local folder = character:FindFirstChild(folderName)
		if folder then
			for _, part in ipairs(folder:GetChildren()) do
				if part:IsA("BasePart") then
					part.Transparency = visible and 0.5 or 1
					part.Color = folderName == M.HITBOX_FOLDER and Color3.fromRGB(255, 80, 80)
						or Color3.fromRGB(80, 180, 255)
				end
			end
		end
	end
end

return M
