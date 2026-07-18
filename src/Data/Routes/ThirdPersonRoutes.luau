--!strict
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       ThirdPersonRoutes
--  ◄► Version:     1.0
--  ◄► Date:        17/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: Data/Routes — RoExpress route table for third-person
--                  camera state (distance, shoulder offset, FOV), following:
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
--► Constants    ◄--
local VALID_SHOULDERS = {"Left", "Right"}

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	ROUTE-BUILDERS
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

Module.Routes = {
	Enable   = RoExpress.Router.Route("camera/thirdperson/enable") :: RouteBuilder<{}>,
	Distance = RoExpress.Router.Route("camera/thirdperson/distance") :: RouteBuilder<{}>,
	Shoulder = RoExpress.Router.Route("camera/thirdperson/shoulder") :: RouteBuilder<{}>,
	Fov      = RoExpress.Router.Route("camera/thirdperson/fov") :: RouteBuilder<{}>,
	Aim      = RoExpress.Router.Route("camera/thirdperson/aim") :: RouteBuilder<{}>,
}

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	REGISTRATION
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Mounts every third-person camera route onto a given RoExpress App (or Port)
-- Called once from Utilities/Core/Server during bootstrap:
--   ThirdPersonRoutes.Register(RoExpress("App"))
Module.Register = function(app: App)

	----------------------------------------------------------------
	-- ENABLE
	----------------------------------------------------------------
	-- POST camera/thirdperson/enable
	-- Expects req.data = {Enabled: boolean}
	app:Post("camera/thirdperson/enable", function(req: Request, res: Response)
		local data = req.data

		if not Validator.IsTable(data) or not Validator.IsBoolean(data.Enabled) then
			res:Status(400):Error("enable request missing boolean 'Enabled'")
			return
		end

		res:Send({Enabled = data.Enabled})
	end)

	----------------------------------------------------------------
	-- DISTANCE
	----------------------------------------------------------------
	-- POST camera/thirdperson/distance
	-- Expects req.data = {Distance: number}
	app:Post("camera/thirdperson/distance", function(req: Request, res: Response)
		local data = req.data

		if not Validator.IsTable(data) or not Validator.IsNumber(data.Distance) then
			res:Status(400):Error("distance request missing number 'Distance'")
			return
		end
		if not Validator.InRange(data.Distance, 0, 30) then
			res:Status(400):Error("Distance must be between 0 and 30")
			return
		end

		res:Send({Distance = data.Distance})
	end)

	----------------------------------------------------------------
	-- SHOULDER SWAP
	----------------------------------------------------------------
	-- POST camera/thirdperson/shoulder
	-- Expects req.data = {Side: "Left" | "Right"}
	app:Post("camera/thirdperson/shoulder", function(req: Request, res: Response)
		local data = req.data

		if not Validator.IsTable(data) or not Validator.IsOneOf(data.Side, VALID_SHOULDERS) then
			res:Status(400):Error("shoulder requires Side to be one of: " .. table.concat(VALID_SHOULDERS, ", "))
			return
		end

		res:Send({Side = data.Side})
	end)

	----------------------------------------------------------------
	-- FOV
	----------------------------------------------------------------
	-- POST camera/thirdperson/fov
	-- Expects req.data = {Fov: number}
	app:Post("camera/thirdperson/fov", function(req: Request, res: Response)
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
	-- AIM (shoulder-cam zoom while aiming down sights in third-person)
	----------------------------------------------------------------
	-- POST camera/thirdperson/aim
	-- Expects req.data = {Aiming: boolean}
	app:Post("camera/thirdperson/aim", function(req: Request, res: Response)
		local data = req.data

		if not Validator.IsTable(data) or not Validator.IsBoolean(data.Aiming) then
			res:Status(400):Error("aim request missing boolean 'Aiming'")
			return
		end

		res:Send({Aiming = data.Aiming})
	end)
end

return Module
