--!strict
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       FirstPersonRoutes
--  ◄► Version:     1.0
--  ◄► Date:        17/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: Data/Routes — RoExpress route table for first-person
--                  camera/viewmodel state (FOV, sway, sensitivity, bob),
--                  following:
--                    roexpress.dev/docs/pages/router.html
--                    roexpress.dev/docs/pages/router-params.html
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--► Services     ◄--
--► Requires     ◄--
local RoExpress = require(script.Parent.Parent.Parent.Utilities.Libraries.RoExpress_Library)
local Router    = require(script.Parent.Parent.Parent.Utilities.Libraries.RoExpress_Library.Router)
local Validator = require(script.Parent.Parent.Parent.Utilities.Libraries.Validator_Library)
--► Types        ◄--
type App      = RoExpress.App
type Request  = RoExpress.Request
type Response = RoExpress.Response
type RouteBuilder<T> = Router.RouteBuilder<T>
--► Tables       ◄--
local Module = {}

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	ROUTE-BUILDERS
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

Module.Routes = {
	Enable      = RoExpress.Router.Route("camera/firstperson/enable") :: RouteBuilder<{}>,
	Fov         = RoExpress.Router.Route("camera/firstperson/fov") :: RouteBuilder<{}>,
	Sensitivity = RoExpress.Router.Route("camera/firstperson/sensitivity") :: RouteBuilder<{}>,
	Sway        = RoExpress.Router.Route("camera/firstperson/sway") :: RouteBuilder<{}>,
	Bob         = RoExpress.Router.Route("camera/firstperson/bob") :: RouteBuilder<{}>,
	ViewModel   = RoExpress.Router.Route("camera/firstperson/viewmodel/:WeaponId=string") :: RouteBuilder<{WeaponId: string}>,
}

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	REGISTRATION
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Mounts every first-person camera route onto a given RoExpress App (or Port)
-- Called once from Utilities/Core/Server during bootstrap:
--   FirstPersonRoutes.Register(RoExpress("App"))
Module.Register = function(app: App)

	----------------------------------------------------------------
	-- ENABLE
	----------------------------------------------------------------
	-- POST camera/firstperson/enable
	-- Expects req.data = {Enabled: boolean}
	app:Post("camera/firstperson/enable", function(req: Request, res: Response)
		local data = req.data

		if not Validator.IsTable(data) or not Validator.IsBoolean(data.Enabled) then
			res:Status(400):Error("enable request missing boolean 'Enabled'")
			return
		end

		res:Send({Enabled = data.Enabled})
	end)

	----------------------------------------------------------------
	-- FOV
	----------------------------------------------------------------
	-- POST camera/firstperson/fov
	-- Expects req.data = {Fov: number}
	app:Post("camera/firstperson/fov", function(req: Request, res: Response)
		local data = req.data

		if not Validator.IsTable(data) or not Validator.IsNumber(data.Fov) then
			res:Status(400):Error("fov request missing number 'Fov'")
			return
		end
		if not Validator.InRange(data.Fov, 30, 120) then
			res:Status(400):Error("Fov must be between 30 and 120")
			return
		end

		res:Send({Fov = data.Fov})
	end)

	----------------------------------------------------------------
	-- SENSITIVITY
	----------------------------------------------------------------
	-- POST camera/firstperson/sensitivity
	-- Expects req.data = {Sensitivity: number}
	app:Post("camera/firstperson/sensitivity", function(req: Request, res: Response)
		local data = req.data

		if not Validator.IsTable(data) or not Validator.IsNumber(data.Sensitivity) then
			res:Status(400):Error("sensitivity request missing number 'Sensitivity'")
			return
		end
		if not Validator.IsPositive(data.Sensitivity) then
			res:Status(400):Error("Sensitivity must be greater than zero")
			return
		end

		res:Send({Sensitivity = data.Sensitivity})
	end)

	----------------------------------------------------------------
	-- SWAY
	----------------------------------------------------------------
	-- POST camera/firstperson/sway
	-- Expects req.data = {Enabled: boolean, Multiplier: number?}
	app:Post("camera/firstperson/sway", function(req: Request, res: Response)
		local data = req.data

		if not Validator.IsTable(data) or not Validator.IsBoolean(data.Enabled) then
			res:Status(400):Error("sway request missing boolean 'Enabled'")
			return
		end
		if data.Multiplier ~= nil and not Validator.IsNonNegative(data.Multiplier) then
			res:Status(400):Error("sway 'Multiplier' must be a non-negative number")
			return
		end

		res:Send({Enabled = data.Enabled, Multiplier = data.Multiplier})
	end)

	----------------------------------------------------------------
	-- BOB
	----------------------------------------------------------------
	-- POST camera/firstperson/bob
	-- Expects req.data = {Enabled: boolean}
	app:Post("camera/firstperson/bob", function(req: Request, res: Response)
		local data = req.data

		if not Validator.IsTable(data) or not Validator.IsBoolean(data.Enabled) then
			res:Status(400):Error("bob request missing boolean 'Enabled'")
			return
		end

		res:Send({Enabled = data.Enabled})
	end)

	----------------------------------------------------------------
	-- VIEWMODEL
	----------------------------------------------------------------
	-- GET camera/firstperson/viewmodel/:WeaponId=string
	app:Get("camera/firstperson/viewmodel/:WeaponId=string", function(req: Request, res: Response)
		local weaponId = req.params.WeaponId :: string

		if not Validator.IsNonEmptyString(weaponId) then
			res:Status(400):Error("WeaponId must be a non-empty string")
			return
		end

		-- TODO: resolve and return the viewmodel/ViewModel asset id for weaponId
		-- (Utilities/Types/Weapons — Config.ViewModel).
		res:Send({WeaponId = weaponId, ViewModel = nil})
	end)
end

return Module
