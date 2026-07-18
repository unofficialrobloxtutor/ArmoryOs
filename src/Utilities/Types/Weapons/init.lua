--!strict
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       Weapons
--  ◄► Version:     1.0
--  ◄► Date:        17/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: Utilities/Types/Weapons aggregate entry point —
--                  collects and re-exports FireArm, Melee, and Throw
--                  weapon type definitions.
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
local FireArm = require(`@self/FireArm`)
local Melee = require(`@self/Melee`)
local Throw = require(`@self/Throw`)


export type FireArm = FireArm.Type
export type Melee = Melee.Type
export type Throw = Throw.Type

export type Config = FireArm.Config | Melee.Config | Throw.Config