--!strict
--[[
	AISpawner.server.luau
	Maintains exactly TOTAL_TARGET entities (Players + NPCs) at all times.

	NPC skins: randomly picks a Roblox User ID from NPC_USER_IDS, fetches
	its HumanoidDescription via pcall, and applies it with ApplyDescription().
	Falls back to a plain grey dummy if the web request fails.

	Entity lifecycle:
	  • Server start    → spawn (TOTAL_TARGET - #Players) NPCs
	  • PlayerAdded     → destroy one NPC
	  • PlayerRemoving  → task.wait(1) then refill
	  • Humanoid.Died   → destroy after 3 s then refill
]]

local Players            = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")

local SimplePath: any = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SimplePath"))

-- ============================================================
-- Constants
-- ============================================================

local TOTAL_TARGET       : number = 25
local NPC_WALK_SPEED     : number = 12
local NPC_DETECTION_RANGE: number = 40
local NPC_SHOOT_RANGE    : number = 40
local NPC_DAMAGE         : number = 15
local NPC_FIRE_INTERVAL  : number = 1.0
local NPC_AI_TICK        : number = 0.5
local RESPAWN_DELAY      : number = 3.0

-- Roblox User IDs used as NPC skins.
-- Each is fetched via GetHumanoidDescriptionFromUserId (pcall-wrapped).
-- Replace or extend this list with any valid Roblox User IDs you prefer.
local NPC_USER_IDS: { number } = {
	1,         -- Roblox
	156,       -- Builderman
	261,       -- Shedletsky
	55347,     -- Merely
	1096093,   -- Clockwork
	1211950,   -- Loleris
	2695978,   -- alexnewtron
	3352398,   -- Quenty
	9498894,   -- asimo3089
	28959030,  -- badcc
	7481548,   -- nosniy
	81619313,  -- Seranok
	4397833,   -- dphantom
	6354356,   -- dRaiderx
	32370614,  -- Merely (alt)
}

local FALLBACK_WAYPOINTS: { Vector3 } = {
	Vector3.new( 0,   3,   0),
	Vector3.new( 25,  3,   25),
	Vector3.new(-25,  3,   25),
	Vector3.new( 25,  3,  -25),
	Vector3.new(-25,  3,  -25),
	Vector3.new( 50,  3,   0),
	Vector3.new( 0,   3,   50),
	Vector3.new(-50,  3,   0),
	Vector3.new( 0,   3,  -50),
}

local AGENT_PARAMS = {
	AgentRadius     = 1.5,
	AgentHeight     = 5,
	AgentCanJump    = true,
	AgentCanClimb   = false,
	WaypointSpacing = 4,
}

-- ============================================================
-- NPC Folder
-- ============================================================

local npcFolder: Folder
do
	local existing = workspace:FindFirstChild("NPCs")
	if existing and existing:IsA("Folder") then
		npcFolder = existing :: Folder
	else
		npcFolder        = Instance.new("Folder")
		npcFolder.Name   = "NPCs"
		npcFolder.Parent = workspace
	end
end

-- ============================================================
-- State
-- ============================================================

local npcCounter: number                    = 0
local npcShootCooldowns: { [Model]: number } = {}

-- ============================================================
-- Entity Count
-- ============================================================

local function getEntityCount(): number
	return #Players:GetPlayers() + #npcFolder:GetChildren()
end

-- ============================================================
-- Spawn Position
-- ============================================================

local function getRandomPatrolWaypoint(): Vector3
	local spawnLocations: { SpawnLocation } = {}
	for _, desc in workspace:GetDescendants() do
		if desc:IsA("SpawnLocation") then
			table.insert(spawnLocations, desc :: SpawnLocation)
		end
	end
	if #spawnLocations > 0 then
		return spawnLocations[math.random(1, #spawnLocations)].Position + Vector3.new(0, 3, 0)
	end
	return FALLBACK_WAYPOINTS[math.random(1, #FALLBACK_WAYPOINTS)]
end

-- ============================================================
-- NPC Model Builder — Primitive Fallback
-- ============================================================

local function buildPrimitiveFallback(name: string): Model
	local model = Instance.new("Model")
	model.Name  = name

	local hrp            = Instance.new("Part")
	hrp.Name             = "HumanoidRootPart"
	hrp.Size             = Vector3.new(2, 5, 1)
	hrp.Transparency     = 1
	hrp.CanCollide       = true
	hrp.Anchored         = false
	hrp.Parent           = model

	local torso          = Instance.new("Part")
	torso.Name           = "Torso"
	torso.Size           = Vector3.new(2, 3, 1)
	torso.Color          = Color3.fromRGB(70, 100, 180)
	torso.Material       = Enum.Material.SmoothPlastic
	torso.CanCollide     = false
	torso.Anchored       = false
	torso.Parent         = model

	local torsoWeld      = Instance.new("Weld")
	torsoWeld.Part0      = hrp
	torsoWeld.Part1      = torso
	torsoWeld.C0         = CFrame.new(0, -0.5, 0)
	torsoWeld.Parent     = hrp

	local head           = Instance.new("Part")
	head.Name            = "Head"
	head.Size            = Vector3.new(1, 1, 1)
	head.Color           = Color3.fromRGB(255, 205, 160)
	head.Material        = Enum.Material.SmoothPlastic
	head.CanCollide      = false
	head.Anchored        = false
	head.Parent          = model

	local headWeld       = Instance.new("Weld")
	headWeld.Part0       = hrp
	headWeld.Part1       = head
	headWeld.C0          = CFrame.new(0, 2.5, 0)
	headWeld.Parent      = hrp

	local humanoid       = Instance.new("Humanoid")
	humanoid.MaxHealth   = 100
	humanoid.Health      = 100
	humanoid.WalkSpeed   = NPC_WALK_SPEED
	humanoid.HipHeight   = 2.5
	humanoid.RigType     = Enum.HumanoidRigType.R15
	humanoid.Parent      = model

	model.PrimaryPart = hrp
	return model
end

-- ============================================================
-- Name Billboard  (shared by both build paths)
-- ============================================================

local function attachNameTag(model: Model, name: string)
	local head = model:FindFirstChild("Head") :: BasePart?
	if not head then return end

	local bg              = Instance.new("BillboardGui")
	bg.Size               = UDim2.new(0, 80, 0, 28)
	bg.StudsOffset        = Vector3.new(0, 3, 0)
	bg.AlwaysOnTop        = false
	bg.Parent             = head

	local label           = Instance.new("TextLabel")
	label.Text            = name
	label.Size            = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextColor3      = Color3.new(1, 1, 1)
	label.Font            = Enum.Font.GothamBold
	label.TextScaled      = true
	label.Parent          = bg
end

-- ============================================================
-- NPC Model Builder — HumanoidDescription (with pcall fallback)
-- ============================================================

local function buildNPCModel(name: string): Model
	local userId = NPC_USER_IDS[math.random(1, #NPC_USER_IDS)]

	-- Step 1: fetch HumanoidDescription
	local desc: HumanoidDescription? = nil
	local ok1, res1 = pcall(function(): HumanoidDescription
		return Players:GetHumanoidDescriptionFromUserId(userId)
	end)
	if ok1 and typeof(res1) == "Instance" then
		desc = res1 :: HumanoidDescription
	end

	-- Step 2: build R15 character from description
	local model: Model? = nil
	if desc then
		local ok2, res2 = pcall(function(): Model
			return Players:CreateHumanoidModelFromDescription(
				desc :: HumanoidDescription,
				Enum.HumanoidRigType.R15
			)
		end)
		if ok2 and typeof(res2) == "Instance" then
			model = res2 :: Model
		end
	end

	-- Step 3: fall back to grey dummy if web calls failed
	if not model then
		warn(("[AISpawner] Skin fetch failed for userId %d — using fallback"):format(userId))
		model = buildPrimitiveFallback(name)
		attachNameTag(model, name)
		return model
	end

	model.Name = name

	-- Ensure PrimaryPart is set
	if not model.PrimaryPart then
		local hrp = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp then model.PrimaryPart = hrp end
	end

	-- Configure Humanoid
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if humanoid then
		humanoid.MaxHealth = 100
		humanoid.Health    = 100
		humanoid.WalkSpeed = NPC_WALK_SPEED
	end

	attachNameTag(model, name)
	return model
end

-- ============================================================
-- AI Helpers
-- ============================================================

local function hasLineOfSight(origin: Vector3, target: Vector3, exclude: { Instance }): boolean
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = exclude
	params.FilterType                 = Enum.RaycastFilterType.Exclude
	return workspace:Raycast(origin, target - origin, params) == nil
end

local function findNearestVisiblePlayer(npcModel: Model, hrp: BasePart): (Player?, BasePart?)
	local nearest: Player?      = nil
	local nearestHRP: BasePart? = nil
	local nearestDist           = NPC_DETECTION_RANGE

	for _, player in Players:GetPlayers() do
		local char = player.Character
		if not char then continue end
		local targetHRP = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not targetHRP then continue end
		local h = char:FindFirstChildOfClass("Humanoid") :: Humanoid?
		if not h or h.Health <= 0 then continue end
		local dist = (targetHRP.Position - hrp.Position).Magnitude
		if dist < nearestDist then
			if hasLineOfSight(hrp.Position + Vector3.new(0, 2, 0), targetHRP.Position, { npcModel, char }) then
				nearest     = player
				nearestHRP  = targetHRP
				nearestDist = dist
			end
		end
	end
	return nearest, nearestHRP
end

local function npcShoot(npcModel: Model, hrp: BasePart, targetHRP: BasePart)
	local now      = tick()
	local lastShot = npcShootCooldowns[npcModel] or 0
	if now - lastShot < NPC_FIRE_INTERVAL then return end
	npcShootCooldowns[npcModel] = now

	local origin    = hrp.Position + Vector3.new(0, 2, 0)
	local direction = targetHRP.Position - origin
	if direction.Magnitude > NPC_SHOOT_RANGE then return end

	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { npcModel }
	params.FilterType                 = Enum.RaycastFilterType.Exclude

	local result = workspace:Raycast(origin, direction, params)
	if not result then return end

	local hitChar = result.Instance:FindFirstAncestorOfClass("Model")
	if not hitChar then return end
	if not Players:GetPlayerFromCharacter(hitChar) then return end

	local h = hitChar:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if h and h.Health > 0 then
		h:TakeDamage(NPC_DAMAGE)
	end
end

-- moveNPCToPosition removed — SimplePath handles stuck detection and continuous re-pathing.

-- ============================================================
-- NPC Animations  (R15 Walk / Idle, server-loaded)
-- ============================================================

local function setupNPCAnimations(npcModel: Model)
	local humanoid = npcModel:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if not humanoid then return end

	-- Ensure Animator exists
	local animator = humanoid:FindFirstChildOfClass("Animator") :: Animator?
	if not animator then
		animator        = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local walkAnim           = Instance.new("Animation")
	walkAnim.AnimationId     = "rbxassetid://507777826"  -- R15 Walk

	local idleAnim           = Instance.new("Animation")
	idleAnim.AnimationId     = "rbxassetid://507766388"  -- R15 Idle

	local walkTrack = (animator :: Animator):LoadAnimation(walkAnim)
	local idleTrack = (animator :: Animator):LoadAnimation(idleAnim)

	walkTrack.Looped = true
	idleTrack.Looped = true

	idleTrack:Play()

	humanoid.Running:Connect(function(speed: number)
		if speed > 0.5 then
			if not walkTrack.IsPlaying then walkTrack:Play()  end
			if idleTrack.IsPlaying     then idleTrack:Stop()  end
		else
			if walkTrack.IsPlaying     then walkTrack:Stop()  end
			if not idleTrack.IsPlaying then idleTrack:Play()  end
		end
	end)
end

-- ============================================================
-- Main NPC AI Loop
-- ============================================================

local function runNPCLoop(npcModel: Model, path: any)
	local humanoid = npcModel:FindFirstChildOfClass("Humanoid") :: Humanoid?
	local hrp      = npcModel.PrimaryPart
	if not humanoid or not hrp then return end

	while npcModel.Parent ~= nil and humanoid.Health > 0 do
		local _, targetHRP = findNearestVisiblePlayer(npcModel, hrp)

		if targetHRP then
			-- Combat mode: stop SimplePath so it doesn't fight MoveTo
			path:Stop()
			humanoid:MoveTo(targetHRP.Position)
			npcShoot(npcModel, hrp, targetHRP)
			task.wait(NPC_AI_TICK)
		else
			-- Patrol mode: SimplePath computes + walks; handles stuck recovery automatically
			local arrived   = false
			local reachConn = path.Reached:Connect(function()
				arrived = true
			end)
			local errConn = path.Error:Connect(function(_errType: any)
				arrived = true  -- treat errors as "done" so the loop advances
			end)

			path:Run(getRandomPatrolWaypoint())

			-- Yield until arrival, error, death, or 12-second timeout
			local deadline = tick() + 12
			while not arrived
				and npcModel.Parent ~= nil
				and humanoid.Health > 0
				and tick() < deadline
			do
				task.wait(NPC_AI_TICK)
			end

			reachConn:Disconnect()
			errConn:Disconnect()
		end

		task.wait(0)
	end
end

-- ============================================================
-- NPC Spawning
-- ============================================================

local function spawnNPCsToFill()
	local deficit = TOTAL_TARGET - getEntityCount()
	if deficit <= 0 then return end

	for _ = 1, deficit do
		npcCounter += 1
		local spawnPos = getRandomPatrolWaypoint()
		local npcName  = "NPC_" .. tostring(npcCounter)

		local model = buildNPCModel(npcName)
		model:PivotTo(CFrame.new(spawnPos))
		model.Parent = npcFolder

		local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
		npcShootCooldowns[model] = 0

		-- One SimplePath per NPC — provides stuck detection + continuous re-pathing
		local path = SimplePath.new(model, AGENT_PARAMS)

		humanoid.Died:Connect(function()
			npcShootCooldowns[model] = nil
			path:Destroy()
			task.delay(RESPAWN_DELAY, function()
				if model.Parent then model:Destroy() end
				spawnNPCsToFill()
			end)
		end)

		task.spawn(runNPCLoop, model, path)
		task.spawn(setupNPCAnimations, model)
	end
end

-- ============================================================
-- Player Hooks
-- ============================================================

Players.PlayerAdded:Connect(function(_player: Player)
	local npcs = npcFolder:GetChildren()
	if #npcs > 0 then
		local toRemove = npcs[1]
		npcShootCooldowns[toRemove :: Model] = nil
		toRemove:Destroy()
	end
end)

Players.PlayerRemoving:Connect(function(_player: Player)
	task.wait(1)
	spawnNPCsToFill()
end)

-- ============================================================
-- Bootstrap
-- ============================================================

task.wait(2)
spawnNPCsToFill()
