--!strict
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       Client
--  ◄► Version:     1.0
--  ◄► Date:        17/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: Utilities/Types type definitions for client-side
--                  state and structures used across Utilities/Core/Client.
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

export type Type = {
    Config: any, -- Types/Config.BaseConfig — untyped here to avoid a Client <-> Config <-> Weapons <-> FireArm cyclic require, same as Class/Streams below
    State: {},
    Camera: Camera,
    
    Player: Player,
    Character: Model,
    Humanoid: Humanoid,
    Animator: Animator,
    
    ViewModel: Model,
    WeaponModel: Model,
    
    Class: any, -- FireArm_Class.Type | Melee_Class.Type | Throw_Class.Type — untyped here to avoid a Client <-> Weapons <-> FireArm cyclic require, same as Streams below

    LiveSignals: {},
    
    Springs: {
       Sway: any,
       Bob: any,
       Breath: any,
       Recoil: any,
    },

    Animations: {
        Character: {
            Movement: {
                Walk: AnimationTrack,
                Sprint: AnimationTrack,
                Crouch: AnimationTrack,
                Jump: AnimationTrack,
                Fall: AnimationTrack,
                Slide: AnimationTrack,
                
                [string]: AnimationTrack,
            },
            Weapon: {
                --Universal weapon animations that are shared across all weapons, such as reload, fire, etc.
                Hold: AnimationTrack,
                Equip: AnimationTrack,
                Unequip: AnimationTrack,
                Drop: AnimationTrack,
                Pickup: AnimationTrack,
                Inspect: AnimationTrack,

                --FireArm
                Fire: AnimationTrack,
                Reload: AnimationTrack,
                TacticalReload: AnimationTrack,

                --Melee
                Swing: AnimationTrack,
                Stab: AnimationTrack,

                --Throwable
                Throw: AnimationTrack,
                Cook: AnimationTrack,
                PullPin: AnimationTrack,


                [string]: AnimationTrack,
            }
        },
        ViewModel: {
            --Universal weapon animations that are shared across all weapons, such as reload, fire, etc.
            Hold: AnimationTrack,
            Equip: AnimationTrack,
            Unequip: AnimationTrack,
            Drop: AnimationTrack,
            Pickup: AnimationTrack,
            Inspect: AnimationTrack,

            --FireArm
            Fire: AnimationTrack,
            Reload: AnimationTrack,
            TacticalReload: AnimationTrack,

            --Melee
            Swing: AnimationTrack,
            Stab: AnimationTrack,

            --Throwable
            Throw: AnimationTrack,
            Cook: AnimationTrack,
            PullPin: AnimationTrack,
        },
    },

    New: (self: any) -> Type,
    -- Data/Streams modules loaded at boot, keyed by module name
    -- (e.g. Streams.FireArmStream.Fire(weaponId, origin, direction)).
    Streams: {[string]: any},
    

    -- Equips weaponId with the given BaseConfig — auto-builds the viewmodel
    -- (arms + weapon model, from Config.ViewModelSettings) and constructs
    -- the matching gameplay class (FireArm_Class | Melee_Class | Throw_Class,
    -- picked off Config.Category) in one call; no separate manual build step.
    Equip: (self: Type, weaponId: string, config: any) -> (), -- config: Types/Config.BaseConfig
    UnEquip: (self: Type) -> (),

    Primary: (self: Type) -> any, -- returns the equipped weapon instance
    Secondary: (self: Type) -> any, -- returns the equipped weapon instance

    -- Relaases a primary or secondary action based on the config and state of the weapon. If the weapon is not in a state to release, it will do nothing.
    Release: (self: Type, ReleaseWhat: string) -> (), -- ReleaseWhat: "Primary" | "Secondary" | "All"

    Hide: (self: Type) -> (), -- View Model/Camera/GUI
    Show: (self: Type) -> (), -- View Model/Camera/GUI

    ApplyAction: (self: Type, action: string, ...any) -> (),

    Drop: (self: Type) -> (),
    Pickup: (self: Type, weaponId: string) -> (),

    Enable: (self: Type) -> (),
    Disable: (self: Type) -> (),
    SetEnabled: (self: Type, enabled: boolean) -> (),

    -- Toggles first-person/third-person off entirely (distinct from
    -- switching which one is active — both can be independently disabled,
    -- e.g. a pure third-person game with no viewmodel at all).
    SetFirstPersonEnabled: (self: Type, enabled: boolean) -> (),
    SetThirdPersonEnabled: (self: Type, enabled: boolean) -> (),

    SetShirt: (self: Type, shirtId: string) -> (),
    SetPants: (self: Type, pantsId: string) -> (),
    SetAccessory: (self: Type, accessoryId: string) -> (),

    Render: (self: Type, dt: number) -> (),
}

return {}
