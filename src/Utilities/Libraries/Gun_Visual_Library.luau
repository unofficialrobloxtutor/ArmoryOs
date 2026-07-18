--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       Gun_Visual_Library
--  ◄► Version:     1.0
--  ◄► Date:        17/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: A human-readable module for firearm visual/audio
--                  feedback — tracers, muzzle flash, shell ejection,
--                  impact effects, bullet holes, and per-material
--                  effect selection. Creates real Instances and cleans
--                  them up via Debris, so it belongs on the client.
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--► Services     ◄--
local Debris          = game:GetService("Debris")
local TweenService    = game:GetService("TweenService")
local Workspace       = game:GetService("Workspace")
--► Tables       ◄--
local Module = {}
--► Variables    ◄--
--► Constants    ◄--
Module.DefaultTracerLifetime  = 0.5
Module.DefaultTracerWidth     = 0.05
Module.DefaultTracerColor     = Color3.fromRGB(255, 213, 128)

Module.DefaultShellLifetime   = 4
Module.DefaultShellVelocity   = 8

Module.DefaultFlashLifetime   = 0.05
Module.DefaultImpactLifetime  = 3
Module.DefaultHoleLifetime    = 12

-- Per-material impact presets: decal color tint and particle color
Module.MaterialEffects = {
	[Enum.Material.Concrete] = {Color = Color3.fromRGB(170, 170, 170), Sound = "Concrete"},
	[Enum.Material.Wood]     = {Color = Color3.fromRGB(120, 85, 60),  Sound = "Wood"},
	[Enum.Material.Metal]    = {Color = Color3.fromRGB(200, 200, 210), Sound = "Metal"},
	[Enum.Material.Grass]    = {Color = Color3.fromRGB(70, 110, 50),  Sound = "Dirt"},
	[Enum.Material.Sand]     = {Color = Color3.fromRGB(210, 190, 140), Sound = "Dirt"},
	[Enum.Material.Water]    = {Color = Color3.fromRGB(140, 180, 220), Sound = "Water"},
	Default                  = {Color = Color3.fromRGB(150, 150, 150), Sound = "Default"},
}

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	INTERNAL HELPERS
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Creates a lightweight, non-colliding anchored part at a position — used as an
-- attach point for beams/particles that don't need a real hitbox
local function createAnchor(position: CFrame | Vector3, parent: Instance?): Attachment
	local part = Instance.new("Part")
	part.Anchored          = true
	part.CanCollide         = false
	part.CanQuery           = false
	part.CanTouch           = false
	part.Transparency       = 1
	part.Size                = Vector3.new(0.05, 0.05, 0.05)
	part.CFrame              = typeof(position) == "CFrame" and position or CFrame.new(position :: Vector3)
	part.Parent               = parent or Workspace

	local attachment = Instance.new("Attachment")
	attachment.Parent = part
	Debris:AddItem(part, Module.DefaultImpactLifetime)
	return attachment
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	TRACERS
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Creates a Beam-based tracer between two world positions and fades it out over its lifetime
Module.CreateBeamTracer = function(origin: Vector3, target: Vector3, config: {
	Color:     Color3?,
	Width:     number?,
	Lifetime:  number?,
}?)
	local cfg      = config or {}
	local lifetime = cfg.Lifetime or Module.DefaultTracerLifetime
	local color    = cfg.Color or Module.DefaultTracerColor
	local width    = cfg.Width or Module.DefaultTracerWidth

	local a0 = createAnchor(origin)
	local a1 = createAnchor(target)

	local beam = Instance.new("Beam")
	beam.Attachment0  = a0
	beam.Attachment1  = a1
	beam.Width0        = width
	beam.Width1        = width
	beam.Color          = ColorSequence.new(color)
	beam.FaceCamera     = true
	beam.Transparency   = NumberSequence.new(0)
	beam.Parent          = a0.Parent

	local tween = TweenService:Create(beam, TweenInfo.new(lifetime, Enum.EasingStyle.Linear), {
		Transparency = NumberSequence.new(1),
	})
	tween:Play()

	Debris:AddItem(beam, lifetime)
	return beam
end

--► Creates a fast-moving Trail-based tracer part that flies from origin to target
-- Returns the flying part; it self-destructs after arrival + lifetime
Module.CreateTrailTracer = function(origin: Vector3, target: Vector3, config: {
	Speed:     number?,
	Color:     Color3?,
	Width:     number?,
	Lifetime:  number?,
}?): BasePart
	local cfg      = config or {}
	local speed    = cfg.Speed or 400
	local color    = cfg.Color or Module.DefaultTracerColor
	local width    = cfg.Width or Module.DefaultTracerWidth
	local lifetime = cfg.Lifetime or Module.DefaultTracerLifetime

	local part = Instance.new("Part")
	part.Anchored    = true
	part.CanCollide   = false
	part.CanQuery     = false
	part.CanTouch     = false
	part.Transparency = 1
	part.Size          = Vector3.new(width, width, width)
	part.CFrame         = CFrame.new(origin)
	part.Parent          = Workspace

	local a0 = Instance.new("Attachment", part)
	local a1 = Instance.new("Attachment", part)
	a1.Position = Vector3.new(0, 0, 2)

	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color         = ColorSequence.new(color)
	trail.Lifetime       = lifetime
	trail.WidthScale      = NumberSequence.new(1, 0)
	trail.Parent            = part

	local distance = (target - origin).Magnitude
	local flightTime = distance / speed

	local tween = TweenService:Create(part, TweenInfo.new(flightTime, Enum.EasingStyle.Linear), {
		CFrame = CFrame.new(target),
	})
	tween:Play()

	Debris:AddItem(part, flightTime + lifetime)
	return part
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	MUZZLE FLASH
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Briefly flashes a ParticleEmitter and PointLight parented to an attachment/part
Module.CreateMuzzleFlash = function(attachment: Attachment | BasePart, config: {
	Brightness: number?,
	Range:      number?,
	Color:      Color3?,
	Lifetime:   number?,
}?)
	local cfg       = config or {}
	local lifetime  = cfg.Lifetime or Module.DefaultFlashLifetime
	local color     = cfg.Color or Color3.fromRGB(255, 200, 120)

	local light = Instance.new("PointLight")
	light.Color       = color
	light.Brightness   = cfg.Brightness or 5
	light.Range         = cfg.Range or 12
	light.Parent          = attachment

	local emitter = attachment:FindFirstChildWhichIsA("ParticleEmitter")
	if emitter then
		emitter:Emit(1)
	end

	Debris:AddItem(light, lifetime)
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	SHELL EJECTION
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Spawns a physical shell casing at a CFrame with an outward + upward velocity,
-- lets it collide/settle briefly, then cleans it up
Module.EjectShell = function(shellTemplate: BasePart, cframe: CFrame, config: {
	Velocity:  Vector3?,
	Spin:      Vector3?,
	Lifetime:  number?,
}?): BasePart
	local cfg      = config or {}
	local lifetime = cfg.Lifetime or Module.DefaultShellLifetime

	local shell = shellTemplate:Clone()
	shell.Anchored    = false
	shell.CanCollide   = true
	shell.CFrame        = cframe
	shell.Parent          = Workspace

	local velocity = cfg.Velocity or (cframe.RightVector * Module.DefaultShellVelocity + Vector3.new(0, 4, 0))
	shell.AssemblyLinearVelocity  = velocity
	shell.AssemblyAngularVelocity = cfg.Spin or Vector3.new(math.random(-10, 10), math.random(-10, 10), math.random(-10, 10))

	Debris:AddItem(shell, lifetime)
	return shell
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	IMPACT EFFECTS
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Looks up the impact preset for a hit material, falling back to Default
Module.GetMaterialEffect = function(material: Enum.Material): {Color: Color3, Sound: string}
	return Module.MaterialEffects[material] or Module.MaterialEffects.Default
end

--► Spawns a short-lived particle burst at a hit position, oriented to the surface normal
-- Uses a template ParticleEmitter/ParticleEmitter-holding part you provide
Module.CreateImpactParticles = function(template: BasePart, position: Vector3, normal: Vector3, material: Enum.Material?)
	local effect = Module.GetMaterialEffect(material or Enum.Material.Plastic)

	local part = template:Clone()
	part.Anchored    = true
	part.CanCollide   = false
	part.CanQuery     = false
	part.Transparency = 1
	part.CFrame         = CFrame.lookAt(position, position + normal)
	part.Parent          = Workspace

	for _, descendant in ipairs(part:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			descendant.Color = ColorSequence.new(effect.Color)
			descendant:Emit(10)
		end
	end

	Debris:AddItem(part, Module.DefaultImpactLifetime)
end

--► Attaches a decal ("bullet hole") to the surface a ray hit, aligned to the surface normal
-- Fades the decal out near the end of its lifetime before removal
Module.CreateBulletHole = function(decalId: string, hitPart: BasePart, position: Vector3, normal: Vector3, config: {
	Size:     number?,
	Lifetime: number?,
}?): Part?
	if not hitPart:IsA("BasePart") then
		return nil
	end

	local cfg      = config or {}
	local size     = cfg.Size or 0.3
	local lifetime = cfg.Lifetime or Module.DefaultHoleLifetime

	local hole = Instance.new("Part")
	hole.Size          = Vector3.new(size, size, 0.02)
	hole.Anchored       = true
	hole.CanCollide      = false
	hole.CanQuery         = false
	hole.CanTouch         = false
	hole.Transparency      = 1
	hole.CFrame              = CFrame.lookAt(position + normal * 0.02, position + normal)
	hole.Parent                = Workspace

	local decal = Instance.new("Decal")
	decal.Texture = decalId
	decal.Face      = Enum.NormalId.Back
	decal.Parent      = hole

	local fadeStart = math.max(lifetime - 1.5, 0)
	task.delay(fadeStart, function()
		if hole.Parent then
			TweenService:Create(decal, TweenInfo.new(lifetime - fadeStart), {Transparency = 1}):Play()
		end
	end)

	Debris:AddItem(hole, lifetime)
	return hole
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	AUDIO
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Plays a one-shot 3D sound at a world position, then cleans up its holder part
Module.PlaySoundAt = function(soundId: string, position: Vector3, config: {
	Volume:     number?,
	Pitch:      number?,
	RollOffMax: number?,
}?): Sound
	local cfg = config or {}

	local holder = Instance.new("Part")
	holder.Anchored    = true
	holder.CanCollide   = false
	holder.CanQuery     = false
	holder.CanTouch     = false
	holder.Transparency = 1
	holder.Size          = Vector3.new(0.05, 0.05, 0.05)
	holder.CFrame          = CFrame.new(position)
	holder.Parent            = Workspace

	local sound = Instance.new("Sound")
	sound.SoundId         = soundId
	sound.Volume            = cfg.Volume or 1
	sound.PlaybackSpeed      = cfg.Pitch or 1
	sound.RollOffMaxDistance   = cfg.RollOffMax or 150
	sound.Parent                 = holder

	sound.Ended:Once(function()
		holder:Destroy()
	end)

	sound:Play()
	Debris:AddItem(holder, math.max(sound.TimeLength, 0.1) + 5)
	return sound
end

--► Plays a sound directly on an existing Instance (e.g. a gun's Fire sound on its part)
-- without cloning/positioning — use for weapon-attached sounds like fire/reload/equip
Module.PlaySoundOn = function(parent: Instance, soundId: string, config: {
	Volume: number?,
	Pitch:  number?,
}?): Sound
	local cfg = config or {}

	local sound = Instance.new("Sound")
	sound.SoundId    = soundId
	sound.Volume       = cfg.Volume or 1
	sound.PlaybackSpeed = cfg.Pitch or 1
	sound.Parent           = parent

	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)

	return sound
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	FULL IMPACT PACKAGE
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Convenience wrapper that fires off particles, a bullet hole, and a material-matched
-- sound in one call, given a RaycastResult and a table of decal/sound IDs
Module.HandleBulletImpact = function(result: RaycastResult, particleTemplate: BasePart, decalId: string?, soundTable: {[string]: string}?)
	local effect = Module.GetMaterialEffect(result.Material)

	Module.CreateImpactParticles(particleTemplate, result.Position, result.Normal, result.Material)

	if decalId then
		Module.CreateBulletHole(decalId, result.Instance, result.Position, result.Normal)
	end

	if soundTable then
		local id = soundTable[effect.Sound] or soundTable.Default
		if id then
			Module.PlaySoundAt(id, result.Position)
		end
	end
end

return Module
