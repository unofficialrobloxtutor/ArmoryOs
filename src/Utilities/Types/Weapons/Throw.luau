--!nolint
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       Throw
--  ◄► Version:     1.0
--  ◄► Date:        18/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: Utilities/Types/Weapons type definitions for throwable
--                  weapon data and configuration, backing Throw_Class.
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
local Client = require(`../Client`)
local State = require(`../../Classes/State_Class`)

export type ThrowTypeNames = "Grenade" | "Knife" | "Molotov" | "Sticky"

-- Named sub-config types instead of inline tables — Roblox Studio's live
-- script parser (as opposed to the IDE's analyzer) doesn't accept indexed-
-- access types like `Config["Fuse"]`, so Throw_Class references these by
-- name instead.
export type PhysicsConfig = {
    Throw_Velocity: number, -- studs/s imparted at release, scaled by HeldTime for a charged throw
    Min_Velocity: number?,  -- floor for a tap-throw (HeldTime ~= 0)
    Gravity_Modifier: number?,
    Max_Distance: number?,
}

export type DamageConfig = {
    Explosion_Radius: number,
    Explosion_Damage: number,
    Explosion_Falloff: boolean?, -- feeds Damage_Library.ExplosionFalloff
    Min_Damage: number?,

    Headshot_Multiplier: number?,
    Limb_Multiplier: number?,

    -- Blocks blast damage to targets without line of sight to the
    -- detonation point — resolved via RayCast_Library.HasLineOfSight.
    Requires_Line_Of_Sight: boolean?,
}

export type FuseConfig = {
    Fuse_Time: number?, -- seconds from PullPin() to auto-detonate
    Cookable: boolean?, -- allow holding past PullPin to shorten the remaining fuse
    Detonate_On_Impact: boolean?, -- explode on first RaycastResult contact instead of waiting out the fuse
}

export type InventoryConfig = {
    Max_Capacity: number,
    Count: number?,
    Consume_On_Use: boolean?,
}

-- Auto-resolved by naming convention; only set here to override the auto-loaded asset.
export type SoundConfig = {
    PullPin: string?,
    Throw: string?,
    Bounce: string?,
    Detonate: string?,
    Equip: string?,
}

-- Auto-resolved by naming convention; only set here to override the auto-loaded asset.
export type AnimationConfig = {
    Idle: string?,
    PullPin: string?,
    Cook: string?,
    Throw: string?,
    Equip: string?,
}

type BaseThrowConfig = {
    Physics: PhysicsConfig,
    Damage: DamageConfig,
    Fuse: FuseConfig?,
    Inventory: InventoryConfig,
    Sound: SoundConfig?,
    Animation: AnimationConfig?,
}

type GrenadeConfig = {
    Type: "Grenade",
    Behavior: {
        Bounce_Count: number?,
        Bounce_Restitution: number?, -- fed into Physics_Library.ReflectVelocity via Damage_Library.CoefficientOfRestitution-style scaling
    },
}
type KnifeConfig = {
    Type: "Knife",
    Behavior: {
        Recoverable: boolean?, -- can be picked back up off the ground after landing
        Sticks_On_Impact: boolean?,
    },
}
type MolotovConfig = {
    Type: "Molotov",
    Behavior: {
        Burn_Duration: number?,
        Burn_Damage_Per_Tick: number?,
        Burn_Tick_Rate: number?,
    },
}
type StickyConfig = {
    Type: "Sticky",
    Behavior: {
        Stick_To_Surfaces: boolean?,
        Remote_Detonate: boolean?, -- requires an explicit Detonate() call instead of the fuse timer
    },
}

export type Config = BaseThrowConfig & (
    GrenadeConfig
    | KnifeConfig
    | MolotovConfig
    | StickyConfig
)

export type WeaponState = "Idle" | "Equipping" | "Equipped" | "Cooking" | "Thrown" | "UnEquipping"

type ThrowClassType = {
    Client: Client.Type,

    data: {
        WeaponId: string,
        Config: Config,
        State: {[string]: any},
    },

    WeaponState: State.Type<WeaponState>,
    New: (client: Client.Type, weaponId: string, config: Config) -> ThrowClassType,

    Equip: (self: ThrowClassType) -> (),
    UnEquip: (self: ThrowClassType) -> (),

    -- Starts the fuse (Config.Fuse.Fuse_Time) — required before Throw() on
    -- Cookable throwables, no-op otherwise.
    PullPin: (self: ThrowClassType) -> (),

    -- Releases the throwable — casts the projected trajectory locally for
    -- preview via RayCast_Library, reports the release over
    -- Data/Streams/ThrowStream.
    Throw: (self: ThrowClassType, direction: Vector3, heldTime: number?) -> (),

    -- Runs the local blast-radius preview at `position`: a HitBox_Class
    -- Sphere query for candidate players, each filtered by a
    -- RayCast_Library.HasLineOfSight occlusion check when
    -- Config.Damage.Requires_Line_Of_Sight is set, then
    -- Damage_Library.ExplosionFalloff per surviving target. Client-side
    -- preview only — server-authoritative resolution happens over
    -- throw/:WeaponId/detonate (Data/Routes/ThrowRoutes).
    Detonate: (self: ThrowClassType, position: Vector3) -> (),

    Render: (self: ThrowClassType, deltaTime: number) -> (),
}

export type Type = ThrowClassType

return {}
