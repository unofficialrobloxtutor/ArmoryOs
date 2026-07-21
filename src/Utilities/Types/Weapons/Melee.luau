--!nolint
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       Melee
--  ◄► Version:     1.0
--  ◄► Date:        18/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: Utilities/Types/Weapons type definitions for melee
--                  weapon data and configuration, backing Melee_Class.
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
local Client = require(`../Client`)
local State = require(`../../Classes/State_Class`)

export type AttackKind = "Light" | "Heavy"
export type MeleeTypeNames = "Sword" | "Axe" | "Blunt" | "Fist" | "Spear"

-- Named sub-config types instead of inline tables — Roblox Studio's live
-- script parser (as opposed to the IDE's analyzer) doesn't accept indexed-
-- access types like `Config["Swing"]`, so Melee_Class references these by
-- name instead.
export type DamageConfig = {
    Base_Damage: number,
    Heavy_Multiplier: number?,
    Headshot_Multiplier: number?,
    Limb_Multiplier: number?,

    Min_Damage: number?,
    Max_Damage: number?,
}

-- Consumed by Melee_Class to drive a HitBox_Class ("Cone" for a swing
-- arc, "Custom"/SetCapsule for a thrust) every attack — see HitBox_Class.
export type SwingConfig = {
    Range: number,
    Angle_Degrees: number, -- cone half-angle for swing arc detection

    Light_Swing_Time: number, -- seconds from Attack() to the hitbox firing
    Heavy_Swing_Time: number,

    Combo_Window: number?, -- seconds after a swing lands before Combo resets
    Max_Combo: number?,
}

export type BlockConfig = {
    Damage_Reduction: number, -- 0-100, fed into Damage_Library.MitigatePercent
    Block_Angle_Degrees: number?, -- only mitigate hits arriving within this frontal arc
}

export type ParryConfig = {
    Parry_Window: number, -- seconds after Parry() during which an incoming hit is negated
    Stagger_Duration: number?, -- how long the parried attacker is staggered
}

export type KnockbackConfig = {
    Base_Force: number?,
    Scale: number?, -- fed into Damage_Library.CalculateKnockback
}

-- Auto-resolved by naming convention; only set here to override the auto-loaded asset.
export type SoundConfig = {
    Swing: string?,
    Hit: string?,
    Block: string?,
    Parry: string?,
    Equip: string?,
}

-- Auto-resolved by naming convention; only set here to override the auto-loaded asset.
export type AnimationConfig = {
    Idle: string?,
    Light_Attack: string?,
    Heavy_Attack: string?,
    Block: string?,
    Parry: string?,
    Equip: string?,
}

export type DataConfig = {
    Hitbox_Debug: boolean?,
}

type BaseMeleeConfig = {
    Damage: DamageConfig,
    Swing: SwingConfig,
    Block: BlockConfig?,
    Parry: ParryConfig?,
    Knockback: KnockbackConfig?,
    Sound: SoundConfig?,
    Animation: AnimationConfig?,
    Data: DataConfig,
}

type SwordConfig = {
    Type: "Sword",
    Behavior: {
        Bleed_Chance: number?,
        Bleed_Damage_Per_Tick: number?,
    },
}
type AxeConfig = {
    Type: "Axe",
    Behavior: {
        Armor_Pierce: number?, -- flat armor penetration, see Damage_Library.PierceArmor
    },
}
type BluntConfig = {
    Type: "Blunt",
    Behavior: {
        Stagger_Chance: number?,
    },
}
type FistConfig = {
    Type: "Fist",
    Behavior: {
        Akimbo: boolean?,
    },
}
type SpearConfig = {
    Type: "Spear",
    Behavior: {
        Thrust_Range_Bonus: number?, -- added to Swing.Range on a Heavy (thrust) attack
    },
}

export type Config = BaseMeleeConfig & (
    SwordConfig
    | AxeConfig
    | BluntConfig
    | FistConfig
    | SpearConfig
)

export type WeaponState = "Idle" | "Equipping" | "Equipped" | "Swinging" | "Blocking" | "Parrying" | "UnEquipping"

type MeleeClassType = {
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
    New: (client: Client.Type, weaponId: string, config: Config) -> MeleeClassType,

    Attach: (self: MeleeClassType, attachmentName: string) -> (),
    Detach: (self: MeleeClassType, attachmentName: string) -> (),

    Equip: (self: MeleeClassType) -> (),
    UnEquip: (self: MeleeClassType) -> (),

    -- Fires a swing — spins up a HitBox_Class:FireUntil() sweep along the
    -- weapon's blade/head for the swing's duration, reports the attack to
    -- the server over Data/Streams/MeleeStream.
    Attack: (self: MeleeClassType, kind: AttackKind) -> (),

    Block: (self: MeleeClassType, isBlocking: boolean) -> (),
    Parry: (self: MeleeClassType) -> (),

    Render: (self: MeleeClassType, deltaTime: number) -> (),
}

export type Type = MeleeClassType

return {}
