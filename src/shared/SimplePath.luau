--[[
	SimplePath.luau  (shared ModuleScript)
	Pathfinding wrapper with stuck detection and continuous path recalculation.
	Original author: @V3N0M_Z  (https://v3n0m-z.github.io/RBLX-SimplePath/)
	License: MIT
]]

local DEFAULT_SETTINGS = {
	TIME_VARIANCE    = 0.07;
	COMPARISON_CHECKS = 1;
	JUMP_WHEN_STUCK  = true;
}

local PathfindingService = game:GetService("PathfindingService")
local Players            = game:GetService("Players")

local function output(func, msg)
	func(((func == error and "SimplePath Error: ") or "SimplePath: ") .. msg)
end

local Path = {
	StatusType = {
		Idle   = "Idle";
		Active = "Active";
	};
	ErrorType = {
		LimitReached     = "LimitReached";
		TargetUnreachable = "TargetUnreachable";
		ComputationError  = "ComputationError";
		AgentStuck        = "AgentStuck";
	};
}

Path.__index = function(t, index)
	if index == "Stopped" and not t._humanoid then
		output(error, "Attempt to use Path.Stopped on a non-humanoid.")
	end
	return (t._events[index] and t._events[index].Event)
		or (index == "LastError" and t._lastError)
		or (index == "Status"    and t._status)
		or Path[index]
end

local visualWaypoint          = Instance.new("Part")
visualWaypoint.Size           = Vector3.new(0.3, 0.3, 0.3)
visualWaypoint.Anchored       = true
visualWaypoint.CanCollide     = false
visualWaypoint.Material       = Enum.Material.Neon
visualWaypoint.Shape          = Enum.PartType.Ball

local function declareError(self, errorType)
	self._lastError = errorType
	self._events.Error:Fire(errorType)
end

local function createVisualWaypoints(waypoints)
	local result = {}
	for _, wp in ipairs(waypoints) do
		local clone = visualWaypoint:Clone()
		clone.Position = wp.Position
		clone.Color    = (wp == waypoints[#waypoints] and Color3.fromRGB(0, 255, 0))
			or (wp.Action == Enum.PathWaypointAction.Jump and Color3.fromRGB(255, 0, 0))
			or Color3.fromRGB(255, 139, 0)
		clone.Parent = workspace
		table.insert(result, clone)
	end
	return result
end

local function destroyVisualWaypoints(waypoints)
	if waypoints then
		for _, wp in ipairs(waypoints) do wp:Destroy() end
	end
end

local function getNonHumanoidWaypoint(self)
	for i = 2, #self._waypoints do
		if (self._waypoints[i].Position - self._waypoints[i - 1].Position).Magnitude > 0.1 then
			return i
		end
	end
	return 2
end

local function setJumpState(self)
	pcall(function()
		if self._humanoid:GetState() ~= Enum.HumanoidStateType.Jumping
			and self._humanoid:GetState() ~= Enum.HumanoidStateType.Freefall then
			self._humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		end
	end)
end

local function move(self)
	if self._waypoints[self._currentWaypoint].Action == Enum.PathWaypointAction.Jump then
		setJumpState(self)
	end
	self._humanoid:MoveTo(self._waypoints[self._currentWaypoint].Position)
end

local function disconnectMoveConnection(self)
	if self._moveConnection then
		self._moveConnection:Disconnect()
		self._moveConnection = nil
	end
end

local function invokeWaypointReached(self)
	local last = self._waypoints[self._currentWaypoint - 1]
	local next = self._waypoints[self._currentWaypoint]
	self._events.WaypointReached:Fire(self._agent, last, next)
end

local function moveToFinished(self, reached)
	if not getmetatable(self) then return end

	if not self._humanoid then
		if reached and self._currentWaypoint + 1 <= #self._waypoints then
			invokeWaypointReached(self)
			self._currentWaypoint += 1
		elseif reached then
			destroyVisualWaypoints(self._visualWaypoints)
			self._target = nil
			self._events.Reached:Fire(self._agent, self._waypoints[self._currentWaypoint])
		else
			destroyVisualWaypoints(self._visualWaypoints)
			self._target = nil
			declareError(self, self.ErrorType.TargetUnreachable)
		end
		return
	end

	if reached and self._currentWaypoint + 1 <= #self._waypoints then
		if self._currentWaypoint + 1 < #self._waypoints then
			invokeWaypointReached(self)
		end
		self._currentWaypoint += 1
		move(self)
	elseif reached then
		disconnectMoveConnection(self)
		self._status = Path.StatusType.Idle
		destroyVisualWaypoints(self._visualWaypoints)
		self._events.Reached:Fire(self._agent, self._waypoints[self._currentWaypoint])
	else
		disconnectMoveConnection(self)
		self._status = Path.StatusType.Idle
		destroyVisualWaypoints(self._visualWaypoints)
		declareError(self, self.ErrorType.TargetUnreachable)
	end
end

local function comparePosition(self)
	if self._currentWaypoint == #self._waypoints then return end
	local moved = (self._agent.PrimaryPart.Position - self._position._last).Magnitude
	self._position._count = (moved <= 0.07 and (self._position._count + 1)) or 0
	self._position._last  = self._agent.PrimaryPart.Position
	if self._position._count >= self._settings.COMPARISON_CHECKS then
		if self._settings.JUMP_WHEN_STUCK then setJumpState(self) end
		declareError(self, self.ErrorType.AgentStuck)
	end
end

-- Static helper: find nearest player character from a world position
function Path.GetNearestCharacter(fromPosition)
	local character, dist = nil, math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character and player.Character.PrimaryPart then
			local d = (player.Character.PrimaryPart.Position - fromPosition).Magnitude
			if d < dist then
				character, dist = player.Character, d
			end
		end
	end
	return character
end

function Path.new(agent, agentParameters, override)
	if not (agent and agent:IsA("Model") and agent.PrimaryPart) then
		output(error, "Pathfinding agent must be a valid Model with a set PrimaryPart.")
	end

	local self = setmetatable({
		_settings = override or {};
		_events   = {
			Reached        = Instance.new("BindableEvent");
			WaypointReached = Instance.new("BindableEvent");
			Blocked        = Instance.new("BindableEvent");
			Error          = Instance.new("BindableEvent");
			Stopped        = Instance.new("BindableEvent");
		};
		_agent    = agent;
		_humanoid = agent:FindFirstChildOfClass("Humanoid");
		_path     = PathfindingService:CreatePath(agentParameters);
		_status   = "Idle";
		_t        = 0;
		_position = { _last = Vector3.new(); _count = 0 };
	}, Path)

	-- Merge defaults
	for k, v in DEFAULT_SETTINGS do
		if self._settings[k] == nil then self._settings[k] = v end
	end

	-- Handle blocked waypoints
	self._path.Blocked:Connect(function(blockedIdx)
		if self._currentWaypoint
			and blockedIdx >= self._currentWaypoint
			and blockedIdx <= self._currentWaypoint + 1
			and self._humanoid
		then
			setJumpState(self)
			self._events.Blocked:Fire(self._agent, self._waypoints and self._waypoints[blockedIdx])
		end
	end)

	return self
end

function Path:Destroy()
	for _, event in self._events do event:Destroy() end
	self._events = nil
	destroyVisualWaypoints(rawget(self, "_visualWaypoints"))
	self._path:Destroy()
	setmetatable(self, nil)
	for k in self do self[k] = nil end
end

function Path:Stop()
	if not self._humanoid then
		output(error, "Attempt to call Path:Stop() on a non-humanoid.")
		return
	end
	if self._status == Path.StatusType.Idle then return end
	disconnectMoveConnection(self)
	self._status = Path.StatusType.Idle
	destroyVisualWaypoints(self._visualWaypoints)
	self._events.Stopped:Fire(self._agent)
end

function Path:Run(target)
	if not (target and (typeof(target) == "Vector3" or (typeof(target) == "Instance" and target:IsA("BasePart")))) then
		output(error, "Pathfinding target must be a Vector3 or BasePart.")
	end

	-- Rate-limit protection
	if os.clock() - self._t <= self._settings.TIME_VARIANCE and self._humanoid then
		task.wait(self._settings.TIME_VARIANCE - (os.clock() - self._t))
		declareError(self, self.ErrorType.LimitReached)
		return false
	elseif self._humanoid then
		self._t = os.clock()
	end

	local targetPos = typeof(target) == "Vector3" and target or (target :: BasePart).Position

	local computed = pcall(function()
		self._path:ComputeAsync(self._agent.PrimaryPart.Position, targetPos)
	end)

	if not computed
		or self._path.Status == Enum.PathStatus.NoPath
		or #self._path:GetWaypoints() < 2
		or (self._humanoid and self._humanoid:GetState() == Enum.HumanoidStateType.Freefall)
	then
		destroyVisualWaypoints(self._visualWaypoints)
		task.wait()
		declareError(self, self.ErrorType.ComputationError)
		return false
	end

	self._status  = self._humanoid and Path.StatusType.Active or Path.StatusType.Idle
	self._target  = target
	pcall(function() self._agent.PrimaryPart:SetNetworkOwner(nil) end)

	self._waypoints        = self._path:GetWaypoints()
	self._currentWaypoint  = 2

	if self._humanoid then comparePosition(self) end

	destroyVisualWaypoints(self._visualWaypoints)
	self._visualWaypoints = self.Visualize and createVisualWaypoints(self._waypoints)

	if not self._moveConnection and self._humanoid then
		self._moveConnection = self._humanoid.MoveToFinished:Connect(function(reached)
			moveToFinished(self, reached)
		end)
	end

	if self._humanoid then
		self._humanoid:MoveTo(self._waypoints[self._currentWaypoint].Position)
	elseif #self._waypoints == 2 then
		self._target = nil
		destroyVisualWaypoints(self._visualWaypoints)
		self._events.Reached:Fire(self._agent, self._waypoints[2])
	else
		self._currentWaypoint = getNonHumanoidWaypoint(self)
		moveToFinished(self, true)
	end

	return true
end

return Path
