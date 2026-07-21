--!nonstrict
--[[
	================================================================
	[ARMORY OS] ASSET BUILDER — Studio Plugin
	Author: DeathToTheStadium (@tostadium)
	================================================================

	# What this does

	Two tools in one dock widget:

	1. AUDIT — walks every config under Data/Configs and reports what
	   the Assets folder is missing for it: the arms rig, the weapon
	   model, category-required parts, expected FirstPerson animations
	   (per category), and ThirdPerson/R6|R15 clips. Same checks as the
	   runtime boot audit (Utilities/Core/Server/Assets), but live in
	   Studio while you're placing assets — no Play needed.

	2. BUILDER — fill in a name/category/type/arms rig and it creates
	   a ready-to-edit config ModuleScript under Data/Configs/<Category>,
	   generated from the same template shape as the shipped examples
	   (1911 / CombatSword / FragGrenade).

	# Expected project shape (found automatically anywhere under
	  ReplicatedStorage):

	  <AmoryOS root>/
	  ├─ Assets/
	  │  ├─ Rigs/            -- viewmodel arm rigs
	  │  ├─ Models/          -- weapon rigs
	  │  └─ Animations/
	  │     ├─ FirstPerson/
	  │     └─ ThirdPerson/R6|R15/
	  ├─ Data/Configs/<Category>/<WeaponId>.luau
	  └─ Utilities/...

	# NOTE on rojo: configs created by the Builder exist only in Studio
	  until you sync them back to the filesystem (rojo two-way sync or
	  copy-paste the source) — the plugin prints a reminder on create.

	# Everything lives in one script on purpose (matches EASY RIG).
]]

-- ============================================================
-- SECTION 0: SERVICES + PLUGIN BOOTSTRAP
-- ============================================================

local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local Selection            = game:GetService("Selection")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local toolbar = plugin:CreateToolbar("Armory OS Asset Builder")
local toggleButton = toolbar:CreateButton(
	"AssetBuilder",
	"Audit weapon assets / build configs",
	"rbxassetid://4458901886"
)

local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Right,
	false, false,
	340, 480,
	300, 360
)
local widget = plugin:CreateDockWidgetPluginGui("ArmoryOSAssetBuilder", widgetInfo)
widget.Title = "[ARMORY OS] Asset Builder"

toggleButton.Click:Connect(function()
	widget.Enabled = not widget.Enabled
	toggleButton:SetActive(widget.Enabled)
end)

-- ============================================================
-- SECTION 1: CONVENTIONS (mirrors Utilities/Core/Server/Assets)
-- ============================================================

local VIEWMODEL_ROOT_NAMES = { "HumanoidRootPart", "RootPart", "Root" }
local WEAPON_ROOT_NAMES    = { "Handle", "Grip" }

local REQUIRED_PARTS = {
	FireArm = { "Muzzle", "EjectShell", "Aim", "Slide" },
	Melee   = { "Blade" },
	Throw   = { "Pin" },
}

local EXPECTED_ANIMATIONS = {
	FireArm = { "Equip", "UnEquip", "Fire", "Reload" },
	Melee   = { "Equip", "UnEquip", "Swing" },
	Throw   = { "Equip", "UnEquip", "Throw" },
}

local CATEGORIES = { "FireArm", "Melee", "Throw" }

-- ============================================================
-- SECTION 2: PROJECT DISCOVERY + SAFE CONFIG REQUIRE
-- ============================================================

-- The AmoryOS root is whichever folder under ReplicatedStorage has both
-- a Data and a Utilities child — name-agnostic so renames don't break us.
local function findProjectRoot(): Instance?
	for _, descendant in ReplicatedStorage:GetDescendants() do
		if descendant:FindFirstChild("Data") and descendant:FindFirstChild("Utilities") then
			return descendant
		end
	end
	if ReplicatedStorage:FindFirstChild("Data") and ReplicatedStorage:FindFirstChild("Utilities") then
		return ReplicatedStorage
	end
	return nil
end

-- require() caches per instance, so edits to a config wouldn't show on
-- rescan. Requiring a fresh clone (parented beside the original so its
-- relative requires still resolve) sidesteps the cache; the clone is
-- destroyed immediately after.
local function requireFresh(moduleScript: ModuleScript): (boolean, any)
	local clone = moduleScript:Clone()
	clone.Name = moduleScript.Name .. "_AssetBuilderScan"
	clone.Parent = moduleScript.Parent
	clone.Archivable = false
	local ok, result = pcall(require, clone)
	clone:Destroy()
	return ok, result
end

local function findFirstNamed(model: Instance, names: { string }): BasePart?
	for _, name in ipairs(names) do
		local found = model:FindFirstChild(name, true)
		if found and found:IsA("BasePart") then
			return found
		end
	end
	return nil
end

-- ============================================================
-- SECTION 3: AUDIT LOGIC
-- ============================================================

export type AuditEntry = {
	WeaponId : string,
	Category : string,
	Problems : { string },
}

local function auditAnimations(animationsFolder: Instance?, weaponId: string, category: string, problems: { string })
	local firstPerson: { [string]: boolean } = {}
	local thirdR6, thirdR15 = 0, 0

	if animationsFolder then
		local prefix = weaponId .. "_"
		for _, descendant in animationsFolder:GetDescendants() do
			if not descendant:IsA("Animation") then
				continue
			end
			if descendant.Name:sub(1, #prefix) ~= prefix then
				continue
			end
			local animName = descendant.Name:sub(#prefix + 1)

			local thirdPerson = descendant:FindFirstAncestor("ThirdPerson")
			if thirdPerson and thirdPerson:IsDescendantOf(animationsFolder) then
				local r6  = descendant:FindFirstAncestor("R6")
				local r15 = descendant:FindFirstAncestor("R15")
				if r6 and r6:IsDescendantOf(thirdPerson) then
					thirdR6 += 1
				elseif r15 and r15:IsDescendantOf(thirdPerson) then
					thirdR15 += 1
				else
					table.insert(problems, ("'%s' sits under ThirdPerson but outside R6/R15 — it will be skipped"):format(descendant.Name))
				end
			else
				firstPerson[animName] = true
			end
		end
	end

	for _, animName in ipairs(EXPECTED_ANIMATIONS[category] or {}) do
		if not firstPerson[animName] then
			table.insert(problems, ("missing Animations/FirstPerson clip '%s_%s'"):format(weaponId, animName))
		end
	end
	if thirdR6 == 0 and thirdR15 == 0 then
		table.insert(problems, "no ThirdPerson clips for either rig type (Animations/ThirdPerson/R6|R15)")
	end
end

local function runAudit(): ({ AuditEntry }, string?)
	local root = findProjectRoot()
	if not root then
		return {}, "No AmoryOS project found under ReplicatedStorage (needs Data + Utilities children)"
	end

	local data          = root:FindFirstChild("Data")
	local configsFolder = data and data:FindFirstChild("Configs")
	if not configsFolder then
		return {}, "No Data/Configs folder found — nothing to audit"
	end

	local assets     = root:FindFirstChild("Assets")
	local rigs       = assets and assets:FindFirstChild("Rigs")
	local models     = assets and assets:FindFirstChild("Models")
	local animations = assets and assets:FindFirstChild("Animations")

	local entries: { AuditEntry } = {}

	for _, descendant in configsFolder:GetDescendants() do
		if not descendant:IsA("ModuleScript") then
			continue
		end
		if descendant.Name:match("_AssetBuilderScan$") then
			continue
		end

		local ok, config = requireFresh(descendant)
		if not ok then
			table.insert(entries, {
				WeaponId = descendant.Name,
				Category = "?",
				Problems = { "config failed to load: " .. tostring(config) },
			})
			continue
		end
		if type(config) ~= "table" or type(config.Name) ~= "string" or type(config.Category) ~= "string" then
			table.insert(entries, {
				WeaponId = descendant.Name,
				Category = "?",
				Problems = { "not a BaseConfig (missing Name/Category)" },
			})
			continue
		end

		local problems: { string } = {}
		local weaponId = config.Name
		local category = config.Category

		if config.Name ~= descendant.Name then
			table.insert(problems, ("module is named '%s' but config.Name is '%s' — tool-driven equip matches by name"):format(descendant.Name, weaponId))
		end

		if not assets then
			table.insert(problems, "no Assets folder under the project root")
		else
			-- Arms rig
			local viewModelSettings = config.ViewModelSettings
			local rigName = type(viewModelSettings) == "table" and viewModelSettings.Arms or nil
			if type(rigName) ~= "string" then
				table.insert(problems, "config has no ViewModelSettings.Arms rig name")
			elseif not rigs then
				table.insert(problems, "no Assets/Rigs folder")
			else
				local rig = rigs:FindFirstChild(rigName, true)
				if not rig or not rig:IsA("Model") then
					table.insert(problems, ("missing arms rig Assets/Rigs/%s"):format(rigName))
				elseif not findFirstNamed(rig, VIEWMODEL_ROOT_NAMES) then
					table.insert(problems, ("rig '%s' has no HumanoidRootPart/RootPart"):format(rigName))
				end
			end

			-- Weapon model + required parts
			if not models then
				table.insert(problems, "no Assets/Models folder")
			else
				local model = models:FindFirstChild(weaponId, true)
				if not model or not model:IsA("Model") then
					table.insert(problems, ("missing weapon model Assets/Models/%s"):format(weaponId))
				else
					if not findFirstNamed(model, WEAPON_ROOT_NAMES) then
						table.insert(problems, "weapon model has no Handle/Grip root")
					end
					for _, partName in ipairs(REQUIRED_PARTS[category] or {}) do
						if not model:FindFirstChild(partName, true) then
							table.insert(problems, ("weapon model is missing required part '%s'"):format(partName))
						end
					end
				end
			end

			auditAnimations(animations, weaponId, category, problems)
		end

		table.insert(entries, { WeaponId = weaponId, Category = category, Problems = problems })
	end

	table.sort(entries, function(a, b)
		return a.WeaponId < b.WeaponId
	end)
	return entries, nil
end

-- ============================================================
-- SECTION 4: CONFIG TEMPLATES (mirror the shipped examples)
-- ============================================================

-- %s slots, in order: Name(title), Category, Name, Category, plus
-- per-template extras filled by buildConfigSource.
local TEMPLATE_HEADER = [[--!nonstrict
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       %s
--  ◄► Version:     1.0
--  ◄► Author:      [ARMORY OS] Asset Builder
--  ◄► Description: Data/Configs/%s — generated BaseConfig. Tune every
--                  value; the numbers are starting points, not balance.
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
local ConfigType = require(script.Parent.Parent.Parent.Parent.Utilities.Types.Config)
local WeaponType = require(script.Parent.Parent.Parent.Parent.Utilities.Types.Weapons.%s)
type BaseConfig = ConfigType.BaseConfig
type WeaponConfig = WeaponType.Config

return {
	Name = "%s",
	Category = "%s",
]]

local TEMPLATE_FIREARM = [[
	Damage = {
		Base = 22,
		Limb = { Head = 3, Torso = 1, Arms = 0.8, Legs = 0.8, Feet = 0.8 },
	},

	CameraInfo = { DefaultFOV = 90 },

	ViewModelSettings = {
		Arms      = "%s",
		HipOffset = CFrame.new(0.4, -1, -1),
		Clothing  = { MatchCharacter = true },
		Sway      = { Intensity = 1.4, Speed = 2.5, MaxOffset = 1.8 },
		Bob       = { Intensity = 0.7, Speed = 8 },
		Breath    = { Intensity = 0.25, Speed = 1.1 },
	},

	WeaponSettings = {
		Physics = {
			Base_Velocity    = 1500,
			Gravity_Modifier = 1,
			Max_Distance     = 500,
		},

		Penetration = {
			Penetration_Count = 1,
			Material_Penetration = {
				[Enum.Material.Wood]  = { Thickness = 0.5, Power = {0.6} },
				[Enum.Material.Metal] = { Thickness = 1.5, Power = {0.2} },
			},
			Damage_Fall_Off_Start  = 25,
			Damage_Fall_Off_End    = 150,
			Ricochet_Angle_Degrees = 15,
		},

		Damage = {
			Base_Damage         = 22,
			Headshot_Multiplier = 3,
			Limb_Multiplier     = 0.8,
			Min_Damage          = 8,
			Max_Damage          = 22,
		},

		Fire = {
			Fire_Modes        = {"Semi"},
			Default_Fire_Mode = "Semi",
			Fire_Rate         = 300,
			Auto_Fire         = false,
		},

		Recoil = {
			Vertical             = 1.8,
			Horizontal           = 0.6,
			Horizontal_Variance  = 0.3,
			Recovery_Speed       = 10,
			Camera_Kick          = 0.4,
			Camera_Kick_Recovery = 12,
		},

		Spread = {
			Base_Spread          = 1,
			Max_Spread           = 4,
			Moving_Multiplier    = 1.6,
			Jumping_Multiplier   = 2.5,
			Crouching_Multiplier = 0.7,
			Aiming_Multiplier    = 0.3,
			Increase_Per_Shot    = 0.4,
			Recovery_Speed       = 8,
		},

		Reload = {
			Reload_Time          = 1.7,
			Tactical_Reload_Time = 1.5,
			Empty_Reload_Time    = 2,
			Chamber_Round        = true,
			Interruptible        = true,
		},

		Aim = {
			Aim_Fov             = 20,
			Aim_Speed           = 10,
			Aim_Sensitivity     = 0.9,
			Aim_Sway_Multiplier = 0.6,
		},

		Ammo = {
			Bullet        = "9mm",
			Ejected_Shell = "PistolShell",
			Reserve       = 90,
			In            = 12,
			Max           = 12,
		},

		Data = {
			Use_Bullets         = true,
			Use_Ray_As_Bullet   = false,
			Use_Trail_As_Bullet = true,
			Infinite_Ammo       = false,
			Infinite_Reserve    = false,
		},

		Sound = {
			Fire    = "rbxasset://sounds/paintball.wav",
			Empty   = "rbxasset://sounds/button.wav",
			Equip   = "rbxasset://sounds/unsheath.wav",
			Reload  = "rbxasset://sounds/electronicpingshort.wav",
			Aim_In  = "rbxasset://sounds/snap.wav",
			Aim_Out = "rbxasset://sounds/snap.wav",
		},

		Type = "%s",
		Behavior = {
			Akimbo = false,
		},
	} :: WeaponConfig,
} :: BaseConfig
]]

local TEMPLATE_MELEE = [[
	Damage = {
		Base = 35,
		Limb = { Head = 2, Torso = 1, Arms = 0.8, Legs = 0.8, Feet = 0.8 },
	},

	CameraInfo = { DefaultFOV = 90 },

	ViewModelSettings = {
		Arms      = "%s",
		HipOffset = CFrame.new(0.4, -0.9, -1),
		Sway      = { Intensity = 1.2, Speed = 2.5, MaxOffset = 1.8 },
		Bob       = { Intensity = 0.6, Speed = 6 },
	},

	WeaponSettings = {
		Damage = {
			Base_Damage         = 35,
			Heavy_Multiplier    = 1.8,
			Headshot_Multiplier = 2,
			Limb_Multiplier     = 0.8,
			Min_Damage          = 10,
		},

		Swing = {
			Range            = 6,
			Angle_Degrees    = 70,
			Light_Swing_Time = 0.35,
			Heavy_Swing_Time = 0.65,
			Combo_Window     = 1.2,
			Max_Combo        = 3,
		},

		Block = {
			Damage_Reduction    = 50,
			Block_Angle_Degrees = 100,
		},

		Parry = {
			Parry_Window     = 0.25,
			Stagger_Duration = 1,
		},

		Knockback = {
			Base_Force = 15,
			Scale      = 0.3,
		},

		Data = {
			Hitbox_Debug = false,
		},

		Type = "%s",
		Behavior = {},
	} :: WeaponConfig,
} :: BaseConfig
]]

local TEMPLATE_THROW = [[
	Damage = {
		Base = 100,
		Limb = { Head = 1, Torso = 1, Arms = 1, Legs = 1, Feet = 1 },
	},

	CameraInfo = { DefaultFOV = 90 },

	ViewModelSettings = {
		Arms      = "%s",
		HipOffset = CFrame.new(0.3, -0.8, -0.9),
		Sway      = { Intensity = 0.8, Speed = 2, MaxOffset = 1 },
		Bob       = { Intensity = 0.5, Speed = 6 },
	},

	WeaponSettings = {
		Physics = {
			Throw_Velocity   = 90,
			Min_Velocity     = 30,
			Gravity_Modifier = 1,
			Max_Distance     = 120,
		},

		Damage = {
			Explosion_Radius       = 18,
			Explosion_Damage       = 100,
			Explosion_Falloff      = true,
			Min_Damage             = 10,
			Headshot_Multiplier    = 1,
			Limb_Multiplier        = 1,
			Requires_Line_Of_Sight = true,
		},

		Fuse = {
			Fuse_Time          = 3.5,
			Cookable           = true,
			Detonate_On_Impact = false,
		},

		Inventory = {
			Max_Capacity   = 2,
			Count          = 2,
			Consume_On_Use = true,
		},

		Type = "%s",
		Behavior = {},
	} :: WeaponConfig,
} :: BaseConfig
]]

local TEMPLATE_BODIES = {
	FireArm = TEMPLATE_FIREARM,
	Melee   = TEMPLATE_MELEE,
	Throw   = TEMPLATE_THROW,
}

local function buildConfigSource(name: string, category: string, weaponType: string, arms: string): string
	local header = TEMPLATE_HEADER:format(name, category, category, name, category)
	local body = TEMPLATE_BODIES[category]:format(arms, weaponType)
	return header .. body
end

-- ============================================================
-- SECTION 5: UI HELPERS
-- ============================================================

local COLOR_BG        = Color3.fromRGB(35, 35, 38)
local COLOR_PANEL     = Color3.fromRGB(46, 46, 50)
local COLOR_FIELD     = Color3.fromRGB(28, 28, 30)
local COLOR_TEXT      = Color3.fromRGB(225, 225, 228)
local COLOR_DIM       = Color3.fromRGB(150, 150, 155)
local COLOR_ACCENT    = Color3.fromRGB(0, 162, 255)
local COLOR_OK        = Color3.fromRGB(90, 200, 120)
local COLOR_WARN      = Color3.fromRGB(235, 170, 60)
local COLOR_BAD       = Color3.fromRGB(235, 90, 90)

local function mk(className: string, props: { [string]: any }, parent: Instance?): Instance
	local instance = Instance.new(className)
	for key, value in props do
		(instance :: any)[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local function mkLabel(text: string, parent: Instance, props: { [string]: any }?): TextLabel
	local label = mk("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextColor3 = COLOR_TEXT,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = text,
		Size = UDim2.new(1, 0, 0, 18),
	}, parent) :: TextLabel
	for key, value in (props or {}) do
		(label :: any)[key] = value
	end
	return label
end

local function mkButton(text: string, parent: Instance, props: { [string]: any }?): TextButton
	local button = mk("TextButton", {
		BackgroundColor3 = COLOR_ACCENT,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = Color3.new(1, 1, 1),
		Text = text,
		AutoButtonColor = true,
		Size = UDim2.new(1, 0, 0, 28),
		BorderSizePixel = 0,
	}, parent) :: TextButton
	mk("UICorner", { CornerRadius = UDim.new(0, 4) }, button)
	for key, value in (props or {}) do
		(button :: any)[key] = value
	end
	return button
end

local function mkTextBox(placeholder: string, parent: Instance, props: { [string]: any }?): TextBox
	local box = mk("TextBox", {
		BackgroundColor3 = COLOR_FIELD,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextColor3 = COLOR_TEXT,
		PlaceholderText = placeholder,
		PlaceholderColor3 = COLOR_DIM,
		Text = "",
		ClearTextOnFocus = false,
		Size = UDim2.new(1, 0, 0, 26),
		BorderSizePixel = 0,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, parent) :: TextBox
	mk("UICorner", { CornerRadius = UDim.new(0, 4) }, box)
	mk("UIPadding", { PaddingLeft = UDim.new(0, 8) }, box)
	for key, value in (props or {}) do
		(box :: any)[key] = value
	end
	return box
end

local function mkScroll(parent: Instance): ScrollingFrame
	local scroll = mk("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, parent) :: ScrollingFrame
	mk("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
	}, scroll)
	mk("UIPadding", {
		PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
		PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
	}, scroll)
	return scroll
end

-- ============================================================
-- SECTION 6: WIDGET LAYOUT — tab bar + two pages
-- ============================================================

local rootFrame = mk("Frame", {
	BackgroundColor3 = COLOR_BG,
	BorderSizePixel = 0,
	Size = UDim2.new(1, 0, 1, 0),
}, widget) :: Frame

local tabBar = mk("Frame", {
	BackgroundColor3 = COLOR_PANEL,
	BorderSizePixel = 0,
	Size = UDim2.new(1, 0, 0, 32),
}, rootFrame) :: Frame
mk("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	SortOrder = Enum.SortOrder.LayoutOrder,
}, tabBar)

local pageHolder = mk("Frame", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 0, 0, 32),
	Size = UDim2.new(1, 0, 1, -32),
}, rootFrame) :: Frame

local auditPage = mk("Frame", {
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 1, 0),
	Visible = true,
}, pageHolder) :: Frame

local builderPage = mk("Frame", {
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 1, 0),
	Visible = false,
}, pageHolder) :: Frame

local tabButtons: { [string]: TextButton } = {}
local pages: { [string]: Frame } = { Audit = auditPage, Builder = builderPage }

local function selectTab(tabName: string)
	for name, page in pages do
		page.Visible = (name == tabName)
		tabButtons[name].BackgroundColor3 = if name == tabName then COLOR_BG else COLOR_PANEL
		tabButtons[name].TextColor3 = if name == tabName then COLOR_ACCENT else COLOR_DIM
	end
end

for index, tabName in ipairs({ "Audit", "Builder" }) do
	local button = mk("TextButton", {
		BackgroundColor3 = COLOR_PANEL,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = COLOR_DIM,
		Text = tabName,
		Size = UDim2.new(0.5, 0, 1, 0),
		LayoutOrder = index,
	}, tabBar) :: TextButton
	tabButtons[tabName] = button
	button.MouseButton1Click:Connect(function()
		selectTab(tabName)
	end)
end
selectTab("Audit")

-- ============================================================
-- SECTION 7: AUDIT PAGE
-- ============================================================

local auditTopBar = mk("Frame", {
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 44),
}, auditPage) :: Frame
mk("UIPadding", {
	PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 8),
}, auditTopBar)

local rescanButton = mkButton("Rescan", auditTopBar)

local auditListHolder = mk("Frame", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 0, 0, 44),
	Size = UDim2.new(1, 0, 1, -44),
}, auditPage) :: Frame
local auditList = mkScroll(auditListHolder)

local function clearAuditList()
	for _, child in auditList:GetChildren() do
		if child:IsA("Frame") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end
end

local function renderAudit()
	clearAuditList()
	local entries, fatal = runAudit()

	if fatal then
		mkLabel(fatal, auditList, { TextColor3 = COLOR_BAD, TextWrapped = true, Size = UDim2.new(1, 0, 0, 40) })
		return
	end
	if #entries == 0 then
		mkLabel("No configs found under Data/Configs.", auditList, { TextColor3 = COLOR_DIM })
		return
	end

	for order, entry in ipairs(entries) do
		local problemCount = #entry.Problems
		local card = mk("Frame", {
			BackgroundColor3 = COLOR_PANEL,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = order,
		}, auditList) :: Frame
		mk("UICorner", { CornerRadius = UDim.new(0, 5) }, card)
		mk("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }, card)
		mk("UIPadding", {
			PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
			PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
		}, card)

		local statusColor = if problemCount == 0 then COLOR_OK
			elseif problemCount <= 3 then COLOR_WARN
			else COLOR_BAD
		local statusText = if problemCount == 0 then "✓ all assets present"
			else ("%d issue%s"):format(problemCount, problemCount == 1 and "" or "s")

		mkLabel(("%s  [%s]"):format(entry.WeaponId, entry.Category), card, {
			Font = Enum.Font.GothamBold,
			TextSize = 14,
			LayoutOrder = 1,
		})
		mkLabel(statusText, card, {
			TextColor3 = statusColor,
			TextSize = 12,
			LayoutOrder = 2,
		})

		for problemIndex, problem in ipairs(entry.Problems) do
			mkLabel("• " .. problem, card, {
				TextColor3 = COLOR_DIM,
				TextSize = 12,
				TextWrapped = true,
				AutomaticSize = Enum.AutomaticSize.Y,
				Size = UDim2.new(1, 0, 0, 0),
				LayoutOrder = 2 + problemIndex,
			})
		end
	end
end

rescanButton.MouseButton1Click:Connect(renderAudit)
widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	if widget.Enabled then
		renderAudit()
	end
end)

-- ============================================================
-- SECTION 8: BUILDER PAGE
-- ============================================================

local builderScrollHolder = mk("Frame", {
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 1, 0),
}, builderPage) :: Frame
local builderForm = mkScroll(builderScrollHolder)

mkLabel("Weapon name (config module + tool name):", builderForm, { LayoutOrder = 1, TextColor3 = COLOR_DIM, TextSize = 12 })
local nameBox = mkTextBox("e.g. AK47", builderForm, { LayoutOrder = 2 })

mkLabel("Category:", builderForm, { LayoutOrder = 3, TextColor3 = COLOR_DIM, TextSize = 12 })
local categoryRow = mk("Frame", {
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 26),
	LayoutOrder = 4,
}, builderForm) :: Frame
mk("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 4),
}, categoryRow)

local selectedCategory = "FireArm"
local categoryButtons: { [string]: TextButton } = {}
local function selectCategory(category: string)
	selectedCategory = category
	for name, button in categoryButtons do
		button.BackgroundColor3 = if name == category then COLOR_ACCENT else COLOR_FIELD
		button.TextColor3 = if name == category then Color3.new(1, 1, 1) else COLOR_DIM
	end
end
for index, category in ipairs(CATEGORIES) do
	local button = mkButton(category, categoryRow, {
		Size = UDim2.new(1 / #CATEGORIES, -3, 1, 0),
		LayoutOrder = index,
		BackgroundColor3 = COLOR_FIELD,
		TextColor3 = COLOR_DIM,
		TextSize = 12,
	})
	categoryButtons[category] = button
	button.MouseButton1Click:Connect(function()
		selectCategory(category)
	end)
end
selectCategory("FireArm")

mkLabel("Weapon type (e.g. Pistol / Sword / Grenade):", builderForm, { LayoutOrder = 5, TextColor3 = COLOR_DIM, TextSize = 12 })
local typeBox = mkTextBox("e.g. Pistol", builderForm, { LayoutOrder = 6 })

mkLabel("Arms rig name (Assets/Rigs/<name>):", builderForm, { LayoutOrder = 7, TextColor3 = COLOR_DIM, TextSize = 12 })
local armsBox = mkTextBox("e.g. Classic", builderForm, { LayoutOrder = 8 })

local createButton = mkButton("Create Config", builderForm, { LayoutOrder = 9 })

local builderStatus = mkLabel("", builderForm, {
	LayoutOrder = 10,
	TextWrapped = true,
	AutomaticSize = Enum.AutomaticSize.Y,
	Size = UDim2.new(1, 0, 0, 0),
	TextSize = 12,
})

local function setBuilderStatus(text: string, color: Color3)
	builderStatus.Text = text
	builderStatus.TextColor3 = color
end

createButton.MouseButton1Click:Connect(function()
	local name = nameBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
	local weaponType = typeBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
	local arms = armsBox.Text:gsub("^%s+", ""):gsub("%s+$", "")

	if name == "" then
		setBuilderStatus("Weapon name is required.", COLOR_BAD)
		return
	end
	if name:match('[%c"\\]') then
		setBuilderStatus("Weapon name contains invalid characters.", COLOR_BAD)
		return
	end
	if weaponType == "" then
		weaponType = if selectedCategory == "FireArm" then "Pistol"
			elseif selectedCategory == "Melee" then "Sword"
			else "Grenade"
	end
	if arms == "" then
		arms = "Classic"
	end

	local root = findProjectRoot()
	if not root then
		setBuilderStatus("No AmoryOS project found under ReplicatedStorage.", COLOR_BAD)
		return
	end
	local data = root:FindFirstChild("Data")
	local configsFolder = data and data:FindFirstChild("Configs")
	if not configsFolder then
		setBuilderStatus("No Data/Configs folder found.", COLOR_BAD)
		return
	end

	if configsFolder:FindFirstChild(name, true) then
		setBuilderStatus(("A config named '%s' already exists."):format(name), COLOR_BAD)
		return
	end

	local recording = ChangeHistoryService:TryBeginRecording("AssetBuilderCreateConfig", "Create Armory OS config")

	local categoryFolder = configsFolder:FindFirstChild(selectedCategory)
	if not categoryFolder then
		categoryFolder = Instance.new("Folder")
		categoryFolder.Name = selectedCategory
		categoryFolder.Parent = configsFolder
	end

	local moduleScript = Instance.new("ModuleScript")
	moduleScript.Name = name
	moduleScript.Source = buildConfigSource(name, selectedCategory, weaponType, arms)
	moduleScript.Parent = categoryFolder

	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end

	Selection:Set({ moduleScript })
	setBuilderStatus(
		("Created Data/Configs/%s/%s. Remember: this only exists in Studio — sync it back to src/Data/Configs before the next rojo sync overwrites it."):format(selectedCategory, name),
		COLOR_OK
	)
	print(("[Asset Builder] Created config '%s' (%s). Sync it back to the filesystem (src/Data/Configs/%s/%s.luau) to keep it."):format(name, selectedCategory, selectedCategory, name))

	renderAudit()
end)

-- Initial scan if the widget starts enabled
if widget.Enabled then
	renderAudit()
end
