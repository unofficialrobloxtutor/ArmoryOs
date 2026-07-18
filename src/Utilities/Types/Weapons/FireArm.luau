--!nolint
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       FireArm
--  ◄► Version:     1.0
--  ◄► Date:        17/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: Utilities/Types/Weapons type definitions for firearm
--                  data and configuration, backing FireArm_Class.
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
local Client = require(`../Client`)
local State = require(`../../Classes/State_Class`)
local ScopeClass = require(`../../Classes/Scope_Class`)

export type FireMode = "Semi" | "Auto" | "Burst"
export type FireArmTypeNames = "Sniper" | "AssaultRifle" | "Shotgun" | "Pistol" | "Explosive" | "Launcher"
export type ScopeConfig = ScopeClass.ScopeUIProps
export type ScopeAPI = ScopeClass.ScopeUIAPI

type BaseFireArmConfig = {
    Physics: {
        Base_Velocity: number,
        Gravity_Modifier: number,
        Max_Distance: number,
    },

    Penetration: {
        Penetration_Count: number?,
        Material_Penetration: {
            [Enum.Material]: {
                Thickness: number,  -- How Thick Before penetration doesnt happen per materai
                Power: {[number]: number}, -- How Much subtracted damage after a penetration
            },
        },

        Damage_Fall_Off_Start: number,
        Damage_Fall_Off_End: number,

        Ricochet_Angle_Degrees: number,
    },

    Damage: {
        Base_Damage: number,
        Headshot_Multiplier: number?,
        Limb_Multiplier: number?,

        Min_Damage: number?,
        Max_Damage: number?,
    },

    Fire: {
        Fire_Modes: {FireMode},
        Default_Fire_Mode: FireMode,

        Fire_Rate: number,          -- Rounds per minute
        Burst_Count: number?,
        Burst_Rate: number?,

        Auto_Fire: boolean,
    },

    Recoil: {
        Vertical: number,
        Horizontal: number,
        Horizontal_Variance: number?,

        Recovery_Speed: number,
        Recovery_Delay: number?,

        Camera_Kick: number?,
        Camera_Kick_Recovery: number?,
    },

    Spread: {
        Base_Spread: number,
        Max_Spread: number,

        Moving_Multiplier: number?,
        Jumping_Multiplier: number?,
        Crouching_Multiplier: number?,
        Aiming_Multiplier: number?,

        Increase_Per_Shot: number,
        Recovery_Speed: number,
    },

    Reload: {
        Reload_Time: number,
        Tactical_Reload_Time: number?,
        Empty_Reload_Time: number?,

        Chamber_Round: boolean?,
        Interruptible: boolean?,
    },

    Aim: {
        Aim_Fov: number?,
        Aim_Speed: number?,
        Aim_Sensitivity: number?,
        Aim_Sway_Multiplier: number?,
    },
    Ammo: {
        Bullet: string,
        Ejected_Shell: string?,

        Reserve: number?,
        In: number?,
        Max: number?
    },

    -- Auto-resolved by naming convention; only set here to override the auto-loaded asset.
    Sound: {
        Fire: string?,
        Fire_Suppressed: string?,
        Reload: string?,
        Empty: string?,
        Equip: string?,
        Aim_In: string?,
        Aim_Out: string?,
    }?,

    -- Auto-resolved by naming convention; only set here to override the auto-loaded asset.
    Animation: {
        Idle: string?,
        Fire: string?,
        Reload: string?,
        Reload_Empty: string?,
        Equip: string?,
        Aim: string?,
    }?,

    Data: {
        Use_Bullets: boolean,
        Use_Ray_As_Bullet: boolean,
        Use_Trail_As_Bullet: boolean,

        Infinite_Ammo: boolean?,
        Infinite_Reserve: boolean?,
    }
}

type SniperConfig = {
    Type: "Sniper",
    Behavior: {
        Zoom: {
            Zoom_Max_Fov: number,
            Zoom_Min_Fov: number,
            Zoom_Speed: number,
        },
    },

    -- Optic overlay config handed straight to Scope_Class.new() — only
    -- relevant when this weapon's aim kind is "Scope" (see FireArm_Class
    -- ScopeAim). Optional: a Sniper with an iron/ACOG-style sight and no
    -- overlay just omits it.
    Scope: ScopeClass.ScopeUIProps?,
}

type AssaultRifleConfig = {
    Type: "AssaultRifle",
    Behavior: {
        Hip_Fire_Accuracy: number?,
    },
}
type ShotgunConfig = {
    Type: "Shotgun",
    Behavior: {
        Pellet_Count: number,
        Pellet_Spread: number,

        Chamber_By_Round: boolean?, -- Reload one shell at a time
    },
}
type PistolConfig = {
    Type: "Pistol",
    Behavior: {
        Akimbo: boolean?,
    },
}

type ExplosiveConfig = {
    Type: "Explosive",
    Behavior: {
        Explosion_Radius: number,
        Explosion_Damage: number,
        Explosion_Falloff: boolean?,

        Fuse_Time: number?,
        Detonate_On_Impact: boolean?,
    },
}

type LauncherConfig = {
    Type: "Launcher",
    Behavior: {
        Projectile_Speed: number,
        Blast_Radius: number,
        Blast_Damage: number,

        Guided: boolean?,
        Turn_Speed: number?,
    },
}

export type Config = BaseFireArmConfig & (
    SniperConfig
    | AssaultRifleConfig
    | ShotgunConfig
    | PistolConfig
    | ExplosiveConfig
    | LauncherConfig
) 




export type WeaponState = "Idle" | "Equipping" | "Equipped" | "Aiming" | "Firing" | "Reloading" | "UnEquipping"

type FireArmClassType = {
    Client: Client.Type,
    attachments: {
        [string]: {
            Name: string,
            Type: string,
            Config: {[string]: any},
        },
    },

    data: {
        WeaponId: string,
        Config: Config,
        State: {[string]: any},
    },

    WeaponState: State.Type<WeaponState>,
    New : (client: Client.Type, weaponId: string, config: Config) -> FireArmClassType,

    Attach: (self: FireArmClassType, attachmentName: string) -> (),
    Detach: (self: FireArmClassType, attachmentName: string) -> (),

    SwitchArm: (self: FireArmClassType, arm: "Left" | "Right") -> (),
    SwitchFireMode: (self: FireArmClassType, fireMode: FireMode) -> (),

    IronSightAim: (self: FireArmClassType, isAiming: boolean) -> (),
    ScopeAim: (self: FireArmClassType, isAiming: boolean) -> (),
    SetAim: (self: FireArmClassType, isAiming: boolean) -> (),

    Fire: (self: FireArmClassType) -> (), -- Fires the correct Routes based on the configuration of the weapon, and handles the logic for firing the weapon.

    Reload: (self: FireArmClassType) -> (),
    TacticalReload: (self: FireArmClassType) -> (),
    EmptyReload: (self: FireArmClassType) -> (),

    Render: (self: FireArmClassType, deltaTime: number) -> (),
}

export type Type = FireArmClassType

return {}

