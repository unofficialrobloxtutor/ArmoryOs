--!strict
--[[
	================================================================
	GUN RIG / VIEWMODEL BUILDER — Studio Plugin
	Author: DeathToTheStadium (@tostadium)
	================================================================

	# What this does

	Point it at a Model. It finds your gun parts (Handle/Grip, Slide,
	Magazine, Muzzle, Aim, EjectShell, Hinge_#), validates that every
	part's aim direction agrees with the Handle's aim direction, then
	welds/Motor6Ds everything together. It also welds cosmetic Weld
	folders (Body, Grip, Magazine, Slide, Hinge_#) onto their matching
	parts, and can build a ViewModel rig (HumanoidRootPart or plain
	root, AnimationController, arms) with accessory attachment points.

	# Naming convention (case-insensitive matching, exact spelling)

	Structural parts (direct children of the gun Model, BaseParts):
		Handle | Grip        -- exactly one of these two, the root
		Slide
		Magazine
		Muzzle
		Aim
		EjectShell
		Hinge_1, Hinge_2, ...  -- any count, for slide stops/hammers/etc

	Cosmetic weld folders (direct children of the gun Model, Folders):
		Body       -> every part inside welds to Handle/Grip
		Grip       -> every part inside welds to Handle/Grip
		Magazine   -> every part inside welds to the Magazine part
		Slide      -> every part inside welds to the Slide part
		Hinge_#    -> every part inside welds to the matching Hinge_# part

	Everything is optional except Handle/Grip. Missing parts are
	skipped, not errored.

	# Direction check

	Every structural part's "aim vector" is assumed to be its local
	+Z (LookVector), matching typical gun/tool forward convention.
	Before building any Motor6D, the plugin dot-products each part's
	world LookVector against the Handle/Grip's world LookVector. If
	the dot product is negative (facing opposite-ish, >90° apart) it's
	flagged. You get a warning per part and a summary before build;
	nothing is silently welded backwards.

	# Everything lives in one script on purpose (per spec).
]]

-- ============================================================
-- SECTION 0: SERVICES + PLUGIN BOOTSTRAP
-- ============================================================

local Selection = game:GetService("Selection")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local CoreGui = game:GetService("CoreGui")
local MarketplaceService = game:GetService("MarketplaceService")

local toolbar = plugin:CreateToolbar("Gun Rig Builder")
local toggleButton = toolbar:CreateButton(
	"Rig Builder",
	"Open the Gun Rig / ViewModel Builder",
	"rbxassetid://4458901886"
)
toggleButton.ClickableWhenViewportHidden = true

-- ============================================================
-- SECTION 1: CONSTANTS
-- ============================================================

local STRUCTURAL_NAMES = {
	"Handle", "Grip", "Slide", "Magazine", "Muzzle", "Aim", "EjectShell",
}

local WELD_FOLDER_NAMES = {
	"Body", "Grip", "Magazine", "Slide",
}

local HINGE_PATTERN = "^[Hh]inge_(%d+)$"

local DOT_WARN_THRESHOLD = 0 -- dot <= this counts as "wrong direction"

-- ============================================================
-- SECTION 2: TYPES
-- ============================================================

type FoundParts = {
	root: BasePart?,        -- the Handle or Grip, whichever was found
	rootKind: string,       -- "Handle" | "Grip" | "none"
	slide: BasePart?,
	magazine: BasePart?,
	muzzle: BasePart?,
	aim: BasePart?,
	ejectShell: BasePart?,
	hinges: { [number]: BasePart }, -- keyed by hinge number
}

type WeldFolders = {
	Body: Folder?,
	Grip: Folder?,
	Magazine: Folder?,
	Slide: Folder?,
	hinges: { [number]: Folder },
}

type DirectionIssue = {
	partName: string,
	dot: number,
}

type LogLevel = "info" | "warn" | "error" | "success"

type LogEntry = {
	level: LogLevel,
	text: string,
}

-- ============================================================
-- SECTION 3: SMALL UTILITIES
-- ============================================================

local function isBasePart(inst: Instance): boolean
	return inst:IsA("BasePart")
end

local function findChildIgnoreCase(parent: Instance, name: string): Instance?
	local lowerName = string.lower(name)
	for _, child in ipairs(parent:GetChildren()) do
		if string.lower(child.Name) == lowerName then
			return child
		end
	end
	return nil
end

local function parseHingeNumber(name: string): number?
	local numStr = string.match(name, HINGE_PATTERN)
	if numStr then
		return tonumber(numStr)
	end
	return nil
end

-- Round-trip-safe float format for the UI log
local function fmtDot(n: number): string
	return string.format("%.3f", n)
end

-- ============================================================
-- SECTION 4: SCANNING THE MODEL
-- ============================================================

-- Scans for structural parts + weld folders. Looks at the model's
-- direct children first; if a 'Main' folder exists (from a previous
-- build moving everything there), also checks inside it and prefers
-- whichever copy is found. This keeps re-scan/re-build idempotent
-- after the first build reorganizes parts into Main. Does NOT recurse
-- into weld folders here; that happens at build time.
local function scanModel(model: Model): (FoundParts, WeldFolders, { string })
	local found: FoundParts = {
		root = nil,
		rootKind = "none",
		slide = nil,
		magazine = nil,
		muzzle = nil,
		aim = nil,
		ejectShell = nil,
		hinges = {},
	}

	local folders: WeldFolders = {
		Body = nil,
		Grip = nil,
		Magazine = nil,
		Slide = nil,
		hinges = {},
	}

	local notes: { string } = {}

	-- If a previous build already created Main, search there too —
	-- direct-child results still win if somehow present in both places.
	local mainInst = findChildIgnoreCase(model, "Main")
	local searchRoots: { Instance } = { model }
	if mainInst and mainInst:IsA("Folder") then
		table.insert(searchRoots, mainInst)
	end

	local function findAcrossRoots(name: string): Instance?
		for _, root in ipairs(searchRoots) do
			local hit = findChildIgnoreCase(root, name)
			if hit then
				return hit
			end
		end
		return nil
	end

	-- Handle / Grip (root) — prefer "Handle" if both exist, warn about it
	local handleInst = findAcrossRoots("Handle")
	local gripInst = findAcrossRoots("Grip")

	local handleIsPart = handleInst ~= nil and isBasePart(handleInst)
	local gripIsPart = gripInst ~= nil and isBasePart(gripInst)

	if handleIsPart and gripIsPart then
		found.root = handleInst :: BasePart
		found.rootKind = "Handle"
		table.insert(notes, "Both a 'Handle' part and a 'Grip' part were found. Using 'Handle' as the root and treating the 'Grip' part as a duplicate root candidate — only one grip/handle is supported as the root. If 'Grip' was meant to be a cosmetic weld target, rename it or move it into a weld Folder named 'Grip' instead.")
	elseif handleIsPart then
		found.root = handleInst :: BasePart
		found.rootKind = "Handle"
	elseif gripIsPart then
		found.root = gripInst :: BasePart
		found.rootKind = "Grip"
	end

	-- Other structural parts
	local slideInst = findAcrossRoots("Slide")
	if slideInst and isBasePart(slideInst) then
		found.slide = slideInst :: BasePart
	end

	local magInst = findAcrossRoots("Magazine")
	if magInst and isBasePart(magInst) then
		found.magazine = magInst :: BasePart
	end

	local muzzleInst = findAcrossRoots("Muzzle")
	if muzzleInst and isBasePart(muzzleInst) then
		found.muzzle = muzzleInst :: BasePart
	end

	local aimInst = findAcrossRoots("Aim")
	if aimInst and isBasePart(aimInst) then
		found.aim = aimInst :: BasePart
	end

	local ejectInst = findAcrossRoots("EjectShell")
	if ejectInst and isBasePart(ejectInst) then
		found.ejectShell = ejectInst :: BasePart
	end

	-- Hinges + weld folders (single pass over children of each search
	-- root). "Constraints" and "Main" are skipped as candidates here so
	-- the plugin's own organizational folders never get misread as a
	-- weld-source folder or a re-scanned duplicate.
	local seenChildren: { [Instance]: boolean } = {}
	for _, searchRoot in ipairs(searchRoots) do
		for _, child in ipairs(searchRoot:GetChildren()) do
			if seenChildren[child] then
				continue
			end
			seenChildren[child] = true

			local lowerChildName = string.lower(child.Name)
			if lowerChildName == "constraints" or lowerChildName == "main" then
				continue
			end

			local hingeNum = parseHingeNumber(child.Name)
			if hingeNum then
				if isBasePart(child) then
					if found.hinges[hingeNum] then
						table.insert(notes, string.format("Multiple parts named 'Hinge_%d' found. Only the first one encountered is used.", hingeNum))
					else
						found.hinges[hingeNum] = child :: BasePart
					end
				elseif child:IsA("Folder") then
					folders.hinges[hingeNum] = child :: Folder
				end
				continue
			end

			if child:IsA("Folder") then
				local lowerName = string.lower(child.Name)
				if lowerName == "body" then
					folders.Body = child :: Folder
				elseif lowerName == "grip" then
					folders.Grip = child :: Folder
				elseif lowerName == "magazine" then
					folders.Magazine = child :: Folder
				elseif lowerName == "slide" then
					folders.Slide = child :: Folder
				end
			end
		end
	end

	return found, folders, notes
end

-- ============================================================
-- SECTION 5: DIRECTION VALIDATION
-- ============================================================

-- Compares every found structural part's world LookVector against the
-- root's world LookVector. Returns a list of parts whose dot product
-- is at/below threshold (i.e. pointing the "wrong" way relative to the
-- root), plus a full report table of every part checked either way.
local function validateDirections(found: FoundParts): ({ DirectionIssue }, { DirectionIssue })
	local issues: { DirectionIssue } = {}
	local allChecked: { DirectionIssue } = {}

	if not found.root then
		return issues, allChecked
	end

	local rootLook = found.root.CFrame.LookVector

	local function check(part: BasePart?, label: string)
		if not part then
			return
		end
		local dot = rootLook:Dot(part.CFrame.LookVector)
		table.insert(allChecked, { partName = label, dot = dot })
		if dot <= DOT_WARN_THRESHOLD then
			table.insert(issues, { partName = label, dot = dot })
		end
	end

	check(found.slide, "Slide")
	check(found.magazine, "Magazine")
	check(found.muzzle, "Muzzle")
	check(found.aim, "Aim")
	check(found.ejectShell, "EjectShell")

	local hingeNums: { number } = {}
	for num in pairs(found.hinges) do
		table.insert(hingeNums, num)
	end
	table.sort(hingeNums)
	for _, num in ipairs(hingeNums) do
		check(found.hinges[num], string.format("Hinge_%d", num))
	end

	return issues, allChecked
end

-- ============================================================
-- SECTION 6: MOTOR6D + WELD CONSTRUCTION
-- ============================================================

-- Builds (or replaces) a Motor6D between root and part. Named
-- "<PartName>Motor". C0/C1 computed so the part doesn't move when the
-- motor is inserted. `destination` is where the Motor6D instance is
-- parented (e.g. a Constraints/Motor6Ds folder) rather than onto the
-- moving part itself — Motor6Ds work regardless of their own parent,
-- only Part0/Part1 matter for the actual joint.
local function buildMotor6D(root: BasePart, part: BasePart, motorName: string, destination: Instance)
	-- Clear any existing motor with this name in the destination folder
	local existing = destination:FindFirstChild(motorName)
	if existing then
		existing:Destroy()
	end

	local motor = Instance.new("Motor6D")
	motor.Name = motorName
	motor.Part0 = root
	motor.Part1 = part
	-- C0 relative to root, C1 identity, so the part's current world
	-- position is preserved on build.
	motor.C0 = root.CFrame:ToObjectSpace(part.CFrame)
	motor.C1 = CFrame.new()
	motor.Parent = destination
	return motor
end

-- Welds every BasePart inside `folder` (recursively) to `target`, using
-- WeldConstraint. Skips the target itself if it happens to live inside
-- the folder. `destination` is where each WeldConstraint instance is
-- parented (e.g. a Constraints/Welds folder) — WeldConstraints work
-- regardless of their own parent, only Part0/Part1 matter. Weld names
-- are disambiguated with the descendant's name so re-running the build
-- can find and replace the right one instead of colliding across parts.
--
-- Along with wiring the weld, each welded part gets its animation-
-- optimal settings applied: Anchored=false so the weld actually holds,
-- Massless=true so the extra part doesn't drag on the Motor6D's
-- movement, and CanCollide/CanQuery/CanTouch all disabled since cosmetic
-- welded pieces shouldn't participate in physics queries. Users who
-- want any of those behaviors on a specific part can restore them
-- manually after the build.
--
-- Returns count welded.
local function weldFolderTo(folder: Folder, target: BasePart, destination: Instance): number
	local count = 0
	for _, descendant in ipairs(folder:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant ~= target then
			local weldName = "_RigBuilderWeld_" .. descendant.Name
			local existing = destination:FindFirstChild(weldName)
			if existing then
				existing:Destroy()
			end
			local weld = Instance.new("WeldConstraint")
			weld.Name = weldName
			weld.Part0 = target
			weld.Part1 = descendant
			weld.Parent = destination

			-- Animation-optimal settings for a welded cosmetic part
			descendant.Anchored = false
			descendant.Massless = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false

			count += 1
		end
	end
	return count
end

-- ============================================================
-- SECTION 7: BUILD PIPELINE (structural motors + cosmetic welds)
-- ============================================================

type BuildOptions = {
	buildStructuralMotors: boolean,
	buildCosmeticWelds: boolean,
	ignoreDirectionWarnings: boolean,
}

type BuildResult = {
	ok: boolean,
	log: { LogEntry },
	motorsBuilt: number,
	weldsBuilt: number,
}

-- Gets or creates the fixed organizational folders under the gun
-- model: Constraints/Motor6Ds, Constraints/Welds, and Main. Safe to
-- call on a model that already has them from a previous build — it
-- reuses what's there instead of duplicating.
local function ensureOrganizationFolders(model: Model): (Folder, Folder, Folder)
	local constraints = model:FindFirstChild("Constraints")
	if not (constraints and constraints:IsA("Folder")) then
		constraints = Instance.new("Folder")
		constraints.Name = "Constraints"
		constraints.Parent = model
	end
	local constraintsFolder = constraints :: Folder

	local motor6dsFolder = constraintsFolder:FindFirstChild("Motor6Ds")
	if not (motor6dsFolder and motor6dsFolder:IsA("Folder")) then
		motor6dsFolder = Instance.new("Folder")
		motor6dsFolder.Name = "Motor6Ds"
		motor6dsFolder.Parent = constraintsFolder
	end

	local weldsFolder = constraintsFolder:FindFirstChild("Welds")
	if not (weldsFolder and weldsFolder:IsA("Folder")) then
		weldsFolder = Instance.new("Folder")
		weldsFolder.Name = "Welds"
		weldsFolder.Parent = constraintsFolder
	end

	local mainFolder = model:FindFirstChild("Main")
	if not (mainFolder and mainFolder:IsA("Folder")) then
		mainFolder = Instance.new("Folder")
		mainFolder.Name = "Main"
		mainFolder.Parent = model
	end

	return motor6dsFolder :: Folder, weldsFolder :: Folder, mainFolder :: Folder
end

local function buildGunRig(model: Model, options: BuildOptions): BuildResult
	local log: { LogEntry } = {}
	local motorsBuilt = 0
	local weldsBuilt = 0

	local function say(level: LogLevel, text: string)
		table.insert(log, { level = level, text = text })
	end

	local found, folders, notes = scanModel(model)

	for _, note in ipairs(notes) do
		say("warn", note)
	end

	if not found.root then
		say("error", "No 'Handle' or 'Grip' part found as a direct child of the model. Exactly one is required as the root. Aborting build.")
		return { ok = false, log = log, motorsBuilt = 0, weldsBuilt = 0 }
	end

	say("info", string.format("Root part: '%s' (%s)", found.root.Name, found.rootKind))

	-- Direction validation
	local issues, allChecked = validateDirections(found)
	for _, checked in ipairs(allChecked) do
		if checked.dot <= DOT_WARN_THRESHOLD then
			say("warn", string.format("'%s' LookVector dot product with root = %s (facing away from/across the root's forward direction). This part will likely animate backwards or sideways relative to the gun's fire direction. Check its orientation before firing.", checked.partName, fmtDot(checked.dot)))
		else
			say("info", string.format("'%s' direction OK (dot = %s)", checked.partName, fmtDot(checked.dot)))
		end
	end

	if #issues > 0 and not options.ignoreDirectionWarnings then
		say("error", string.format("%d part(s) failed the direction check against root '%s'. Fix orientation or enable 'Build anyway' to proceed despite warnings.", #issues, found.root.Name))
		return { ok = false, log = log, motorsBuilt = 0, weldsBuilt = 0 }
	end

	-- Organizational folders: Constraints/Motor6Ds, Constraints/Welds, Main
	local motor6dsFolder, weldsFolder, mainFolder = ensureOrganizationFolders(model)
	say("info", "Constraints/Motor6Ds, Constraints/Welds, and Main folders ready.")

	-- Structural Motor6Ds: everything found (except root) connects to root.
	-- Motors are parented into Constraints/Motor6Ds, not onto the parts
	-- themselves — Part0/Part1 define the joint regardless of where the
	-- Motor6D instance lives.
	if options.buildStructuralMotors then
		local function motorFor(part: BasePart?, label: string)
			if not part then
				return
			end
			buildMotor6D(found.root :: BasePart, part, label .. "Motor", motor6dsFolder)
			motorsBuilt += 1
			say("success", string.format("Motor6D built: %s -> %s", found.root.Name, label))
		end

		motorFor(found.slide, "Slide")
		motorFor(found.magazine, "Magazine")
		motorFor(found.muzzle, "Muzzle")
		motorFor(found.aim, "Aim")
		motorFor(found.ejectShell, "EjectShell")

		local hingeNums: { number } = {}
		for num in pairs(found.hinges) do
			table.insert(hingeNums, num)
		end
		table.sort(hingeNums)
		for _, num in ipairs(hingeNums) do
			motorFor(found.hinges[num], string.format("Hinge_%d", num))
		end
	else
		say("info", "Skipped structural Motor6D construction (disabled in options).")
	end

	-- Cosmetic weld folders. WeldConstraints are parented into
	-- Constraints/Welds rather than onto the welded part.
	if options.buildCosmeticWelds then
		if folders.Body then
			local c = weldFolderTo(folders.Body, found.root :: BasePart, weldsFolder)
			weldsBuilt += c
			say("success", string.format("Body folder: welded %d part(s) to %s", c, found.root.Name))
		end
		if folders.Grip then
			local c = weldFolderTo(folders.Grip, found.root :: BasePart, weldsFolder)
			weldsBuilt += c
			say("success", string.format("Grip folder: welded %d part(s) to %s", c, found.root.Name))
		end
		if folders.Magazine then
			if found.magazine then
				local c = weldFolderTo(folders.Magazine, found.magazine, weldsFolder)
				weldsBuilt += c
				say("success", string.format("Magazine folder: welded %d part(s) to Magazine", c))
			else
				say("warn", "A 'Magazine' weld folder exists but no 'Magazine' structural part was found. Skipped.")
			end
		end
		if folders.Slide then
			if found.slide then
				local c = weldFolderTo(folders.Slide, found.slide, weldsFolder)
				weldsBuilt += c
				say("success", string.format("Slide folder: welded %d part(s) to Slide", c))
			else
				say("warn", "A 'Slide' weld folder exists but no 'Slide' structural part was found. Skipped.")
			end
		end

		local hingeFolderNums: { number } = {}
		for num in pairs(folders.hinges) do
			table.insert(hingeFolderNums, num)
		end
		table.sort(hingeFolderNums)
		for _, num in ipairs(hingeFolderNums) do
			local hingePart = found.hinges[num]
			local hingeFolder = folders.hinges[num]
			if hingePart then
				local c = weldFolderTo(hingeFolder, hingePart, weldsFolder)
				weldsBuilt += c
				say("success", string.format("Hinge_%d folder: welded %d part(s) to Hinge_%d", num, c, num))
			else
				say("warn", string.format("A 'Hinge_%d' weld folder exists but no matching 'Hinge_%d' part was found. Skipped.", num, num))
			end
		end
	else
		say("info", "Skipped cosmetic weld construction (disabled in options).")
	end

	-- Move the weld-source folders into Main; leave the animation parts
	-- (Handle/Grip root, Slide, Magazine, Muzzle, Aim, EjectShell,
	-- Hinge_#) at the top of the model where AnimationTracks and other
	-- runtime lookups by name expect to find them. WeldConstraints and
	-- Motor6Ds already point at parts by reference, so moving the
	-- source folders doesn't break any joint.
	do
		local movedCount = 0

		local function moveToMain(inst: Instance?)
			if inst and inst.Parent ~= mainFolder then
				inst.Parent = mainFolder
				movedCount += 1
			end
		end

		moveToMain(folders.Body)
		moveToMain(folders.Grip)
		moveToMain(folders.Magazine)
		moveToMain(folders.Slide)

		local hingeFolderNumsForMove: { number } = {}
		for num in pairs(folders.hinges) do
			table.insert(hingeFolderNumsForMove, num)
		end
		table.sort(hingeFolderNumsForMove)
		for _, num in ipairs(hingeFolderNumsForMove) do
			moveToMain(folders.hinges[num])
		end

		if movedCount > 0 then
			say("info", string.format("Moved %d weld-source folder(s) into Main.", movedCount))
		end
	end

	say("success", string.format("Build complete: %d Motor6D(s), %d weld(s).", motorsBuilt, weldsBuilt))
	return { ok = true, log = log, motorsBuilt = motorsBuilt, weldsBuilt = weldsBuilt }
end

-- ============================================================
-- SECTION 8: VIEWMODEL RIG CONSTRUCTION
-- ============================================================

-- The four ViewModel presets. Each corresponds to a Model that should
-- live as a child of this plugin script at:
--   script.ViewModels.DefaultR6
--   script.ViewModels.DefaultR15
--   script.ViewModels.CustomMeshR6
--   script.ViewModels.CustomMeshR15
--
-- When buildViewModel runs it clones the matching Model from there and
-- applies color / shirt / accessory slots on top. If the child Model is
-- missing (e.g. the user hasn't imported their custom mesh yet) it falls
-- back to the procedural cube-part builder for that type.
--
-- How to add your custom mesh arms:
--   1. Build or import your arm Model into the Explorer.
--   2. In the Plugin script hierarchy, create a Folder called ViewModels
--      under this script (use the Explorer).
--   3. Parent your Model(s) into that Folder with the exact names above.
--   4. The plugin will use them automatically on next run.
local RIG_TYPES = { "DefaultR6", "DefaultR15", "CustomMeshR6", "CustomMeshR15" }

type LimbSpec = {
	name: string,
	parentLimb: string?, -- nil = attaches to the rig's root part
	motorName: string,
	defaultSize: Vector3,
	defaultOffset: Vector3,
	isHand: boolean,
}

type RigDefinition = {
	name: string,
	rootSize: Vector3,
	limbs: { LimbSpec },
}

local RIG_DEFINITIONS: { [string]: RigDefinition } = {
	-- DefaultR6: R6-named single-bone arms, procedural fallback
	DefaultR6 = {
		name = "DefaultR6",
		rootSize = Vector3.new(2, 2, 1),
		limbs = {
			{ name = "Left Arm",  parentLimb = nil, motorName = "Left Shoulder",  defaultSize = Vector3.new(1, 2, 1), defaultOffset = Vector3.new(-1.5, -0.5, 0), isHand = true  },
			{ name = "Right Arm", parentLimb = nil, motorName = "Right Shoulder", defaultSize = Vector3.new(1, 2, 1), defaultOffset = Vector3.new( 1.5, -0.5, 0), isHand = true  },
		},
	},
	-- DefaultR15: R15-named three-bone arms, procedural fallback
	DefaultR15 = {
		name = "DefaultR15",
		rootSize = Vector3.new(2, 2, 1),
		limbs = {
			{ name = "LeftUpperArm",  parentLimb = nil,             motorName = "LeftShoulder",  defaultSize = Vector3.new(1, 1.4, 1),  defaultOffset = Vector3.new(-1.5,  0.2, 0), isHand = false },
			{ name = "LeftLowerArm",  parentLimb = "LeftUpperArm",  motorName = "LeftElbow",     defaultSize = Vector3.new(1, 1.1, 1),  defaultOffset = Vector3.new(0, -1.25, 0),   isHand = false },
			{ name = "LeftHand",      parentLimb = "LeftLowerArm",  motorName = "LeftWrist",     defaultSize = Vector3.new(1, 0.45, 1), defaultOffset = Vector3.new(0, -0.75, 0),   isHand = true  },
			{ name = "RightUpperArm", parentLimb = nil,             motorName = "RightShoulder", defaultSize = Vector3.new(1, 1.4, 1),  defaultOffset = Vector3.new( 1.5,  0.2, 0), isHand = false },
			{ name = "RightLowerArm", parentLimb = "RightUpperArm", motorName = "RightElbow",    defaultSize = Vector3.new(1, 1.1, 1),  defaultOffset = Vector3.new(0, -1.25, 0),   isHand = false },
			{ name = "RightHand",     parentLimb = "RightLowerArm", motorName = "RightWrist",    defaultSize = Vector3.new(1, 0.45, 1), defaultOffset = Vector3.new(0, -0.75, 0),   isHand = true  },
		},
	},
	-- CustomMeshR6: same motor topology as DefaultR6 — the mesh comes from
	-- script.ViewModels.CustomMeshR6; this is the procedural fallback only.
	CustomMeshR6 = {
		name = "CustomMeshR6",
		rootSize = Vector3.new(2, 2, 1),
		limbs = {
			{ name = "Left Arm",  parentLimb = nil, motorName = "Left Shoulder",  defaultSize = Vector3.new(1, 2, 1), defaultOffset = Vector3.new(-1.5, -0.5, 0), isHand = true  },
			{ name = "Right Arm", parentLimb = nil, motorName = "Right Shoulder", defaultSize = Vector3.new(1, 2, 1), defaultOffset = Vector3.new( 1.5, -0.5, 0), isHand = true  },
		},
	},
	-- CustomMeshR15: same motor topology as DefaultR15 — mesh from
	-- script.ViewModels.CustomMeshR15; this is the procedural fallback only.
	CustomMeshR15 = {
		name = "CustomMeshR15",
		rootSize = Vector3.new(2, 2, 1),
		limbs = {
			{ name = "LeftUpperArm",  parentLimb = nil,             motorName = "LeftShoulder",  defaultSize = Vector3.new(1, 1.4, 1),  defaultOffset = Vector3.new(-1.5,  0.2, 0), isHand = false },
			{ name = "LeftLowerArm",  parentLimb = "LeftUpperArm",  motorName = "LeftElbow",     defaultSize = Vector3.new(1, 1.1, 1),  defaultOffset = Vector3.new(0, -1.25, 0),   isHand = false },
			{ name = "LeftHand",      parentLimb = "LeftLowerArm",  motorName = "RightWrist",    defaultSize = Vector3.new(1, 0.45, 1), defaultOffset = Vector3.new(0, -0.75, 0),   isHand = true  },
			{ name = "RightUpperArm", parentLimb = nil,             motorName = "RightShoulder", defaultSize = Vector3.new(1, 1.4, 1),  defaultOffset = Vector3.new( 1.5,  0.2, 0), isHand = false },
			{ name = "RightLowerArm", parentLimb = "RightUpperArm", motorName = "RightElbow",    defaultSize = Vector3.new(1, 1.1, 1),  defaultOffset = Vector3.new(0, -1.25, 0),   isHand = false },
			{ name = "RightHand",     parentLimb = "RightLowerArm", motorName = "RightWrist",    defaultSize = Vector3.new(1, 0.45, 1), defaultOffset = Vector3.new(0, -0.75, 0),   isHand = true  },
		},
	},
}

type LimbOverride = {
	size: Vector3?,    -- nil = use the rig's default
	include: boolean?, -- nil or true = include; false = skip this limb
}

type ViewModelOptions = {
	name: string,
	rigType: string,
	includeRootPart: boolean,
	useHumanoidRootPart: boolean,
	rootPriority: number,
	rootCFrame: CFrame,
	includeAnimationController: boolean,
	includeHumanoid: boolean,
	accessorySlots: { string },
	limbOverrides: { [string]: LimbOverride },
	slotOffsets: { [string]: CFrame },
	armColor: Color3,        -- color applied to all limb parts
	shirtId: string,         -- rbxassetid:// for a Shirt template (applied to torso if present, else UpperTorso)
}

-- Plain cube Part for each limb — straightforward, always visible,
-- no mesh quirks. Color is passed in from ViewModelOptions.armColor.
local function makeLimbPart(name: string, size: Vector3, worldCF: CFrame, color: Color3): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = worldCF
	part.Anchored = false
	part.CanCollide = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = color
	return part
end

local function buildViewModel(vmOptions: ViewModelOptions): (Model, { LogEntry })
	local log: { LogEntry } = {}
	local function say(level: LogLevel, text: string)
		table.insert(log, { level = level, text = text })
	end

	-- ── Try to load the rig from script.ViewModels.<rigType> first ──────────
	-- If the author has placed a pre-built Model there (custom mesh arms,
	-- UV-mapped gore arms, etc.) we clone it and layer color/shirt/slots on
	-- top instead of building procedurally. This is the primary path for
	-- DefaultR6 / DefaultR15 / CustomMeshR6 / CustomMeshR15.
	local vmFolder = script:FindFirstChild("ViewModels")
	local sourceModel: Model? = nil
	if vmFolder then
		local child = vmFolder:FindFirstChild(vmOptions.rigType)
		if child and child:IsA("Model") then
			sourceModel = child :: Model
		end
	end

	if sourceModel then
		-- Clone-based path ────────────────────────────────────────────────
		say("info", string.format("Loading '%s' from script.ViewModels.%s.", vmOptions.rigType, vmOptions.rigType))
		local vm = sourceModel:Clone()
		vm.Name = vmOptions.name ~= "" and vmOptions.name or "ViewModel"

		-- Apply arm color to every non-transparent BasePart
		for _, desc in ipairs(vm:GetDescendants()) do
			if desc:IsA("BasePart") and (desc :: BasePart).Transparency < 0.5 then
				(desc :: BasePart).Color = vmOptions.armColor
			end
		end

		-- Shirt texture via SurfaceAppearance on every non-root BasePart
		if vmOptions.shirtId and vmOptions.shirtId ~= "" then
			local numId = vmOptions.shirtId:match("(%d+)$") or vmOptions.shirtId
			local texId = "rbxassetid://" .. numId
			local count = 0
			for _, desc in ipairs(vm:GetDescendants()) do
				if desc:IsA("BasePart") and (desc :: BasePart).Transparency < 0.5 then
					local sa = Instance.new("SurfaceAppearance")
					sa.AlbedoMap = texId
					sa.Name = "ShirtTexture"
					sa.Parent = desc
					count += 1
				end
			end
			say("success", string.format("Shirt texture applied to %d part(s) via SurfaceAppearance.", count))
		end

		-- Accessory slot Attachments on hand-flagged parts.
		-- We identify hands by checking whether they already have a
		-- RightGripAttachment or LeftGripAttachment child (convention),
		-- or by name containing "Hand" / "Arm" (R6 single-bone).
		if #vmOptions.accessorySlots > 0 then
			for _, part in ipairs(vm:GetDescendants()) do
				if not part:IsA("BasePart") then continue end
				local lname = string.lower(part.Name)
				local isHand = string.find(lname, "hand") or
					(string.find(lname, "arm") and not string.find(lname, "upper") and not string.find(lname, "lower"))
				if not isHand then continue end
				local isRight = string.find(lname, "right") ~= nil
				local isLeft  = string.find(lname, "left")  ~= nil
				for _, slotName in ipairs(vmOptions.accessorySlots) do
					local sl = string.lower(slotName)
					if string.find(sl, "right") and not isRight then continue end
					if string.find(sl, "left")  and not isLeft  then continue end
					if part:FindFirstChild(slotName) then continue end -- already has it
					local att = Instance.new("Attachment")
					att.Name = slotName
					att.Parent = part
				end
			end
			say("info", "Accessory attachments added to hand parts.")
		end

		-- RootPriority and AnimController / Humanoid
		local rp = vm:FindFirstChildWhichIsA("BasePart", true)
		if vm.PrimaryPart then
			local pp = vm.PrimaryPart :: BasePart
			pp.RootPriority = vmOptions.rootPriority
		end
		if vmOptions.includeAnimationController then
			if not vm:FindFirstChildOfClass("AnimationController") then
				local ac = Instance.new("AnimationController")
				ac.Parent = vm
			end
			say("success", "AnimationController added.")
		elseif vmOptions.includeHumanoid then
			if not vm:FindFirstChildOfClass("Humanoid") then
				local hum = Instance.new("Humanoid")
				hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
				hum.Parent = vm
			end
			say("success", "Humanoid added.")
		end

		say("success", string.format("ViewModel '%s' built from script.ViewModels.%s.", vm.Name, vmOptions.rigType))
		return vm, log
	end

	-- ── Procedural fallback ──────────────────────────────────────────────────
	-- script.ViewModels.<rigType> not found — build from cube parts using
	-- the RIG_DEFINITIONS table. This is the same path as before.
	local rigDef = RIG_DEFINITIONS[vmOptions.rigType]
	if not rigDef then
		say("warn", string.format("Unknown rig type '%s' and no script.ViewModels child found — falling back to DefaultR6.", vmOptions.rigType))
		rigDef = RIG_DEFINITIONS.DefaultR6
	end
	say("info", string.format("script.ViewModels.%s not found — building procedural %s rig.", vmOptions.rigType, rigDef.name))

	local vm = Instance.new("Model")
	vm.Name = vmOptions.name ~= "" and vmOptions.name or "ViewModel"

	local originCF = vmOptions.rootCFrame or CFrame.new()

	-- Root part
	local rootPart: BasePart? = nil
	if vmOptions.includeRootPart then
		local rootName = vmOptions.useHumanoidRootPart and "HumanoidRootPart" or "Root"
		local root = Instance.new("Part")
		root.Name = rootName
		root.Size = rigDef.rootSize
		root.Transparency = 1
		root.CanCollide = false
		root.Anchored = false
		root.CastShadow = false
		root.CFrame = originCF
		root.Parent = vm
		
		rootPart = root
		rootPart.RootPriority = vmOptions.rootPriority
		vm.PrimaryPart = rootPart
		say("success", string.format("Created %s (RootPriority=%d).", rootName, vmOptions.rootPriority))
	else
		say("info", "No root part requested; limbs will hang together via Motor6Ds but the rig will have no primary anchor point.")
	end

	if vmOptions.includeAnimationController then
		local controller = Instance.new("AnimationController")
		controller.Parent = vm
		say("success", "AnimationController added.")
	elseif vmOptions.includeHumanoid then
		local hum = Instance.new("Humanoid")
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.Parent = vm
		say("success", "Humanoid added.")
	end

	-- Camera attachment on the root for viewmodel-to-camera positioning
	if rootPart then
		local camAttach = Instance.new("Attachment")
		camAttach.Name = "CameraAttachment"
		camAttach.Parent = rootPart
	end

	-- Pass 1: create every included limb part and record world CFrames
	-- so pass 2 can wire Motor6Ds using each part's actual placement.
	-- Included status resolves per-limb overrides against the rig def.
	local createdLimbs: { [string]: BasePart } = {}
	local limbSizes: { [string]: Vector3 } = {}

	local function limbIsIncluded(spec: LimbSpec): boolean
		local override = vmOptions.limbOverrides[spec.name]
		if override and override.include == false then
			return false
		end
		return true
	end

	local function limbSize(spec: LimbSpec): Vector3
		local override = vmOptions.limbOverrides[spec.name]
		if override and override.size then
			return override.size
		end
		return spec.defaultSize
	end

	-- Recursive resolver for world CFrame: walks the parent chain up to
	-- the root, composing offsets in each parent's local space.
	local function worldCFrameForLimb(spec: LimbSpec): CFrame
		if spec.parentLimb == nil then
			-- Attaches directly to the root part
			return originCF * CFrame.new(spec.defaultOffset)
		end
		-- Find parent spec in the rig
		local parentSpec: LimbSpec? = nil
		for _, other in ipairs(rigDef.limbs) do
			if other.name == spec.parentLimb then
				parentSpec = other
				break
			end
		end
		if not parentSpec then
			-- Parent listed but not found in the rig — treat as root-attached
			return originCF * CFrame.new(spec.defaultOffset)
		end
		return worldCFrameForLimb(parentSpec) * CFrame.new(spec.defaultOffset)
	end

	-- Skip a limb whose parent chain contains an excluded limb — orphaned
	-- children make no sense in a rig
	local function ancestorIncluded(spec: LimbSpec): boolean
		if spec.parentLimb == nil then
			return true
		end
		for _, other in ipairs(rigDef.limbs) do
			if other.name == spec.parentLimb then
				if not limbIsIncluded(other) then
					return false
				end
				return ancestorIncluded(other)
			end
		end
		return true
	end

	for _, spec in ipairs(rigDef.limbs) do
		if not limbIsIncluded(spec) then
			continue
		end
		if not ancestorIncluded(spec) then
			say("warn", string.format("Skipping '%s' — an ancestor limb is excluded.", spec.name))
			continue
		end

		local size = limbSize(spec)
		local worldCF = worldCFrameForLimb(spec)
		local part = makeLimbPart(spec.name, size, worldCF, vmOptions.armColor or Color3.fromRGB(255, 211, 160))
		part.Parent = vm

		createdLimbs[spec.name] = part
		limbSizes[spec.name] = size
	end

	-- Shirt texture: instead of a Shirt instance (which requires a Humanoid),
	-- apply the ShirtTemplate texture directly to every limb part as a
	-- SurfaceAppearance.AlbedoMap. Roblox's shirt texture is a UV atlas
	-- designed for the R6/R15 body layout — it maps correctly to the flat
	-- faces of the cube Parts when applied this way.
	-- This means the arms show the shirt texture with zero Humanoid dependency,
	-- which is exactly what a custom viewmodel rig using UV-mapped arm meshes
	-- or gore models needs.
	if vmOptions.shirtId and vmOptions.shirtId ~= "" then
		local texId = vmOptions.shirtId
		-- Normalise: strip wrapping rbxassetid:// if present so we can
		-- re-add it in a known format. SurfaceAppearance AlbedoMap expects
		-- "rbxassetid://NNN".
		local numericId = texId:match("(%d+)$") or texId
		local finalTexId = "rbxassetid://" .. numericId

		local appliedCount = 0
		for partName, part in pairs(createdLimbs) do
			local sa = Instance.new("SurfaceAppearance")
			sa.AlbedoMap = finalTexId
			-- No NormalMap / MetalnessMap / RoughnessMap — keep it simple;
			-- the user's mesh shader handles the rest.
			sa.Name = "ShirtTexture"
			sa.Parent = part
			appliedCount += 1
		end
		say("success", string.format(
			"Shirt texture applied via SurfaceAppearance.AlbedoMap to %d limb part(s). " ..
				"No Humanoid required — texture UV-maps to part faces directly.",
			appliedCount
			))
	end

	-- Pass 2: build Motor6Ds parented onto each limb (same convention as
	-- the arm rig had before — Motor6D lives on Part1). Root motors connect
	-- to the root part if it exists; otherwise the limb becomes free-floating.
	for _, spec in ipairs(rigDef.limbs) do
		local limbPart = createdLimbs[spec.name]
		if not limbPart then
			continue
		end
		local parentPart: BasePart? = nil
		if spec.parentLimb == nil then
			parentPart = rootPart
		else
			parentPart = createdLimbs[spec.parentLimb]
		end
		if parentPart then
			buildMotor6D(parentPart, limbPart, spec.motorName, limbPart)
			say("success", string.format("Motor6D built: %s -> %s (%s)", parentPart.Name, spec.name, spec.motorName))
		else
			say("warn", string.format("No parent part available for '%s'; skipped Motor6D.", spec.name))
		end
	end

	-- Accessory slots — one Attachment per slot per hand-flagged limb.
	-- Slot names are already the canonical Roblox attachment names
	-- (e.g. "RightGripAttachment") so we use them directly.
	if #vmOptions.accessorySlots > 0 then
		local handCount = 0
		for _, spec in ipairs(rigDef.limbs) do
			if spec.isHand and createdLimbs[spec.name] then
				local hand = createdLimbs[spec.name]
				local size = limbSizes[spec.name]
				local isRight = string.find(string.lower(spec.name), "right") ~= nil
				local isLeft  = string.find(string.lower(spec.name), "left")  ~= nil
				for _, slotName in ipairs(vmOptions.accessorySlots) do
					-- Skip grip slots that don't match the hand side so
					-- RightGripAttachment only appears on the right hand.
					local slotLower = string.lower(slotName)
					local slotIsRight = string.find(slotLower, "right") ~= nil
					local slotIsLeft  = string.find(slotLower, "left")  ~= nil
					if slotIsRight and not isRight then continue end
					if slotIsLeft  and not isLeft  then continue end

					local attach = Instance.new("Attachment")
					attach.Name = slotName
					-- Default position at the tip of the hand; overridden by
					-- per-slot offset stored in the UI slot picker.
					local defaultCF = CFrame.new(0, -size.Y * 0.5, 0)
					-- getSlotOffset is only accessible from within the plugin
					-- UI closure, so we store the offset on vmOptions.
					local customOffset = (vmOptions :: any).slotOffsets and (vmOptions :: any).slotOffsets[slotName]
					attach.CFrame = customOffset and (defaultCF * customOffset) or defaultCF
					attach.Parent = hand
				end
				handCount += 1
			end
		end
		say("info", string.format("Accessory attachments added to %d hand(s): %s", handCount, table.concat(vmOptions.accessorySlots, ", ")))
	end

	return vm, log
end

-- ============================================================
-- SECTION 8B: MODEL SERIALIZATION (for the weapon library)
-- ============================================================

--[[
	Serializes a Model (or Folder tree) into a plain Lua table that
	round-trips through plugin:SetSetting / GetSetting. This lets the
	Weapon Library keep copies of guns that survive the original being
	deleted from the game — the serialized form is stored with the
	plugin, not with the place.

	Design:
	- Each serialized instance is { c=ClassName, n=Name, p={props}, k={children} }.
	- Values that aren't primitive get encoded with a type tag:
	    CFrame  -> {"_CF", 12 components}
	    Vector3 -> {"_V3", x, y, z}
	    Color3  -> {"_C3", r, g, b}
	    Enum    -> {"_EN", "EnumType", "Name"}
	    Instance ref (Part0/Part1/PrimaryPart) -> {"_ID", numericId}
	- Every serialized instance gets a numeric id at serialization
	  time so cross-references (Motor6D.Part0/Part1) can be resolved
	  during deserialization via an id -> instance map.
	- Classes not in the whitelist get skipped rather than partially
	  serialized — better to lose an unknown Script than to crash on
	  restore. The whitelist covers everything a gun rig typically
	  contains: Model, Folder, Part, MeshPart, SpecialMesh, Motor6D,
	  WeldConstraint, Weld (legacy), Attachment, Sound, and the basic
	  *Value classes.
]]

local SERIALIZABLE_CLASSES: { [string]: boolean } = {
	Model = true, Folder = true,
	Part = true, MeshPart = true, WedgePart = true, TrussPart = true,
	SpecialMesh = true, CylinderMesh = true, BlockMesh = true, FileMesh = true,
	Motor6D = true, WeldConstraint = true, Weld = true, ManualWeld = true, Snap = true,
	Attachment = true, Sound = true,
	StringValue = true, NumberValue = true, BoolValue = true, IntValue = true,
	CFrameValue = true, Vector3Value = true, Color3Value = true, ObjectValue = true,
	Configuration = true,
	SurfaceAppearance = true,
	-- UnionOperation is handled specially: serialized as Part + _UnionStub
	-- attribute so size/CFrame/material round-trip and the stub can be
	-- re-identified later for proper union restoration when implemented.
	UnionOperation = true,
}

local BASEPART_PROPS = {
	"Size", "CFrame", "Color", "Material", "Transparency", "Reflectance",
	"CanCollide", "Anchored", "CastShadow", "Massless", "CanQuery", "CanTouch",
	"CollisionGroup",
}
local CLASS_PROPS: { [string]: { string } } = {
	Part           = table.clone(BASEPART_PROPS),
	MeshPart       = table.clone(BASEPART_PROPS),
	WedgePart      = table.clone(BASEPART_PROPS),
	TrussPart      = table.clone(BASEPART_PROPS),
	UnionOperation = table.clone(BASEPART_PROPS),  -- stub; geometry lost, props kept
	SpecialMesh  = { "MeshId", "TextureId", "MeshType", "Scale", "Offset", "VertexColor" },
	CylinderMesh = { "Scale", "Offset", "VertexColor" },
	BlockMesh    = { "Scale", "Offset", "VertexColor" },
	FileMesh     = { "MeshId", "TextureId", "Scale", "Offset", "VertexColor" },
	Motor6D        = { "Part0", "Part1", "C0", "C1", "MaxVelocity", "DesiredAngle", "CurrentAngle" },
	WeldConstraint = { "Part0", "Part1", "Enabled" },
	Weld           = { "Part0", "Part1", "C0", "C1" },
	ManualWeld     = { "Part0", "Part1", "C0", "C1" },
	Snap           = { "Part0", "Part1", "C0", "C1" },
	Attachment     = { "CFrame", "Visible" },
	Sound          = { "SoundId", "Volume", "PlaybackSpeed", "Looped", "RollOffMode",
		"RollOffMaxDistance", "RollOffMinDistance", "MaxDistance" },
	SurfaceAppearance = { "AlbedoMap", "NormalMap", "RoughnessMap", "MetalnessMap",
		"ColorMap", "TexturePack", "AlphaMode" },
	StringValue = { "Value" }, NumberValue = { "Value" }, BoolValue = { "Value" },
	IntValue    = { "Value" }, CFrameValue = { "Value" }, Vector3Value = { "Value" },
	Color3Value = { "Value" }, ObjectValue = { "Value" },
	Model       = { "PrimaryPart" },
	Folder      = {},
	Configuration = {},
}
-- MeshPart: TextureID (capital ID) is the correct property name in Roblox's
-- API. MeshId is intentionally excluded — it's not writable after creation
-- in plugin context and the mesh geometry can't be reconstructed from id alone.
table.insert(CLASS_PROPS.MeshPart, "TextureID")

-- Type tag markers
local TAG_CFRAME = "_CF"
local TAG_VECTOR3 = "_V3"
local TAG_COLOR3 = "_C3"
local TAG_ENUM = "_EN"
local TAG_IDREF = "_ID"

local function encodeValue(v: any, instanceToId: { [Instance]: number }): any
	local t = typeof(v)
	if t == "CFrame" then
		local a, b, c, d, e, f, g, h, i, j, k, l = v:GetComponents()
		return { TAG_CFRAME, a, b, c, d, e, f, g, h, i, j, k, l }
	elseif t == "Vector3" then
		return { TAG_VECTOR3, v.X, v.Y, v.Z }
	elseif t == "Color3" then
		return { TAG_COLOR3, v.R, v.G, v.B }
	elseif t == "EnumItem" then
		return { TAG_ENUM, tostring(v.EnumType), v.Name }
	elseif t == "Instance" then
		local id = instanceToId[v]
		if id then
			return { TAG_IDREF, id }
		end
		return nil -- external ref, can't serialize
	elseif t == "string" or t == "number" or t == "boolean" then
		return v
	end
	return nil -- unsupported type, drop it
end

local function decodeValue(v: any, idToInstance: { [number]: Instance }): any
	if type(v) ~= "table" then
		return v
	end
	local tag = v[1]
	if tag == TAG_CFRAME then
		return CFrame.new(v[2], v[3], v[4], v[5], v[6], v[7], v[8], v[9], v[10], v[11], v[12], v[13])
	elseif tag == TAG_VECTOR3 then
		return Vector3.new(v[2], v[3], v[4])
	elseif tag == TAG_COLOR3 then
		return Color3.new(v[2], v[3], v[4])
	elseif tag == TAG_ENUM then
		local enumType = (Enum :: any)[v[2]]
		if enumType then
			local ok, item = pcall(function()
				return enumType[v[3]]
			end)
			if ok then
				return item
			end
		end
		return nil
	elseif tag == TAG_IDREF then
		return idToInstance[v[2]]
	end
	return v
end

-- First pass: recursively assign ids to every serializable instance
-- reachable from `root`. Returns the map.
local function assignIds(root: Instance): { [Instance]: number }
	local map: { [Instance]: number } = {}
	local nextId = 1
	local function walk(inst: Instance)
		if not SERIALIZABLE_CLASSES[inst.ClassName] then
			return
		end
		map[inst] = nextId
		nextId += 1
		for _, child in ipairs(inst:GetChildren()) do
			walk(child)
		end
	end
	walk(root)
	return map
end

local function serializeInstance(inst: Instance, instanceToId: { [Instance]: number }): any
	if not SERIALIZABLE_CLASSES[inst.ClassName] then
		return nil
	end

	local effectiveClass = inst.ClassName
	local isUnionStub = false
	if inst.ClassName == "UnionOperation" then
		effectiveClass = "Part"
		isUnionStub = true
	end

	local out: any = {
		c = effectiveClass,
		n = inst.Name,
		id = instanceToId[inst],
		p = {},
		k = {},
		attrs = {},
	}

	if isUnionStub then
		out.p["_UnionStub"] = true
	end

	-- For MeshPart, store MeshId and TextureID in dedicated fields so the
	-- deserializer can attempt to reconstruct with proper geometry. These are
	-- NOT in CLASS_PROPS because they can't be set via assignment post-creation.
	if inst.ClassName == "MeshPart" then
		local mp = inst :: MeshPart
		local ok1, mid = pcall(function() return mp.MeshId end)
		if ok1 and mid and mid ~= "" then out.meshId = mid end
		local ok2, tid = pcall(function() return mp.TextureID end)
		if ok2 and tid and tid ~= "" then out.textureId = tid end
	end

	local props = CLASS_PROPS[inst.ClassName] or {}
	for _, propName in ipairs(props) do
		local ok, val = pcall(function()
			return (inst :: any)[propName]
		end)
		if ok then
			local encoded = encodeValue(val, instanceToId)
			if encoded ~= nil then
				out.p[propName] = encoded
			end
		end
	end

	local ok2, attrs = pcall(function() return inst:GetAttributes() end)
	if ok2 and attrs then
		for attrName, attrVal in pairs(attrs) do
			local encoded = encodeValue(attrVal, instanceToId)
			if encoded ~= nil then
				out.attrs[attrName] = encoded
			end
		end
	end

	for _, child in ipairs(inst:GetChildren()) do
		local childData = serializeInstance(child, instanceToId)
		if childData then
			table.insert(out.k, childData)
		end
	end
	return out
end

local function serializeModel(root: Instance): any
	local instanceToId = assignIds(root)
	return serializeInstance(root, instanceToId)
end

-- Deserialization: two passes. Pass 1 creates every instance and sets
-- non-ref properties, populating an id -> instance map. Pass 2 walks the
-- serialized tree again and applies ref properties (Part0/Part1/etc)
-- using the resolved instances. Skipping ref props in pass 1 avoids
-- setting them to nil when Part0/Part1 hasn't been created yet.
local function isRefValue(v: any): boolean
	return type(v) == "table" and v[1] == TAG_IDREF
end

local InsertService = game:GetService("InsertService")

local function createFromData(data: any): (Instance?, { [number]: Instance })
	local idToInstance: { [number]: Instance } = {}

	local function pass1(node: any, parent: Instance?): Instance?
		local inst: Instance? = nil

		-- MeshPart with a stored MeshId: reconstruct via InsertService so
		-- the mesh geometry actually round-trips. InsertService:CreateMeshPartAsync
		-- returns a MeshPart with the mesh loaded, then we apply remaining props.
		if node.c == "MeshPart" and node.meshId and node.meshId ~= "" then
			local ok, mp = pcall(function()
				return InsertService:CreateMeshPartAsync(
					node.meshId,
					Enum.CollisionFidelity.Default,
					Enum.RenderFidelity.Automatic
				)
			end)
			if ok and mp then
				inst = mp :: Instance
				-- Apply texture separately (also can't be set post-creation
				-- on older API, but TextureID IS writable on the returned part)
				if node.textureId and node.textureId ~= "" then
					pcall(function()
						(inst :: any).TextureID = node.textureId
					end)
				end
			end
		end

		-- Fallback / all other classes
		if not inst then
			local ok2, created = pcall(Instance.new, node.c)
			if not ok2 or not created then return nil end
			inst = created
		end

		inst = inst :: Instance
		inst.Name = node.n
		if node.id then
			idToInstance[node.id] = inst
		end

		for propName, encoded in pairs(node.p) do
			if propName == "_UnionStub" then
				pcall(function() inst:SetAttribute("_UnionStub", true) end)
			elseif not isRefValue(encoded) then
				local decoded = decodeValue(encoded, idToInstance)
				if decoded ~= nil then
					pcall(function()
						(inst :: any)[propName] = decoded
					end)
				end
			end
		end

		-- Restore serialized attributes
		if type(node.attrs) == "table" then
			for attrName, encoded in pairs(node.attrs) do
				if not isRefValue(encoded) then
					local decoded = decodeValue(encoded, idToInstance)
					if decoded ~= nil then
						pcall(function() inst:SetAttribute(attrName, decoded) end)
					end
				end
			end
		end

		for _, childNode in ipairs(node.k) do
			pass1(childNode, inst)
		end
		if parent then
			inst.Parent = parent
		end
		return inst
	end

	local rootInst = pass1(data, nil)

	local function pass2(node: any)
		local inst = idToInstance[node.id]
		if inst then
			for propName, encoded in pairs(node.p) do
				if isRefValue(encoded) then
					local resolved = decodeValue(encoded, idToInstance)
					if resolved then
						pcall(function()
							(inst :: any)[propName] = resolved
						end)
					end
				end
			end
		end
		for _, childNode in ipairs(node.k) do
			pass2(childNode)
		end
	end
	if data then
		pass2(data)
	end

	return rootInst, idToInstance
end

local function deserializeModel(data: any): Instance?
	if type(data) ~= "table" then
		return nil
	end
	local inst = createFromData(data)
	return inst
end

-- ============================================================
-- SECTION 8C: WEAPON LIBRARY (persistent storage via plugin settings)
-- ============================================================

local LIBRARY_SETTING_KEY = "GunRigBuilder_WeaponLibrary_v1"
local LIBRARY_ENTRIES_KEY = "GunRigBuilder_WeaponLibrary_v1_Entries"

type LibraryEntry = {
	name: string,
	savedAt: number, -- os.time() at save
	data: any,       -- serialized model tree
}

-- Library state is a dictionary keyed by weapon name. plugin:SetSetting
-- stores tables of JSON-serializable data, which our serialized-model
-- format is (only strings/numbers/booleans/nested tables — see the tags
-- in section 8B). Names are unique keys; saving with an existing name
-- overwrites, mirroring the "quick attach or store" phrasing.
local libraryCache: { [string]: LibraryEntry }? = nil

local function libraryLoad(): { [string]: LibraryEntry }
	if libraryCache then
		return libraryCache
	end
	local raw = plugin:GetSetting(LIBRARY_SETTING_KEY)
	if type(raw) == "table" then
		libraryCache = raw :: any
	else
		libraryCache = {}
	end
	return libraryCache :: { [string]: LibraryEntry }
end

local function libraryPersist()
	if libraryCache then
		plugin:SetSetting(LIBRARY_SETTING_KEY, libraryCache)
		-- Also store a lightweight name-only list under a separate key for
		-- quick "what's in the library" lookups without decoding every
		-- serialized model. Kept in sync on every mutation below.
		local names: { string } = {}
		for name in pairs(libraryCache) do
			table.insert(names, name)
		end
		table.sort(names)
		plugin:SetSetting(LIBRARY_ENTRIES_KEY, names)
	end
end

local function librarySave(name: string, model: Instance): (boolean, string)
	if name == "" then
		return false, "Weapon name cannot be empty."
	end
	local data = serializeModel(model)
	if not data then
		return false, "Model could not be serialized (unsupported root class)."
	end
	local lib = libraryLoad()
	lib[name] = {
		name = name,
		savedAt = os.time(),
		data = data,
	}
	libraryPersist()
	return true, string.format("Saved '%s' to the weapon library.", name)
end

local function libraryDelete(name: string): boolean
	local lib = libraryLoad()
	if lib[name] then
		lib[name] = nil
		libraryPersist()
		return true
	end
	return false
end

local function libraryList(): { string }
	local lib = libraryLoad()
	local names: { string } = {}
	for name in pairs(lib) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

local function libraryRestore(name: string): Instance?
	local lib = libraryLoad()
	local entry = lib[name]
	if not entry then
		return nil
	end
	return deserializeModel(entry.data)
end

-- ============================================================
-- SECTION 8D: VIEWPORT PREVIEW
-- ============================================================

--[[
	Builds a self-contained viewport widget: a ViewportFrame with an
	orbit camera that slowly rotates around whatever model is currently
	set as the preview subject. Returns a `setPreview(model)` function
	that clones the given model into the viewport (destroying any
	previously-set preview) and reframes the camera to fit.

	The viewport uses ONE preview clone — swap it whenever settings
	change. Physics don't run inside a ViewportFrame, so Anchored state
	doesn't matter and Motor6Ds won't animate; this is a static preview,
	not a play-simulation.
]]

local function createViewport(parent: Instance, layoutOrder: number): (Frame, (Instance?) -> ())
	local container = Instance.new("Frame")
	container.Size = UDim2.new(1, 0, 0, 220)
	container.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	container.BorderSizePixel = 0
	container.LayoutOrder = layoutOrder
	container.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = container

	local vp = Instance.new("ViewportFrame")
	vp.Size = UDim2.new(1, -4, 1, -4)
	vp.Position = UDim2.fromOffset(2, 2)
	vp.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
	vp.BorderSizePixel = 0
	vp.LightColor = Color3.fromRGB(255, 240, 220)
	vp.LightDirection = Vector3.new(-0.4, -1, -0.3)
	vp.Ambient = Color3.fromRGB(120, 120, 130)
	vp.Parent = container

	local camera = Instance.new("Camera")
	camera.FieldOfView = 50
	camera.Parent = vp
	vp.CurrentCamera = camera

	local placeholder = Instance.new("TextLabel")
	placeholder.Text = "no preview yet — build once to populate"
	placeholder.Font = Enum.Font.SourceSansItalic
	placeholder.TextSize = 13
	placeholder.TextColor3 = Color3.fromRGB(140, 140, 150)
	placeholder.BackgroundTransparency = 1
	placeholder.Size = UDim2.fromScale(1, 1)
	placeholder.Parent = container

	local currentPreview: Instance? = nil
	local previewCenter: Vector3 = Vector3.new()
	local previewRadius: number = 5
	local angle: number = 0

	local function reframeCamera()
		if not currentPreview then
			return
		end
		if currentPreview:IsA("Model") then
			local model = currentPreview :: Model
			local ok, cf, size = pcall(function()
				return model:GetBoundingBox()
			end)
			if ok and cf and size then
				previewCenter = cf.Position
				previewRadius = math.max(size.X, size.Y, size.Z) * 1.2 + 2
			end
		elseif currentPreview:IsA("BasePart") then
			local p = currentPreview :: BasePart
			previewCenter = p.Position
			previewRadius = math.max(p.Size.X, p.Size.Y, p.Size.Z) * 1.5 + 2
		end
	end

	local function setPreview(model: Instance?)
		if currentPreview then
			currentPreview:Destroy()
			currentPreview = nil
		end
		if not model then
			placeholder.Visible = true
			return
		end
		placeholder.Visible = false
		local clone = model:Clone()
		-- Parts inside a ViewportFrame render regardless of Anchored,
		-- but destroying live joints keeps the preview visually stable.
		for _, desc in ipairs(clone:GetDescendants()) do
			if desc:IsA("BasePart") then
				desc.Anchored = true
			end
		end
		clone.Parent = vp
		currentPreview = clone
		reframeCamera()
	end

	-- Simple orbit: update on Heartbeat, position camera on a circle
	-- around the model at previewCenter.
	local RunService = game:GetService("RunService")
	local conn = RunService.Heartbeat:Connect(function(dt)
		if not currentPreview then
			return
		end
		angle += dt * 0.4
		local x = math.sin(angle) * previewRadius
		local z = math.cos(angle) * previewRadius
		local eye = previewCenter + Vector3.new(x, previewRadius * 0.4, z)
		camera.CFrame = CFrame.new(eye, previewCenter)
	end)

	-- Clean up when the container goes away (widget close, plugin
	-- unload). AncestryChanged fires when the container is orphaned.
	container.AncestryChanged:Connect(function(_, newParent)
		if not newParent then
			conn:Disconnect()
		end
	end)

	return container, setPreview
end

-- ============================================================
-- SECTION 8E: CLICK-TO-PLACE MODE
-- ============================================================

--[[
	`enterClickToPlace(spawnFn, onDone)` puts the plugin into a mouse-
	capturing mode. The next left-click in the viewport calls spawnFn
	with the CFrame of the click's hit position (surface hit if any,
	otherwise a fallback position in front of the camera). onDone runs
	after either a successful click OR a cancel.

	Cancellation: user clicks the same "Place by Click" button again,
	presses Escape, or the widget closes. The returned `cancel()`
	function lets the caller unhook programmatically.
]]

local pluginMouse: PluginMouse? = nil
local activePlaceConn: RBXScriptConnection? = nil
local activePlaceEscConn: RBXScriptConnection? = nil

local function enterClickToPlace(spawnFn: (CFrame) -> (), onDone: () -> ()): () -> ()
	-- Cancel any in-flight place operation before starting a new one.
	if activePlaceConn then
		activePlaceConn:Disconnect()
		activePlaceConn = nil
	end
	if activePlaceEscConn then
		activePlaceEscConn:Disconnect()
		activePlaceEscConn = nil
	end

	if not pluginMouse then
		pluginMouse = plugin:GetMouse()
	end
	local mouse = pluginMouse :: PluginMouse

	plugin:Activate(true)
	mouse.Icon = "rbxasset://SystemCursors/Cross"

	local function finish()
		if activePlaceConn then
			activePlaceConn:Disconnect()
			activePlaceConn = nil
		end
		if activePlaceEscConn then
			activePlaceEscConn:Disconnect()
			activePlaceEscConn = nil
		end
		mouse.Icon = ""
		plugin:Deactivate()
		onDone()
	end

	activePlaceConn = mouse.Button1Down:Connect(function()
		-- mouse.Hit is a CFrame at the surface hit point (or a fallback
		-- position along the ray if nothing was hit). Good enough for
		-- spawning a model — the caller can offset from here.
		local hitCF = mouse.Hit
		spawnFn(hitCF)
		finish()
	end)

	local UserInputService = game:GetService("UserInputService")
	activePlaceEscConn = UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape then
			finish()
		end
	end)

	return finish
end



-- ============================================================
-- SECTION 9: LIVE PART PLACEMENT HELPERS
-- ============================================================

-- "Live added to the model" support: given a folder or model the user
-- clicks/selects, clone its parts into the target gun model so the
-- user can position them manually before running Build.
local function importPartsFromSelectionInto(targetModel: Model, source: Instance): (number, { LogEntry })
	local log: { LogEntry } = {}
	local count = 0

	local function say(level: LogLevel, text: string)
		table.insert(log, { level = level, text = text })
	end

	if source == targetModel then
		say("warn", "Skipped import: source and target are the same model.")
		return 0, log
	end

	if source:IsA("Folder") or source:IsA("Model") then
		for _, child in ipairs(source:GetChildren()) do
			if child:IsA("BasePart") or child:IsA("Folder") or child:IsA("Model") then
				local clone = child:Clone()
				clone.Parent = targetModel
				count += 1
			end
		end
		say("success", string.format("Imported %d item(s) from '%s' into '%s'. Position them, then run Scan/Build.", count, source.Name, targetModel.Name))
	elseif source:IsA("BasePart") then
		local clone = source:Clone()
		clone.Parent = targetModel
		count = 1
		say("success", string.format("Imported part '%s' into '%s'.", source.Name, targetModel.Name))
	else
		say("warn", string.format("'%s' is not a Folder, Model, or BasePart — nothing imported.", source.Name))
	end

	return count, log
end

-- ============================================================
-- SECTION 10: MARKDOWN DOCUMENTATION (simple renderer)
-- ============================================================

local DOCUMENTATION_MD = [[
# Gun Rig / ViewModel Builder

## Quick Start
1. Select your gun Model in the Explorer.
2. Open this plugin, choose the Gun Rig tab, click Use Selected Model as Target.
3. Click Scan to validate.
4. Fix any direction warnings shown in the log.
5. Click Build Gun Rig.
6. Switch to the ViewModel tab to generate an arm rig, or the Library tab to save your gun for later.

## Structural Part Names
- Handle or Grip (exactly one, this is the root)
- Slide
- Magazine
- Muzzle
- Aim
- EjectShell
- Hinge_1, Hinge_2, Hinge_3, and so on

## Weld Folder Names
- Body -> welds every part inside to Handle or Grip
- Grip -> welds every part inside to Handle or Grip
- Magazine -> welds every part inside to the Magazine part
- Slide -> welds every part inside to the Slide part
- Hinge_# -> welds every part inside to the matching Hinge_# part

## Direction Check
All structural parts are compared to the Handle or Grip using LookVector dot product.
A negative or zero dot product is flagged as facing the wrong way.
Fix part orientation in the 3D view, then re-scan.

## After a Build
- Motor6Ds live in Constraints/Motor6Ds
- WeldConstraints live in Constraints/Welds
- Structural parts and weld-source folders live in Main
- Re-scan and re-build both continue to work after this reorganization

## ViewModel Rig Types
- ArmsOnly: classic first-person viewmodel with just arms hanging off a root
- R6: full skeletal structure matching Roblox's default R6 rig naming (Torso, Head, Left/Right Arm, Left/Right Leg)
- R15: full skeletal structure matching R15 (LowerTorso, UpperTorso, Head, and Upper/Lower/Hand + Upper/Lower/Foot chains)

## Per-Limb Adjustments
- Every limb has an Include checkbox and X / Y / Z size fields
- Unchecking a limb excludes it AND its children (skipping a torso skips the arms)
- Sizes are in studs; the rig recomputes joint positions from your override sizes

## Preview
The viewport shows a static, orbiting preview of the currently-configured rig.
Click Refresh Preview to rebuild it after changing settings.
Motor6Ds don't animate inside a viewport frame; this is a shape preview, not a simulation.

## Placing Rigs
- Build at Workspace Origin: spawns the rig at (0, 0, 0)
- Place by Click: enter click-to-place mode, then click anywhere in the 3D viewport to spawn
- Press Escape to cancel a pending click

## Weapon Library
- Save Selection to Library: saves whatever's currently selected in the Explorer
- Save Gun Rig Target to Library: saves whichever model is set as the Gun Rig target
- Saved weapons persist across Studio sessions (stored via plugin:SetSetting)
- The library survives the original model being deleted from the game
- Each entry has Load (spawns at origin), Place by Click, and Delete buttons

## Live Import
Select a Folder or Model anywhere in the game and use Import Selected Into Target
to clone its contents into your gun model for manual placement before building.

## Notes
- Re-running Build is safe. Existing Motor6Ds and plugin welds with matching names are replaced, not duplicated.
- Everything runs inside one ChangeHistoryService waypoint per action, so Undo works normally.
- Serialization covers Model, Folder, Part, MeshPart, SpecialMesh, Motor6D, WeldConstraint, Attachment, Sound, Value objects, and Configuration. Scripts and other classes are skipped rather than corrupted on save.
]]

-- Very small Markdown -> rich text-ish plain rendering for a TextLabel.
-- Supports: # / ## headings, plain lines, and blank lines as spacing.
-- Returns an array of {text, isHeading, level} for the UI to lay out.
type DocLine = { text: string, level: number }

local function parseSimpleMarkdown(md: string): { DocLine }
	local lines: { DocLine } = {}
	for line in string.gmatch(md, "([^\n]*)\n?") do
		if line ~= "" or #lines > 0 then
			local hashes, rest = string.match(line, "^(#+)%s+(.*)$")
			if hashes then
				table.insert(lines, { text = rest, level = #hashes })
			elseif string.match(line, "^%- (.*)$") then
				local bulletText = string.match(line, "^%- (.*)$")
				table.insert(lines, { text = "•  " .. bulletText, level = 0 })
			elseif line == "" then
				table.insert(lines, { text = "", level = -1 }) -- spacer marker
			else
				table.insert(lines, { text = line, level = 0 })
			end
		end
	end
	return lines
end

-- ============================================================
-- SECTION 11: UI — DockWidget + rendering
-- ============================================================

local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Right,
	false, -- enabled by default
	false, -- override previous enabled state
	380,   -- default width
	560,   -- default height
	320,   -- min width
	420    -- min height
)

local widget = plugin:CreateDockWidgetPluginGui("GunRigBuilderWidget", widgetInfo)
widget.Title = "Gun Rig / ViewModel Builder"
widget.Name = "GunRigBuilderWidget"

-- ---- root frame + tab system ----

local root = Instance.new("Frame")
root.Size = UDim2.fromScale(1, 1)
root.BackgroundColor3 = Color3.fromRGB(46, 46, 46)
root.BorderSizePixel = 0
root.Parent = widget

local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, 0, 0, 32)
tabBar.BackgroundColor3 = Color3.fromRGB(36, 36, 36)
tabBar.BorderSizePixel = 0
tabBar.Parent = root

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabLayout.Parent = tabBar

local pages = Instance.new("Frame")
pages.Size = UDim2.new(1, 0, 1, -32)
pages.Position = UDim2.new(0, 0, 0, 32)
pages.BackgroundTransparency = 1
pages.Parent = root

local function makeTabButton(text: string, order: number): TextButton
	local btn = Instance.new("TextButton")
	btn.Name = text .. "Tab"
	btn.Size = UDim2.new(0, 58, 1, 0)
	btn.BackgroundColor3 = Color3.fromRGB(46, 46, 46)
	btn.BorderSizePixel = 0
	btn.Text = text
	btn.TextColor3 = Color3.fromRGB(220, 220, 220)
	btn.Font = Enum.Font.SourceSansSemibold
	btn.TextSize = 14
	btn.LayoutOrder = order
	btn.AutoButtonColor = false
	btn.Parent = tabBar
	return btn
end

local function makePage(name: string): ScrollingFrame
	local page = Instance.new("ScrollingFrame")
	page.Name = name .. "Page"
	page.Size = UDim2.fromScale(1, 1)
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.ScrollBarThickness = 6
	page.CanvasSize = UDim2.new(0, 0, 0, 0)
	page.AutomaticCanvasSize = Enum.AutomaticSize.Y
	page.Visible = false
	page.Parent = pages

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = page

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.Parent = page

	return page
end

local buildTab    = makeTabButton("Rig",      1)
local vmTab       = makeTabButton("VM",       2)
local libraryTab  = makeTabButton("Library",  3)
local catalogueTab = makeTabButton("Catalog", 4)
local docsTab     = makeTabButton("Docs",     5)
local settingsTab = makeTabButton("Settings", 6)

local buildPage     = makePage("Build")
local vmPage        = makePage("ViewModel")
local libraryPage   = makePage("Library")
local cataloguePage = makePage("Catalogue")
local docsPage      = makePage("Docs")
local settingsPage  = makePage("Settings")

local allTabs  = { buildTab, vmTab, libraryTab, catalogueTab, docsTab, settingsTab }
local allPages = { buildPage, vmPage, libraryPage, cataloguePage, docsPage, settingsPage }

local function selectTab(index: number)
	for i, tab in ipairs(allTabs) do
		local isSelected = i == index
		tab.BackgroundColor3 = isSelected and Color3.fromRGB(60, 90, 140) or Color3.fromRGB(46, 46, 46)
		allPages[i].Visible = isSelected
	end
end

buildTab.MouseButton1Click:Connect(function() selectTab(1) end)
vmTab.MouseButton1Click:Connect(function() selectTab(2) end)
libraryTab.MouseButton1Click:Connect(function() selectTab(3) end)
catalogueTab.MouseButton1Click:Connect(function() selectTab(4) end)
docsTab.MouseButton1Click:Connect(function() selectTab(5) end)
settingsTab.MouseButton1Click:Connect(function() selectTab(6) end)

selectTab(1)

-- ---- generic UI helpers ----

local function sectionLabel(parent: Instance, text: string, order: number): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.Text = text
	lbl.Font = Enum.Font.SourceSansBold
	lbl.TextSize = 15
	lbl.TextColor3 = Color3.fromRGB(230, 230, 230)
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.new(1, 0, 0, 22)
	lbl.LayoutOrder = order
	lbl.Parent = parent
	return lbl
end

local function hintLabel(parent: Instance, text: string, order: number): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.Text = text
	lbl.Font = Enum.Font.SourceSans
	lbl.TextSize = 13
	lbl.TextWrapped = true
	lbl.TextColor3 = Color3.fromRGB(170, 170, 170)
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextYAlignment = Enum.TextYAlignment.Top
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.new(1, 0, 0, 32)
	lbl.LayoutOrder = order
	lbl.Parent = parent
	return lbl
end

local function actionButton(parent: Instance, text: string, order: number, color: Color3?): TextButton
	local btn = Instance.new("TextButton")
	btn.Text = text
	btn.Font = Enum.Font.SourceSansSemibold
	btn.TextSize = 14
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.BackgroundColor3 = color or Color3.fromRGB(70, 120, 70)
	btn.Size = UDim2.new(1, 0, 0, 32)
	btn.LayoutOrder = order
	btn.AutoButtonColor = true
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = btn
	btn.Parent = parent
	return btn
end

local function makeCheckbox(parent: Instance, labelText: string, order: number, default: boolean): (Frame, () -> boolean, (boolean) -> ())
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 24)
	row.BackgroundTransparency = 1
	row.LayoutOrder = order
	row.Parent = parent

	local box = Instance.new("TextButton")
	box.Size = UDim2.new(0, 18, 0, 18)
	box.Position = UDim2.new(0, 0, 0.5, -9)
	box.BackgroundColor3 = default and Color3.fromRGB(80, 140, 80) or Color3.fromRGB(70, 70, 70)
	box.Text = default and "X" or ""
	box.TextColor3 = Color3.new(1, 1, 1)
	box.Font = Enum.Font.SourceSansBold
	box.TextSize = 14
	box.AutoButtonColor = false
	box.Parent = row

	local lbl = Instance.new("TextLabel")
	lbl.Text = labelText
	lbl.Font = Enum.Font.SourceSans
	lbl.TextSize = 14
	lbl.TextColor3 = Color3.fromRGB(220, 220, 220)
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.BackgroundTransparency = 1
	lbl.Position = UDim2.new(0, 26, 0, 0)
	lbl.Size = UDim2.new(1, -26, 1, 0)
	lbl.Parent = row

	local state = default

	local function get(): boolean
		return state
	end

	local function set(v: boolean)
		state = v
		box.BackgroundColor3 = state and Color3.fromRGB(80, 140, 80) or Color3.fromRGB(70, 70, 70)
		box.Text = state and "X" or ""
	end

	box.MouseButton1Click:Connect(function()
		set(not state)
	end)

	return row, get, set
end

local function makeNumberField(parent: Instance, labelText: string, order: number, default: number): (Frame, () -> number)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 24)
	row.BackgroundTransparency = 1
	row.LayoutOrder = order
	row.Parent = parent

	local lbl = Instance.new("TextLabel")
	lbl.Text = labelText
	lbl.Font = Enum.Font.SourceSans
	lbl.TextSize = 14
	lbl.TextColor3 = Color3.fromRGB(220, 220, 220)
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.new(0.6, 0, 1, 0)
	lbl.Parent = row

	local box = Instance.new("TextBox")
	box.Text = tostring(default)
	box.Font = Enum.Font.SourceSans
	box.TextSize = 14
	box.TextColor3 = Color3.new(1, 1, 1)
	box.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	box.Position = UDim2.new(0.6, 4, 0, 0)
	box.Size = UDim2.new(0.4, -4, 1, 0)
	box.ClearTextOnFocus = false
	box.Parent = row

	local value = default

	box.FocusLost:Connect(function()
		local n = tonumber(box.Text)
		if n then
			value = n
		else
			box.Text = tostring(value)
		end
	end)

	local function get(): number
		return value
	end

	return row, get
end

local function makeTextField(parent: Instance, labelText: string, order: number, default: string): (Frame, () -> string)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 24)
	row.BackgroundTransparency = 1
	row.LayoutOrder = order
	row.Parent = parent

	local lbl = Instance.new("TextLabel")
	lbl.Text = labelText
	lbl.Font = Enum.Font.SourceSans
	lbl.TextSize = 14
	lbl.TextColor3 = Color3.fromRGB(220, 220, 220)
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.new(0.4, 0, 1, 0)
	lbl.Parent = row

	local box = Instance.new("TextBox")
	box.Text = default
	box.Font = Enum.Font.SourceSans
	box.TextSize = 14
	box.TextColor3 = Color3.new(1, 1, 1)
	box.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	box.Position = UDim2.new(0.4, 4, 0, 0)
	box.Size = UDim2.new(0.6, -4, 1, 0)
	box.ClearTextOnFocus = false
	box.Parent = row

	local value = default
	box.FocusLost:Connect(function()
		value = box.Text
	end)

	local function get(): string
		return value
	end

	return row, get
end

-- Log panel factory (used on both Build and ViewModel pages)
local function makeLogPanel(parent: Instance, order: number, heightScale: number): (Frame, (LogEntry) -> (), () -> ())
	local container = Instance.new("Frame")
	container.Size = UDim2.new(1, 0, 0, 180)
	container.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
	container.LayoutOrder = order
	container.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = container

	local scroller = Instance.new("ScrollingFrame")
	scroller.Size = UDim2.new(1, -8, 1, -8)
	scroller.Position = UDim2.fromOffset(4, 4)
	scroller.BackgroundTransparency = 1
	scroller.BorderSizePixel = 0
	scroller.ScrollBarThickness = 5
	scroller.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroller.Parent = container

	local logLayout = Instance.new("UIListLayout")
	logLayout.SortOrder = Enum.SortOrder.LayoutOrder
	logLayout.Padding = UDim.new(0, 2)
	logLayout.Parent = scroller

	local nextOrder = 0

	local colorFor: { [LogLevel]: Color3 } = {
		info = Color3.fromRGB(180, 180, 180),
		warn = Color3.fromRGB(240, 190, 90),
		error = Color3.fromRGB(240, 100, 100),
		success = Color3.fromRGB(130, 210, 130),
	}

	local function pushEntry(entry: LogEntry)
		nextOrder += 1
		local lbl = Instance.new("TextLabel")
		lbl.Text = entry.text
		lbl.Font = Enum.Font.Code
		lbl.TextSize = 12
		lbl.TextWrapped = true
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.TextYAlignment = Enum.TextYAlignment.Top
		lbl.TextColor3 = colorFor[entry.level]
		lbl.BackgroundTransparency = 1
		lbl.AutomaticSize = Enum.AutomaticSize.Y
		lbl.Size = UDim2.new(1, 0, 0, 0)
		lbl.LayoutOrder = nextOrder
		lbl.Parent = scroller
	end

	local function clearLog()
		nextOrder = 0
		for _, child in ipairs(scroller:GetChildren()) do
			if child:IsA("TextLabel") then
				child:Destroy()
			end
		end
	end

	return container, pushEntry, clearLog
end

-- Segmented button group: a row of mutually-exclusive buttons. Renders
-- horizontally, highlights the selected one, calls onChange when the
-- selection flips. Used for the rig type picker (ArmsOnly / R6 / R15).
local function makeSegmentedGroup(parent: Instance, labelText: string, order: number, options: { string }, defaultIndex: number, onChange: (string, number) -> ()): (Frame, () -> string, (string) -> ())
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 28)
	row.BackgroundTransparency = 1
	row.LayoutOrder = order
	row.Parent = parent

	local lbl = Instance.new("TextLabel")
	lbl.Text = labelText
	lbl.Font = Enum.Font.SourceSans
	lbl.TextSize = 14
	lbl.TextColor3 = Color3.fromRGB(220, 220, 220)
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.new(0.35, 0, 1, 0)
	lbl.Parent = row

	local btnStrip = Instance.new("Frame")
	btnStrip.Size = UDim2.new(0.65, -4, 1, 0)
	btnStrip.Position = UDim2.new(0.35, 4, 0, 0)
	btnStrip.BackgroundTransparency = 1
	btnStrip.Parent = row

	local stripLayout = Instance.new("UIListLayout")
	stripLayout.FillDirection = Enum.FillDirection.Horizontal
	stripLayout.Padding = UDim.new(0, 3)
	stripLayout.Parent = btnStrip

	local buttons: { TextButton } = {}
	local selectedIndex = defaultIndex

	local function refresh()
		for i, b in ipairs(buttons) do
			b.BackgroundColor3 = i == selectedIndex and Color3.fromRGB(60, 90, 140) or Color3.fromRGB(60, 60, 60)
		end
	end

	for i, opt in ipairs(options) do
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(1 / #options, -3, 1, 0)
		b.Font = Enum.Font.SourceSansSemibold
		b.TextSize = 13
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Text = opt
		b.LayoutOrder = i
		b.AutoButtonColor = false
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 3)
		c.Parent = b
		b.Parent = btnStrip
		table.insert(buttons, b)
		b.MouseButton1Click:Connect(function()
			if selectedIndex ~= i then
				selectedIndex = i
				refresh()
				onChange(options[i], i)
			end
		end)
	end
	refresh()

	local function get(): string
		return options[selectedIndex]
	end

	local function set(value: string)
		for i, opt in ipairs(options) do
			if opt == value then
				if selectedIndex ~= i then
					selectedIndex = i
					refresh()
					onChange(value, i)
				end
				return
			end
		end
	end

	return row, get, set
end

-- ============================================================
-- SECTION 11B: SOUND SYSTEM
-- ============================================================

local SOUND_HOLDER = Instance.new("Frame")
SOUND_HOLDER.Name = "_GRB_Sounds"
SOUND_HOLDER.Size = UDim2.new(0, 0, 0, 0)
SOUND_HOLDER.BackgroundTransparency = 1
SOUND_HOLDER.Parent = widget

local function makeSound(name: string, id: string, vol: number, pitch: number): Sound
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = id
	s.Volume = vol
	s.PlaybackSpeed = pitch
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.MaxDistance = 0
	s.Parent = SOUND_HOLDER
	return s
end

local SND_HOVER  = makeSound("Hover",  "rbxasset://sounds/uiclick.wav",    0.08, 1.3)
local SND_CLICK  = makeSound("Click",  "rbxasset://sounds/uiclick.wav",    0.20, 1.0)
local SND_BUILD  = makeSound("Build",  "rbxasset://sounds/electronicpingshort.wav", 0.35, 1.0)
local SND_SAVE   = makeSound("Save",   "rbxasset://sounds/electronicpingshort.wav", 0.25, 1.3)
local SND_DELETE = makeSound("Delete", "rbxasset://sounds/uiclick.wav",    0.20, 0.6)
local SND_ERROR  = makeSound("Error",  "rbxasset://sounds/uiclick.wav",    0.25, 0.4)

local soundsEnabled     = true
local soundMasterVolume = 0.6

local function playSound(snd: Sound)
	if not soundsEnabled then return end
	local base = snd.Volume
	snd.Volume = base * soundMasterVolume
	snd:Play()
	task.delay(0.05, function() snd.Volume = base end)
end

local function attachSounds(btn: GuiButton, hoverSnd: Sound?, clickSnd: Sound?)
	local h = hoverSnd or SND_HOVER
	local k = clickSnd  or SND_CLICK
	btn.MouseEnter:Connect(function() playSound(h) end)
	btn.MouseButton1Down:Connect(function() playSound(k) end)
end

-- ============================================================
-- SECTION 11C: TOOLTIP SYSTEM
-- ============================================================
-- Tooltip must be parented to `root` (the top-level Frame), NOT to
-- `widget` directly. DockWidgetPluginGui treats its children as
-- siblings of the root frame, so widget-parented overlays render
-- underneath scroll frames regardless of ZIndex. Parenting to the
-- root Frame puts the tooltip in the same layer hierarchy as all
-- other UI and lets ZIndex = 100 actually win.

local tooltipFrame = Instance.new("Frame")
tooltipFrame.Name = "_GRB_Tooltip"
tooltipFrame.Size = UDim2.new(0, 220, 0, 0)
tooltipFrame.AutomaticSize = Enum.AutomaticSize.Y
tooltipFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
tooltipFrame.BorderSizePixel = 0
tooltipFrame.ZIndex = 200
tooltipFrame.Visible = false
tooltipFrame.Parent = root  -- root Frame, not widget

do
	local co = Instance.new("UICorner")
	co.CornerRadius = UDim.new(0, 5)
	co.Parent = tooltipFrame
	local st = Instance.new("UIStroke")
	st.Color = Color3.fromRGB(90, 90, 110)
	st.Thickness = 1
	st.Parent = tooltipFrame
	local pd = Instance.new("UIPadding")
	pd.PaddingTop    = UDim.new(0, 7)
	pd.PaddingBottom = UDim.new(0, 7)
	pd.PaddingLeft   = UDim.new(0, 9)
	pd.PaddingRight  = UDim.new(0, 9)
	pd.Parent = tooltipFrame
end

local tooltipLabel = Instance.new("TextLabel")
tooltipLabel.Text = ""
tooltipLabel.Font = Enum.Font.SourceSans
tooltipLabel.TextSize = 13
tooltipLabel.TextColor3 = Color3.fromRGB(235, 235, 235)
tooltipLabel.TextWrapped = true
tooltipLabel.TextXAlignment = Enum.TextXAlignment.Left
tooltipLabel.TextYAlignment = Enum.TextYAlignment.Top
tooltipLabel.BackgroundTransparency = 1
tooltipLabel.AutomaticSize = Enum.AutomaticSize.Y
-- Concrete width fills the frame minus padding; height auto-grows.
-- Without a concrete Y the label collapses to 0px and text is invisible.
tooltipLabel.Size = UDim2.new(1, 0, 0, 16)
tooltipLabel.ZIndex = 201
tooltipLabel.Parent = tooltipFrame

local TOOLTIP_GAP = 8
local tooltipsEnabled = true

local function positionTooltip(anchor: GuiObject, placement: string)
	local aPos  = anchor.AbsolutePosition
	local aSize = anchor.AbsoluteSize
	local wPos  = root.AbsolutePosition  -- root Frame, not widget
	local lx    = aPos.X - wPos.X
	local ly    = aPos.Y - wPos.Y
	local tw    = tooltipFrame.AbsoluteSize.X
	local th    = tooltipFrame.AbsoluteSize.Y
	local x, y
	if placement == "above" then
		x = lx + aSize.X * 0.5 - tw * 0.5
		y = ly - th - TOOLTIP_GAP
	elseif placement == "left" then
		x = lx - tw - TOOLTIP_GAP
		y = ly + aSize.Y * 0.5 - th * 0.5
	elseif placement == "right" then
		x = lx + aSize.X + TOOLTIP_GAP
		y = ly + aSize.Y * 0.5 - th * 0.5
	else
		x = lx + aSize.X * 0.5 - tw * 0.5
		y = ly + aSize.Y + TOOLTIP_GAP
	end
	local ww = root.AbsoluteSize.X
	local wh = root.AbsoluteSize.Y
	x = math.clamp(x, 4, math.max(4, ww - tw - 4))
	y = math.clamp(y, 4, math.max(4, wh - th - 4))
	tooltipFrame.Position = UDim2.fromOffset(x, y)
end

local function addTooltip(anchor: GuiObject, text: string, placement: string?)
	local place = placement or "below"
	anchor.MouseEnter:Connect(function()
		if not tooltipsEnabled then return end
		tooltipLabel.Text = text
		tooltipFrame.Visible = true
		task.defer(function() positionTooltip(anchor, place) end)
	end)
	anchor.MouseLeave:Connect(function()
		tooltipFrame.Visible = false
	end)
end

-- ============================================================
-- SECTION 11C2: NOTIFICATION TOAST SYSTEM
-- ============================================================
-- A small toast bar that slides up from the bottom of the root
-- frame and auto-dismisses after a few seconds. Supports four
-- levels matching LogEntry: info, success, warn, error.
-- Call pushNotification(level, message) from anywhere in the plugin.

local TOAST_HEIGHT = 34
local TOAST_SHOW_SECS = 3.5   -- auto-dismiss after this many seconds
local TOAST_ANIM_SECS = 0.18  -- slide animation duration

local toastFrame = Instance.new("Frame")
toastFrame.Name = "_GRB_Toast"
toastFrame.Size = UDim2.new(1, 0, 0, TOAST_HEIGHT)
toastFrame.Position = UDim2.new(0, 0, 1, 0)   -- starts below visible area
toastFrame.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
toastFrame.BorderSizePixel = 0
toastFrame.ZIndex = 150
toastFrame.Parent = root
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,4); c.Parent = toastFrame
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0,10); p.PaddingRight = UDim.new(0,36)
	p.PaddingTop = UDim.new(0,4); p.PaddingBottom = UDim.new(0,4)
	p.Parent = toastFrame
end

local toastLabel = Instance.new("TextLabel")
toastLabel.Text = ""
toastLabel.Font = Enum.Font.SourceSansSemibold
toastLabel.TextSize = 13
toastLabel.TextColor3 = Color3.new(1, 1, 1)
toastLabel.TextWrapped = false
toastLabel.TextXAlignment = Enum.TextXAlignment.Left
toastLabel.BackgroundTransparency = 1
toastLabel.Size = UDim2.new(1, 0, 1, 0)
toastLabel.ZIndex = 151
toastLabel.Parent = toastFrame

local toastClose = Instance.new("TextButton")
toastClose.Text = "✕"
toastClose.Font = Enum.Font.SourceSansBold
toastClose.TextSize = 13
toastClose.TextColor3 = Color3.fromRGB(200, 200, 200)
toastClose.BackgroundTransparency = 1
toastClose.Size = UDim2.new(0, 28, 1, 0)
toastClose.Position = UDim2.new(1, -28, 0, 0)
toastClose.ZIndex = 152
toastClose.Parent = toastFrame

local toastCancelToken = { id = 0 }  -- increment to cancel any pending dismiss

local TOAST_COLORS = {
	info    = Color3.fromRGB(50, 70, 100),
	success = Color3.fromRGB(40, 90, 50),
	warn    = Color3.fromRGB(100, 80, 20),
	["error"] = Color3.fromRGB(100, 30, 30),
}

local function dismissToast()
	toastCancelToken.id += 1
	local tweenSvc = game:GetService("TweenService")
	tweenSvc:Create(toastFrame,
		TweenInfo.new(TOAST_ANIM_SECS, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = UDim2.new(0, 0, 1, 0) }
	):Play()
end

local function pushNotification(level: string, message: string)
	toastCancelToken.id += 1
	local myToken = toastCancelToken.id
	local col = TOAST_COLORS[level] or TOAST_COLORS.info
	toastFrame.BackgroundColor3 = col
	toastLabel.Text = message
	toastFrame.Position = UDim2.new(0, 0, 1, 0)
	local tweenSvc = game:GetService("TweenService")
	tweenSvc:Create(toastFrame,
		TweenInfo.new(TOAST_ANIM_SECS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0, 0, 0, root.AbsoluteSize.Y - TOAST_HEIGHT - 22) }
	):Play()
	task.delay(TOAST_SHOW_SECS, function()
		if toastCancelToken.id == myToken then dismissToast() end
	end)
end

toastClose.MouseButton1Click:Connect(dismissToast)

-- ============================================================
-- SECTION 11D: SETTINGS SYSTEM
-- ============================================================

local SETTINGS_KEY = "GunRigBuilder_Settings_v1"

type PluginSettings = {
	soundsEnabled: boolean,
	soundVolume: number,
	tooltipsEnabled: boolean,
	autoRefreshPreview: boolean,
	defaultRigType: string,
}

local DEFAULT_SETTINGS: PluginSettings = {
	soundsEnabled = true,
	soundVolume = 0.6,
	tooltipsEnabled = true,
	autoRefreshPreview = true,
	defaultRigType = "DefaultR6",
}

local activeSettings: PluginSettings = table.clone(DEFAULT_SETTINGS)

local function applySettings()
	soundsEnabled     = activeSettings.soundsEnabled
	soundMasterVolume = activeSettings.soundVolume
	tooltipsEnabled   = activeSettings.tooltipsEnabled
end

local function settingsLoad()
	local raw = plugin:GetSetting(SETTINGS_KEY)
	if type(raw) == "table" then
		for k, v in pairs(raw) do
			if (DEFAULT_SETTINGS :: any)[k] ~= nil then
				(activeSettings :: any)[k] = v
			end
		end
	end
	applySettings()
end

local function settingsSave()
	plugin:SetSetting(SETTINGS_KEY, activeSettings)
	applySettings()
end

settingsLoad()

-- ============================================================
-- SECTION 11E: GUN RIG VIEWPORT (LookVector adornments)
-- ============================================================

local function createGunViewport(parent: Instance, order: number): (Frame, (FoundParts?, { DirectionIssue }?) -> ())
	local container = Instance.new("Frame")
	container.Size = UDim2.new(1, 0, 0, 200)
	container.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	container.BorderSizePixel = 0
	container.LayoutOrder = order
	container.Parent = parent
	local cc = Instance.new("UICorner")
	cc.CornerRadius = UDim.new(0, 4)
	cc.Parent = container

	local vp = Instance.new("ViewportFrame")
	vp.Size = UDim2.new(1, -4, 1, -22)
	vp.Position = UDim2.fromOffset(2, 2)
	vp.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
	vp.BorderSizePixel = 0
	vp.LightColor = Color3.fromRGB(255, 240, 220)
	vp.LightDirection = Vector3.new(-0.4, -1, -0.3)
	vp.Ambient = Color3.fromRGB(110, 110, 120)
	vp.Parent = container

	local cam = Instance.new("Camera")
	cam.FieldOfView = 55
	cam.Parent = vp
	vp.CurrentCamera = cam

	local hint = Instance.new("TextLabel")
	hint.Text = "Scan a gun model to preview LookVectors"
	hint.Font = Enum.Font.SourceSansItalic
	hint.TextSize = 13
	hint.TextColor3 = Color3.fromRGB(140, 140, 150)
	hint.BackgroundTransparency = 1
	hint.Size = UDim2.fromScale(1, 1)
	hint.Parent = container

	local legend = Instance.new("Frame")
	legend.Size = UDim2.new(1, 0, 0, 18)
	legend.Position = UDim2.new(0, 0, 1, -20)
	legend.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	legend.BorderSizePixel = 0
	legend.Parent = container
	local ll = Instance.new("TextLabel")
	ll.Text = " ▶ green = OK   ▶ red = direction fail   ▶ white = root"
	ll.Font = Enum.Font.SourceSans
	ll.TextSize = 11
	ll.TextColor3 = Color3.fromRGB(200, 200, 200)
	ll.BackgroundTransparency = 1
	ll.Size = UDim2.fromScale(1, 1)
	ll.TextXAlignment = Enum.TextXAlignment.Left
	ll.Parent = legend

	local angle = 0
	local orbitCenter = Vector3.new()
	local orbitRadius = 8
	local previewModel: Model? = nil
	local adornments: { Instance } = {}
	local clone: Model = Instance.new("Model") -- hoisted; reassigned in setGunPreview

	local RunService = game:GetService("RunService")
	local conn = RunService.Heartbeat:Connect(function(dt)
		if not previewModel then return end
		angle += dt * 0.45
		local x = math.sin(angle) * orbitRadius
		local z = math.cos(angle) * orbitRadius
		cam.CFrame = CFrame.new(orbitCenter + Vector3.new(x, orbitRadius * 0.3, z), orbitCenter)
	end)
	container.AncestryChanged:Connect(function(_, p) if not p then conn:Disconnect() end end)

	local ARROW_LEN = 1.2

	local function clearAdornments()
		for _, a in ipairs(adornments) do
			pcall(function() a:Destroy() end)
		end
		adornments = {}
	end

	-- Draw a direction arrow using pure geometry inside the ViewportFrame.
	-- ConeHandleAdornment / ArrowHandleAdornment ONLY work when the Adornee
	-- is parented inside workspace — they silently do nothing on instances
	-- inside a ViewportFrame. So we build an arrow from a cylinder shaft
	-- and a wedge tip, both parented as children of the target part clone.
	-- The arrow points along the part's +Z (LookVector).
	local function addArrow(part: BasePart, color: Color3)
		-- Highlight outline via SelectionBox — this DOES work when both
		-- box and adornee are under the same ViewportFrame root.
		local box = Instance.new("SelectionBox")
		box.Adornee = part
		box.Color3 = color
		box.LineThickness = 0.04
		box.SurfaceTransparency = 0.88
		box.SurfaceColor3 = color
		box.Parent = vp
		table.insert(adornments, box)

		-- Shaft: thin neon cylinder along +Z
		local shaft = Instance.new("Part")
		shaft.Name = "_GRBArrowShaft"
		shaft.Size = Vector3.new(0.08, 0.08, ARROW_LEN * 0.65)
		-- offset from part center along +Z (LookVector), rotate to align Z
		shaft.CFrame = part.CFrame
			* CFrame.new(0, 0, -(ARROW_LEN * 0.35))
		shaft.Material = Enum.Material.Neon
		shaft.Color = color
		shaft.Anchored = true
		shaft.CanCollide = false
		shaft.CastShadow = false
		shaft.Parent = clone  -- inside the preview model, rendered in vp
		table.insert(adornments, shaft)

		-- Tip: wedge pointing along +Z
		local tip = Instance.new("WedgePart")
		tip.Name = "_GRBArrowTip"
		tip.Size = Vector3.new(0.18, 0.28, 0.30)
		-- place tip at the end of the shaft, rotated so wedge apex → +Z
		tip.CFrame = part.CFrame
			* CFrame.new(0, 0, -(ARROW_LEN * 0.72))
			* CFrame.Angles(math.rad(90), 0, 0)
		tip.Material = Enum.Material.Neon
		tip.Color = color
		tip.Anchored = true
		tip.CanCollide = false
		tip.CastShadow = false
		tip.Parent = clone
		table.insert(adornments, tip)
	end

	local function setGunPreview(found: FoundParts?, issues: { DirectionIssue }?, sourceModel: Model?)
		clearAdornments()
		if previewModel then
			previewModel:Destroy()
			previewModel = nil
		end
		if not found or not found.root then
			hint.Visible = true
			return
		end
		hint.Visible = false

		local failSet: { [string]: boolean } = {}
		for _, issue in ipairs(issues or {}) do
			failSet[issue.partName] = true
		end

		-- If the caller provides the real source model, clone all of it
		-- so the viewport shows the actual weapon geometry, not proxy cubes.
		-- We still need our own mini-clones to attach arrows to, so we build
		-- two layers: the full model clone (geometry) plus small invisible
		-- marker Parts at each structural part's CFrame (arrow targets).
		if sourceModel then
			local fullClone = sourceModel:Clone()
			-- Anchor everything so physics don't run inside the VP
			for _, desc in ipairs(fullClone:GetDescendants()) do
				if desc:IsA("BasePart") then
					(desc :: BasePart).Anchored = true
				end
			end
			fullClone.Parent = vp
		end

		local clone_new = Instance.new("Model")
		clone_new.Name = "_GRB_Arrows"
		clone = clone_new

		-- Thin invisible marker Part at each structural part location — arrows
		-- point from there so they align with the real geometry.
		local function markerAt(src: BasePart, color: Color3)
			local p = Instance.new("Part")
			p.Size = Vector3.new(0.05, 0.05, 0.05)
			p.CFrame = src.CFrame
			p.Transparency = 1
			p.Anchored = true
			p.CanCollide = false
			p.CastShadow = false
			p.Name = src.Name .. "_Marker"
			p.Parent = clone
			addArrow(p, color)
		end

		local GREEN = Color3.fromRGB(80, 210, 100)
		local RED   = Color3.fromRGB(220, 80,  80)
		local WHITE = Color3.fromRGB(230, 230, 230)

		markerAt(found.root :: BasePart, WHITE)

		local checks: { { part: BasePart? } } = {
			{ part = found.slide },
			{ part = found.magazine },
			{ part = found.muzzle },
			{ part = found.aim },
			{ part = found.ejectShell },
		}
		for _, entry in ipairs(checks) do
			if entry.part then
				markerAt(entry.part :: BasePart, failSet[entry.part.Name] and RED or GREEN)
			end
		end
		for _, hp in pairs(found.hinges) do
			markerAt(hp, failSet[hp.Name] and RED or GREEN)
		end

		clone.Parent = vp
		previewModel = clone

		-- Reframe based on what's actually in the VP
		local reframeTarget = vp:FindFirstChildOfClass("Model")
		if reframeTarget then
			local ok, cf, sz = pcall(function() return (reframeTarget :: Model):GetBoundingBox() end)
			if ok and cf and sz then
				orbitCenter = cf.Position
				orbitRadius = math.max(sz.X, sz.Y, sz.Z) * 1.4 + 2
			end
		end
	end

	-- Also expose a function to insert a loaded accessory model into the VP
	-- for the catalogue viewer — called externally via the hoisted setter.
	local function addAccessoryToPreview(accessoryModel: Model)
		if not previewModel then return end
		local cloneAcc = accessoryModel:Clone()
		for _, desc in ipairs(cloneAcc:GetDescendants()) do
			if desc:IsA("BasePart") then
				(desc :: BasePart).Anchored = true
			end
		end
		-- Position near the current gun preview
		cloneAcc.Parent = vp
	end

	return container, setGunPreview, addAccessoryToPreview
end

-- ============================================================
-- SECTION 11F: VIEWMODEL COLLISION GROUP HELPER
-- ============================================================

local PhysicsService = game:GetService("PhysicsService")
local VM_COLLISION_GROUP = "ViewModel"

local function ensureViewModelCollisionGroup(): boolean
	local groups = PhysicsService:GetRegisteredCollisionGroups()
	for _, g in ipairs(groups) do
		if g.name == VM_COLLISION_GROUP then
			return true
		end
	end
	local ok = pcall(function()
		PhysicsService:RegisterCollisionGroup(VM_COLLISION_GROUP)
	end)
	if not ok then return false end
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(VM_COLLISION_GROUP, "Default", false)
	end)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(VM_COLLISION_GROUP, VM_COLLISION_GROUP, false)
	end)
	return true
end

local function assignViewModelCollisionGroup(model: Model): number
	if not ensureViewModelCollisionGroup() then return 0 end
	local count = 0
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			pcall(function()
				(desc :: BasePart).CollisionGroup = VM_COLLISION_GROUP
			end)
			count += 1
		end
	end
	return count
end

-- ============================================================
-- Cross-section forward declarations
-- ============================================================
-- Hoisted here so sections 12/13/13B can share state while each
-- section's own locals are wrapped in do...end to stay under the
-- Lua 200-local-per-chunk limit.

local targetModel: Model? = nil
local pushBuildLog: (LogEntry) -> ()  = function(_) end
local clearBuildLog: () -> ()          = function() end
local pushVmLog: (LogEntry) -> ()     = function(_) end
local clearVmLog: () -> ()             = function() end
local setPreviewModel: (Instance?) -> () = function(_) end
local pushLibraryLog: (LogEntry) -> () = function(_) end
local clearLibraryLog: () -> ()        = function() end
local refreshLibraryList: () -> ()     = function() end
local setGunPreview: (FoundParts?, { DirectionIssue }?, Model?) -> () = function(_, _, _) end
local addAccessoryToGunPreview: (Model) -> () = function(_) end
local currentRigType = "DefaultR6"
local limbRowContainer: Frame? = nil
local limbRowGetters: { [string]: () -> LimbOverride } = {}
local placeInFlight = false
local getApplyVmCollisionGroup: () -> boolean = function() return true end

-- ============================================================
-- SECTION 12: BUILD TAB CONTENTS
-- ============================================================

do -- scope block keeps build-tab locals from piling up in the chunk
	sectionLabel(buildPage, "Target Model", 1)
	hintLabel(buildPage, "Select your gun Model in the Explorer, then click the button below to set it as the target.", 2)

	local targetLabel = Instance.new("TextLabel")
	targetLabel.Text = "No model selected"
	targetLabel.Font = Enum.Font.SourceSansItalic
	targetLabel.TextSize = 13
	targetLabel.TextColor3 = Color3.fromRGB(200, 200, 120)
	targetLabel.TextXAlignment = Enum.TextXAlignment.Left
	targetLabel.BackgroundTransparency = 1
	targetLabel.Size = UDim2.new(1, 0, 0, 20)
	targetLabel.LayoutOrder = 3
	targetLabel.Parent = buildPage

	local refreshTargetBtn = actionButton(buildPage, "Use Selected Model as Target", 4, Color3.fromRGB(80, 80, 130))
	attachSounds(refreshTargetBtn)
	addTooltip(refreshTargetBtn, "Select one Model in the Explorer, then click this to register it as the gun rig build target.", "below")

	local unsetTargetBtn = actionButton(buildPage, "Unset Target", 4, Color3.fromRGB(100, 60, 60))
	unsetTargetBtn.Size = UDim2.new(0.48, -2, 0, 28)
	local copyModelBtn  = actionButton(buildPage, "Copy Model to Workspace", 4, Color3.fromRGB(60, 90, 60))
	copyModelBtn.Size   = UDim2.new(0.48, -2, 0, 28)

	-- Place the two small buttons side-by-side inside a row frame
	do
		local btnRow = Instance.new("Frame")
		btnRow.Size = UDim2.new(1, 0, 0, 28)
		btnRow.BackgroundTransparency = 1
		btnRow.LayoutOrder = 4
		btnRow.Parent = buildPage
		-- re-parent the buttons into the row
		unsetTargetBtn.Parent = btnRow
		unsetTargetBtn.Position = UDim2.new(0, 0, 0, 0)
		unsetTargetBtn.LayoutOrder = 1
		copyModelBtn.Parent = btnRow
		copyModelBtn.Position = UDim2.new(0.5, 2, 0, 0)
		copyModelBtn.LayoutOrder = 2
	end
	attachSounds(unsetTargetBtn)
	attachSounds(copyModelBtn)
	addTooltip(unsetTargetBtn, "Clears the current target so the plugin stops tracking the model.", "below")
	addTooltip(copyModelBtn,   "Clones the target model and places the copy in the same parent. Useful for testing before destructive changes.", "below")

	sectionLabel(buildPage, "LookVector Preview", 5)
	hintLabel(buildPage, "After a Scan the viewport shows each structural part with a directional cone — green = OK, red = direction mismatch, white = root.", 6)
	local _gpFrame, _gpSet, _gpAddAcc = createGunViewport(buildPage, 7)
	setGunPreview = _gpSet
	addAccessoryToGunPreview = _gpAddAcc

	sectionLabel(buildPage, "Build Options", 8)
	local _, getBuildMotors = makeCheckbox(buildPage, "Build structural Motor6Ds", 9, true)
	local _, getBuildWelds  = makeCheckbox(buildPage, "Build cosmetic welds (Body/Grip/Magazine/Slide/Hinge folders)", 10, true)
	local _, getIgnoreDirWarnings = makeCheckbox(buildPage, "Build anyway if direction check fails", 11, false)
	addTooltip((buildPage:FindFirstChild("9") or buildPage), "Creates Motor6D joints from root to each structural part (Slide, Magazine, Muzzle, Aim, EjectShell, Hinge_#).", "right")

	sectionLabel(buildPage, "Part Properties", 12)
	hintLabel(buildPage, "Lists each structural part found in the last Scan. Edit RootPriority per part, then click Apply to write the values. The 'All Main' field below sets RootPriority on every BasePart inside the Main folder at once.", 13)

	-- Per-part RootPriority list — rebuilt every Scan
	local partPriorityFrame = Instance.new("Frame")
	partPriorityFrame.Size = UDim2.new(1, 0, 0, 0)
	partPriorityFrame.AutomaticSize = Enum.AutomaticSize.Y
	partPriorityFrame.BackgroundTransparency = 1
	partPriorityFrame.LayoutOrder = 14
	partPriorityFrame.Parent = buildPage
	do
		local pl = Instance.new("UIListLayout")
		pl.SortOrder = Enum.SortOrder.LayoutOrder
		pl.Padding = UDim.new(0, 3)
		pl.Parent = partPriorityFrame
	end

	-- Map of partName -> getter function, rebuilt on each scan
	local partPriorityGetters: { { name: string, part: BasePart, getValue: () -> number } } = {}

	local function buildPartPriorityList(found: FoundParts)
		-- Clear old rows
		for _, child in ipairs(partPriorityFrame:GetChildren()) do
			if not child:IsA("UIListLayout") then child:Destroy() end
		end
		partPriorityGetters = {}

		local entries: { { label: string, part: BasePart } } = {}
		if found.root then
			table.insert(entries, { label = found.root.Name .. " (root)", part = found.root :: BasePart })
		end
		local function tryAdd(part: BasePart?, label: string)
			if part then table.insert(entries, { label = label, part = part :: BasePart }) end
		end
		tryAdd(found.slide,      "Slide")
		tryAdd(found.magazine,   "Magazine")
		tryAdd(found.muzzle,     "Muzzle")
		tryAdd(found.aim,        "Aim")
		tryAdd(found.ejectShell, "EjectShell")
		local hnums: { number } = {}
		for n in pairs(found.hinges) do table.insert(hnums, n) end
		table.sort(hnums)
		for _, n in ipairs(hnums) do
			tryAdd(found.hinges[n], string.format("Hinge_%d", n))
		end

		if #entries == 0 then
			local empty = Instance.new("TextLabel")
			empty.Text = "(scan a model to populate)"
			empty.Font = Enum.Font.SourceSansItalic
			empty.TextSize = 12
			empty.TextColor3 = Color3.fromRGB(140, 140, 140)
			empty.BackgroundTransparency = 1
			empty.Size = UDim2.new(1, 0, 0, 18)
			empty.TextXAlignment = Enum.TextXAlignment.Left
			empty.LayoutOrder = 1
			empty.Parent = partPriorityFrame
			return
		end

		for idx, entry in ipairs(entries) do
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 24)
			row.BackgroundTransparency = 1
			row.LayoutOrder = idx
			row.Parent = partPriorityFrame

			local nameLbl = Instance.new("TextLabel")
			nameLbl.Text = entry.label
			nameLbl.Font = Enum.Font.SourceSans
			nameLbl.TextSize = 13
			nameLbl.TextColor3 = Color3.fromRGB(210, 210, 210)
			nameLbl.TextXAlignment = Enum.TextXAlignment.Left
			nameLbl.BackgroundTransparency = 1
			nameLbl.Size = UDim2.new(0.65, 0, 1, 0)
			nameLbl.Parent = row

			local box = Instance.new("TextBox")
			box.Text = tostring(entry.part.RootPriority or 0)
			box.Font = Enum.Font.SourceSans
			box.TextSize = 13
			box.TextColor3 = Color3.new(1, 1, 1)
			box.BackgroundColor3 = Color3.fromRGB(55, 55, 60)
			box.Position = UDim2.new(0.65, 4, 0, 2)
			box.Size = UDim2.new(0.35, -4, 1, -4)
			box.ClearTextOnFocus = false
			box.Parent = row

			local function getValue(): number
				return tonumber(box.Text) or 0
			end
			table.insert(partPriorityGetters, { name = entry.label, part = entry.part, getValue = getValue })
		end
	end

	local applyPartPriorityBtn = actionButton(buildPage, "Apply Per-Part RootPriority", 15, Color3.fromRGB(80, 100, 130))
	attachSounds(applyPartPriorityBtn)
	addTooltip(applyPartPriorityBtn, "Writes the RootPriority property on each listed part using the values in the fields above.", "above")

	-- All-Main RootPriority
	local allMainRPRow = Instance.new("Frame")
	allMainRPRow.Size = UDim2.new(1, 0, 0, 24)
	allMainRPRow.BackgroundTransparency = 1
	allMainRPRow.LayoutOrder = 16
	allMainRPRow.Parent = buildPage
	do
		local lbl = Instance.new("TextLabel")
		lbl.Text = "All Main parts RootPriority"
		lbl.Font = Enum.Font.SourceSans
		lbl.TextSize = 13
		lbl.TextColor3 = Color3.fromRGB(210, 210, 210)
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.BackgroundTransparency = 1
		lbl.Size = UDim2.new(0.65, 0, 1, 0)
		lbl.Parent = allMainRPRow
	end
	local allMainRPBox = Instance.new("TextBox")
	allMainRPBox.Text = "0"
	allMainRPBox.Font = Enum.Font.SourceSans
	allMainRPBox.TextSize = 13
	allMainRPBox.TextColor3 = Color3.new(1, 1, 1)
	allMainRPBox.BackgroundColor3 = Color3.fromRGB(55, 55, 60)
	allMainRPBox.Position = UDim2.new(0.65, 4, 0, 2)
	allMainRPBox.Size = UDim2.new(0.35, -4, 1, -4)
	allMainRPBox.ClearTextOnFocus = false
	allMainRPBox.Parent = allMainRPRow

	local applyAllMainRPBtn = actionButton(buildPage, "Apply to All Main Parts", 17, Color3.fromRGB(80, 100, 130))
	attachSounds(applyAllMainRPBtn)
	addTooltip(applyAllMainRPBtn, "Sets RootPriority property on every BasePart inside the Main folder to the value above.", "above")

	applyPartPriorityBtn.MouseButton1Click:Connect(function()
		if #partPriorityGetters == 0 then
			pushBuildLog({ level = "warn", text = "No parts listed — run a Scan first." })
			return
		end
		ChangeHistoryService:SetWaypoint("Before Apply Per-Part RootPriority")
		local count = 0
		for _, entry in ipairs(partPriorityGetters) do
			if entry.part and entry.part.Parent then
				entry.part.RootPriority = entry.getValue()
				count += 1
			end
		end
		pushBuildLog({ level = "success", text = string.format("RootPriority applied to %d part(s).", count) })
		pushNotification("success", string.format("RootPriority applied to %d part(s).", count))
		ChangeHistoryService:SetWaypoint("Apply Per-Part RootPriority")
	end)

	applyAllMainRPBtn.MouseButton1Click:Connect(function()
		if not targetModel then
			pushBuildLog({ level = "error", text = "No target model set." })
			return
		end
		local mainFolder = targetModel:FindFirstChild("Main")
		if not mainFolder then
			pushBuildLog({ level = "warn", text = "No Main folder found — build the rig first." })
			return
		end
		local value = tonumber(allMainRPBox.Text) or 0
		ChangeHistoryService:SetWaypoint("Before Apply All Main RootPriority")
		local count = 0
		for _, desc in ipairs(mainFolder:GetDescendants()) do
			if desc:IsA("BasePart") then
				desc.RootPriority = value
				count += 1
			end
		end
		pushBuildLog({ level = "success", text = string.format("RootPriority=%d applied to %d BasePart(s) in Main.", value, count) })
		pushNotification("success", string.format("RootPriority=%d → %d parts in Main.", value, count))
		ChangeHistoryService:SetWaypoint("Apply All Main RootPriority")
	end)

	sectionLabel(buildPage, "Live Import", 18)
	hintLabel(buildPage, "Select a Folder, Model, or Part elsewhere then click Import to clone it into your target model for positioning.", 19)
	local importBtn = actionButton(buildPage, "Import Selected Into Target", 20, Color3.fromRGB(80, 80, 130))
	attachSounds(importBtn)

	sectionLabel(buildPage, "Actions", 21)
	local scanBtn  = actionButton(buildPage, "Scan (validate only)", 22, Color3.fromRGB(90, 90, 90))
	local buildBtn = actionButton(buildPage, "Build Gun Rig", 23, Color3.fromRGB(70, 130, 70))
	attachSounds(scanBtn)
	attachSounds(buildBtn, nil, SND_BUILD)
	addTooltip(scanBtn,  "Validates parts, direction checks, and weld folders. Makes no changes to your model.", "above")
	addTooltip(buildBtn, "Runs the full build: Motor6Ds into Constraints/Motor6Ds, WeldConstraints into Constraints/Welds, weld-source folders moved into Main.", "above")

	sectionLabel(buildPage, "Log", 24)
	do local _f, _p, _c = makeLogPanel(buildPage, 25, 180); pushBuildLog = _p; clearBuildLog = _c end

	-- targetModel, pushBuildLog, clearBuildLog declared above (hoisted)

	local function refreshTargetFromSelection()
		local sel = Selection:Get()
		if #sel == 1 and sel[1]:IsA("Model") then
			targetModel = sel[1] :: Model
			targetLabel.Text = "Target: " .. targetModel:GetFullName()
			targetLabel.TextColor3 = Color3.fromRGB(140, 220, 140)
		else
			targetLabel.Text = "Select exactly one Model in the Explorer, then click this button."
			targetLabel.TextColor3 = Color3.fromRGB(220, 140, 140)
		end
	end

	refreshTargetBtn.MouseButton1Click:Connect(refreshTargetFromSelection)

	unsetTargetBtn.MouseButton1Click:Connect(function()
		targetModel = nil
		targetLabel.Text = "No model selected"
		targetLabel.TextColor3 = Color3.fromRGB(200, 200, 120)
		setGunPreview(nil, nil)
		buildPartPriorityList({ root = nil, rootKind = "none", slide = nil,
			magazine = nil, muzzle = nil, aim = nil, ejectShell = nil, hinges = {} })
		pushBuildLog({ level = "info", text = "Target cleared." })
	end)

	copyModelBtn.MouseButton1Click:Connect(function()
		if not targetModel then
			pushBuildLog({ level = "error", text = "No target model set." })
			playSound(SND_ERROR)
			return
		end
		ChangeHistoryService:SetWaypoint("Before Copy Model")
		local copy = targetModel:Clone()
		copy.Name = targetModel.Name .. "_Copy"
		copy.Parent = targetModel.Parent
		Selection:Set({ copy })
		pushBuildLog({ level = "success", text = string.format("Copied '%s' → '%s'.", targetModel.Name, copy.Name) })
		playSound(SND_SAVE)
		pushNotification("success", string.format("Model copied: %s_Copy", targetModel.Name))
		ChangeHistoryService:SetWaypoint("Copy Model")
	end)

	-- Helper: apply animation priority attribute to all structural parts
	importBtn.MouseButton1Click:Connect(function()
		if not targetModel then
			pushBuildLog({ level = "error", text = "No target model set. Click 'Use Selected Model as Target' first." })
			playSound(SND_ERROR)
			return
		end
		local sel = Selection:Get()
		if #sel ~= 1 then
			pushBuildLog({ level = "error", text = "Select exactly one Folder, Model, or Part to import." })
			playSound(SND_ERROR)
			return
		end
		ChangeHistoryService:SetWaypoint("Before Import Parts")
		local _, log = importPartsFromSelectionInto(targetModel, sel[1])
		for _, entry in ipairs(log) do
			pushBuildLog(entry)
		end
		ChangeHistoryService:SetWaypoint("Import Parts")
	end)

	scanBtn.MouseButton1Click:Connect(function()
		clearBuildLog()
		if not targetModel then
			pushBuildLog({ level = "error", text = "No target model set." })
			playSound(SND_ERROR)
			return
		end
		local found, folders, notes = scanModel(targetModel)
		for _, note in ipairs(notes) do
			pushBuildLog({ level = "warn", text = note })
		end
		if found.root then
			pushBuildLog({ level = "success", text = string.format("Root: %s (%s)", found.root.Name, found.rootKind) })
		else
			pushBuildLog({ level = "error", text = "No Handle or Grip part found. This is required." })
			playSound(SND_ERROR)
		end

		local function reportPart(part: BasePart?, label: string)
			if part then
				pushBuildLog({ level = "info", text = label .. ": " .. part.Name })
			else
				pushBuildLog({ level = "info", text = label .. ": not found (optional)" })
			end
		end
		reportPart(found.slide, "Slide")
		reportPart(found.magazine, "Magazine")
		reportPart(found.muzzle, "Muzzle")
		reportPart(found.aim, "Aim")
		reportPart(found.ejectShell, "EjectShell")

		local hingeNums: { number } = {}
		for num in pairs(found.hinges) do table.insert(hingeNums, num) end
		table.sort(hingeNums)
		if #hingeNums == 0 then
			pushBuildLog({ level = "info", text = "Hinges: none" })
		else
			for _, num in ipairs(hingeNums) do
				pushBuildLog({ level = "info", text = string.format("Hinge_%d: %s", num, found.hinges[num].Name) })
			end
		end

		local function reportFolder(folder: Folder?, label: string)
			if folder then
				pushBuildLog({ level = "info", text = string.format("%s folder: %d part(s)", label, #folder:GetDescendants()) })
			else
				pushBuildLog({ level = "info", text = label .. " folder: absent" })
			end
		end
		reportFolder(folders.Body, "Body")
		reportFolder(folders.Grip, "Grip")
		reportFolder(folders.Magazine, "Magazine")
		reportFolder(folders.Slide, "Slide")

		local issues: { DirectionIssue } = {}
		local allChecked: { DirectionIssue } = {}
		if found.root then
			issues, allChecked = validateDirections(found)
			for _, checked in ipairs(allChecked) do
				if checked.dot <= DOT_WARN_THRESHOLD then
					pushBuildLog({ level = "warn", text = string.format("Direction FAIL '%s' (dot=%s)", checked.partName, fmtDot(checked.dot)) })
				else
					pushBuildLog({ level = "success", text = string.format("Direction OK '%s' (dot=%s)", checked.partName, fmtDot(checked.dot)) })
				end
			end
			if #allChecked == 0 then
				pushBuildLog({ level = "info", text = "No other structural parts to direction-check." })
			end
		end

		-- Update viewport and part priority list
		setGunPreview(found, issues, targetModel)
		buildPartPriorityList(found)

		pushBuildLog({ level = "info", text = "Scan complete — no changes made." })
		pushNotification("info", "Scan complete — no changes made.")
	end)

	buildBtn.MouseButton1Click:Connect(function()
		clearBuildLog()
		if not targetModel then
			pushBuildLog({ level = "error", text = "No target model set." })
			playSound(SND_ERROR)
			return
		end
		if not targetModel.Parent then
			pushBuildLog({ level = "error", text = "Target model was deleted. Re-select and refresh." })
			playSound(SND_ERROR)
			return
		end

		ChangeHistoryService:SetWaypoint("Before Build Gun Rig")

		local result = buildGunRig(targetModel, {
			buildStructuralMotors    = getBuildMotors(),
			buildCosmeticWelds       = getBuildWelds(),
			ignoreDirectionWarnings  = getIgnoreDirWarnings(),
		})

		for _, entry in ipairs(result.log) do
			pushBuildLog(entry)
		end

		if result.ok then
			-- Refresh viewport and part list with post-build scan state
			local found2, _, _ = scanModel(targetModel)
			local issues2, _ = validateDirections(found2)
			setGunPreview(found2, issues2, targetModel)
			buildPartPriorityList(found2)

			playSound(SND_BUILD)
			pushNotification("success", "✓ Gun Rig built successfully.")
			ChangeHistoryService:SetWaypoint("Build Gun Rig")
		else
			playSound(SND_ERROR)
			pushNotification("error", "✕ Build failed — check the log.")
			ChangeHistoryService:SetWaypoint("Build Gun Rig (failed)")
		end
	end)

	-- ── Attach Gun to ViewModel ─────────────────────────────────────────────
	-- Creates a Motor6D from the ViewModel's HumanoidRootPart/Root to the
	-- gun's Handle, so the gun follows the arms in first-person.
	-- Both the ViewModel and the Gun Rig target must be set.
	sectionLabel(buildPage, "Attach Gun to ViewModel", 26)
	hintLabel(buildPage, "Select a built ViewModel in the Explorer, then click Attach. Creates a Motor6D from the ViewModel root to the gun Handle so the gun is welded to the arms.", 27)

	local attachGunBtn = actionButton(buildPage, "Attach Gun to Selected ViewModel", 28, Color3.fromRGB(120, 80, 140))
	attachSounds(attachGunBtn)
	addTooltip(attachGunBtn, "Select your built ViewModel Model, then click. Creates Motor6D: ViewModel Root → Gun Handle, parented under the ViewModel's root part.", "above")

	attachGunBtn.MouseButton1Click:Connect(function()
		if not targetModel then
			pushBuildLog({ level = "error", text = "No gun rig target set. Set one from the Gun Rig tab first." })
			pushNotification("error", "No gun target set.")
			playSound(SND_ERROR)
			return
		end
		local sel = Selection:Get()
		if #sel ~= 1 or not sel[1]:IsA("Model") then
			pushBuildLog({ level = "error", text = "Select exactly one ViewModel Model in the Explorer first." })
			pushNotification("error", "Select one ViewModel Model.")
			playSound(SND_ERROR)
			return
		end
		local vmModel = sel[1] :: Model

		-- Find the ViewModel root part (HumanoidRootPart or Root)
		local vmRoot: BasePart? = vmModel:FindFirstChild("HumanoidRootPart") :: BasePart?
			or vmModel:FindFirstChild("Root") :: BasePart?
		if not vmRoot then
			-- Fall back to PrimaryPart
			vmRoot = vmModel.PrimaryPart
		end
		if not vmRoot then
			pushBuildLog({ level = "error", text = string.format(
				"'%s' has no HumanoidRootPart, Root, or PrimaryPart — can't create the joint.",
				vmModel.Name
				)})
			pushNotification("error", "ViewModel has no root part.")
			playSound(SND_ERROR)
			return
		end

		-- Find the gun Handle
		local gunHandle: BasePart? = targetModel:FindFirstChild("Handle") :: BasePart?
			or targetModel:FindFirstChild("Grip") :: BasePart?
		-- Also search inside Main folder
		if not gunHandle then
			local mainF = targetModel:FindFirstChild("Main")
			if mainF then
				gunHandle = mainF:FindFirstChild("Handle") :: BasePart?
					or mainF:FindFirstChild("Grip") :: BasePart?
			end
		end
		if not gunHandle then
			pushBuildLog({ level = "error", text = string.format(
				"Gun model '%s' has no Handle or Grip part.",
				targetModel.Name
				)})
			pushNotification("error", "Gun has no Handle/Grip.")
			playSound(SND_ERROR)
			return
		end

		ChangeHistoryService:SetWaypoint("Before Attach Gun to ViewModel")

		-- Remove any existing gun attachment motor
		local existing = vmRoot:FindFirstChild("_GRB_GunAttach")
		if existing then existing:Destroy() end

		-- Place the gun model at the ViewModel root's position so the Motor6D
		-- starts at a neutral offset. Users can adjust C0/C1 after placement.
		local motor = Instance.new("Motor6D")
		motor.Name = "_GRB_GunAttach"
		motor.Part0 = vmRoot
		motor.Part1 = gunHandle
		-- C0 = offset from vmRoot center to where the grip should sit.
		-- Default: slightly forward and down (typical first-person gun hold).
		motor.C0 = CFrame.new(0, -0.5, -1.5)
		motor.C1 = CFrame.new()
		motor.Parent = vmRoot  -- parent onto the root part (same convention as arm motors)

		pushBuildLog({ level = "success", text = string.format(
			"Motor6D '_GRB_GunAttach' created: %s.%s → %s.%s. Adjust C0 in Properties to position the gun.",
			vmModel.Name, vmRoot.Name, targetModel.Name, gunHandle.Name
			)})
		pushNotification("success", "✓ Gun attached to ViewModel.")
		playSound(SND_BUILD)
		ChangeHistoryService:SetWaypoint("Attach Gun to ViewModel")

		-- Select the motor so the user can immediately adjust C0 in Properties
		Selection:Set({ motor })
	end)

end -- end do: section 12

-- ============================================================
-- SECTION 13: VIEWMODEL TAB CONTENTS
-- ============================================================

do -- scope block: ViewModel tab locals die here

	-- currentRigType, limbRowContainer, limbRowGetters declared above (hoisted)
	-- placeInFlight declared above (hoisted)

	sectionLabel(vmPage, "ViewModel Library", 1)
	hintLabel(vmPage, "Load saved ViewModel Models from your Explorer. The plugin checks that the Model has a Root/HumanoidRootPart and recognizable arm part names (R6 or R15). Once loaded it clones it on every Build.", 2)

	-- ── ViewModel slot list ─────────────────────────────────────────────────
	-- Each entry: { displayName, rigType, model? }
	-- rigType drives the rig selector — loading a model here auto-selects
	-- the matching rig type so the per-limb overrides match.

	local vmLibraryFrame = Instance.new("Frame")
	vmLibraryFrame.Size = UDim2.new(1, 0, 0, 0)
	vmLibraryFrame.AutomaticSize = Enum.AutomaticSize.Y
	vmLibraryFrame.BackgroundTransparency = 1
	vmLibraryFrame.LayoutOrder = 2
	vmLibraryFrame.Parent = vmPage
	do
		local vl = Instance.new("UIListLayout")
		vl.SortOrder = Enum.SortOrder.LayoutOrder
		vl.Padding = UDim.new(0, 4)
		vl.Parent = vmLibraryFrame
	end

	-- Detect which rig type a model belongs to by checking part names.
	-- Returns "DefaultR6", "DefaultR15", "CustomMeshR6", "CustomMeshR15", or nil.
	local R6_ARM_NAMES  = { "left arm", "right arm" }
	local R15_ARM_NAMES = { "leftupperarm", "rightupperarm", "leftlowerarm", "rightlowerarm" }

	local function detectRigType(model: Model): string?
		local hasRoot = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Root")
		local partNames: { [string]: boolean } = {}
		for _, desc in ipairs(model:GetDescendants()) do
			if desc:IsA("BasePart") then
				partNames[string.lower(desc.Name)] = true
			end
		end
		local isR6, isR15 = false, false
		for _, n in ipairs(R6_ARM_NAMES) do
			if partNames[n] then isR6 = true end
		end
		for _, n in ipairs(R15_ARM_NAMES) do
			if partNames[n] then isR15 = true end
		end
		if not (isR6 or isR15) then return nil end
		-- Prefer R15 if it has the 4-bone chain; use R6 for single-bone
		-- Treat as Custom if the model has mesh-based arm parts (MeshPart children)
		local hasMesh = false
		for _, desc in ipairs(model:GetDescendants()) do
			if desc:IsA("MeshPart") or (desc:IsA("SpecialMesh") and desc.MeshId ~= "") then
				hasMesh = true; break
			end
		end
		if isR15 then
			return hasMesh and "CustomMeshR15" or "DefaultR15"
		else
			return hasMesh and "CustomMeshR6" or "DefaultR6"
		end
	end

	-- Stored loaded ViewModels: rigType → Model
	local loadedVMs: { [string]: Model } = {}
	-- Ordered display list of loaded entries (name, rigType)
	local vmEntries: { { name: string, rigType: string } } = {}
	local vmEntryRows: { Frame } = {}
	-- Only one rig may be in use at a time — the rigType currently
	-- registered under script.ViewModels (nil = none). Use/Unuse toggles
	-- it; Remove clears it if the removed entry was the one in use.
	local inUseRigType: string? = nil

	-- Tears down the in-use rig: destroys its script.ViewModels copy and
	-- clears the viewport preview so no stale rig lingers in the viewframe.
	local function unuseCurrentRig()
		if not inUseRigType then
			return
		end
		local folder = script:FindFirstChild("ViewModels")
		local copy = folder and folder:FindFirstChild(inUseRigType)
		if copy then
			copy:Destroy()
		end
		setPreviewModel(nil)
		inUseRigType = nil
	end

	local function rebuildVMLibraryRows()
		for _, row in ipairs(vmEntryRows) do
			pcall(function() row:Destroy() end)
		end
		vmEntryRows = {}

		if #vmEntries == 0 then
			local empty = Instance.new("TextLabel")
			empty.Text = "(no ViewModels loaded — use 'Load from Selection' below)"
			empty.Font = Enum.Font.SourceSansItalic
			empty.TextSize = 12
			empty.TextColor3 = Color3.fromRGB(140, 140, 140)
			empty.BackgroundTransparency = 1
			empty.Size = UDim2.new(1, 0, 0, 20)
			empty.TextXAlignment = Enum.TextXAlignment.Left
			empty.LayoutOrder = 1
			empty.Parent = vmLibraryFrame
			table.insert(vmEntryRows, empty :: any)
			return
		end

		for idx, entry in ipairs(vmEntries) do
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 44)
			row.BackgroundColor3 = Color3.fromRGB(34, 34, 40)
			row.BorderSizePixel = 0
			row.LayoutOrder = idx
			row.Parent = vmLibraryFrame
			do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,4); c.Parent = row end
			table.insert(vmEntryRows, row)

			local nameLbl = Instance.new("TextLabel")
			nameLbl.Text = string.format("✓  %s  [%s]", entry.name, entry.rigType)
			nameLbl.Font = Enum.Font.SourceSansSemibold
			nameLbl.TextSize = 12
			nameLbl.TextColor3 = Color3.fromRGB(120, 220, 120)
			nameLbl.TextXAlignment = Enum.TextXAlignment.Left
			nameLbl.BackgroundTransparency = 1
			nameLbl.Position = UDim2.fromOffset(8, 4)
			nameLbl.Size = UDim2.new(1, -16, 0, 16)
			nameLbl.Parent = row

			-- Use / Remove buttons
			local useBtn = Instance.new("TextButton")
			useBtn.Text = (inUseRigType == entry.rigType) and "Unuse" or "Use"
			useBtn.Font = Enum.Font.SourceSansSemibold
			useBtn.TextSize = 11
			useBtn.TextColor3 = Color3.new(1,1,1)
			useBtn.BackgroundColor3 = Color3.fromRGB(70, 110, 160)
			useBtn.Size = UDim2.new(0.48, -6, 0, 22)
			useBtn.Position = UDim2.fromOffset(6, 20)
			useBtn.AutoButtonColor = true
			useBtn.Parent = row
			do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,3); c.Parent = useBtn end
			attachSounds(useBtn)

			local removeBtn = Instance.new("TextButton")
			removeBtn.Text = "Remove"
			removeBtn.Font = Enum.Font.SourceSansSemibold
			removeBtn.TextSize = 11
			removeBtn.TextColor3 = Color3.new(1,1,1)
			removeBtn.BackgroundColor3 = Color3.fromRGB(110, 50, 50)
			removeBtn.Size = UDim2.new(0.48, -6, 0, 22)
			removeBtn.Position = UDim2.new(0.52, 0, 0, 20)
			removeBtn.AutoButtonColor = true
			removeBtn.Parent = row
			do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,3); c.Parent = removeBtn end
			attachSounds(removeBtn)

			local capturedEntry = entry
			useBtn.MouseButton1Click:Connect(function()
				-- Toggle off: this entry is the one in use → Unuse it,
				-- clearing both the script.ViewModels copy and the preview.
				if inUseRigType == capturedEntry.rigType then
					unuseCurrentRig()
					rebuildVMLibraryRows()
					pushNotification("info", string.format("'%s' is no longer in use.", capturedEntry.name))
					playSound(SND_DELETE)
					return
				end

				-- Only one rig in use at a time — block, don't silently swap.
				if inUseRigType then
					pushNotification("error", string.format("A %s rig is already in use — click its 'Unuse' button first.", inUseRigType))
					playSound(SND_ERROR)
					return
				end

				-- Register this model under script.ViewModels/<rigType>
				local folder = script:FindFirstChild("ViewModels")
				if not folder then
					folder = Instance.new("Folder")
					folder.Name = "ViewModels"
					folder.Parent = script
				end
				local ex = folder:FindFirstChild(capturedEntry.rigType)
				if ex then ex:Destroy() end
				local copy = loadedVMs[capturedEntry.rigType]:Clone()
				copy.Name = capturedEntry.rigType
				copy.Parent = folder
				inUseRigType = capturedEntry.rigType
				setPreviewModel(copy)
				rebuildVMLibraryRows()
				pushNotification("success", string.format("✓ Using '%s' as %s.", capturedEntry.name, capturedEntry.rigType))
				playSound(SND_SAVE)
			end)

			removeBtn.MouseButton1Click:Connect(function()
				-- Removing the rig that's in use also unuses it, so the
				-- preview and script.ViewModels copy never go stale.
				if inUseRigType == capturedEntry.rigType then
					unuseCurrentRig()
				end
				loadedVMs[capturedEntry.rigType] = nil
				for i2, e in ipairs(vmEntries) do
					if e == capturedEntry then
						table.remove(vmEntries, i2)
						break
					end
				end
				rebuildVMLibraryRows()
				pushNotification("info", capturedEntry.name .. " removed from library.")
				playSound(SND_DELETE)
			end)
		end
	end

	-- Load from Selection button
	local loadVMBtn = actionButton(vmPage, "Load ViewModel from Selection", 3, Color3.fromRGB(70, 100, 140))
	attachSounds(loadVMBtn)
	addTooltip(loadVMBtn, "Select a Model in the Explorer. The plugin checks for Root/HumanoidRootPart and R6/R15 arm part names, then adds it to the library.", "below")

	loadVMBtn.MouseButton1Click:Connect(function()
		local sel = Selection:Get()
		if #sel ~= 1 or not sel[1]:IsA("Model") then
			pushNotification("error", "Select exactly one Model to load.")
			return
		end
		local model = sel[1] :: Model
		local rigType = detectRigType(model)
		if not rigType then
			pushNotification("error", string.format(
				"'%s' doesn't look like a ViewModel — needs Root/HumanoidRootPart and R6 arm names ('Left Arm') or R15 arm names ('LeftUpperArm').",
				model.Name
				))
			playSound(SND_ERROR)
			return
		end
		-- Overwrite if this rigType is already loaded
		loadedVMs[rigType] = model
		-- Update or add entry
		local found = false
		for _, e in ipairs(vmEntries) do
			if e.rigType == rigType then
				e.name = model.Name
				found = true
				break
			end
		end
		if not found then
			table.insert(vmEntries, { name = model.Name, rigType = rigType })
		end
		rebuildVMLibraryRows()
		pushNotification("success", string.format("✓ '%s' loaded as %s.", model.Name, rigType))
		playSound(SND_SAVE)
	end)

	rebuildVMLibraryRows()

	local _, getRigType, setRigType = makeSegmentedGroup(vmPage, "Rig", 4, RIG_TYPES, 1, function(value)
		currentRigType = value
		-- rebuild the limb rows for the new rig; deferred to next resumption
		-- so we don't recurse into the UI-building code from a click handler
		task.defer(function()
			if limbRowContainer then
				for _, child in ipairs(limbRowContainer:GetChildren()) do
					if not child:IsA("UIListLayout") then
						child:Destroy()
					end
				end
			end
			limbRowGetters = {}
			local rigDef = RIG_DEFINITIONS[value]
			if not rigDef or not limbRowContainer then
				return
			end
			for i, spec in ipairs(rigDef.limbs) do
				local row = Instance.new("Frame")
				row.Size = UDim2.new(1, 0, 0, 46)
				row.BackgroundColor3 = Color3.fromRGB(40, 40, 44)
				row.BorderSizePixel = 0
				row.LayoutOrder = i
				row.Parent = limbRowContainer

				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(0, 3)
				corner.Parent = row

				local nameLbl = Instance.new("TextLabel")
				nameLbl.Text = spec.name
				nameLbl.Font = Enum.Font.SourceSansSemibold
				nameLbl.TextSize = 13
				nameLbl.TextColor3 = Color3.fromRGB(230, 230, 230)
				nameLbl.TextXAlignment = Enum.TextXAlignment.Left
				nameLbl.BackgroundTransparency = 1
				nameLbl.Position = UDim2.fromOffset(28, 2)
				nameLbl.Size = UDim2.new(1, -32, 0, 20)
				nameLbl.Parent = row

				local includeBox = Instance.new("TextButton")
				includeBox.Size = UDim2.new(0, 18, 0, 18)
				includeBox.Position = UDim2.new(0, 6, 0, 4)
				includeBox.BackgroundColor3 = Color3.fromRGB(80, 140, 80)
				includeBox.Text = "X"
				includeBox.TextColor3 = Color3.new(1, 1, 1)
				includeBox.Font = Enum.Font.SourceSansBold
				includeBox.TextSize = 14
				includeBox.AutoButtonColor = false
				includeBox.Parent = row
				local includeState = true
				includeBox.MouseButton1Click:Connect(function()
					includeState = not includeState
					includeBox.BackgroundColor3 = includeState and Color3.fromRGB(80, 140, 80) or Color3.fromRGB(70, 70, 70)
					includeBox.Text = includeState and "X" or ""
				end)

				local function makeAxisBox(axisLabel: string, xPos: UDim, defaultVal: number): TextBox
					local axisRow = Instance.new("Frame")
					axisRow.Size = UDim2.new(0.31, -4, 0, 20)
					axisRow.Position = UDim2.new(xPos.Scale, xPos.Offset, 0, 22)
					axisRow.BackgroundTransparency = 1
					axisRow.Parent = row

					local axisLbl = Instance.new("TextLabel")
					axisLbl.Text = axisLabel
					axisLbl.Font = Enum.Font.SourceSans
					axisLbl.TextSize = 12
					axisLbl.TextColor3 = Color3.fromRGB(180, 180, 180)
					axisLbl.BackgroundTransparency = 1
					axisLbl.Size = UDim2.fromOffset(12, 20)
					axisLbl.TextXAlignment = Enum.TextXAlignment.Left
					axisLbl.Parent = axisRow

					local box = Instance.new("TextBox")
					box.Text = string.format("%.2f", defaultVal)
					box.Font = Enum.Font.SourceSans
					box.TextSize = 12
					box.TextColor3 = Color3.new(1, 1, 1)
					box.BackgroundColor3 = Color3.fromRGB(55, 55, 55)
					box.Position = UDim2.fromOffset(14, 0)
					box.Size = UDim2.new(1, -14, 1, 0)
					box.ClearTextOnFocus = false
					box.Parent = axisRow
					return box
				end

				local xBox = makeAxisBox("X", UDim.new(0, 6),  spec.defaultSize.X)
				local yBox = makeAxisBox("Y", UDim.new(0.34, 3), spec.defaultSize.Y)
				local zBox = makeAxisBox("Z", UDim.new(0.67, 0), spec.defaultSize.Z)

				limbRowGetters[spec.name] = function(): LimbOverride
					local sx = tonumber(xBox.Text) or spec.defaultSize.X
					local sy = tonumber(yBox.Text) or spec.defaultSize.Y
					local sz = tonumber(zBox.Text) or spec.defaultSize.Z
					return {
						include = includeState,
						size = Vector3.new(math.max(0.05, sx), math.max(0.05, sy), math.max(0.05, sz)),
					}
				end
			end
		end)
	end)

	local _, getVmName = makeTextField(vmPage, "Name", 4, "ViewModel")

	sectionLabel(vmPage, "Root Part", 5)
	local _, getIncludeRoot = makeCheckbox(vmPage, "Include a root part", 6, true)
	local _, getUseHRP = makeCheckbox(vmPage, "Use HumanoidRootPart (unchecked = plain 'Root' part)", 7, true)
	local _, getRootPriority = makeNumberField(vmPage, "RootPriority (attribute)", 8, 0)

	sectionLabel(vmPage, "Animation", 9)
	-- AnimationController and Humanoid are mutually exclusive — only one can
	-- be active at a time. Both can be off (no controller added).
	sectionLabel(vmPage, "Animation Controller", 9)
	hintLabel(vmPage, "Choose one or neither. AnimationController = custom; Humanoid = standard character rig (required if adding a Shirt).", 9)

	local animCtrlRow = Instance.new("Frame")
	animCtrlRow.Size = UDim2.new(1, 0, 0, 24)
	animCtrlRow.BackgroundTransparency = 1
	animCtrlRow.LayoutOrder = 9
	animCtrlRow.Parent = vmPage
	do
		local rl = Instance.new("UIListLayout")
		rl.FillDirection = Enum.FillDirection.Horizontal
		rl.Padding = UDim.new(0, 8)
		rl.Parent = animCtrlRow
	end

	local animCtrlState = 0  -- 0=none, 1=AnimationController, 2=Humanoid

	local btnAnim = Instance.new("TextButton")
	btnAnim.Text = "AnimationController"
	btnAnim.Font = Enum.Font.SourceSansSemibold
	btnAnim.TextSize = 12
	btnAnim.TextColor3 = Color3.new(1,1,1)
	btnAnim.BackgroundColor3 = Color3.fromRGB(70,130,70)
	btnAnim.Size = UDim2.new(0.5, -4, 1, 0)
	btnAnim.AutoButtonColor = false
	btnAnim.LayoutOrder = 1
	btnAnim.Parent = animCtrlRow
	do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,3); c.Parent = btnAnim end

	local btnHuman = Instance.new("TextButton")
	btnHuman.Text = "Humanoid"
	btnHuman.Font = Enum.Font.SourceSansSemibold
	btnHuman.TextSize = 12
	btnHuman.TextColor3 = Color3.new(1,1,1)
	btnHuman.BackgroundColor3 = Color3.fromRGB(60,60,60)
	btnHuman.Size = UDim2.new(0.5, -4, 1, 0)
	btnHuman.AutoButtonColor = false
	btnHuman.LayoutOrder = 2
	btnHuman.Parent = animCtrlRow
	do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,3); c.Parent = btnHuman end

	local function refreshAnimBtns()
		btnAnim.BackgroundColor3  = animCtrlState == 1 and Color3.fromRGB(70,130,70) or Color3.fromRGB(60,60,60)
		btnHuman.BackgroundColor3 = animCtrlState == 2 and Color3.fromRGB(130,70,70) or Color3.fromRGB(60,60,60)
	end

	btnAnim.MouseButton1Click:Connect(function()
		animCtrlState = animCtrlState == 1 and 0 or 1
		refreshAnimBtns(); playSound(SND_CLICK)
	end)
	btnHuman.MouseButton1Click:Connect(function()
		animCtrlState = animCtrlState == 2 and 0 or 2
		refreshAnimBtns(); playSound(SND_CLICK)
	end)

	-- Compatibility shims so existing code that calls getIncludeAnimController /
	-- setIncludeAnimController keeps working unchanged.
	local function getIncludeAnimController(): boolean return animCtrlState == 1 end
	local function getIncludeHumanoid(): boolean return animCtrlState == 2 end
	local function setIncludeAnimController(v: boolean)
		animCtrlState = v and 1 or (animCtrlState == 1 and 0 or animCtrlState)
		refreshAnimBtns()
	end

	sectionLabel(vmPage, "Appearance", 10)
	hintLabel(vmPage, "Arm color applies to all limb parts. Shirt ID maps the Roblox shirt UV atlas directly via SurfaceAppearance — no Humanoid needed.", 10)

	-- Arm color picker — 64 BrickColors as swatches.
	-- colorPickerFrame needs a UIListLayout so children stack; colorGrid inside
	-- needs a concrete starting size so UIGridLayout can resolve its height.
	local armColorValue: Color3 = Color3.fromRGB(255, 211, 160)  -- default skin

	local colorPickerFrame = Instance.new("Frame")
	colorPickerFrame.Size = UDim2.new(1, 0, 0, 0)
	colorPickerFrame.AutomaticSize = Enum.AutomaticSize.Y
	colorPickerFrame.BackgroundTransparency = 1
	colorPickerFrame.LayoutOrder = 11   -- unique order, after hint at 10
	colorPickerFrame.Parent = vmPage
	do
		local cl = Instance.new("UIListLayout")
		cl.SortOrder = Enum.SortOrder.LayoutOrder
		cl.Padding = UDim.new(0, 2)
		cl.Parent = colorPickerFrame
	end

	-- Current color preview strip + label
	local colorPreviewRow = Instance.new("Frame")
	colorPreviewRow.Size = UDim2.new(1, 0, 0, 24)
	colorPreviewRow.BackgroundTransparency = 1
	colorPreviewRow.LayoutOrder = 1
	colorPreviewRow.Parent = colorPickerFrame

	local colorPreviewSwatch = Instance.new("Frame")
	colorPreviewSwatch.Size = UDim2.new(0, 40, 0, 20)
	colorPreviewSwatch.Position = UDim2.new(0, 0, 0, 2)
	colorPreviewSwatch.BackgroundColor3 = armColorValue
	colorPreviewSwatch.BorderSizePixel = 1
	colorPreviewSwatch.Parent = colorPreviewRow
	do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,3); c.Parent = colorPreviewSwatch end

	local colorPreviewLbl = Instance.new("TextLabel")
	colorPreviewLbl.Text = "Skin (default)"
	colorPreviewLbl.Font = Enum.Font.SourceSans
	colorPreviewLbl.TextSize = 12
	colorPreviewLbl.TextColor3 = Color3.fromRGB(180, 180, 180)
	colorPreviewLbl.TextXAlignment = Enum.TextXAlignment.Left
	colorPreviewLbl.BackgroundTransparency = 1
	colorPreviewLbl.Position = UDim2.fromOffset(46, 4)
	colorPreviewLbl.Size = UDim2.new(1, -46, 1, 0)
	colorPreviewLbl.Parent = colorPreviewRow

	-- Grid of swatches
	local colorGrid = Instance.new("Frame")
	-- Give it a concrete starting size so UIGridLayout can render cells;
	-- AutomaticSize will then grow it to fit all swatches.
	colorGrid.Size = UDim2.new(1, 0, 0, 30)
	colorGrid.AutomaticSize = Enum.AutomaticSize.Y
	colorGrid.BackgroundTransparency = 1
	colorGrid.LayoutOrder = 2
	colorGrid.Parent = colorPickerFrame
	do
		local gl = Instance.new("UIGridLayout")
		gl.CellSize = UDim2.new(0, 26, 0, 26)
		gl.CellPadding = UDim2.new(0, 2, 0, 2)
		gl.SortOrder = Enum.SortOrder.LayoutOrder
		gl.Parent = colorGrid
	end

	-- Roblox's native BrickColors — all 64 unique ones available in the
	-- BrickColor palette tool, grouped by hue family.
	local BRICK_COLORS: { BrickColor } = {
		BrickColor.new("White"),         BrickColor.new("Light grey"),
		BrickColor.new("Medium grey"),   BrickColor.new("Dark grey"),
		BrickColor.new("Black"),         BrickColor.new("Reddish brown"),
		BrickColor.new("Bright red"),    BrickColor.new("Dark red"),
		BrickColor.new("Bright orange"), BrickColor.new("Nougat"),
		BrickColor.new("Light orange"),  BrickColor.new("Bright yellow"),
		BrickColor.new("Bright blue"),   BrickColor.new("Medium blue"),
		BrickColor.new("Sand blue"),     BrickColor.new("Dark blue"),
		BrickColor.new("Bright green"),  BrickColor.new("Medium green"),
		BrickColor.new("Sand green"),    BrickColor.new("Dark green"),
		BrickColor.new("Cyan"),          BrickColor.new("Bright bluish green"),
		BrickColor.new("Bright violet"), BrickColor.new("Medium lilac"),
		BrickColor.new("Pink"),          BrickColor.new("Light pink"),
		BrickColor.new("Magenta"),       BrickColor.new("Dark pink"),
		BrickColor.new("Warm yellowish orange"), BrickColor.new("Yellowish green"),
		BrickColor.new("Sand yellow"),   BrickColor.new("Earth orange"),
		BrickColor.new("Light reddish violet"), BrickColor.new("Brick yellow"),
		BrickColor.new("Light yellowish orange"), BrickColor.new("Rust"),
		BrickColor.new("Olive"),         BrickColor.new("Mint"),
		BrickColor.new("Forest green"),  BrickColor.new("Bright reddish violet"),
		BrickColor.new("Deep orange"),   BrickColor.new("Lavender"),
		BrickColor.new("Very light grey"),BrickColor.new("Teal"),
		BrickColor.new("Lime green"),    BrickColor.new("Maersk blue"),
		BrickColor.new("Daisy orange"),  BrickColor.new("Cool yellow"),
		BrickColor.new("Gold"),          BrickColor.new("Eggshell"),
		BrickColor.new("Medium stone grey"),    BrickColor.new("Dark stone grey"),
		BrickColor.new("Light stone grey"),     BrickColor.new("Pearl"),
		BrickColor.new("Soft blue"),     BrickColor.new("Lapis"),
		BrickColor.new("Tr. Flu. Blue"), BrickColor.new("Tr. Flu. Green"),
		BrickColor.new("Tr. Red"),       BrickColor.new("Tr. Yellow"),
		BrickColor.new("Tr. Blue"),      BrickColor.new("Tr. Black"),
	}

	local selectedColorBtn: TextButton? = nil

	for i, bc in ipairs(BRICK_COLORS) do
		local swatch = Instance.new("TextButton")
		swatch.Size = UDim2.new(0, 28, 0, 28)
		swatch.BackgroundColor3 = bc.Color
		swatch.Text = ""
		swatch.AutoButtonColor = false
		swatch.BorderSizePixel = 2
		swatch.BorderColor3 = Color3.fromRGB(60, 60, 60)
		swatch.LayoutOrder = i
		swatch.Parent = colorGrid
		addTooltip(swatch, bc.Name, "above")
		swatch.MouseButton1Click:Connect(function()
			armColorValue = bc.Color
			colorPreviewSwatch.BackgroundColor3 = bc.Color
			colorPreviewLbl.Text = bc.Name
			if selectedColorBtn then
				selectedColorBtn.BorderColor3 = Color3.fromRGB(60, 60, 60)
				selectedColorBtn.BorderSizePixel = 2
			end
			swatch.BorderColor3 = Color3.fromRGB(255, 255, 255)
			swatch.BorderSizePixel = 3
			selectedColorBtn = swatch
			playSound(SND_CLICK)
		end)
	end

	local _, getShirtId = makeTextField(vmPage, "Shirt asset ID", 12, "")

	local applyShirtBtn = actionButton(vmPage, "Load Shirt (warns if AnimController enabled)", 12, Color3.fromRGB(90, 70, 110))
	applyShirtBtn.LayoutOrder = 12
	attachSounds(applyShirtBtn)
	addTooltip(applyShirtBtn, "Validates the shirt ID and warns you that adding a shirt requires a Humanoid, not an AnimationController. Also auto-unchecks AnimationController.", "below")

	applyShirtBtn.MouseButton1Click:Connect(function()
		local shirtIdVal = getShirtId():match("^%s*(.-)%s*$")
		if shirtIdVal == "" then
			pushNotification("warn", "⚠ No shirt ID entered.")
			pushVmLog({ level = "warn", text = "Enter a shirt asset ID first (e.g. rbxassetid://12345)." })
			return
		end
		pushVmLog({ level = "success", text = string.format(
			"Shirt ID set: %s — texture will be applied via SurfaceAppearance.AlbedoMap on every limb part. " ..
				"No Humanoid needed — the shirt UV atlas maps directly to the cube part faces. " ..
				"AnimationController can stay enabled.",
			shirtIdVal
			) })
		pushNotification("info", "Shirt ID set — UV maps via SurfaceAppearance, no Humanoid needed.")
	end)

	sectionLabel(vmPage, "Accessory Attachment Slots", 13)
	hintLabel(vmPage, "Each checked slot creates a named Attachment on every hand. The CFrame offset positions it relative to the hand's center. These match Roblox's built-in accessory slot names so HumanoidDescription accessories snap correctly.", 12)

	-- Built-in Roblox accessory attachment slot names. These are the
	-- canonical names Roblox uses on R6/R15 characters — accessories
	-- with a matching Attachment name will auto-connect.
	local ROBLOX_SLOT_NAMES = {
		"RightGripAttachment",   -- primary weapon grip (right hand)
		"LeftGripAttachment",    -- secondary / left-hand grip
		"WristRightAttachment",  -- watch / wrist accessory (right) ← Watch
		"WristLeftAttachment",   -- watch / wrist accessory (left)
		"BodyFrontAttachment",   -- chest front
		"BodyBackAttachment",    -- back / backpack
		"NeckAttachment",        -- neck/collar
		"HatAttachment",         -- top of head
		"HairAttachment",        -- hair
		"FaceFrontAttachment",   -- face front
		"FaceRearAttachment",    -- behind the head
	}

	-- Slot state: enabled + offset per slot name. Stored as upvalues for
	-- collectVmOptions to read.
	local slotEnabled: { [string]: boolean } = {}
	local slotOffset: { [string]: CFrame } = {}

	-- Pre-enable the grip slots which are the most common viewmodel need
	slotEnabled["RightGripAttachment"] = true
	slotEnabled["LeftGripAttachment"]  = true

	local slotListFrame = Instance.new("Frame")
	slotListFrame.Size = UDim2.new(1, 0, 0, 0)
	slotListFrame.AutomaticSize = Enum.AutomaticSize.Y
	slotListFrame.BackgroundTransparency = 1
	slotListFrame.LayoutOrder = 13
	slotListFrame.Parent = vmPage
	do
		local sl = Instance.new("UIListLayout")
		sl.SortOrder = Enum.SortOrder.LayoutOrder
		sl.Padding = UDim.new(0, 3)
		sl.Parent = slotListFrame
	end

	for si, slotName in ipairs(ROBLOX_SLOT_NAMES) do
		local isOn = slotEnabled[slotName] or false
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 48)
		row.BackgroundColor3 = Color3.fromRGB(36, 36, 40)
		row.BorderSizePixel = 0
		row.LayoutOrder = si
		row.Parent = slotListFrame
		do local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0,3); rc.Parent = row end

		local chk = Instance.new("TextButton")
		chk.Size = UDim2.new(0, 16, 0, 16)
		chk.Position = UDim2.fromOffset(5, 5)
		chk.BackgroundColor3 = isOn and Color3.fromRGB(80,140,80) or Color3.fromRGB(60,60,60)
		chk.Text = isOn and "X" or ""
		chk.TextColor3 = Color3.new(1,1,1)
		chk.Font = Enum.Font.SourceSansBold
		chk.TextSize = 12
		chk.AutoButtonColor = false
		chk.Parent = row

		local nameLbl = Instance.new("TextLabel")
		nameLbl.Text = slotName
		nameLbl.Font = Enum.Font.SourceSansSemibold
		nameLbl.TextSize = 12
		nameLbl.TextColor3 = Color3.fromRGB(220,220,220)
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.BackgroundTransparency = 1
		nameLbl.Position = UDim2.fromOffset(26, 4)
		nameLbl.Size = UDim2.new(1,-30,0,16)
		nameLbl.Parent = row

		-- Offset fields: X, Y, Z on second line
		local function makeOffBox(label: string, xOff: number, idx: number): TextBox
			local f = Instance.new("Frame")
			f.Size = UDim2.new(0.32,-4,0,20)
			f.Position = UDim2.new((idx-1)*0.33, 4, 0, 24)
			f.BackgroundTransparency = 1
			f.Parent = row
			local l = Instance.new("TextLabel")
			l.Text = label
			l.Font = Enum.Font.SourceSans
			l.TextSize = 11
			l.TextColor3 = Color3.fromRGB(160,160,160)
			l.BackgroundTransparency = 1
			l.Size = UDim2.fromOffset(12, 20)
			l.TextXAlignment = Enum.TextXAlignment.Left
			l.Parent = f
			local b = Instance.new("TextBox")
			b.Text = string.format("%.2f", xOff)
			b.Font = Enum.Font.SourceSans
			b.TextSize = 11
			b.TextColor3 = Color3.new(1,1,1)
			b.BackgroundColor3 = Color3.fromRGB(52,52,56)
			b.Position = UDim2.fromOffset(13,0)
			b.Size = UDim2.new(1,-14,1,0)
			b.ClearTextOnFocus = false
			b.Parent = f
			return b
		end

		local bx = makeOffBox("X", 0, 1)
		local by = makeOffBox("Y", 0, 2)
		local bz = makeOffBox("Z", 0, 3)

		slotOffset[slotName] = CFrame.new(0, 0, 0)

		local function syncOffset()
			local x = tonumber(bx.Text) or 0
			local y = tonumber(by.Text) or 0
			local z = tonumber(bz.Text) or 0
			slotOffset[slotName] = CFrame.new(x, y, z)
		end
		bx.FocusLost:Connect(syncOffset)
		by.FocusLost:Connect(syncOffset)
		bz.FocusLost:Connect(syncOffset)

		chk.MouseButton1Click:Connect(function()
			slotEnabled[slotName] = not (slotEnabled[slotName] or false)
			local on = slotEnabled[slotName]
			chk.BackgroundColor3 = on and Color3.fromRGB(80,140,80) or Color3.fromRGB(60,60,60)
			chk.Text = on and "X" or ""
		end)
	end

	-- Returns the list of enabled slot names for collectVmOptions
	local function getEnabledSlots(): { string }
		local out = {}
		for _, name in ipairs(ROBLOX_SLOT_NAMES) do
			if slotEnabled[name] then
				table.insert(out, name)
			end
		end
		return out
	end

	-- Returns the offset CFrame for a given slot name
	local function getSlotOffset(slotName: string): CFrame
		return slotOffset[slotName] or CFrame.new()
	end

	sectionLabel(vmPage, "Per-Limb Adjustments", 14)
	hintLabel(vmPage, "Each limb has an Include checkbox and X / Y / Z size fields in studs. Uncheck a limb to skip it (its children skip too).", 15)

	-- Container for the per-limb rows; populated by the segmented group's
	-- onChange callback above (fired once at startup via setRigType below).
	local limbRowFrame = Instance.new("Frame")
	limbRowFrame.Size = UDim2.new(1, 0, 0, 0)
	limbRowFrame.AutomaticSize = Enum.AutomaticSize.Y
	limbRowFrame.BackgroundTransparency = 1
	limbRowFrame.LayoutOrder = 16
	limbRowFrame.Parent = vmPage
	local limbLayout = Instance.new("UIListLayout")
	limbLayout.SortOrder = Enum.SortOrder.LayoutOrder
	limbLayout.Padding = UDim.new(0, 3)
	limbLayout.Parent = limbRowFrame
	limbRowContainer = limbRowFrame

	-- Trigger the first population of limb rows for the default rig type.
	-- setRigType only invokes the callback on a change, so the initial
	-- state has to be seeded explicitly.
	do
		local seedRig = getRigType()
		setRigType("DefaultR15") -- force a change to trigger rebuild
		setRigType(seedRig) -- back to default
	end

	sectionLabel(vmPage, "Preview", 17)
	do local _f, _s = createViewport(vmPage, 18); setPreviewModel = _s end

	sectionLabel(vmPage, "Actions", 19)
	local _, _getApplyVmCG = makeCheckbox(vmPage, "Assign ViewModel collision group (no world/self collisions)", 19, true)
	getApplyVmCollisionGroup = _getApplyVmCG

	local previewBtn      = actionButton(vmPage, "Refresh Preview",               20, Color3.fromRGB(80, 80, 130))
	local buildVmBtn      = actionButton(vmPage, "Build at Workspace Origin",     21, Color3.fromRGB(70, 130, 70))
	local buildVmClickBtn = actionButton(vmPage, "Place by Click (Esc cancels)",  22, Color3.fromRGB(140, 100, 60))
	attachSounds(previewBtn)
	attachSounds(buildVmBtn, nil, SND_BUILD)
	attachSounds(buildVmClickBtn)
	addTooltip(previewBtn,      "Rebuilds the orbiting static preview from current settings. Does not write to Workspace.", "above")
	addTooltip(buildVmBtn,      "Spawns the rig at the world origin (0,0,0). Undo works normally.", "above")
	addTooltip(buildVmClickBtn, "Enters click-to-place mode — next click in the 3D viewport sets spawn position. Press Esc to cancel.", "above")

	sectionLabel(vmPage, "Log", 23)
	do local _f, _p, _c = makeLogPanel(vmPage, 24, 180); pushVmLog = _p; clearVmLog = _c end

	local function collectVmOptions(rootCF: CFrame?): ViewModelOptions
		local overrides: { [string]: LimbOverride } = {}
		for limbName, getter in pairs(limbRowGetters) do
			overrides[limbName] = getter()
		end
		-- Build offset table from the slot picker
		local offsets: { [string]: CFrame } = {}
		for _, slotName in ipairs(ROBLOX_SLOT_NAMES) do
			if slotEnabled[slotName] then
				offsets[slotName] = getSlotOffset(slotName)
			end
		end
		return {
			name = getVmName(),
			rigType = currentRigType,
			includeRootPart = getIncludeRoot(),
			useHumanoidRootPart = getUseHRP(),
			rootPriority = math.floor(getRootPriority()),
			rootCFrame = rootCF or CFrame.new(),
			includeAnimationController = getIncludeAnimController(),
			includeHumanoid = getIncludeHumanoid(),
			accessorySlots = getEnabledSlots(),
			limbOverrides = overrides,
			slotOffsets = offsets,
			armColor = armColorValue,
			shirtId = getShirtId(),
		}
	end

	previewBtn.MouseButton1Click:Connect(function()
		-- Build a temporary rig at origin, feed it to the viewport, destroy
		-- the original (viewport gets its own clone). Root motors don't
		-- animate inside a ViewportFrame so this is a static shape preview.
		local vm = buildViewModel(collectVmOptions())
		setPreviewModel(vm)
		vm:Destroy()
	end)

	buildVmBtn.MouseButton1Click:Connect(function()
		clearVmLog()
		ChangeHistoryService:SetWaypoint("Before Build ViewModel")
		local vm, log = buildViewModel(collectVmOptions())
		vm.Parent = workspace
		for _, entry in ipairs(log) do
			pushVmLog(entry)
		end
		if getApplyVmCollisionGroup() then
			local n = assignViewModelCollisionGroup(vm)
			pushVmLog({ level = "info", text = string.format("ViewModel collision group '%s' applied to %d part(s). Group has no world/self collisions.", VM_COLLISION_GROUP, n) })
		end
		pushVmLog({ level = "success", text = string.format("ViewModel '%s' placed at Workspace origin.", vm.Name) })
		pushNotification("success", string.format("✓ ViewModel '%s' built.", vm.Name))
		playSound(SND_BUILD)
		Selection:Set({ vm })
		setPreviewModel(vm)
		ChangeHistoryService:SetWaypoint("Build ViewModel")
	end)

	-- Click-to-place: highlight the button while active, then wait for the
	-- user's click. The place-mode helper handles Escape cancellation.
	-- placeInFlight declared in hoisted vars above
	buildVmClickBtn.MouseButton1Click:Connect(function()
		if placeInFlight then
			-- second click on the same button = cancel
			return
		end
		placeInFlight = true
		buildVmClickBtn.Text = "Click in viewport to place... (Esc = cancel)"
		buildVmClickBtn.BackgroundColor3 = Color3.fromRGB(180, 130, 70)
		pushVmLog({ level = "info", text = "Click somewhere in the 3D viewport to place the ViewModel. Press Esc to cancel." })
		enterClickToPlace(function(hitCF)
			clearVmLog()
			ChangeHistoryService:SetWaypoint("Before Build ViewModel (Click)")
			local vm, log = buildViewModel(collectVmOptions(CFrame.new(hitCF.Position)))
			vm.Parent = workspace
			for _, entry in ipairs(log) do
				pushVmLog(entry)
			end
			if getApplyVmCollisionGroup() then
				local n = assignViewModelCollisionGroup(vm)
				pushVmLog({ level = "info", text = string.format("Collision group '%s' applied to %d part(s).", VM_COLLISION_GROUP, n) })
			end
			pushVmLog({ level = "success", text = string.format("ViewModel '%s' placed at click position.", vm.Name) })
			pushNotification("success", string.format("✓ ViewModel '%s' placed.", vm.Name))
			playSound(SND_BUILD)
			Selection:Set({ vm })
			setPreviewModel(vm)
			ChangeHistoryService:SetWaypoint("Build ViewModel (Click)")
		end, function()
			placeInFlight = false
			buildVmClickBtn.Text = "Place by Click (Esc cancels)"
			buildVmClickBtn.BackgroundColor3 = Color3.fromRGB(140, 100, 60)
		end)
	end)

end -- end do: section 13

-- ============================================================
-- SECTION 13B: LIBRARY TAB CONTENTS
-- ============================================================

do -- scope block: library tab locals die here

	sectionLabel(libraryPage, "Weapon Library", 1)
	hintLabel(libraryPage, "Weapons saved here persist across Studio sessions and survive the original being deleted. Storage is per-plugin (plugin:SetSetting), scoped to your Studio install.", 2)

	sectionLabel(libraryPage, "Save Current", 3)
	hintLabel(libraryPage, "Save whatever's selected in the Explorer (usually your gun Model). Leave the name blank to use the model's own name.", 4)
	local _, getSaveName = makeTextField(libraryPage, "Name (blank = model.Name)", 5, "")
	local saveSelectedBtn = actionButton(libraryPage, "Save Selection to Library",        6, Color3.fromRGB(70, 130, 70))
	local saveTargetBtn   = actionButton(libraryPage, "Save Gun Rig Target to Library",  7, Color3.fromRGB(80, 130, 90))
	attachSounds(saveSelectedBtn, nil, SND_SAVE)
	attachSounds(saveTargetBtn,   nil, SND_SAVE)
	addTooltip(saveSelectedBtn, "Serializes the selected Explorer item and stores it in the plugin. Survives place reloads.", "below")
	addTooltip(saveTargetBtn,   "Serializes the Gun Rig tab's current target model into the library.", "below")

	sectionLabel(libraryPage, "Saved Weapons", 8)
	local libraryListFrame = Instance.new("Frame")
	libraryListFrame.Size = UDim2.new(1, 0, 0, 0)
	libraryListFrame.AutomaticSize = Enum.AutomaticSize.Y
	libraryListFrame.BackgroundTransparency = 1
	libraryListFrame.LayoutOrder = 9
	libraryListFrame.Parent = libraryPage
	local libListLayout = Instance.new("UIListLayout")
	libListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	libListLayout.Padding = UDim.new(0, 4)
	libListLayout.Parent = libraryListFrame

	sectionLabel(libraryPage, "Log", 10)
	do local _f, _p, _c = makeLogPanel(libraryPage, 11, 140); pushLibraryLog = _p; clearLibraryLog = _c end

	-- Renders the current library state into libraryListFrame. Called on
	-- startup and after every save/delete so the visible list stays fresh.
	refreshLibraryList = function()
		for _, child in ipairs(libraryListFrame:GetChildren()) do
			if not child:IsA("UIListLayout") then
				child:Destroy()
			end
		end

		local names = libraryList()
		if #names == 0 then
			local empty = Instance.new("TextLabel")
			empty.Text = "(library is empty — save a weapon above to see it here)"
			empty.Font = Enum.Font.SourceSansItalic
			empty.TextSize = 13
			empty.TextColor3 = Color3.fromRGB(150, 150, 150)
			empty.TextXAlignment = Enum.TextXAlignment.Left
			empty.BackgroundTransparency = 1
			empty.Size = UDim2.new(1, 0, 0, 20)
			empty.LayoutOrder = 1
			empty.Parent = libraryListFrame
			return
		end

		for i, name in ipairs(names) do
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 52)
			row.BackgroundColor3 = Color3.fromRGB(40, 40, 44)
			row.BorderSizePixel = 0
			row.LayoutOrder = i
			row.Parent = libraryListFrame
			local rowCorner = Instance.new("UICorner")
			rowCorner.CornerRadius = UDim.new(0, 4)
			rowCorner.Parent = row

			local nameLbl = Instance.new("TextLabel")
			nameLbl.Text = name
			nameLbl.Font = Enum.Font.SourceSansSemibold
			nameLbl.TextSize = 14
			nameLbl.TextColor3 = Color3.fromRGB(230, 230, 230)
			nameLbl.TextXAlignment = Enum.TextXAlignment.Left
			nameLbl.BackgroundTransparency = 1
			nameLbl.Position = UDim2.fromOffset(8, 4)
			nameLbl.Size = UDim2.new(1, -16, 0, 20)
			nameLbl.Parent = row

			local function makeRowBtn(label: string, xScale: number, xOffset: number, wScale: number, wOffset: number, color: Color3): TextButton
				local b = Instance.new("TextButton")
				b.Text = label
				b.Font = Enum.Font.SourceSansSemibold
				b.TextSize = 12
				b.TextColor3 = Color3.new(1, 1, 1)
				b.BackgroundColor3 = color
				b.Position = UDim2.new(xScale, xOffset, 0, 26)
				b.Size = UDim2.new(wScale, wOffset, 0, 20)
				b.AutoButtonColor = true
				local c = Instance.new("UICorner")
				c.CornerRadius = UDim.new(0, 3)
				c.Parent = b
				b.Parent = row
				return b
			end

			local loadBtn = makeRowBtn("Load", 0, 8, 0.32, -12, Color3.fromRGB(70, 130, 70))
			local clickBtn = makeRowBtn("Place by Click", 0.32, 4, 0.44, -8, Color3.fromRGB(140, 100, 60))
			local delBtn = makeRowBtn("Delete", 0.76, 4, 0.24, -12, Color3.fromRGB(140, 70, 70))

			loadBtn.MouseButton1Click:Connect(function()
				ChangeHistoryService:SetWaypoint("Before Load Weapon")
				local restored = libraryRestore(name)
				if restored then
					restored.Parent = workspace
					Selection:Set({ restored })
					pushLibraryLog({ level = "success", text = string.format("Loaded '%s' at Workspace origin.", name) })
					pushNotification("success", "✓ Loaded: " .. name)
				else
					pushLibraryLog({ level = "error", text = string.format("Failed to load '%s' (library entry missing or corrupt).", name) })
				end
				ChangeHistoryService:SetWaypoint("Load Weapon")
			end)

			local clickState = false
			clickBtn.MouseButton1Click:Connect(function()
				if clickState then
					return
				end
				clickState = true
				clickBtn.Text = "Click to place (Esc = cancel)"
				clickBtn.BackgroundColor3 = Color3.fromRGB(180, 130, 70)
				enterClickToPlace(function(hitCF)
					ChangeHistoryService:SetWaypoint("Before Load Weapon (Click)")
					local restored = libraryRestore(name)
					if restored then
						-- Use only the hit *position*; strip the surface-normal
						-- rotation so weapons don't tilt when dropped on a slope.
						local placeCF = CFrame.new(hitCF.Position)
						if restored:IsA("Model") then
							-- Model:PivotTo works whether or not PrimaryPart is set
							-- (falls back to bounding-box center).
							(restored :: Model):PivotTo(placeCF)
						elseif restored:IsA("BasePart") then
							(restored :: BasePart).CFrame = placeCF
						end
						restored.Parent = workspace
						Selection:Set({ restored })
						pushLibraryLog({ level = "success", text = string.format("Placed '%s' at click position.", name) })
						pushNotification("success", "✓ Placed: " .. name)
					else
						pushLibraryLog({ level = "error", text = string.format("Failed to load '%s'.", name) })
					end
					ChangeHistoryService:SetWaypoint("Load Weapon (Click)")
				end, function()
					clickState = false
					clickBtn.Text = "Place by Click"
					clickBtn.BackgroundColor3 = Color3.fromRGB(140, 100, 60)
				end)
			end)

			delBtn.MouseButton1Click:Connect(function()
				if libraryDelete(name) then
					pushLibraryLog({ level = "info", text = string.format("Deleted '%s' from the library.", name) })
					pushNotification("info", "Deleted: " .. name)
					refreshLibraryList()
				end
			end)
		end
	end

	-- Helper: save the given Instance under a chosen name (blank = use its
	-- own Name). Handles the input validation and refresh centrally.
	local function doSaveToLibrary(model: Instance, requestedName: string): boolean
		local finalName = requestedName
		if finalName == "" then
			finalName = model.Name
		end
		local ok, msg = librarySave(finalName, model)
		if ok then
			pushLibraryLog({ level = "success", text = msg })
			pushNotification("success", "✓ Saved to library: " .. finalName)
			refreshLibraryList()
		else
			pushLibraryLog({ level = "error", text = msg })
		end
		return ok
	end

	saveSelectedBtn.MouseButton1Click:Connect(function()
		local sel = Selection:Get()
		if #sel ~= 1 then
			pushLibraryLog({ level = "error", text = "Select exactly one item in the Explorer to save." })
			return
		end
		doSaveToLibrary(sel[1], getSaveName())
	end)

	saveTargetBtn.MouseButton1Click:Connect(function()
		-- `targetModel` is the module-level variable set by the Gun Rig tab.
		if not targetModel then
			pushLibraryLog({ level = "error", text = "No Gun Rig target set. Set one from the Gun Rig tab first, or use 'Save Selection' instead." })
			return
		end
		doSaveToLibrary(targetModel, getSaveName())
	end)

	-- Initial render so anything already in library storage shows up right away.
	refreshLibraryList()

end -- end do: section 13B

-- ============================================================
-- SECTION 13C: SETTINGS TAB CONTENTS
-- ============================================================

do -- scope block: settings tab locals die here

	sectionLabel(settingsPage, "Sounds", 1)
	local _, getSoundsEnabled, setSoundsEnabled = makeCheckbox(settingsPage, "Enable UI sounds", 2, activeSettings.soundsEnabled)
	local _, getSoundVolume = makeNumberField(settingsPage, "Master volume (0.0 – 1.0)", 3, activeSettings.soundVolume)
	addTooltip(settingsPage:FindFirstChild("2") or settingsPage, "Plays subtle click, hover, build, and error sounds while using the plugin.", "right")

	sectionLabel(settingsPage, "Tooltips", 4)
	local _, getTooltipsEnabled, setTooltipsEnabledUI = makeCheckbox(settingsPage, "Enable tooltips", 5, activeSettings.tooltipsEnabled)
	addTooltip(settingsPage:FindFirstChild("5") or settingsPage, "Shows small descriptive popups when you hover over buttons and controls.", "right")

	sectionLabel(settingsPage, "Preview", 6)
	local _, getAutoRefreshPreview, setAutoRefreshPreview = makeCheckbox(settingsPage, "Auto-refresh VM preview after build", 7, activeSettings.autoRefreshPreview)
	addTooltip(settingsPage:FindFirstChild("7") or settingsPage, "When enabled, building a ViewModel also updates the preview viewport automatically.", "right")

	sectionLabel(settingsPage, "Defaults", 8)
	local _, getDefaultRigType, setDefaultRigTypeUI = makeSegmentedGroup(settingsPage, "Default rig", 9, RIG_TYPES, 1, function() end)

	local applySettingsBtn = actionButton(settingsPage, "Apply & Save Settings", 10, Color3.fromRGB(70, 120, 140))
	local resetSettingsBtn = actionButton(settingsPage, "Reset to Defaults",      11, Color3.fromRGB(120, 70, 70))
	attachSounds(applySettingsBtn, nil, SND_SAVE)
	attachSounds(resetSettingsBtn, nil, SND_DELETE)
	addTooltip(applySettingsBtn, "Saves settings to plugin storage — they'll be restored next time you open Studio.", "above")
	addTooltip(resetSettingsBtn, "Resets all settings to factory defaults and saves immediately.", "above")

	applySettingsBtn.MouseButton1Click:Connect(function()
		activeSettings.soundsEnabled    = getSoundsEnabled()
		activeSettings.soundVolume      = math.clamp(getSoundVolume(), 0, 1)
		activeSettings.tooltipsEnabled  = getTooltipsEnabled()
		activeSettings.autoRefreshPreview = getAutoRefreshPreview()
		activeSettings.defaultRigType   = getDefaultRigType()
		settingsSave()
		playSound(SND_SAVE)
	end)

	resetSettingsBtn.MouseButton1Click:Connect(function()
		activeSettings = table.clone(DEFAULT_SETTINGS)
		settingsSave()
		-- Sync all the UI controls back to defaults
		setSoundsEnabled(DEFAULT_SETTINGS.soundsEnabled)
		setTooltipsEnabledUI(DEFAULT_SETTINGS.tooltipsEnabled)
		setAutoRefreshPreview(DEFAULT_SETTINGS.autoRefreshPreview)
		setDefaultRigTypeUI(DEFAULT_SETTINGS.defaultRigType)
	end)

end -- end do: section 13C

-- ============================================================
-- SECTION 13C2: PREMIUM FEATURES (Theme + Sound Swap)
-- Gamepass-gated. Owner (userId 34899885 = DeathToTheStadium)
-- always has access regardless of gamepass ownership.
-- ============================================================

do -- scope: premium features locals

	-- Gamepass ID — set this to your actual Roblox gamepass ID once you
	-- create one on the Creator Dashboard. 0 means "not yet set".
	local PREMIUM_GAMEPASS_ID = 0  -- ← replace with your gamepass id

	-- Owner userId — always granted full access regardless of gamepass.
	local OWNER_USER_ID = 34899885  -- DeathToTheStadium

	-- Check whether the current Studio user is the owner or has the gamepass.
	-- `plugin:GetCreatorId()` returns the plugin creator's userId in Studio,
	-- which is the logged-in developer's id.
	local function hasPremiumAccess(): boolean
		-- Owner bypass — always true for DeathToTheStadium
		local studioUserId: number = 0
		pcall(function()
			-- game.CreatorId reflects the place owner in a published game;
			-- for plugins we use the logged-in user heuristic via Studio env.
			studioUserId = game.CreatorId
		end)
		if studioUserId == OWNER_USER_ID then
			return true
		end
		-- Gamepass check (only meaningful if PREMIUM_GAMEPASS_ID is set)
		if PREMIUM_GAMEPASS_ID > 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(studioUserId, PREMIUM_GAMEPASS_ID)
			end)
			if ok and owns then return true end
		end
		return studioUserId == OWNER_USER_ID  -- final fallback
	end

	-- ── Theme definitions ──────────────────────────────────────────────────────
	-- Each theme is a table of named Color3 values applied to key UI elements.
	type Theme = {
		tabBar: Color3,
		tabSelected: Color3,
		pageBackground: Color3,
		sectionText: Color3,
		buttonDefault: Color3,
		buttonBuild: Color3,
		inputBackground: Color3,
		logBackground: Color3,
	}

	local THEMES: { [string]: Theme } = {
		Dark = {
			tabBar = Color3.fromRGB(36, 36, 36),
			tabSelected = Color3.fromRGB(60, 90, 140),
			pageBackground = Color3.fromRGB(46, 46, 46),
			sectionText = Color3.fromRGB(230, 230, 230),
			buttonDefault = Color3.fromRGB(70, 120, 70),
			buttonBuild = Color3.fromRGB(70, 130, 70),
			inputBackground = Color3.fromRGB(60, 60, 60),
			logBackground = Color3.fromRGB(28, 28, 28),
		},
		Light = {
			tabBar = Color3.fromRGB(200, 200, 210),
			tabSelected = Color3.fromRGB(80, 120, 200),
			pageBackground = Color3.fromRGB(230, 230, 235),
			sectionText = Color3.fromRGB(30, 30, 30),
			buttonDefault = Color3.fromRGB(60, 150, 80),
			buttonBuild = Color3.fromRGB(50, 160, 60),
			inputBackground = Color3.fromRGB(210, 210, 215),
			logBackground = Color3.fromRGB(180, 180, 185),
		},
		Midnight = {
			tabBar = Color3.fromRGB(14, 14, 22),
			tabSelected = Color3.fromRGB(90, 60, 160),
			pageBackground = Color3.fromRGB(18, 18, 28),
			sectionText = Color3.fromRGB(200, 190, 240),
			buttonDefault = Color3.fromRGB(80, 50, 140),
			buttonBuild = Color3.fromRGB(70, 60, 180),
			inputBackground = Color3.fromRGB(28, 28, 44),
			logBackground = Color3.fromRGB(10, 10, 18),
		},
		ARMORY = {
			tabBar = Color3.fromRGB(20, 20, 20),
			tabSelected = Color3.fromRGB(160, 60, 40),
			pageBackground = Color3.fromRGB(24, 24, 24),
			sectionText = Color3.fromRGB(230, 200, 160),
			buttonDefault = Color3.fromRGB(140, 50, 30),
			buttonBuild = Color3.fromRGB(160, 60, 40),
			inputBackground = Color3.fromRGB(36, 32, 28),
			logBackground = Color3.fromRGB(14, 12, 10),
		},
	}

	local THEME_NAMES = { "Dark", "Light", "Midnight", "ARMORY" }
	local activeTheme: Theme = THEMES["Dark"]

	local function applyTheme(themeName: string)
		local t = THEMES[themeName]
		if not t then return end
		activeTheme = t
		tabBar.BackgroundColor3 = t.tabBar
		root.BackgroundColor3 = t.pageBackground
		for i, tab in ipairs(allTabs) do
			local isSelected = allPages[i].Visible
			tab.BackgroundColor3 = isSelected and t.tabSelected or t.tabBar
			tab.TextColor3 = t.sectionText
		end
		-- Walk every page and update text labels so light/dark themes stay readable.
		-- sectionLabel text = sectionText; hintLabel = sectionText at 75% brightness;
		-- page background = pageBackground.
		for _, page in ipairs(allPages) do
			page.BackgroundColor3 = t.pageBackground
			for _, desc in ipairs(page:GetDescendants()) do
				if desc:IsA("ScrollingFrame") then
					(desc :: ScrollingFrame).BackgroundColor3 = t.pageBackground
				elseif desc:IsA("TextLabel") then
					local lbl = desc :: TextLabel
					-- Only recolor non-log, non-colored labels (avoid status greens/reds)
					local c = lbl.TextColor3
					local isStatusColored = (c.G > 0.6 and c.R < 0.6) or (c.R > 0.6 and c.G < 0.4)
					if not isStatusColored then
						-- Bold section labels get full sectionText; hints get dimmer version
						if lbl.Font == Enum.Font.SourceSansBold then
							lbl.TextColor3 = t.sectionText
						else
							-- Hint/body text: blend sectionText toward background slightly
							local s = t.sectionText
							lbl.TextColor3 = Color3.new(s.R * 0.8, s.G * 0.8, s.B * 0.8)
						end
					end
				elseif desc:IsA("TextBox") then
					desc.BackgroundColor3 = t.inputBackground
					desc.TextColor3 = t.sectionText
				end
			end
		end
		-- Tooltip: invert for light themes so it remains visible
		local isLight = themeName == "Light"
		tooltipFrame.BackgroundColor3 = isLight and Color3.fromRGB(30, 30, 40) or Color3.fromRGB(18, 18, 22)
		tooltipLabel.TextColor3 = Color3.fromRGB(235, 235, 235)  -- always white on dark tooltip bg
		plugin:SetSetting("GunRigBuilder_Theme", themeName)
	end

	-- Restore saved theme on load
	do
		local savedTheme = plugin:GetSetting("GunRigBuilder_Theme")
		if type(savedTheme) == "string" and THEMES[savedTheme] then
			applyTheme(savedTheme)
		end
	end

	-- ── Premium UI ─────────────────────────────────────────────────────────────
	-- The settings page gets a "Premium" section; if the user doesn't have
	-- access it shows a locked notice and a purchase button.

	sectionLabel(settingsPage, "Premium Features", 12)

	local premiumGate = Instance.new("Frame")
	premiumGate.Size = UDim2.new(1, 0, 0, 0)
	premiumGate.AutomaticSize = Enum.AutomaticSize.Y
	premiumGate.BackgroundTransparency = 1
	premiumGate.LayoutOrder = 13
	premiumGate.Parent = settingsPage

	local function buildPremiumUI()
		for _, child in ipairs(premiumGate:GetChildren()) do child:Destroy() end

		-- UIListLayout must be re-added after every clear.
		do
			local pgl = Instance.new("UIListLayout")
			pgl.SortOrder = Enum.SortOrder.LayoutOrder
			pgl.Padding = UDim.new(0, 6)
			pgl.Parent = premiumGate
		end

		if not hasPremiumAccess() then
			local lockLbl = Instance.new("TextLabel")
			lockLbl.Text = "🔒  Theme & Sound Swap are premium features.\nGet the gamepass to unlock them."
			lockLbl.Font = Enum.Font.SourceSans
			lockLbl.TextSize = 13
			lockLbl.TextColor3 = Color3.fromRGB(190, 160, 80)
			lockLbl.TextWrapped = true
			lockLbl.TextXAlignment = Enum.TextXAlignment.Left
			lockLbl.BackgroundColor3 = Color3.fromRGB(44, 38, 20)
			lockLbl.Size = UDim2.new(1, 0, 0, 48)
			lockLbl.LayoutOrder = 1
			lockLbl.Parent = premiumGate
			do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,4); c.Parent = lockLbl end
			do local p = Instance.new("UIPadding"); p.PaddingLeft=UDim.new(0,8); p.PaddingTop=UDim.new(0,6); p.Parent=lockLbl end
			if PREMIUM_GAMEPASS_ID > 0 then
				local buyBtn = actionButton(premiumGate, "Get Premium Gamepass", 2, Color3.fromRGB(200, 140, 30))
				buyBtn.LayoutOrder = 2
				attachSounds(buyBtn, nil, SND_CLICK)
				buyBtn.MouseButton1Click:Connect(function()
					pcall(function()
						MarketplaceService:PromptGamePassPurchase(game.Players.LocalPlayer, PREMIUM_GAMEPASS_ID)
					end)
				end)
			end
			return
		end

		-- Theme label
		local themeLbl = Instance.new("TextLabel")
		themeLbl.Text = "Theme"
		themeLbl.Font = Enum.Font.SourceSansBold
		themeLbl.TextSize = 14
		themeLbl.TextColor3 = Color3.fromRGB(220, 220, 220)
		themeLbl.TextXAlignment = Enum.TextXAlignment.Left
		themeLbl.BackgroundTransparency = 1
		themeLbl.Size = UDim2.new(1, 0, 0, 20)
		themeLbl.LayoutOrder = 1
		themeLbl.Parent = premiumGate

		-- Theme button row
		local themeRow = Instance.new("Frame")
		themeRow.Size = UDim2.new(1, 0, 0, 34)
		themeRow.BackgroundTransparency = 1
		themeRow.LayoutOrder = 2
		themeRow.Parent = premiumGate
		do
			local tl = Instance.new("UIListLayout")
			tl.FillDirection = Enum.FillDirection.Horizontal
			tl.Padding = UDim.new(0, 4)
			tl.SortOrder = Enum.SortOrder.LayoutOrder
			tl.Parent = themeRow
		end
		for ti, themeName in ipairs(THEME_NAMES) do
			local t = THEMES[themeName]
			local tb = Instance.new("TextButton")
			tb.Size = UDim2.new(0.24, -4, 1, 0)
			tb.BackgroundColor3 = t.tabSelected
			tb.Text = themeName
			tb.Font = Enum.Font.SourceSansSemibold
			tb.TextSize = 11
			tb.TextColor3 = Color3.new(1, 1, 1)
			tb.AutoButtonColor = false
			tb.LayoutOrder = ti
			tb.Parent = themeRow
			do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,3); c.Parent = tb end
			attachSounds(tb)
			tb.MouseButton1Click:Connect(function()
				applyTheme(themeName)
				pushNotification("success", "✓ Theme: " .. themeName)
				playSound(SND_SAVE)
			end)
		end

		-- Sound swap label
		local soundLbl = Instance.new("TextLabel")
		soundLbl.Text = "Custom Sounds (asset IDs)"
		soundLbl.Font = Enum.Font.SourceSansBold
		soundLbl.TextSize = 14
		soundLbl.TextColor3 = Color3.fromRGB(220, 220, 220)
		soundLbl.TextXAlignment = Enum.TextXAlignment.Left
		soundLbl.BackgroundTransparency = 1
		soundLbl.Size = UDim2.new(1, 0, 0, 20)
		soundLbl.LayoutOrder = 3
		soundLbl.Parent = premiumGate

		local SOUND_ENTRIES: { { label: string, snd: Sound } } = {
			{ label = "Hover",  snd = SND_HOVER  },
			{ label = "Click",  snd = SND_CLICK  },
			{ label = "Build",  snd = SND_BUILD  },
			{ label = "Save",   snd = SND_SAVE   },
			{ label = "Delete", snd = SND_DELETE },
			{ label = "Error",  snd = SND_ERROR  },
		}

		for i, entry in ipairs(SOUND_ENTRIES) do
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 26)
			row.BackgroundTransparency = 1
			row.LayoutOrder = 3 + i
			row.Parent = premiumGate
			do
				local rl = Instance.new("UIListLayout")
				rl.FillDirection = Enum.FillDirection.Horizontal
				rl.Padding = UDim.new(0, 4)
				rl.SortOrder = Enum.SortOrder.LayoutOrder
				rl.VerticalAlignment = Enum.VerticalAlignment.Center
				rl.Parent = row
			end

			local nameLbl = Instance.new("TextLabel")
			nameLbl.Text = entry.label
			nameLbl.Font = Enum.Font.SourceSans
			nameLbl.TextSize = 13
			nameLbl.TextColor3 = Color3.fromRGB(200, 200, 200)
			nameLbl.BackgroundTransparency = 1
			nameLbl.Size = UDim2.new(0.22, 0, 1, 0)
			nameLbl.TextXAlignment = Enum.TextXAlignment.Left
			nameLbl.LayoutOrder = 1
			nameLbl.Parent = row

			local box = Instance.new("TextBox")
			box.Text = entry.snd.SoundId
			box.Font = Enum.Font.SourceSans
			box.TextSize = 11
			box.TextColor3 = Color3.new(1, 1, 1)
			box.BackgroundColor3 = Color3.fromRGB(50, 50, 55)
			box.Size = UDim2.new(0.60, 0, 1, -4)
			box.ClearTextOnFocus = false
			box.PlaceholderText = "rbxasset:// or rbxassetid://"
			box.LayoutOrder = 2
			box.Parent = row
			do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,2); c.Parent = box end

			local testBtn = Instance.new("TextButton")
			testBtn.Text = "▶"
			testBtn.Font = Enum.Font.SourceSansBold
			testBtn.TextSize = 13
			testBtn.TextColor3 = Color3.new(1, 1, 1)
			testBtn.BackgroundColor3 = Color3.fromRGB(70, 70, 80)
			testBtn.Size = UDim2.new(0.18, 0, 1, -4)
			testBtn.AutoButtonColor = true
			testBtn.LayoutOrder = 3
			testBtn.Parent = row
			do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,2); c.Parent = testBtn end

			box.FocusLost:Connect(function()
				local id = box.Text:match("^%s*(.-)%s*$")
				if id ~= "" then
					entry.snd.SoundId = id
					plugin:SetSetting("GunRigBuilder_Sound_" .. entry.label, id)
				end
			end)
			testBtn.MouseButton1Click:Connect(function()
				entry.snd:Play()
			end)

			do
				local saved = plugin:GetSetting("GunRigBuilder_Sound_" .. entry.label)
				if type(saved) == "string" and saved ~= "" then
					entry.snd.SoundId = saved
					box.Text = saved
				end
			end
		end
	end

	buildPremiumUI()

end -- end do: section 13C2
-- ============================================================
-- Lets the user browse Roblox's Avatar Shop accessories by type,
-- see a thumbnail, and place an Attachment slot for that accessory
-- on the ViewModel rig at the correct canonical attachment point.
-- Uses InsertService + MarketplaceService to fetch catalogue data.
-- Because plugin HTTP calls go through Roblox's infrastructure,
-- this works without any external API key.

do -- scope: catalogue tab locals

	-- Canonical accessory type → attachment slot name mapping.
	-- This is the same mapping Roblox's HumanoidDescription uses internally.
	local ACCESSORY_SLOT_MAP: { [string]: string } = {
		["Hat"]           = "HatAttachment",
		["HairAccessory"] = "HairAttachment",
		["FaceAccessory"] = "FaceFrontAttachment",
		["NeckAccessory"] = "NeckAttachment",
		["ShoulderAccessory"] = "NeckAttachment",
		["FrontAccessory"] = "BodyFrontAttachment",
		["BackAccessory"]  = "BodyBackAttachment",
		["WaistAccessory"] = "WaistFrontAttachment",
	}

	sectionLabel(cataloguePage, "Accessory Catalogue", 1)
	hintLabel(cataloguePage, "Enter an accessory Asset ID from the Roblox catalogue, fetch its info, then add it as an attachment slot to your ViewModel rig. The slot type is determined by the accessory's AccessoryType.", 2)

	local _, getCatalogueId = makeTextField(cataloguePage, "Asset ID", 3, "")
	local fetchCatalogueBtn = actionButton(cataloguePage, "Fetch Accessory Info", 4, Color3.fromRGB(80, 80, 130))
	attachSounds(fetchCatalogueBtn)
	addTooltip(fetchCatalogueBtn, "Looks up the accessory by asset ID via MarketplaceService. Paste the numeric ID from the URL of the item's Roblox catalogue page.", "below")

	-- Info display panel
	local infoPanel = Instance.new("Frame")
	infoPanel.Size = UDim2.new(1, 0, 0, 90)
	infoPanel.BackgroundColor3 = Color3.fromRGB(34, 34, 38)
	infoPanel.BorderSizePixel = 0
	infoPanel.LayoutOrder = 5
	infoPanel.Visible = false
	infoPanel.Parent = cataloguePage
	do
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,4); c.Parent = infoPanel
		local p = Instance.new("UIPadding")
		p.PaddingTop = UDim.new(0,8); p.PaddingLeft = UDim.new(0,8)
		p.PaddingRight = UDim.new(0,8); p.PaddingBottom = UDim.new(0,8)
		p.Parent = infoPanel
	end

	local catalogueNameLbl = Instance.new("TextLabel")
	catalogueNameLbl.Text = ""
	catalogueNameLbl.Font = Enum.Font.SourceSansBold
	catalogueNameLbl.TextSize = 14
	catalogueNameLbl.TextColor3 = Color3.fromRGB(240, 240, 240)
	catalogueNameLbl.TextXAlignment = Enum.TextXAlignment.Left
	catalogueNameLbl.BackgroundTransparency = 1
	catalogueNameLbl.Size = UDim2.new(1, 0, 0, 20)
	catalogueNameLbl.TextTruncate = Enum.TextTruncate.AtEnd
	catalogueNameLbl.Parent = infoPanel

	local catalogueTypeLbl = Instance.new("TextLabel")
	catalogueTypeLbl.Text = ""
	catalogueTypeLbl.Font = Enum.Font.SourceSans
	catalogueTypeLbl.TextSize = 12
	catalogueTypeLbl.TextColor3 = Color3.fromRGB(180, 180, 200)
	catalogueTypeLbl.TextXAlignment = Enum.TextXAlignment.Left
	catalogueTypeLbl.BackgroundTransparency = 1
	catalogueTypeLbl.Position = UDim2.fromOffset(0, 22)
	catalogueTypeLbl.Size = UDim2.new(1, 0, 0, 16)
	catalogueTypeLbl.Parent = infoPanel

	local catalogueSlotLbl = Instance.new("TextLabel")
	catalogueSlotLbl.Text = ""
	catalogueSlotLbl.Font = Enum.Font.SourceSans
	catalogueSlotLbl.TextSize = 12
	catalogueSlotLbl.TextColor3 = Color3.fromRGB(130, 210, 130)
	catalogueSlotLbl.TextXAlignment = Enum.TextXAlignment.Left
	catalogueSlotLbl.BackgroundTransparency = 1
	catalogueSlotLbl.Position = UDim2.fromOffset(0, 40)
	catalogueSlotLbl.Size = UDim2.new(1, 0, 0, 16)
	catalogueSlotLbl.Parent = infoPanel

	local addSlotBtn = actionButton(infoPanel, "Add This Slot to ViewModel", 6, Color3.fromRGB(70, 130, 70))
	addSlotBtn.Position = UDim2.fromOffset(0, 60)
	addSlotBtn.Size = UDim2.new(1, 0, 0, 26)
	addSlotBtn.LayoutOrder = 0
	attachSounds(addSlotBtn, nil, SND_SAVE)

	local _, pushCatalogueLog, _ = makeLogPanel(cataloguePage, 7, 120)

	local currentCatalogueSlot = ""
	local lastAccessoryModel: Model? = nil  -- kept for preview; destroyed on next fetch

	fetchCatalogueBtn.MouseButton1Click:Connect(function()
		local idStr = getCatalogueId():match("^%s*(.-)%s*$")
		local assetId = tonumber(idStr)
		if not assetId then
			pushCatalogueLog({ level = "error", text = "Enter a valid numeric asset ID." })
			playSound(SND_ERROR)
			return
		end

		pushCatalogueLog({ level = "info", text = string.format("Fetching asset %d...", assetId) })
		infoPanel.Visible = false

		-- MarketplaceService:GetProductInfo works in plugin context
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(assetId, Enum.InfoType.Asset)
		end)

		if not ok or not info then
			pushCatalogueLog({ level = "error", text = "Failed to fetch asset info. Check the ID and try again." })
			playSound(SND_ERROR)
			return
		end

		-- Try to get the accessory type by loading a temporary copy
		-- InsertService:LoadAsset returns a Model containing the accessory
		local accessoryType = "Unknown"
		local slotName = ""
		local loadOk, assetModel = pcall(function()
			return InsertService:LoadAsset(assetId)
		end)
		if loadOk and assetModel then
			-- Find the Accessory inside the loaded model
			for _, child in ipairs(assetModel:GetDescendants()) do
				if child:IsA("Accessory") then
					local accType = tostring(child.AccessoryType)
					local mapped = ACCESSORY_SLOT_MAP[accType]
					if mapped then
						slotName = mapped
						accessoryType = accType
					else
						accessoryType = accType
						slotName = "HatAttachment"
					end
					break
				end
			end
			-- Keep a clean copy for preview, destroy the original container
			if lastAccessoryModel then
				pcall(function() lastAccessoryModel:Destroy() end)
			end
			lastAccessoryModel = assetModel:Clone()
			assetModel:Destroy()
		end

		currentCatalogueSlot = slotName ~= "" and slotName or "HatAttachment"

		catalogueNameLbl.Text = info.Name or ("Asset " .. assetId)
		catalogueTypeLbl.Text = string.format("Type: %s  |  Creator: %s",
			accessoryType, tostring(info.Creator and info.Creator.Name or "Unknown"))
		catalogueSlotLbl.Text = "→ Slot: " .. currentCatalogueSlot
		infoPanel.Visible = true

		pushCatalogueLog({ level = "success", text = string.format("'%s' maps to slot '%s'.", info.Name or "?", currentCatalogueSlot) })
	end)

	addSlotBtn.MouseButton1Click:Connect(function()
		if currentCatalogueSlot == "" then
			pushCatalogueLog({ level = "warn", text = "Fetch an accessory first." })
			return
		end
		-- Show the accessory in the gun rig viewport so you can see how it
		-- would look alongside the weapon. addAccessoryToGunPreview is safe
		-- to call even when the gun preview is empty.
		if lastAccessoryModel then
			addAccessoryToGunPreview(lastAccessoryModel)
			pushCatalogueLog({ level = "success", text = "Accessory added to the Rig viewport preview." })
		end
		pushCatalogueLog({ level = "info", text = string.format(
			"Slot '%s' — switch to VM tab and enable it in the Accessory Attachment Slots list.",
			currentCatalogueSlot) })
		if setclipboard then
			pcall(setclipboard, currentCatalogueSlot)
			pushCatalogueLog({ level = "info", text = "Slot name copied to clipboard." })
		end
	end)

end -- end do: section 13D

-- ============================================================
-- SECTION 13E: COPYRIGHT FOOTER + ABOUT PANEL
-- ============================================================

do -- scope: copyright locals

	-- Copyright bar — always visible at the bottom of the root frame,
	-- outside the scrolling page area. Hovering it reveals the About button.
	local copyrightBar = Instance.new("Frame")
	copyrightBar.Name = "_GRB_CopyrightBar"
	copyrightBar.Size = UDim2.new(1, 0, 0, 22)
	copyrightBar.Position = UDim2.new(0, 0, 1, -22)
	copyrightBar.BackgroundColor3 = Color3.fromRGB(22, 22, 26)
	copyrightBar.BorderSizePixel = 0
	copyrightBar.ZIndex = 50
	copyrightBar.Parent = root  -- root Frame, sits above pages

	local copyrightLbl = Instance.new("TextLabel")
	copyrightLbl.Text = "© DeathToTheStadium — Gun Rig / ViewModel Builder"
	copyrightLbl.Font = Enum.Font.SourceSans
	copyrightLbl.TextSize = 11
	copyrightLbl.TextColor3 = Color3.fromRGB(130, 130, 140)
	copyrightLbl.BackgroundTransparency = 1
	copyrightLbl.Size = UDim2.new(1, -60, 1, 0)
	copyrightLbl.TextXAlignment = Enum.TextXAlignment.Left
	copyrightLbl.ZIndex = 51
	copyrightLbl.Parent = copyrightBar
	do
		local p = Instance.new("UIPadding"); p.PaddingLeft = UDim.new(0,8); p.Parent = copyrightLbl
	end

	local aboutBtn = Instance.new("TextButton")
	aboutBtn.Text = "About ▸"
	aboutBtn.Font = Enum.Font.SourceSansSemibold
	aboutBtn.TextSize = 11
	aboutBtn.TextColor3 = Color3.fromRGB(130, 170, 230)
	aboutBtn.BackgroundTransparency = 1
	aboutBtn.Size = UDim2.new(0, 56, 1, 0)
	aboutBtn.Position = UDim2.new(1, -60, 0, 0)
	aboutBtn.ZIndex = 51
	aboutBtn.Parent = copyrightBar
	attachSounds(aboutBtn)

	-- ---- About overlay ----
	local aboutOverlay = Instance.new("Frame")
	aboutOverlay.Name = "_GRB_About"
	aboutOverlay.Size = UDim2.new(1, 0, 1, -22)  -- full height minus copyright bar
	aboutOverlay.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
	aboutOverlay.BorderSizePixel = 0
	aboutOverlay.ZIndex = 80
	aboutOverlay.Visible = false
	aboutOverlay.Parent = root

	-- Header row inside the overlay
	local aboutHeader = Instance.new("Frame")
	aboutHeader.Size = UDim2.new(1, 0, 0, 36)
	aboutHeader.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
	aboutHeader.BorderSizePixel = 0
	aboutHeader.ZIndex = 81
	aboutHeader.Parent = aboutOverlay

	local aboutTitle = Instance.new("TextLabel")
	aboutTitle.Text = "About — Gun Rig / ViewModel Builder"
	aboutTitle.Font = Enum.Font.SourceSansBold
	aboutTitle.TextSize = 14
	aboutTitle.TextColor3 = Color3.fromRGB(230, 230, 230)
	aboutTitle.BackgroundTransparency = 1
	aboutTitle.Size = UDim2.new(1, -40, 1, 0)
	aboutTitle.TextXAlignment = Enum.TextXAlignment.Left
	aboutTitle.ZIndex = 82
	aboutTitle.Parent = aboutHeader
	do
		local p = Instance.new("UIPadding"); p.PaddingLeft = UDim.new(0,10); p.Parent = aboutTitle
	end

	local closeAboutBtn = Instance.new("TextButton")
	closeAboutBtn.Text = "✕"
	closeAboutBtn.Font = Enum.Font.SourceSansBold
	closeAboutBtn.TextSize = 14
	closeAboutBtn.TextColor3 = Color3.fromRGB(200, 100, 100)
	closeAboutBtn.BackgroundTransparency = 1
	closeAboutBtn.Size = UDim2.new(0, 36, 1, 0)
	closeAboutBtn.Position = UDim2.new(1, -36, 0, 0)
	closeAboutBtn.ZIndex = 82
	closeAboutBtn.Parent = aboutHeader
	attachSounds(closeAboutBtn)

	-- Sub-tab bar inside the overlay
	local aboutTabBar = Instance.new("Frame")
	aboutTabBar.Size = UDim2.new(1, 0, 0, 28)
	aboutTabBar.Position = UDim2.fromOffset(0, 36)
	aboutTabBar.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
	aboutTabBar.BorderSizePixel = 0
	aboutTabBar.ZIndex = 81
	aboutTabBar.Parent = aboutOverlay
	do
		local l = Instance.new("UIListLayout")
		l.FillDirection = Enum.FillDirection.Horizontal
		l.SortOrder = Enum.SortOrder.LayoutOrder
		l.Parent = aboutTabBar
	end

	local aboutContent = Instance.new("ScrollingFrame")
	aboutContent.Size = UDim2.new(1, 0, 1, -64)
	aboutContent.Position = UDim2.fromOffset(0, 64)
	aboutContent.BackgroundTransparency = 1
	aboutContent.BorderSizePixel = 0
	aboutContent.ScrollBarThickness = 5
	aboutContent.AutomaticCanvasSize = Enum.AutomaticSize.Y
	aboutContent.CanvasSize = UDim2.new(0, 0, 0, 0)
	aboutContent.ZIndex = 81
	aboutContent.Parent = aboutOverlay
	do
		local l = Instance.new("UIListLayout")
		l.SortOrder = Enum.SortOrder.LayoutOrder
		l.Padding = UDim.new(0, 6)
		l.Parent = aboutContent
		local p = Instance.new("UIPadding")
		p.PaddingTop = UDim.new(0,10); p.PaddingLeft = UDim.new(0,12)
		p.PaddingRight = UDim.new(0,12); p.PaddingBottom = UDim.new(0,10)
		p.Parent = aboutContent
	end

	-- Helper: make a sub-tab button inside the About overlay
	local function makeAboutTab(label: string, order: number): TextButton
		local b = Instance.new("TextButton")
		b.Text = label
		b.Font = Enum.Font.SourceSansSemibold
		b.TextSize = 12
		b.TextColor3 = Color3.fromRGB(210, 210, 210)
		b.BackgroundColor3 = Color3.fromRGB(36, 36, 44)
		b.Size = UDim2.new(0, 90, 1, 0)
		b.BorderSizePixel = 0
		b.AutoButtonColor = false
		b.LayoutOrder = order
		b.ZIndex = 82
		b.Parent = aboutTabBar
		attachSounds(b)
		return b
	end

	local ownerTab   = makeAboutTab("Owner",       1)
	local rightsTab  = makeAboutTab("Your Rights", 2)
	local licenseTab = makeAboutTab("License",     3)

	-- Helper: clear and populate the content area
	local function showAboutSection(lines: { { bold: boolean, text: string } })
		for _, child in ipairs(aboutContent:GetChildren()) do
			if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
				child:Destroy()
			end
		end
		for i, line in ipairs(lines) do
			local lbl = Instance.new("TextLabel")
			lbl.Text = line.text
			lbl.Font = line.bold and Enum.Font.SourceSansBold or Enum.Font.SourceSans
			lbl.TextSize = line.bold and 14 or 13
			lbl.TextColor3 = line.bold and Color3.fromRGB(230,230,230) or Color3.fromRGB(190,190,200)
			lbl.TextWrapped = true
			lbl.TextXAlignment = Enum.TextXAlignment.Left
			lbl.TextYAlignment = Enum.TextYAlignment.Top
			lbl.BackgroundTransparency = 1
			lbl.AutomaticSize = Enum.AutomaticSize.Y
			lbl.Size = UDim2.new(1, 0, 0, 0)
			lbl.LayoutOrder = i
			lbl.ZIndex = 82
			lbl.Parent = aboutContent
		end
	end

	local ABOUT_TABS: { { { bold: boolean, text: string } } } = {
		-- Owner
		{
			{ bold = true,  text = "DeathToTheStadium (@tostadium)" },
			{ bold = false, text = "Solo indie developer and entrepreneur with 14+ years of Roblox and Luau experience." },
			{ bold = false, text = "Operates MatterDox, a rapid-deployment software design lab, and builds open-source tooling and games for the Roblox ecosystem." },
			{ bold = true,  text = "Flagship projects" },
			{ bold = false, text = "RoExpress — Express.js-inspired Luau networking framework  (roexpress.dev)" },
			{ bold = false, text = "ARMORY OS — modular weapon framework for Roblox (this plugin is part of the tooling suite)" },
			{ bold = false, text = "Retro Rumble — game developed in partnership with Lucidity" },
			{ bold = true,  text = "Find me" },
			{ bold = false, text = "Roblox: @tostadium\nGitHub: DeathToTheStadium\nDevForum: @tostadium" },
		},
		-- Your Rights
		{
			{ bold = true,  text = "What you can do with this plugin" },
			{ bold = false, text = "✓  Use it freely in your own Roblox projects, commercial or personal." },
			{ bold = false, text = "✓  Modify a local copy for your own use." },
			{ bold = false, text = "✓  Share the unmodified plugin file with collaborators on your team." },
			{ bold = true,  text = "What you cannot do" },
			{ bold = false, text = "✗  Redistribute, resell, or publish this plugin (modified or unmodified) on the Roblox Creator Store or any other marketplace without written permission." },
			{ bold = false, text = "✗  Remove or alter the copyright notice, author credit, or license text." },
			{ bold = false, text = "✗  Claim authorship of this tool." },
			{ bold = true,  text = "No warranty" },
			{ bold = false, text = "This plugin is provided as-is. DeathToTheStadium is not liable for data loss, model corruption, or any other damages arising from its use." },
		},
		-- License
		{
			{ bold = true,  text = "Proprietary — All Rights Reserved" },
			{ bold = false, text = "Copyright © DeathToTheStadium. All rights reserved." },
			{ bold = false, text = "This software is the exclusive property of DeathToTheStadium. No part of this software may be reproduced, distributed, or transmitted in any form or by any means, including photocopying, recording, or other electronic or mechanical methods, without the prior written permission of the author, except for personal, non-commercial use within your own Roblox projects." },
			{ bold = true,  text = "Third-party services" },
			{ bold = false, text = "This plugin uses Roblox's MarketplaceService and InsertService to access catalogue data. Use of those services is subject to Roblox's Terms of Use and API policies." },
			{ bold = true,  text = "Contact" },
			{ bold = false, text = "For licensing inquiries, contact DeathToTheStadium on the Roblox DevForum or via the MatterDox site." },
		},
	}

	local currentAboutTab = 1
	local function selectAboutTab(i: number)
		currentAboutTab = i
		local TABS = { ownerTab, rightsTab, licenseTab }
		for j, t in ipairs(TABS) do
			t.BackgroundColor3 = j == i and Color3.fromRGB(60, 90, 140) or Color3.fromRGB(36, 36, 44)
		end
		showAboutSection(ABOUT_TABS[i])
	end

	ownerTab.MouseButton1Click:Connect(function() selectAboutTab(1) end)
	rightsTab.MouseButton1Click:Connect(function() selectAboutTab(2) end)
	licenseTab.MouseButton1Click:Connect(function() selectAboutTab(3) end)

	aboutBtn.MouseButton1Click:Connect(function()
		aboutOverlay.Visible = true
		selectAboutTab(1)
		playSound(SND_CLICK)
	end)

	closeAboutBtn.MouseButton1Click:Connect(function()
		aboutOverlay.Visible = false
		playSound(SND_CLICK)
	end)

end -- end do: section 13E

-- ============================================================
-- SECTION 14: DOCS TAB CONTENTS (simple Markdown renderer)
-- ============================================================

do -- scope block: docs and selection-sync locals die here
	local docLines = parseSimpleMarkdown(DOCUMENTATION_MD)

	for i, docLine in ipairs(docLines) do
		if docLine.level == -1 then
			local spacer = Instance.new("Frame")
			spacer.Size = UDim2.new(1, 0, 0, 6)
			spacer.BackgroundTransparency = 1
			spacer.LayoutOrder = i
			spacer.Parent = docsPage
		else
			local lbl = Instance.new("TextLabel")
			lbl.Text = docLine.text
			lbl.TextWrapped = true
			lbl.TextXAlignment = Enum.TextXAlignment.Left
			lbl.TextYAlignment = Enum.TextYAlignment.Top
			lbl.BackgroundTransparency = 1
			lbl.AutomaticSize = Enum.AutomaticSize.Y
			lbl.Size = UDim2.new(1, 0, 0, 0)
			lbl.LayoutOrder = i

			if docLine.level == 1 then
				lbl.Font = Enum.Font.SourceSansBold
				lbl.TextSize = 20
				lbl.TextColor3 = Color3.fromRGB(240, 240, 240)
			elseif docLine.level == 2 then
				lbl.Font = Enum.Font.SourceSansBold
				lbl.TextSize = 16
				lbl.TextColor3 = Color3.fromRGB(210, 210, 230)
			else
				lbl.Font = Enum.Font.SourceSans
				lbl.TextSize = 13
				lbl.TextColor3 = Color3.fromRGB(190, 190, 190)
			end

			lbl.Parent = docsPage
		end
	end

	-- ============================================================
	-- SECTION 15: SELECTION SYNC + TOGGLE
	-- ============================================================

	Selection.SelectionChanged:Connect(function()
		-- Auto-refresh target label is handled by the refreshTargetBtn click handler.
		-- Nothing needed here that requires cross-section state.
	end)

	toggleButton.Click:Connect(function()
		widget.Enabled = not widget.Enabled
	end)

	widget:GetPropertyChangedSignal("Enabled"):Connect(function()
		toggleButton:SetActive(widget.Enabled)
	end)

	toggleButton:SetActive(widget.Enabled)

end -- end do: sections 14 + 15