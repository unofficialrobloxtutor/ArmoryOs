--!strict
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       Sound_Library
--  ◄► Version:     1.0
--  ◄► Date:        18/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: General-purpose audio module — one-shot 2D/3D
--                  playback, pitch-varied one-shots, looping ambience
--                  with fade in/out, SoundGroup channels with volume
--                  control, random pick-from-set, and preloading.
--                  Gun_Visual_Library keeps its own PlaySoundOn/At for
--                  weapon-attached shots; this is the framework-wide
--                  library everything else (UI, ambience, hit feedback,
--                  melee, throwables) should reach for.
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--► Services     ◄--
local SoundService   = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local TweenService    = game:GetService("TweenService")
local Workspace       = game:GetService("Workspace")
local Debris          = game:GetService("Debris")
--► Tables       ◄--
local Module = {}
--► Variables    ◄--
local _groups: { [string]: SoundGroup } = {}
--► Constants    ◄--
Module.DefaultRollOffMax = 150

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	PRIVATE
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

-- Accepts "rbxassetid://123", "123", or 123 and returns a proper SoundId.
local function _normalizeId(soundId: string | number): string
	if type(soundId) == "number" then
		return "rbxassetid://" .. soundId
	end
	if soundId:match("^%d+$") then
		return "rbxassetid://" .. soundId
	end
	return soundId
end

local function _buildSound(soundId: string | number, cfg: {[string]: any}): Sound
	local sound = Instance.new("Sound")
	sound.SoundId       = _normalizeId(soundId)
	sound.Volume         = cfg.Volume or 1
	sound.PlaybackSpeed   = cfg.Pitch or 1
	sound.TimePosition     = cfg.StartTime or 0
	if cfg.Group then
		sound.SoundGroup = Module.GetGroup(cfg.Group)
	end
	return sound
end

-- Invisible anchored holder so a Sound can exist at a world position.
local function _holderAt(position: Vector3): Part
	local holder = Instance.new("Part")
	holder.Anchored     = true
	holder.CanCollide    = false
	holder.CanQuery       = false
	holder.CanTouch        = false
	holder.Transparency     = 1
	holder.Size = Vector3.new(0.05, 0.05, 0.05)
	holder.CFrame = CFrame.new(position)
	holder.Parent = Workspace
	return holder
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	GROUPS — named SoundGroup channels (SFX / Music / UI / ...)
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Returns (lazily creating) the SoundGroup for a channel name. Route
--  sounds into channels via config {Group = "SFX"} on any play call.
Module.GetGroup = function(name: string): SoundGroup
	local existing = _groups[name]
	if existing then
		return existing
	end
	local group = Instance.new("SoundGroup")
	group.Name   = name
	group.Volume = 1
	group.Parent = SoundService
	_groups[name] = group
	return group
end

--► Sets a channel's master volume (0-10, typically 0-1) — a settings
--  menu's volume sliders should call this.
Module.SetGroupVolume = function(name: string, volume: number)
	Module.GetGroup(name).Volume = math.clamp(volume, 0, 10)
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	ONE-SHOTS
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

export type PlayConfig = {
	Volume:      number?,
	Pitch:       number?,
	PitchRange:  number?,  -- random +/- variation, e.g. 0.1 → 0.9-1.1x
	StartTime:   number?,
	Group:       string?,
	RollOffMax:  number?,  -- 3D only
}

--► Plays a non-positional (2D/global) one-shot — UI clicks, hit markers,
--  round-start stingers. Self-destructs when finished.
Module.Play = function(soundId: string | number, config: PlayConfig?): Sound
	local cfg = (config or {}) :: {[string]: any}
	local sound = _buildSound(soundId, cfg)
	if cfg.PitchRange then
		sound.PlaybackSpeed += (math.random() * 2 - 1) * cfg.PitchRange
	end
	sound.Parent = SoundService

	sound.Ended:Once(function()
		sound:Destroy()
	end)
	sound:Play()
	Debris:AddItem(sound, 30)
	return sound
end

--► Plays a 3D one-shot at a world position; the invisible holder cleans
--  itself up after the sound ends.
Module.PlayAt = function(soundId: string | number, position: Vector3, config: PlayConfig?): Sound
	local cfg = (config or {}) :: {[string]: any}
	local holder = _holderAt(position)
	local sound = _buildSound(soundId, cfg)
	sound.RollOffMaxDistance = cfg.RollOffMax or Module.DefaultRollOffMax
	if cfg.PitchRange then
		sound.PlaybackSpeed += (math.random() * 2 - 1) * cfg.PitchRange
	end
	sound.Parent = holder

	sound.Ended:Once(function()
		holder:Destroy()
	end)
	sound:Play()
	Debris:AddItem(holder, math.max(sound.TimeLength, 0.1) + 5)
	return sound
end

--► Plays a one-shot parented to an existing Instance (follows it as it
--  moves) — footsteps on a character, a beep on a gadget.
Module.PlayOn = function(parent: Instance, soundId: string | number, config: PlayConfig?): Sound
	local cfg = (config or {}) :: {[string]: any}
	local sound = _buildSound(soundId, cfg)
	if cfg.PitchRange then
		sound.PlaybackSpeed += (math.random() * 2 - 1) * cfg.PitchRange
	end
	sound.Parent = parent

	sound.Ended:Once(function()
		sound:Destroy()
	end)
	sound:Play()
	Debris:AddItem(sound, 30)
	return sound
end

--► Plays one random id from a set — pass several footstep/impact
--  variants so repetition doesn't grate. 3D when position is given.
Module.PlayRandom = function(soundIds: {string | number}, position: Vector3?, config: PlayConfig?): Sound?
	if #soundIds == 0 then
		return nil
	end
	local pick = soundIds[math.random(1, #soundIds)]
	if position then
		return Module.PlayAt(pick, position, config)
	end
	return Module.Play(pick, config)
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	LOOPS — ambience / music with fades
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Starts a looping sound (music, room tone). Fades in over FadeTime if
--  given. Returns the Sound — keep the reference to StopLoop it later.
--  3D when a position is supplied, global otherwise.
Module.StartLoop = function(soundId: string | number, config: (PlayConfig & {
	FadeTime: number?,
	Position: Vector3?,
})?): Sound
	local cfg = (config or {}) :: {[string]: any}
	local sound = _buildSound(soundId, cfg)
	sound.Looped = true

	if cfg.Position then
		sound.RollOffMaxDistance = cfg.RollOffMax or Module.DefaultRollOffMax
		sound.Parent = _holderAt(cfg.Position)
	else
		sound.Parent = SoundService
	end

	local targetVolume = cfg.Volume or 1
	if cfg.FadeTime and cfg.FadeTime > 0 then
		sound.Volume = 0
		sound:Play()
		TweenService:Create(sound, TweenInfo.new(cfg.FadeTime), {Volume = targetVolume}):Play()
	else
		sound:Play()
	end

	return sound
end

--► Stops a looping sound, fading out over FadeTime if given, then
--  destroys it (and its position holder, when it has one).
Module.StopLoop = function(sound: Sound, fadeTime: number?)
	local holder = sound.Parent
	local function cleanup()
		if holder and holder:IsA("BasePart") and holder.Transparency == 1 then
			holder:Destroy() -- takes the sound with it
		else
			sound:Destroy()
		end
	end

	if fadeTime and fadeTime > 0 then
		local tween = TweenService:Create(sound, TweenInfo.new(fadeTime), {Volume = 0})
		tween.Completed:Once(cleanup)
		tween:Play()
	else
		cleanup()
	end
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	PRELOAD
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Preloads sound assets so first playback isn't silent while the asset
--  streams in — call during loading with a weapon's Sound config values.
--  Non-blocking (runs in its own task).
Module.Preload = function(soundIds: {string | number})
	local sounds = {}
	for _, id in soundIds do
		local sound = Instance.new("Sound")
		sound.SoundId = _normalizeId(id)
		table.insert(sounds, sound)
	end
	task.spawn(function()
		ContentProvider:PreloadAsync(sounds)
		for _, sound in sounds do
			sound:Destroy()
		end
	end)
end

return Module
