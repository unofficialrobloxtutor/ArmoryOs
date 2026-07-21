--!strict
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       FireArmRoutes
--  ◄► Version:     1.0
--  ◄► Date:        17/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: Data/Routes — RoExpress route table for firearm-type
--                  weapons. Typed named params, a constrained slot param,
--                  and a glob diagnostics route, following:
--                    roexpress.dev/docs/pages/router.html
--                    roexpress.dev/docs/pages/router-params.html
--                    roexpress.dev/docs/pages/router-wildcards.html
--                    roexpress.dev/docs/pages/router-constraints.html
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--► Services     ◄--
--► Requires     ◄--
local RoExpress  = require(script.Parent.Parent.Parent.Utilities.Libraries.RoExpress_Library)
local Router     = require(script.Parent.Parent.Parent.Utilities.Libraries.RoExpress_Library.Router)
local Validator  = require(script.Parent.Parent.Parent.Utilities.Libraries.Validator_Library)
local Configs    = require(script.Parent.Parent.Configs)
local Damage      = require(script.Parent.Parent.Parent.Utilities.Libraries.Damage_Library)
local RayCast     = require(script.Parent.Parent.Parent.Utilities.Libraries.RayCast_Library)
local Penetration = require(script.Parent.Parent.Parent.Utilities.Libraries.Penetration_Library)
local Explosion   = require(script.Parent.Parent.Parent.Utilities.Libraries.Explosion_Library)
local ServerCore = require(script.Parent.Parent.Parent.Utilities.Types.Server)
--► Types        ◄--
type App      = RoExpress.App
type Request  = RoExpress.Request
type Response = RoExpress.Response
type Server   = ServerCore.Type
type RouteBuilder<T> = Router.RouteBuilder<T>
--► Tables       ◄--
local Module = {}
--► Constants    ◄--
local VALID_ATTACHMENT_SLOTS = {"Sight", "Barrel", "Underbarrel", "Magazine", "Grip", "Stock"}
local VALID_FIRE_MODES       = {"Semi", "Auto", "Burst"}

-- Hit-zone classification for server-side damage — mirrors the client
-- preview tables in FireArm_Class (R6 + R15 part names).
local HEAD_PART_NAMES = {Head = true}
local LIMB_PART_NAMES = {["Left Arm"] = true, ["Right Arm"] = true, ["Left Leg"] = true, ["Right Leg"] = true,
	LeftUpperArm = true, RightUpperArm = true, LeftLowerArm = true, RightLowerArm = true,
	LeftUpperLeg = true, RightUpperLeg = true, LeftLowerLeg = true, RightLowerLeg = true,
	LeftHand = true, RightHand = true, LeftFoot = true, RightFoot = true}

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	ROUTE-BUILDERS (type-safe URL construction — see router-params.html)
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

Module.Routes = {
	Config     = RoExpress.Router.Route("firearm/:WeaponId=string/config") :: RouteBuilder<{WeaponId: string}>,
	Equip      = RoExpress.Router.Route("firearm/:WeaponId=string/equip") :: RouteBuilder<{WeaponId: string}>,
	Unequip    = RoExpress.Router.Route("firearm/:WeaponId=string/unequip") :: RouteBuilder<{WeaponId: string}>,
	-- Fire is not an App route — it goes over Data/Streams/FireArmStream.
	Reload     = RoExpress.Router.Route("firearm/:WeaponId=string/reload") :: RouteBuilder<{WeaponId: string}>,
	Aim        = RoExpress.Router.Route("firearm/:WeaponId=string/aim") :: RouteBuilder<{WeaponId: string}>,
	FireMode   = RoExpress.Router.Route("firearm/:WeaponId=string/firemode") :: RouteBuilder<{WeaponId: string}>,
	Ammo       = RoExpress.Router.Route("firearm/:WeaponId=string/ammo") :: RouteBuilder<{WeaponId: string}>,
	Hit        = RoExpress.Router.Route("firearm/:WeaponId=string/hit") :: RouteBuilder<{WeaponId: string}>,
	Attachment = RoExpress.Router.Route("firearm/:WeaponId(%a[%w_]*)/attachment/:Slot=string") :: RouteBuilder<{WeaponId: string, Slot: string}>,
}

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	REGISTRATION
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Mounts every firearm route onto a given RoExpress App (or Port).
-- `server` is the Utilities/Core/Server instance — used here to fire
-- weapon lifecycle events (Server:Fire) and push authoritative state to
-- clients (Server:UpdateWeaponState). Called once from Utilities/Core/Network
-- during bootstrap:
--   FireArmRoutes.Register(RoExpress("App"), server)
Module.Register = function(app: App, server: Server)

	----------------------------------------------------------------
	-- CONFIG — read-only lookup of a weapon's baked config
	----------------------------------------------------------------
	-- GET firearm/:WeaponId=string/config
	app:Get("firearm/:WeaponId=string/config", function(req: Request, res: Response)
		local weaponId = req.params.WeaponId :: string

		if not Validator.IsNonEmptyString(weaponId) then
			res:Status(400):Error("WeaponId must be a non-empty string")
			return
		end

		local config = Configs.Get(weaponId)
		if not config or config.Category ~= "FireArm" then
			res:Status(404):Error("Unknown firearm '" .. weaponId .. "'")
			return
		end
		res:Send({WeaponId = weaponId, Config = config})
	end)

	----------------------------------------------------------------
	-- EQUIP / UNEQUIP
	----------------------------------------------------------------
	-- POST firearm/:WeaponId=string/equip
	app:Post("firearm/:WeaponId=string/equip", function(req: Request, res: Response)
		local weaponId = req.params.WeaponId :: string
		local player    = req.player

		if not player then
			res:Status(401):Error("Equip requires an authenticated player")
			return
		end

		local config = Configs.Get(weaponId)
		if not config or config.Category ~= "FireArm" then
			res:Status(404):Error("Unknown firearm '" .. weaponId .. "'")
			return
		end

		local session = server:EquipWeapon(player, config)
		server:Fire("WeaponEquipped", {Player = player, WeaponId = weaponId})
		res:Send({WeaponId = weaponId, Equipped = true, Ammo = session.Ammo, FireMode = session.FireMode})
	end)

	-- POST firearm/:WeaponId=string/unequip
	app:Post("firearm/:WeaponId=string/unequip", function(req: Request, res: Response)
		local weaponId = req.params.WeaponId :: string
		local player    = req.player

		if player then
			server:UnequipWeapon(player)
			server:Fire("WeaponUnequipped", {Player = player, WeaponId = weaponId})
		end
		res:Send({WeaponId = weaponId, Equipped = false})
	end)

	----------------------------------------------------------------
	-- FIRE — moved off the App/Router entirely
	----------------------------------------------------------------
	-- Firing is high-frequency and doesn't need a request/response round
	-- trip, so it goes over the binary RoExpress.Stream channel instead:
	--   Data/Streams/FireArmStream.luau
	--     server: FireArmStream.Register(server)  — subscribes, fires
	--             "WeaponFired" on the event bus, replicates to other clients
	--     client: FireArmStream.Fire(weaponId, origin, direction)

	----------------------------------------------------------------
	-- RELOAD
	----------------------------------------------------------------
	-- POST firearm/:WeaponId=string/reload
	app:Post("firearm/:WeaponId=string/reload", function(req: Request, res: Response)
		local weaponId = req.params.WeaponId :: string
		local player    = req.player

		if not player then
			res:Status(401):Error("Reload requires an authenticated player")
			return
		end

		local session = server:GetSession(player)
		if not session or session.WeaponId ~= weaponId then
			res:Status(409):Error("'" .. weaponId .. "' is not the equipped weapon")
			return
		end
		local ammo = session.Ammo
		if not ammo then
			res:Status(409):Error("'" .. weaponId .. "' has no ammo state")
			return
		end
		if session.Reloading then
			res:Status(409):Error("Already reloading")
			return
		end

		local settings  = session.Config.WeaponSettings or {}
		local dataFlags = settings.Data or {}
		if ammo.In >= ammo.Max then
			res:Status(409):Error("Magazine already full")
			return
		end
		if ammo.Reserve <= 0 and not dataFlags.Infinite_Reserve then
			res:Status(409):Error("No reserve ammo")
			return
		end

		local reloadCfg  = settings.Reload or {}
		local reloadTime = if ammo.In <= 0
			then (reloadCfg.Empty_Reload_Time or reloadCfg.Reload_Time or 2)
			else (reloadCfg.Tactical_Reload_Time or reloadCfg.Reload_Time or 2)

		session.Reloading = true
		server:UpdateWeaponState(player, weaponId, {Reloading = true})

		task.delay(reloadTime, function()
			-- Session may have been swapped/cleared (unequip, leave) mid-reload.
			local current = server:GetSession(player)
			if current ~= session or not session.Reloading then
				return
			end
			session.Reloading = false

			local ammoNow = session.Ammo :: {In: number, Reserve: number, Max: number}
			-- +1 chambered round on a tactical reload if the config allows it.
			local target = ammoNow.Max
			if reloadCfg.Chamber_Round and ammoNow.In > 0 then
				target += 1
			end
			local needed = math.max(0, target - ammoNow.In)
			local taken  = if dataFlags.Infinite_Reserve then needed else math.min(needed, ammoNow.Reserve)

			ammoNow.In += taken
			if not dataFlags.Infinite_Reserve then
				ammoNow.Reserve -= taken
			end

			server:UpdateWeaponState(player, weaponId, {Reloading = false, Ammo = {In = ammoNow.In, Reserve = ammoNow.Reserve, Max = ammoNow.Max}})
			server:Fire("WeaponReloaded", {Player = player, WeaponId = weaponId, Data = {Ammo = ammoNow}})
		end)

		res:Send({WeaponId = weaponId, Reloading = true, Duration = reloadTime})
	end)

	----------------------------------------------------------------
	-- AIM
	----------------------------------------------------------------
	-- POST firearm/:WeaponId=string/aim
	-- Expects req.data = {Aiming: boolean}
	app:Post("firearm/:WeaponId=string/aim", function(req: Request, res: Response)
		local weaponId = req.params.WeaponId :: string
		local data      = req.data

		if not Validator.IsTable(data) or not Validator.IsBoolean(data.Aiming) then
			res:Status(400):Error("Aim request missing boolean 'Aiming'")
			return
		end

		res:Send({WeaponId = weaponId, Aiming = data.Aiming})
	end)

	----------------------------------------------------------------
	-- FIRE MODE
	----------------------------------------------------------------
	-- POST firearm/:WeaponId=string/firemode
	-- Expects req.data = {Mode: "Semi" | "Auto" | "Burst"}
	app:Post("firearm/:WeaponId=string/firemode", function(req: Request, res: Response)
		local weaponId = req.params.WeaponId :: string
		local data      = req.data
		local player    = req.player

		if not Validator.IsTable(data) or not Validator.IsOneOf(data.Mode, VALID_FIRE_MODES) then
			res:Status(400):Error("firemode requires Mode to be one of: " .. table.concat(VALID_FIRE_MODES, ", "))
			return
		end

		if not player then
			res:Status(401):Error("firemode requires an authenticated player")
			return
		end
		local session = server:GetSession(player)
		if not session or session.WeaponId ~= weaponId then
			res:Status(409):Error("'" .. weaponId .. "' is not the equipped weapon")
			return
		end

		local fireCfg = (session.Config.WeaponSettings or {}).Fire or {}
		if not Validator.IsOneOf(data.Mode, fireCfg.Fire_Modes or {}) then
			res:Status(400):Error("'" .. weaponId .. "' does not support fire mode '" .. tostring(data.Mode) .. "'")
			return
		end

		session.FireMode = data.Mode
		server:Fire("WeaponStateChanged", {Player = player, WeaponId = weaponId, Data = {FireMode = data.Mode}})
		res:Send({WeaponId = weaponId, Mode = data.Mode})
	end)

	----------------------------------------------------------------
	-- AMMO
	----------------------------------------------------------------
	-- GET firearm/:WeaponId=string/ammo
	app:Get("firearm/:WeaponId=string/ammo", function(req: Request, res: Response)
		local weaponId = req.params.WeaponId :: string

		local player  = req.player
		local session = player and server:GetSession(player)
		if not session or session.WeaponId ~= weaponId or not session.Ammo then
			res:Status(404):Error("No live ammo state for '" .. weaponId .. "'")
			return
		end
		local ammo = session.Ammo :: {In: number, Reserve: number, Max: number}
		res:Send({WeaponId = weaponId, In = ammo.In, Reserve = ammo.Reserve, Max = ammo.Max})
	end)

	----------------------------------------------------------------
	-- HIT REGISTRATION
	----------------------------------------------------------------
	-- POST firearm/:WeaponId=string/hit
	-- Expects req.data = {HitPart: Instance, Position: Vector3, Normal: Vector3}
	app:Post("firearm/:WeaponId=string/hit", function(req: Request, res: Response)
		local weaponId = req.params.WeaponId :: string
		local data      = req.data
		local player    = req.player

		if not Validator.IsTable(data) then
			res:Status(400):Error("Hit request body must be a table")
			return
		end
		if not Validator.IsInstance(data.HitPart) then
			res:Status(400):Error("Hit request missing Instance 'HitPart'")
			return
		end
		if not Validator.IsVector3(data.Position) or not Validator.IsVector3(data.Normal) then
			res:Status(400):Error("Hit request missing Vector3 'Position'/'Normal'")
			return
		end

		if player then
			local session = server:GetSession(player)
			if not session or session.WeaponId ~= weaponId then
				res:Status(409):Error("'" .. weaponId .. "' is not the equipped weapon")
				return
			end

			-- Distance sanity check — the claimed hit must be within the
			-- weapon's max range of the shooter's character.
			local physics = (session.Config.WeaponSettings or {}).Physics or {}
			local maxDistance = physics.Max_Distance or 1000
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and (data.Position - root.Position).Magnitude > maxDistance + 50 then
				res:Status(400):Error("Hit position exceeds weapon range")
				return
			end

			server:Fire("WeaponHit", {
				Player = player,
				WeaponId = weaponId,
				Data = {HitPart = data.HitPart, Position = data.Position, Normal = data.Normal},
			})

			-- Server-authoritative damage: re-run the SAME penetration cast
			-- the client used (Penetration_Library) from the shooter toward
			-- the claimed hit. This verifies line of fire — walls without a
			-- Material_Penetration entry, over-thick walls, and ricochet
			-- angles all block the shot server-side — and yields the
			-- authoritative penetration damage multiplier. The client never
			-- sends a damage value.
			local hitPart = data.HitPart :: BasePart
			local hitCharacter = hitPart:FindFirstAncestorOfClass("Model")
			local humanoid = hitCharacter and hitCharacter:FindFirstChildOfClass("Humanoid")
			local dealt = 0

			if humanoid and humanoid.Health > 0 and hitCharacter ~= player.Character and root then
				local settings  = session.Config.WeaponSettings or {}
				local damageCfg = settings.Damage or {}
				local penCfg    = settings.Penetration or {}

				-- The client reports its true shot origin (the gun's muzzle —
				-- see FireArm_Class._dischargeOnce). Accept it only if it's
				-- physically near the shooter's character; otherwise fall
				-- back to the head so a spoofed origin can't teleport shots.
				local head = character and character:FindFirstChild("Head") :: BasePart?
				local anchor = head and head.Position or root.Position
				local shotOrigin = anchor
				if Validator.IsVector3(data.Origin) and (data.Origin - anchor).Magnitude <= 8 then
					shotOrigin = data.Origin
				end

				local verified = Penetration.VerifyHit(
					shotOrigin, data.Position, hitPart,
					penCfg, maxDistance,
					RayCast.ParamsExcludeCharacter(character :: Model)
				)
				if not verified then
					res:Status(400):Error("Hit could not be verified from the shooter's position")
					return
				end

				-- Zone-classify by the part the SERVER's cast resolved, not
				-- the client's claim (they can differ across a limb boundary).
				local serverHitPart = verified.Result.Instance
				local distance = (verified.Result.Position - shotOrigin).Magnitude

				local dmg = damageCfg.Base_Damage or 0
				dmg = Damage.LinearFalloff(dmg, distance, penCfg.Damage_Fall_Off_Start or 0, penCfg.Damage_Fall_Off_End or math.huge, damageCfg.Min_Damage or 0)
				dmg *= verified.DamageMultiplier
				if HEAD_PART_NAMES[serverHitPart.Name] then
					dmg = Damage.HeadshotDamage(dmg, true, damageCfg.Headshot_Multiplier)
				elseif LIMB_PART_NAMES[serverHitPart.Name] then
					dmg = Damage.LimbDamage(dmg, true, damageCfg.Limb_Multiplier)
				end
				dmg = Damage.ClampDamage(dmg, damageCfg.Min_Damage or 0, damageCfg.Max_Damage or dmg)

				humanoid:TakeDamage(dmg)
				dealt = dmg

				server:Fire("WeaponDamaged", {
					Player = player,
					WeaponId = weaponId,
					Data = {Target = hitCharacter, HitPart = serverHitPart, Damage = dmg, Penetrated = verified.DamageMultiplier < 1},
				})
			end

			res:Send({WeaponId = weaponId, Registered = true, Damage = dealt})
			return
		end
		res:Send({WeaponId = weaponId, Registered = true})
	end)

	----------------------------------------------------------------
	-- EXPLOSIONS — Explosive / Launcher blast resolution
	----------------------------------------------------------------
	-- POST firearm/:WeaponId=string/explode
	-- Expects req.data = {Position: Vector3}
	-- The client reports WHERE its rocket/round detonated; the server
	-- checks the weapon actually explodes and the position is in range,
	-- then deals radial damage itself (falloff + line-of-sight) — the
	-- client never sends damage numbers or target lists.
	app:Post("firearm/:WeaponId=string/explode", function(req: Request, res: Response)
		local weaponId = req.params.WeaponId :: string
		local data      = req.data
		local player    = req.player

		if not player then
			res:Status(401):Error("explode requires an authenticated player")
			return
		end
		if not Validator.IsTable(data) or not Validator.IsVector3(data.Position) then
			res:Status(400):Error("explode requires Vector3 'Position'")
			return
		end

		local session = server:GetSession(player)
		if not session or session.WeaponId ~= weaponId then
			res:Status(409):Error("'" .. weaponId .. "' is not the equipped weapon")
			return
		end

		local settings = session.Config.WeaponSettings or {}
		local weaponType = settings.Type
		local behavior = settings.Behavior or {}
		local radius: number?
		local damage: number?
		local falloff: boolean?

		if weaponType == "Launcher" then
			radius, damage, falloff = behavior.Blast_Radius, behavior.Blast_Damage, true
		elseif weaponType == "Explosive" then
			radius, damage, falloff = behavior.Explosion_Radius, behavior.Explosion_Damage, behavior.Explosion_Falloff
		else
			res:Status(400):Error("'" .. weaponId .. "' is not an explosive weapon")
			return
		end
		if not radius or not damage then
			res:Status(500):Error("'" .. weaponId .. "' is missing blast radius/damage config")
			return
		end

		-- Range sanity: the detonation must be within the weapon's flight
		-- envelope of the shooter (projectiles can't teleport).
		local physics = settings.Physics or {}
		local maxDistance = physics.Max_Distance or 1000
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and (data.Position - root.Position).Magnitude > maxDistance + 50 then
			res:Status(400):Error("Explosion position exceeds weapon range")
			return
		end

		local damaged = Explosion.Apply(data.Position, radius, damage, falloff)

		server:Fire("WeaponHit", {
			Player = player,
			WeaponId = weaponId,
			Data = {Position = data.Position, Radius = radius, Targets = #damaged},
		})
		for _, entry in ipairs(damaged) do
			server:Fire("WeaponDamaged", {
				Player = player,
				WeaponId = weaponId,
				Data = {Target = entry.Character, Damage = entry.Damage, Explosive = true},
			})
		end

		res:Send({WeaponId = weaponId, Exploded = true, Targets = #damaged})
	end)

	----------------------------------------------------------------
	-- ATTACHMENTS — constrained param example (see router-constraints.html)
	----------------------------------------------------------------
	-- POST firearm/:WeaponId(%a[%w_]*)/attachment/:Slot=string
	-- WeaponId here is constrained to start with a letter, then word chars/underscores.
	-- Expects req.data = {AttachmentId: string}
	app:Post("firearm/:WeaponId(%a[%w_]*)/attachment/:Slot=string", function(req: Request, res: Response)
		local weaponId = req.params.WeaponId :: string
		local slot      = req.params.Slot :: string
		local data       = req.data
		local player     = req.player

		if not Validator.IsOneOf(slot, VALID_ATTACHMENT_SLOTS) then
			res:Status(400):Error("Unknown attachment slot '" .. slot .. "'")
			return
		end
		if not Validator.IsTable(data) or not Validator.IsNonEmptyString(data.AttachmentId) then
			res:Status(400):Error("Attachment request missing string 'AttachmentId'")
			return
		end

		-- TODO: validate the attachment is compatible with this slot/weapon, then attach.
		if player then
			server:Fire("WeaponAttachmentChanged", {
				Player = player,
				WeaponId = weaponId,
				Data = {Slot = slot, AttachmentId = data.AttachmentId, Removed = false},
			})
		end
		res:Send({WeaponId = weaponId, Slot = slot, AttachmentId = data.AttachmentId})
	end)

	-- DELETE firearm/:WeaponId(%a[%w_]*)/attachment/:Slot=string
	app:Delete("firearm/:WeaponId(%a[%w_]*)/attachment/:Slot=string", function(req: Request, res: Response)
		local weaponId = req.params.WeaponId :: string
		local slot      = req.params.Slot :: string
		local player     = req.player

		if not Validator.IsOneOf(slot, VALID_ATTACHMENT_SLOTS) then
			res:Status(400):Error("Unknown attachment slot '" .. slot .. "'")
			return
		end

		-- TODO: detach whatever attachment currently occupies this slot.
		if player then
			server:Fire("WeaponAttachmentChanged", {
				Player = player,
				WeaponId = weaponId,
				Data = {Slot = slot, Removed = true},
			})
		end
		res:Send({WeaponId = weaponId, Slot = slot, Removed = true})
	end)

	----------------------------------------------------------------
	-- DIAGNOSTICS — glob example (see router-wildcards.html)
	----------------------------------------------------------------
	-- GET firearm/debug/**
	-- Matches firearm/debug, firearm/debug/a, firearm/debug/a/b/c, ...
	app:Get("firearm/debug/**", function(req: Request, res: Response)
		local trail = req.captures[1] :: {string}
		res:Send({Path = table.concat(trail, "/")})
	end)
end

return Module
