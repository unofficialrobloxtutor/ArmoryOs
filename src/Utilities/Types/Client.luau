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
    New: (self: any) -> Type,
    -- Data/Streams modules loaded at boot, keyed by module name
    -- (e.g. Streams.FireArmStream.Fire(weaponId, origin, direction)).
    Streams: {[string]: any},
}

return {}
