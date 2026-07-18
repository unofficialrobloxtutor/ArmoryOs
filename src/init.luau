--!nolint
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       init
--  ◄► Version:     1.0
--  ◄► Date:        17/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: Root entry point of the Armory OS Advanced Weapon
--                  Framework. Bootstraps the framework on require,
--                  wiring together Utilities, Core, and Libraries.
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--TODO: Implement a proper init system that can handle multiple modules and dependencies.

--►► Services ◄◄--
local RunService = game:GetService("RunService")
--►► Requires ◄◄--
local Server  = require(`@self/Utilities/Core/Server`)
local Network = require(`@self/Utilities/Core/Network`)
local Client  = require(`@self/Utilities/Core/Client`)
--►► Variables ◄◄--
--►► Tables ◄◄--
local module = {}
--►► Types ◄◄--
export type Type = {}
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
-- Functions
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--►► Local ◄◄--
--►► Global ◄◄--
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
-- Constructor
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

function module.New(): Type
    local self = setmetatable({}, { __index = module }) :: Type

    if RunService:IsClient() then
        self.Client = Client.New()
    else
        -- Server boots first so it owns the shared RoExpress App singleton;
        -- Network.New(self.Server) then mounts Data/Routes onto that same
        -- App and threads Server through to every route's Register(app, server).
        self.Server  = Server.New()
        self.Network = Network.New(self.Server)
    end

    return self
end


--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
-- Methods
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■