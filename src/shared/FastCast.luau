--[[
	FastCast.luau  (shared ModuleScript)
	Minimal projectile physics module — API-compatible with FastCastRedux.

	Implements:
	  FastCast.new()          → Caster (with LengthChanged, RayHit, CastTerminating signals)
	  FastCast.newBehavior()  → FastCastBehavior config table
	  caster:Fire(origin, direction, velocity, behavior) → ActiveCast
	  ActiveCast.UserData     → { [string]: any }  (set per-shot data after Fire)
	  ActiveCast:Terminate()  → immediately ends the cast

	Event order on hit:     LengthChanged → RayHit → CastTerminating
	Event order on miss:    LengthChanged (each step) → CastTerminating
]]

local RunService = game:GetService("RunService")

-- ── Simple Signal ──────────────────────────────────────────────────────────

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _fns = {} }, Signal)
end

function Signal:Connect(fn)
	local fns = self._fns
	table.insert(fns, fn)
	return {
		Disconnect = function()
			local i = table.find(fns, fn)
			if i then table.remove(fns, i) end
		end,
	}
end

function Signal:Fire(...)
	for _, fn in self._fns do
		task.spawn(fn, ...)
	end
end

-- ── ActiveCast ─────────────────────────────────────────────────────────────

local ActiveCast = {}
ActiveCast.__index = ActiveCast

function ActiveCast.new(caster, origin, direction, speed, behavior)
	local self     = setmetatable({}, ActiveCast)
	self._caster   = caster
	self._origin   = origin
	self._vel      = direction.Unit * speed  -- initial velocity vector
	self._behavior = behavior
	self._elapsed  = 0
	self._distTraveled = 0
	self._lastPos  = origin
	self._terminated = false
	self.UserData  = { hitDetected = false }

	-- Clone cosmetic bullet if a template is provided
	local cosmeticPart = nil
	if behavior.CosmeticBulletTemplate then
		cosmeticPart           = behavior.CosmeticBulletTemplate:Clone()
		cosmeticPart.CFrame    = CFrame.new(origin, origin + direction)
		cosmeticPart.Parent    = behavior.CosmeticBulletContainer or workspace.Terrain
	end
	self._cosmeticPart = cosmeticPart

	-- Simulate each Heartbeat
	self._conn = RunService.Heartbeat:Connect(function(dt)
		if not self._terminated then self:_step(dt) end
	end)

	return self
end

function ActiveCast:_step(dt)
	self._elapsed += dt

	local accel  = self._behavior.Acceleration
	local newPos = self._origin
		+ self._vel * self._elapsed
		+ accel * (self._elapsed * self._elapsed * 0.5)

	local diff = newPos - self._lastPos
	local dist = diff.Magnitude
	if dist < 0.001 then return end

	local currentVel = self._vel + accel * self._elapsed
	local rayParams  = self._behavior.RaycastParams
	local result     = workspace:Raycast(self._lastPos, diff, rayParams)

	if result then
		-- ── Hit ──
		self.UserData.hitDetected = true

		local snap = self._cosmeticPart
		self._caster.LengthChanged:Fire(self, self._lastPos, diff.Unit, dist, currentVel, snap)

		-- Clean up cosmetic before notifying listeners
		if self._cosmeticPart then
			self._cosmeticPart:Destroy()
			self._cosmeticPart = nil
		end

		-- Terminate (disconnect heartbeat FIRST, then fire events)
		self._terminated = true
		if self._conn then self._conn:Disconnect(); self._conn = nil end

		-- RayHit → CastTerminating
		self._caster.RayHit:Fire(self, result, currentVel, nil)
		self._caster.CastTerminating:Fire(self)
		return
	end

	-- ── Still in flight ──
	self._distTraveled += dist
	self._caster.LengthChanged:Fire(self, self._lastPos, diff.Unit, dist, currentVel, self._cosmeticPart)

	if self._distTraveled >= (self._behavior.MaxDistance or 1000) then
		-- Max distance: miss
		if self._cosmeticPart then
			self._cosmeticPart:Destroy()
			self._cosmeticPart = nil
		end
		self._terminated = true
		if self._conn then self._conn:Disconnect(); self._conn = nil end
		self._caster.CastTerminating:Fire(self)
		return
	end

	self._lastPos = newPos
end

function ActiveCast:Terminate()
	if self._terminated then return end
	self._terminated = true
	if self._conn then self._conn:Disconnect(); self._conn = nil end
	if self._cosmeticPart then self._cosmeticPart:Destroy(); self._cosmeticPart = nil end
	self._caster.CastTerminating:Fire(self)
end

-- ── FastCast (Caster factory) ──────────────────────────────────────────────

local FastCast = {}
FastCast.__index      = FastCast
FastCast.DebugLogging = false
FastCast.VisualizeCasts = false

function FastCast.new()
	return setmetatable({
		LengthChanged   = Signal.new(),
		RayHit          = Signal.new(),
		RayPierced      = Signal.new(),
		CastTerminating = Signal.new(),
		WorldRoot       = workspace,
	}, FastCast)
end

function FastCast.newBehavior()
	return {
		RaycastParams           = nil,
		Acceleration            = Vector3.new(0, -workspace.Gravity * 0.05, 0),
		MaxDistance             = 1000,
		CanPierceFunction       = nil,
		CosmeticBulletTemplate  = nil,
		CosmeticBulletContainer = nil,
	}
end

--[[
	origin    : Vector3  — ray origin (e.g. camera position)
	direction : Vector3  — unit direction of travel
	velocity  : number | Vector3 — speed in studs/s, or initial velocity vector
	behavior  : FastCastBehavior table from newBehavior()

	Returns an ActiveCast. Set .UserData fields immediately after calling Fire.
]]
function FastCast:Fire(origin, direction, velocity, behavior)
	local speed = if typeof(velocity) == "Vector3"
		then (velocity :: Vector3).Magnitude
		else velocity :: number

	return ActiveCast.new(self, origin, direction, speed, behavior or FastCast.newBehavior())
end

return FastCast
