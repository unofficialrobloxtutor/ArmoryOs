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

		-- TODO: look up the baked Config for weaponId (Utilities/Types/Weapons/FireArm)
		-- and hand it back once the config registry exists.
		res:Send({WeaponId = weaponId, Config = nil})
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

		-- TODO: hand off to FireArm_Class to construct/attach the tool instance.
		server:Fire("WeaponEquipped", {Player = player, WeaponId = weaponId})
		res:Send({WeaponId = weaponId, Equipped = true})
	end)

	-- POST firearm/:WeaponId=string/unequip
	app:Post("firearm/:WeaponId=string/unequip", function(req: Request, res: Response)
		local weaponId = req.params.WeaponId :: string
		local player    = req.player

		-- TODO: hand off to FireArm_Class to detach/cleanup the tool instance.
		if player then
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

		-- TODO: validate ammo state, start reload timer, replenish In/Reserve.
		if player then
			server:UpdateWeaponState(player, weaponId, {Reloading = true})
			server:Fire("WeaponReloaded", {Player = player, WeaponId = weaponId})
		end
		res:Send({WeaponId = weaponId, Reloading = true})
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

		-- TODO: verify weaponId's Config.Fire.Fire_Modes actually includes data.Mode.
		if player then
			server:Fire("WeaponStateChanged", {Player = player, WeaponId = weaponId, Data = {FireMode = data.Mode}})
		end
		res:Send({WeaponId = weaponId, Mode = data.Mode})
	end)

	----------------------------------------------------------------
	-- AMMO
	----------------------------------------------------------------
	-- GET firearm/:WeaponId=string/ammo
	app:Get("firearm/:WeaponId=string/ammo", function(req: Request, res: Response)
		local weaponId = req.params.WeaponId :: string

		-- TODO: return live {In, Reserve, Max} from the player's weapon state.
		res:Send({WeaponId = weaponId, In = 0, Reserve = 0, Max = 0})
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

		-- TODO: distance/line-of-sight re-validation, Damage_Library application,
		-- Gore_Library feedback, Gun_Visual_Library.HandleBulletImpact on clients.
		if player then
			server:Fire("WeaponHit", {
				Player = player,
				WeaponId = weaponId,
				Data = {HitPart = data.HitPart, Position = data.Position, Normal = data.Normal},
			})
		end
		res:Send({WeaponId = weaponId, Registered = true})
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
