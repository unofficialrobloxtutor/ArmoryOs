--!strict
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       MeleeRoutes
--  ◄► Version:     1.0
--  ◄► Date:        17/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: Data/Routes — RoExpress route table for melee-type
--                  weapons. Typed named params + a constrained WeaponId,
--                  following:
--                    roexpress.dev/docs/pages/router.html
--                    roexpress.dev/docs/pages/router-params.html
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

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	ROUTE-BUILDERS
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

Module.Routes = {
	Config  = RoExpress.Router.Route("melee/:WeaponId=string/config") :: RouteBuilder<{WeaponId: string}>,
	Equip   = RoExpress.Router.Route("melee/:WeaponId=string/equip") :: RouteBuilder<{WeaponId: string}>,
	Unequip = RoExpress.Router.Route("melee/:WeaponId=string/unequip") :: RouteBuilder<{WeaponId: string}>,
	-- Attack is not an App route — it's fired/checked every swing, so it
	-- goes over Data/Streams/MeleeStream instead.
	Block   = RoExpress.Router.Route("melee/:WeaponId=string/block") :: RouteBuilder<{WeaponId: string}>,
	Parry   = RoExpress.Router.Route("melee/:WeaponId=string/parry") :: RouteBuilder<{WeaponId: string}>,
	Hit     = RoExpress.Router.Route("melee/:WeaponId=string/hit") :: RouteBuilder<{WeaponId: string}>,
	Throw   = RoExpress.Router.Route("melee/:WeaponId(%a[%w_]*)/throw") :: RouteBuilder<{WeaponId: string}>,
}

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	REGISTRATION
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Mounts every melee route onto a given RoExpress App (or Port).
-- `server` is the Utilities/Core/Server instance — used to fire weapon
-- lifecycle events and push authoritative state to clients. Called once
-- from Utilities/Core/Network during bootstrap:
--   MeleeRoutes.Register(RoExpress("App"), server)
Module.Register = function(app: App, server: Server)

	----------------------------------------------------------------
	-- CONFIG
	----------------------------------------------------------------
	-- GET melee/:WeaponId=string/config
	app:Get("melee/:WeaponId=string/config", function(req: Request, res: Response)
		local weaponId = req.params.WeaponId :: string

		if not Validator.IsNonEmptyString(weaponId) then
			res:Status(400):Error("WeaponId must be a non-empty string")
			return
		end

		-- TODO: look up the baked Config for weaponId (Utilities/Types/Weapons/Melee).
		res:Send({WeaponId = weaponId, Config = nil})
	end)

	----------------------------------------------------------------
	-- EQUIP / UNEQUIP
	----------------------------------------------------------------
	-- POST melee/:WeaponId=string/equip
	app:Post("melee/:WeaponId=string/equip", function(req: Request, res: Response)
		local weaponId = req.params.WeaponId :: string
		local player    = req.player

		if not player then
			res:Status(401):Error("Equip requires an authenticated player")
			return
		end

		-- TODO: hand off to Melee_Class to construct/attach the tool instance.
		server:Fire("WeaponEquipped", {Player = player, WeaponId = weaponId})
		res:Send({WeaponId = weaponId, Equipped = true})
	end)

	-- POST melee/:WeaponId=string/unequip
	app:Post("melee/:WeaponId=string/unequip", function(req: Request, res: Response)
		local weaponId = req.params.WeaponId :: string
		local player    = req.player

		-- TODO: hand off to Melee_Class to detach/cleanup the tool instance.
		if player then
			server:Fire("WeaponUnequipped", {Player = player, WeaponId = weaponId})
		end
		res:Send({WeaponId = weaponId, Equipped = false})
	end)

	----------------------------------------------------------------
	-- ATTACK — moved off the App/Router entirely
	----------------------------------------------------------------
	-- Attacks are fired/checked every swing, so they go over the binary
	-- RoExpress.Stream channel instead:
	--   Data/Streams/MeleeStream.luau
	--     server: MeleeStream.Register(server)  — subscribes, validates,
	--             fires "WeaponStateChanged" on the event bus, replicates
	--             to other clients
	--     client: MeleeStream.Attack(weaponId, "Light" | "Heavy", combo)

	----------------------------------------------------------------
	-- BLOCK / PARRY
	----------------------------------------------------------------
	-- POST melee/:WeaponId=string/block
	-- Expects req.data = {Blocking: boolean}
	app:Post("melee/:WeaponId=string/block", function(req: Request, res: Response)
		local weaponId = req.params.WeaponId :: string
		local data      = req.data
		local player    = req.player

		if not Validator.IsTable(data) or not Validator.IsBoolean(data.Blocking) then
			res:Status(400):Error("block request missing boolean 'Blocking'")
			return
		end

		if player then
			server:Fire("WeaponStateChanged", {Player = player, WeaponId = weaponId, Data = {Blocking = data.Blocking}})
		end
		res:Send({WeaponId = weaponId, Blocking = data.Blocking})
	end)

	-- POST melee/:WeaponId=string/parry
	app:Post("melee/:WeaponId=string/parry", function(req: Request, res: Response)
		local weaponId = req.params.WeaponId :: string
		local player    = req.player

		-- TODO: validate parry timing window against the incoming attack's swing state.
		if player then
			server:Fire("WeaponStateChanged", {Player = player, WeaponId = weaponId, Data = {Parried = true}})
		end
		res:Send({WeaponId = weaponId, Parried = true})
	end)

	----------------------------------------------------------------
	-- HIT REGISTRATION
	----------------------------------------------------------------
	-- POST melee/:WeaponId=string/hit
	-- Expects req.data = {HitPart: Instance, Position: Vector3}
	app:Post("melee/:WeaponId=string/hit", function(req: Request, res: Response)
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
		if not Validator.IsVector3(data.Position) then
			res:Status(400):Error("Hit request missing Vector3 'Position'")
			return
		end

		-- TODO: attack-range/angle re-validation, Damage_Library application,
		-- Gore_Library feedback.
		if player then
			server:Fire("WeaponHit", {
				Player = player,
				WeaponId = weaponId,
				Data = {HitPart = data.HitPart, Position = data.Position},
			})
		end
		res:Send({WeaponId = weaponId, Registered = true})
	end)

	----------------------------------------------------------------
	-- THROWABLE MELEE — constrained param example
	----------------------------------------------------------------
	-- POST melee/:WeaponId(%a[%w_]*)/throw
	-- Only weapons flagged Throwable in their config should reach here.
	app:Post("melee/:WeaponId(%a[%w_]*)/throw", function(req: Request, res: Response)
		local weaponId = req.params.WeaponId :: string
		local data       = req.data
		local player      = req.player

		if not Validator.IsTable(data) or not Validator.IsVector3(data.Velocity) then
			res:Status(400):Error("throw request missing Vector3 'Velocity'")
			return
		end

		-- TODO: verify weaponId's Config.States.Throwable, consume the weapon,
		-- spawn a thrown projectile.
		if player then
			server:Fire("WeaponUnequipped", {Player = player, WeaponId = weaponId, Data = {Thrown = true, Velocity = data.Velocity}})
		end
		res:Send({WeaponId = weaponId, Thrown = true})
	end)
end

return Module
