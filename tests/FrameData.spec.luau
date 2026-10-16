--!strict
-- Тесты фреймдаты. Гоняются в Studio через TestEZ (см. README, раздел "Тесты").
-- Смысл: любые правки чисел в data/moves.json не должны ломать инварианты.

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Shared = ReplicatedStorage:WaitForChild("Shared")
	local FrameData = require(Shared:WaitForChild("FrameData"))
	local StaminaSystem = require(Shared:WaitForChild("StaminaSystem"))
	local FightMath = require(Shared:WaitForChild("FightMath"))
	local Moves = require(Shared:WaitForChild("Moves"))

	describe("FrameData фазы", function()
		local jab = Moves.get("jab")
		it("джеб существует в базе", function()
			expect(jab).to.be.ok()
		end)

		it("фаза startup до активного кадра", function()
			expect(FrameData.phaseAt(jab, 1)).to.equal("startup")
			expect(FrameData.phaseAt(jab, jab.timing.startup)).to.equal("startup")
		end)

		it("хитбокс живёт только в активных кадрах", function()
			expect(FrameData.hitboxSpecAt(jab, jab.timing.startup)).to.equal(nil)
			expect(FrameData.hitboxSpecAt(jab, jab.timing.startup + 1)).to.be.ok()
			expect(FrameData.hitboxSpecAt(jab, FrameData.totalFrames(jab) + 5)).to.equal(nil)
		end)

		it("окно отмены внутри мува", function()
			local s, e = FrameData.cancelWindow(jab)
			expect(s).to.be.a("number")
			expect(e).to.be.a("number")
			expect(FrameData.canCancel(jab, s)).to.equal(true)
			expect(FrameData.canCancel(jab, FrameData.totalFrames(jab) + 10)).to.equal(false)
		end)
	end)

	describe("Разрешение попаданий", function()
		local cross = Moves.get("cross")

		it("блок режет урон по здоровью, но жжёт стамину", function()
			local clean = FrameData.resolveHit(cross, 70, {
				blocked = false, stamina = 100, maxStamina = 100, stunned = false, grounded = false,
			})
			local blocked = FrameData.resolveHit(cross, 70, {
				blocked = true, blockHeldFrames = 5, stamina = 100, maxStamina = 100, stunned = false, grounded = false,
			})
			expect(blocked.healthDamage < clean.healthDamage).to.equal(true)
			expect(blocked.staminaDamage > clean.staminaDamage).to.equal(true)
		end)

		it("уставший боец падает чаще", function()
			local fresh = FrameData.resolveHit(Moves.get("kick_head"), 70, {
				blocked = false, stamina = 100, maxStamina = 100, stunned = false, grounded = false,
			})
			local tired = FrameData.resolveHit(Moves.get("kick_head"), 70, {
				blocked = false, stamina = 10, maxStamina = 100, stunned = false, grounded = false,
			})
			expect(tired.knockdown or not fresh.knockdown).to.equal(true)
		end)
	end)

	describe("Стамина", function()
		it("нельзя потратить больше, чем есть", function()
			local model = StaminaSystem.new()
			model.value = 3
			expect(model:spend(10)).to.equal(false)
			expect(model:spend(2)).to.equal(true)
		end)

		it("усталость замедляет", function()
			local model = StaminaSystem.new()
			model.value = 0
			model.exhausted = true
			expect(StaminaSystem.speedMultiplier(model) < 0.7).to.equal(true)
		end)
	end)

	describe("FightMath", function()
		it("contestChance в пределах 5..95%", function()
			local c = FightMath.contestChance(90, 10, 1, 1)
			expect(c >= 0.05 and c <= 0.95).to.equal(true)
		end)

		it("remap клампит", function()
			expect(FightMath.remap(1000, 0, 100, 0, 1)).to.equal(1)
			expect(FightMath.remap(-50, 0, 100, 0, 1)).to.equal(0)
		end)
	end)

	describe("Целостность данных moves.json", function()
		it("у всех страйков есть тайминги и хитбокс", function()
			for _, move in ipairs(Moves.all()) do
				expect(move.timing.startup >= 0).to.equal(true)
				expect(move.timing.active >= 0).to.equal(true)
				expect(move.timing.recovery >= 0).to.equal(true)
				if move.category == "strike" or move.category == "ground_strike" then
					expect(move.hitbox).to.be.ok()
					expect(move.hitbox.reach > 0).to.equal(true)
				end
			end
		end)

		it("grapple-мувы ссылаются на существующие позиции", function()
			local valid = {
				standing = true, clinch = true, guard_top = true, guard_bottom = true,
				side_top = true, side_bottom = true, mount_top = true, mount_bottom = true,
				back_top = true, back_bottom = true,
			}
			for _, move in ipairs(Moves.byCategory("grapple")) do
				if move.grapple and move.grapple.to then
					expect(valid[move.grapple.to]).to.equal(true)
				end
			end
		end)
	end)
end
