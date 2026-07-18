--!strict
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       ThrowRoutes
--  ◄► Version:     1.0
--  ◄► Date:        17/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: Data/Routes — RoExpress route table for throwable
--                  weapons (grenades, knives, etc.), following:
--                    roexpress.dev/docs/pages/router.html
--                    roexpress.dev/docs/pages/router-params.html
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
	Config    = RoExpress.Router.Route("throw/:WeaponId=string/config") :: RouteBuilder<{WeaponId: string}>,
	Equip     = RoExpress.Router.Route("throw/:WeaponId=string/equip") :: RouteBuilder<{WeaponId: string}>,
	Unequip   = RoExpress.Router.Route("throw/:WeaponId=string/unequip") :: RouteBuilder<{WeaponId: string}>,
	PullPin   = RoExpress.Router.Route("throw/:WeaponId=string/pullpin") :: RouteBuilder<{WeaponId: string}>,
	-- Throw is not an App route — it's fired/checked every use, so it
	-- goes over Data/Streams/ThrowStream instead.
	Detonate  = RoExpress.Router.Route("throw/:WeaponId=string/detonate") :: RouteBuilder<{WeaponId: string}>,
	Inventory = RoExpress.Router.Route("throw/:WeaponId=string/inventory") :: RouteBuilder<{WeaponId: string}>,
}

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	REGISTRATION
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Mounts every throwable route onto a given RoExpress App (or Port).
-- `server` is the Utilities/Core/Server instance — used to fire weapon
-- lifecycle events and push authoritative state to clients. Called once
-- from Utilities/Core/Network during bootstrap:
--   ThrowRoutes.Register(RoExpress("App"), server)
Module.Register = function(app: App, server: Server)

	----------------------------------------------------------------
	-- CONFIG
	----------------------------------------------------------------
	-- GET throw/:WeaponId=string/config
	app:Get("throw/:WeaponId=string/config", function(req: Request, res: Response)
		local weaponId = req.params.WeaponId :: string

		if not Validator.IsNonEmptyString(weaponId) then
			res:Status(400):Error("WeaponId must be a non-empty string")
			return
		end

		-- TODO: look up the baked Config for weaponId (Utilities/Types/Weapons/Throw).
		res:Send({WeaponId = weaponId, Config = nil})
	end)

	----------------------------------------------------------------
	-- EQUIP / UNEQUIP
	----------------------------------------------------------------
	-- POST throw/:WeaponId=string/equip
	app:Post("throw/:WeaponId=string/equip", function(req: Request, res: Response)
		local weaponId = req.params.WeaponId :: string
		local player    = req.player

		if not player then
			res:Status(401):Error("Equip requires an authenticated player")
			return
		end

		-- TODO: hand off to Throw_Class to construct/attach the tool instance.
		server:Fire("WeaponEquipped", {Player = player, WeaponId = weaponId})
		res:Send({WeaponId = weaponId, Equipped = true})
	end)

	-- POST throw/:WeaponId=string/unequip
	app:Post("throw/:WeaponId=string/unequip", function(req: Request, res: Response)
		local weaponId = req.params.WeaponId :: string
		local player    = req.player

		-- TODO: hand off to Throw_Class to detach/cleanup the tool instance.
		if player then
			server:Fire("WeaponUnequipped", {Player = player, WeaponId = weaponId})
		end
		res:Send({WeaponId = weaponId, Equipped = false})
	end)

	----------------------------------------------------------------
	-- PULL PIN (start fuse for cookable throwables)
	----------------------------------------------------------------
	-- POST throw/:WeaponId=string/pullpin
	app:Post("throw/:WeaponId=string/pullpin", function(req: Request, res: Response)
		local weaponId = req.params.WeaponId :: string
		local player    = req.player

		-- TODO: verify weaponId's Config.States.Cookable before starting a fuse timer.
		if player then
			server:UpdateWeaponState(player, weaponId, {PinPulled = true})
			server:Fire("WeaponStateChanged", {Player = player, WeaponId = weaponId, Data = {PinPulled = true}})
		end
		res:Send({WeaponId = weaponId, PinPulled = true})
	end)

	----------------------------------------------------------------
	-- THROW — moved off the App/Router entirely
	----------------------------------------------------------------
	-- Throws are fired/checked every use, so they go over the binary
	-- RoExpress.Stream channel instead:
	--   Data/Streams/ThrowStream.luau
	--     server: ThrowStream.Register(server)  — subscribes, fires
	--             "WeaponFired" on the event bus, replicates to other clients
	--     client: ThrowStream.Throw(weaponId, origin, velocity, heldTime)

	----------------------------------------------------------------
	-- DETONATE
	----------------------------------------------------------------
	-- POST throw/:WeaponId=string/detonate
	-- Expects req.data = {Position: Vector3}
	app:Post("throw/:WeaponId=string/detonate", function(req: Request, res: Response)
		local weaponId = req.params.WeaponId :: string
		local data      = req.data
		local player    = req.player

		if not Validator.IsTable(data) or not Validator.IsVector3(data.Position) then
			res:Status(400):Error("detonate request missing Vector3 'Position'")
			return
		end

		-- TODO: explosion resolution — radius falloff (Damage_Library.ExplosionFalloff),
		-- blast damage, self-damage modifier, VFX broadcast.
		if player then
			server:Fire("WeaponHit", {
				Player = player,
				WeaponId = weaponId,
				Data = {Detonated = true, Position = data.Position},
			})
		end
		res:Send({WeaponId = weaponId, Detonated = true})
	end)

	----------------------------------------------------------------
	-- INVENTORY
	----------------------------------------------------------------
	-- GET throw/:WeaponId=string/inventory
	app:Get("throw/:WeaponId=string/inventory", function(req: Request, res: Response)
		local weaponId = req.params.WeaponId :: string

		-- TODO: return live {Count, Max_Capacity} from the player's throwable state.
		res:Send({WeaponId = weaponId, Count = 0, Max = 0})
	end)
end

return Module
