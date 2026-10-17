-- Horses, client side:
--   * rides the horse you sit on: forward walks, Ctrl switches trot on / off, holding Shift sprints
--     (canter -> gallop) and uses stamina; let go to slow down (into a trot: coming off a sprint
--     switches trot on), back brakes / backs up, left / right steer, hold Space to charge a jump,
--     E gets off. Stamina comes back fast while walking or standing, slowly while trotting; run it
--     dry and sprint is locked until it is back to Config.Stamina.Recover. Going fast, letting go of
--     the sprint and steering hard drifts (Config.Drift): a tighter turn that keeps the speed.
--     Gamepad: L3 sprint, Y trot, A jump, B get off; touch gets on-screen buttons. Movement input
--     comes from the seated Humanoid's MoveDirection (works with or without the PlayerModule),
--     turned back into stick input with the camera's yaw.
--   * animates every horse (legs, knees, body, neck, tail, rider) from how fast it is moving. Each
--     client animates all horses itself, so everyone sees them move.
-- Hooks other scripts can use (attributes; times are workspace:GetServerTimeNow()):
--   horse  Locked (bool)      the horse pulls up (Config.LockBrake) and can't be steered
--          SpeedCap (number)  top speed; at or below TrotSpeed no sprint / drift either
--          JoltAt, JoltPower  a hit: the body and rider rock back and away, then settle
--          Limp (0-2)         the body drops on every step (an injured horse)
--          RideAnimation      animation asset id the rider plays instead of the sit / riding pose
--          PreviewSpeed, PreviewPhase  freeze the animation at a speed and cycle phase (posing)
--   rider  RiderFreeArm ("Left Arm" / "Right Arm")  leave that arm to another script (holding a weapon)
--   shared.RiderLean[character] = CFrame  an extra turn of the rider's torso (attacks, waves)
local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage:WaitForChild("GameShared"):WaitForChild("Horse"):WaitForChild("HorseConfig"))

local player = Players.LocalPlayer
local TAU = 2 * math.pi

-- HUD while riding: gait + speed, stamina bar, keys
local STAMINA_COLOR, TIRED_COLOR = Color3.fromRGB(232, 182, 84), Color3.fromRGB(196, 78, 58)
local gui = Instance.new("ScreenGui")
gui.Name = "HorseHUD"
gui.ResetOnSpawn = false
gui.Enabled = false
local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 1)
panel.Position = UDim2.new(0.5, 0, 1, -20)
panel.Size = UDim2.fromOffset(400, 74)
panel.BackgroundTransparency = 0.4
panel.BackgroundColor3 = Color3.fromRGB(30, 24, 18)
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 8)
local function text(y, height, size, font, transparency)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Position = UDim2.fromOffset(0, y)
	t.Size = UDim2.new(1, 0, 0, height)
	t.TextColor3 = Color3.fromRGB(245, 235, 215)
	t.TextTransparency = transparency
	t.Font = font
	t.TextSize = size
	t.RichText = true
	t.Parent = panel
	return t
end
local label = text(6, 24, 20, Enum.Font.GothamBold, 0)
local bar = Instance.new("Frame")
bar.Position = UDim2.fromOffset(16, 36)
bar.Size = UDim2.new(1, -32, 0, 8)
bar.BackgroundColor3 = Color3.fromRGB(15, 12, 9)
bar.BorderSizePixel = 0
bar.Parent = panel
Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)
local fill = Instance.new("Frame")
fill.Size = UDim2.fromScale(1, 1)
fill.BackgroundColor3 = STAMINA_COLOR
fill.BorderSizePixel = 0
fill.Parent = bar
Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)
local chargeBar = Instance.new("Frame") -- jump charge, under the stamina bar while Space is held
chargeBar.Position = UDim2.fromOffset(16, 46)
chargeBar.BackgroundColor3 = Color3.fromRGB(245, 235, 215)
chargeBar.BorderSizePixel = 0
chargeBar.Visible = false
chargeBar.Parent = panel
local hint = text(51, 18, 13, Enum.Font.Gotham, 0.3)
gui.Parent = player:WaitForChild("PlayerGui")

local function gaitName(speed)
	for _, g in Config.Gaits do
		if math.abs(speed) < g[1] then
			return g[2]
		end
	end
	return ""
end

---------------------------------------------------------------------------------------------------
-- Riding
---------------------------------------------------------------------------------------------------
local riding -- { hum, horse, root, gait, heading, speed, yaw, travel, drift, charge, track }
local stamina, exhausted = Config.Stamina.Max, false -- the rider's; kept between rides
local sprintHeld, trotOn = false, false

-- gap between the bottom of a horse's Root box and the ground under it (math.huge: nothing in reach)
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function groundGap(horse, root)
	local seat = horse:FindFirstChild("Saddle")
	local rider = seat and seat.Occupant and seat.Occupant.Parent
	rayParams.FilterDescendantsInstances = if rider then { horse, rider } else { horse }
	local half = root.Size.Y / 2
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -(half + 6), 0), rayParams)
	return if hit then root.Position.Y - half - hit.Position.Y else math.huge
end

-- Shift / Ctrl / Space / E are bound only while riding, above the default jump and Shift's
-- mouse-lock toggle
local PRIORITY = Enum.ContextActionPriority.High.Value + 10
local function onJump(_, state)
	local r = riding
	if r then
		if state == Enum.UserInputState.Begin then
			r.chargeStart = os.clock()
		elseif r.chargeStart then -- let go: jump (ride() does it on the next physics step)
			r.jumpCharge = math.min(1, (os.clock() - r.chargeStart) / Config.Jump.ChargeTime)
			r.chargeStart = nil
		end
	end
	return Enum.ContextActionResult.Sink
end
local function onGetOff(_, state)
	if state == Enum.UserInputState.Begin and riding then
		-- leaves the seat; onSeated then sets the rider down beside the horse. (Humanoid.Jump = true
		-- isn't reliable: engine-side controls can reset it every frame)
		riding.hum.Sit = false
	end
	return Enum.ContextActionResult.Sink
end
local function onSprint(_, state)
	sprintHeld = state == Enum.UserInputState.Begin
	return Enum.ContextActionResult.Sink
end
local function onTrot(_, state)
	if state == Enum.UserInputState.Begin then
		trotOn = not trotOn
	end
	return Enum.ContextActionResult.Sink
end
local function bindKeys(on)
	if on then
		ContextActionService:BindActionAtPriority("HorseSprint", onSprint, true, PRIORITY,
			Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.ButtonL3)
		ContextActionService:BindActionAtPriority("HorseTrot", onTrot, true, PRIORITY,
			Enum.KeyCode.LeftControl, Enum.KeyCode.RightControl, Enum.KeyCode.ButtonY)
		ContextActionService:BindActionAtPriority("HorseJump", onJump, true, PRIORITY,
			Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
		ContextActionService:BindActionAtPriority("HorseGetOff", onGetOff, true, PRIORITY,
			Enum.KeyCode.E, Enum.KeyCode.ButtonB)
		ContextActionService:SetTitle("HorseSprint", "Gallop")
		ContextActionService:SetTitle("HorseTrot", "Trot")
		ContextActionService:SetTitle("HorseJump", "Jump")
		ContextActionService:SetTitle("HorseGetOff", "Get off")
	else
		for _, name in { "HorseSprint", "HorseTrot", "HorseJump", "HorseGetOff" } do
			ContextActionService:UnbindAction(name)
		end
	end
	sprintHeld, trotOn = false, false
end

local function stopRiding()
	if riding then
		if riding.track then
			riding.track:Stop(0.3)
		end
		riding.hum.CameraOffset = Vector3.zero
		bindKeys(false)
	end
	riding = nil
	gui.Enabled = false
end

-- put the rider down on the horse's left instead of on its back
local function getOff(hum, root)
	local char = hum.Parent
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp or hum.Health <= 0 or hum.SeatPart or not root.Parent then
		return
	end
	local floor = root.Position.Y - root.Size.Y / 2
	local side = root.CFrame * Vector3.new(-(root.Size.X / 2 + 2), 0, 0)
	char:PivotTo(CFrame.new(side.X, floor + hum.HipHeight + hrp.Size.Y / 2 + 0.2, side.Z) * root.CFrame.Rotation)
	hrp.AssemblyLinearVelocity = Vector3.zero
end

local function onSeated(hum, seatPart)
	local was = riding
	stopRiding()
	if was and not seatPart then
		task.defer(getOff, hum, was.root)
	end
	local horse = seatPart and seatPart.Name == "Saddle" and seatPart.Parent
	if not horse or not CollectionService:HasTag(horse, Config.Tag) then
		return
	end
	local root = horse:FindFirstChild("Root")
	if not root then
		return
	end
	local look = root.CFrame.LookVector
	riding = {
		hum = hum,
		horse = horse,
		root = root,
		gait = root:WaitForChild("Gait"),
		heading = root:WaitForChild("Heading"),
		speed = 0,
		yaw = math.atan2(-look.X, -look.Z),
		travel = math.atan2(-look.X, -look.Z), -- direction of travel (differs from yaw in a drift)
		drifting = false,
		drift = 0, -- 0..1, eases the drift's handling in and out
		charge = 0, -- jump charge 0..1 while Space is held
		airborneAt = 0, -- last time the horse was off the ground (jump cooldown)
	}
	local animId = horse:GetAttribute("RideAnimation")
	local animator = hum:FindFirstChildOfClass("Animator")
	if animId and animator then
		local anim = Instance.new("Animation")
		anim.AnimationId = if tonumber(animId) then "rbxassetid://" .. animId else tostring(animId)
		local ok, track = pcall(animator.LoadAnimation, animator, anim)
		if ok then
			track.Priority = Enum.AnimationPriority.Action
			track.Looped = true
			track:Play(0.3)
			riding.track = track
		end
	end
	bindKeys(true)
	gui.Enabled = true
end

local function hookCharacter(char)
	local hum = char:WaitForChild("Humanoid")
	hum.Seated:Connect(function(active, seatPart)
		onSeated(hum, active and seatPart or nil)
	end)
	onSeated(hum, hum.SeatPart)
end
if player.Character then
	task.spawn(hookCharacter, player.Character)
end
player.CharacterAdded:Connect(hookCharacter)
player.CharacterRemoving:Connect(stopRiding)

-- sprinting uses stamina; anything else gives it back (slower while moving faster than a walk)
local function updateStamina(dt, sprinting, speed)
	local S = Config.Stamina
	if sprinting then
		stamina = math.max(0, stamina - S.SprintDrain * dt)
		exhausted = exhausted or stamina == 0
	else
		local regen = if math.abs(speed) > Config.WalkSpeed + 1 then S.TrotRegen else S.WalkRegen
		stamina = math.min(S.Max, stamina + regen * dt)
		exhausted = exhausted and stamina < S.Recover
	end
end

local function ride(dt)
	local r = riding
	if not r or not r.root.Parent then
		updateStamina(dt, false, 0) -- resting on foot
		return
	end
	-- MoveDirection is the input turned to the camera's yaw: turn it back (X = right, -Z = forward)
	local look = workspace.CurrentCamera.CFrame.LookVector
	local move = CFrame.Angles(0, math.atan2(-look.X, -look.Z), 0):VectorToObjectSpace(r.hum.MoveDirection)
	-- W + A arrives as a unit diagonal (0.71 each): stretch it back out so steering doesn't cut the throttle
	local most = math.max(math.abs(move.X), math.abs(move.Z))
	if most > 1e-3 then
		move *= move.Magnitude / most
	end
	local throttle, steer = -move.Z, move.X

	-- hooks for other scripts (horse attributes): Locked pulls the horse up (LockBrake) with no
	-- steering or jumping; SpeedCap caps the speed - at a trot or below, no sprint / drift either
	local locked = r.horse:GetAttribute("Locked") == true
	if locked then
		throttle, steer = 0, 0
		r.jumpCharge, r.chargeStart = nil, nil
	end
	local cap = r.horse:GetAttribute("SpeedCap") or math.huge
	local slowed = cap <= Config.TrotSpeed
	local sprinting = sprintHeld and throttle > 0.1 and not exhausted and not slowed
	-- coming off a sprint (Shift let go, W let go or out of stamina) at speed drops into a trot
	if r.sprinting and not sprinting and r.speed > Config.TrotSpeed then
		trotOn = true
	end
	r.sprinting = sprinting

	-- drift (Config.Drift): going fast, let go of the sprint (Shift or W) and steer hard. It lasts
	-- while you keep steering hard and don't sprint again, down to ExitSpeed; meanwhile the horse
	-- carries its speed instead of settling back to a walk / trot
	local D = Config.Drift
	local hard = math.abs(steer) > 0.5 and not slowed
	if r.drifting then
		r.drifting = hard and not sprinting and r.speed >= D.ExitSpeed
	else
		r.drifting = hard and not sprinting and r.speed >= D.MinSpeed
	end

	if locked then
		r.drifting = false
		r.speed = if r.speed > 0
			then math.max(0, r.speed - Config.LockBrake * dt)
			else math.min(0, r.speed + Config.LockBrake * dt)
	elseif r.drifting then
		r.speed = math.max(0, r.speed - (D.Slow + D.Drag * math.abs(math.sin(r.yaw - r.travel))) * dt)
	elseif throttle > 0.1 then
		-- head for the gait's speed: walk, trot (Ctrl) or gallop (Shift); settle back after a sprint
		local target = throttle * (if sprinting then Config.MaxSpeed elseif trotOn then Config.TrotSpeed else Config.WalkSpeed)
		target = math.min(target, cap)
		if r.speed < target then
			local accel = if not sprinting then Config.Accel
				elseif r.speed < Config.FastSpeed then Config.SprintAccel
				else Config.TopAccel -- the slow top end
			r.speed = math.min(target, r.speed + accel * dt)
		else
			r.speed = math.max(target, r.speed - Config.Settle * dt)
		end
	elseif throttle < -0.1 then
		if r.speed > 0 then
			r.speed = math.max(0, r.speed - Config.Brake * -throttle * dt)
		else
			r.speed = math.max(-Config.ReverseSpeed, r.speed - Config.Accel * -throttle * dt)
		end
	elseif r.speed > 0 then
		r.speed = math.max(0, r.speed - Config.Coast * dt)
	else
		r.speed = math.min(0, r.speed + Config.Coast * dt)
	end
	if r.speed > cap then -- capped at speed: pulls back to what it may do
		r.speed = math.max(cap, r.speed - Config.Settle * dt)
	end

	-- steering. In a drift the nose comes round fast while the horse keeps sliding the way it was
	-- going (travel lags behind yaw): a tighter turn for a little speed
	r.drift = math.clamp(r.drift + (if r.drifting then dt / 0.2 else -dt / 0.35), 0, 1)
	local t = math.clamp(math.abs(r.speed) / Config.FastSpeed, 0, 1)
	local rate = Config.TurnRateStill + (Config.TurnRateGallop - Config.TurnRateStill) * t
	rate += (D.TurnRate - rate) * r.drift
	r.yaw -= steer * math.rad(rate) * dt
	local grip = 15 + (D.Grip - 15) * r.drift
	local slip = ((r.yaw - r.travel + math.pi) % TAU - math.pi) * math.exp(-grip * dt)
	slip = math.clamp(slip, -math.rad(D.MaxSlip), math.rad(D.MaxSlip))
	r.travel = r.yaw - slip

	-- blocked by a wall: don't keep building up speed
	local travel = CFrame.Angles(0, r.travel, 0).LookVector
	local actual = r.root.AssemblyLinearVelocity:Dot(travel)
	r.speed = math.clamp(r.speed, actual - 10, actual + 10)

	r.heading.CFrame = CFrame.Angles(0, r.yaw, 0)
	local v = travel * r.speed
	r.gait.PlaneVelocity = Vector2.new(v.X, v.Z)

	-- jump: charges while Space is held, goes when it's let go - only from the ground. The Gait only
	-- holds the horizontal speed, so an upward kick is all a jump needs; gravity brings it down.
	local J = Config.Jump
	r.charge = if r.chargeStart then math.min(1, (os.clock() - r.chargeStart) / J.ChargeTime) else 0
	local grounded = groundGap(r.horse, r.root) < 0.35
	if not grounded then
		r.airborneAt = os.clock()
	end
	if r.jumpCharge then
		if grounded and os.clock() - r.airborneAt > J.Cooldown then
			local height = J.MinHeight + (J.MaxHeight - J.MinHeight) * r.jumpCharge
			local up = math.sqrt(2 * workspace.Gravity * height)
			r.root:ApplyImpulse(Vector3.yAxis * (up - r.root.AssemblyLinearVelocity.Y) * r.root.AssemblyMass)
		end
		r.jumpCharge = nil
	end

	updateStamina(dt, sprinting, r.speed)
	label.Text = ("%s  <font transparency=\"0.4\">%d</font>%s"):format(gaitName(r.speed), math.round(math.abs(r.speed)),
		if r.drift > 0.5 then "  <i>drift</i>" else "")
	fill.Size = UDim2.fromScale(stamina / Config.Stamina.Max, 1)
	fill.BackgroundColor3 = if exhausted then TIRED_COLOR else STAMINA_COLOR
	chargeBar.Visible = r.charge > 0
	chargeBar.Size = UDim2.new((1 - 32 / 400) * r.charge, 0, 0, 3) -- (as wide as the stamina bar when full)
	hint.Text = ("Ctrl trot %s  ·  Shift gallop  ·  hold Space jump  ·  E get off"):format(
		if trotOn then "<b>on</b>" else "off"
	)
end

---------------------------------------------------------------------------------------------------
-- Animation (every horse, from its velocity)
---------------------------------------------------------------------------------------------------
-- After Richard Williams' horse walk, trot and gallop (The Animator's Survival Kit):
--   walk    4 beats: a hind, the front on the same side, then the other side, a quarter cycle apart;
--           each hoof is down ~60% of the time, the head nods twice a cycle
--   trot    diagonal pairs land together with a short float between, the body bounces twice a cycle
--   gallop  hind, hind, front, front, then all four tucked under in the air: chest up / rear down
--           as the hinds land, stretched, chest down / rear up on the fronts, compressed in the air
-- A hoof on the ground stays planted (2-bone IK with HorseServer's leg measurements) and the cycle
-- runs as fast as the horse covers its stride, so nothing slides at any speed. In the air the legs
-- fold along keyed curves (front: knee tucks the cannon back, then the forearm reaches; hind: kick
-- back, then stifle + hock fold the leg under the belly).
-- Preview a pose: set PreviewSpeed (studs/s) and PreviewPhase (0-1) attributes on a horse model.
local rad, sin, cos = math.rad, math.sin, math.cos

-- stride: studs per cycle at the gait's slowest / fastest speed; duty: share of the cycle a hoof is
-- down; crouch: how much lower than standing the body moves (a leg can't reach far while straight);
-- lift: a small arc of the hoof in the air (the knee / hock folds do the real lifting: lifting through
-- the IK bends the elbow and throws the shoulder block back); off: when each hoof
-- lands (gallop timing measured off Williams' 12 drawings)
-- (walk ~1.1 and trot ~1.5 cycles a second at their HorseConfig speeds; faster looked too busy.
-- Tuned for the default HorseConfig speeds: if you scale those a lot, scale these speed ranges with
-- them and the strides by about the square root, so the legs cycle a little faster rather than
-- reaching further than they can)
local GAITS = {
	{ speeds = { 0, 11 }, stride = { 5, 7.8 }, duty = 0.55, crouch = 0.3, lift = 0.12, fold = 0.5, tail = 8, -- walk
		off = { B_L = 0, F_L = 0.25, B_R = 0.5, F_R = 0.75 } },
	-- (trot: short reach and a long float between the diagonal pairs, so the body bounces;
	-- longer-reaching legs under a still body looked wrong)
	{ speeds = { 11, 30 }, stride = { 9, 15 }, duty = 0.32, crouch = 0.3, lift = 0.15, fold = 0.6, tail = 20, -- trot
		off = { B_L = 0, F_R = 0.02, B_R = 0.5, F_L = 0.52 } },
	{ speeds = { 31, Config.FastSpeed }, stride = { 13.4, 18.5 }, duty = 0.24, crouch = 0.35, lift = 0.15, fold = 1, tail = 40, -- gallop
		off = { B_R = 0, B_L = 0.12, F_R = 0.29, F_L = 0.38 } },
	-- full gallop (the slow top end, FastSpeed..MaxSpeed): longer, flatter strides, hooves down less
	{ speeds = { Config.FastSpeed, Config.MaxSpeed }, stride = { 18.5, 22.4 }, duty = 0.2, crouch = 0.4, lift = 0.15, fold = 1.1, tail = 50,
		off = { B_R = 0, B_L = 0.12, F_R = 0.29, F_L = 0.38 } },
}
-- body per gait at cycle phase u: heave (studs), pitch, roll, neck (degrees; + = nose / head up)
local BODY = {
	function(u)
		return -0.04 * cos(2 * TAU * (u - 0.1)), 0.6 * sin(2 * TAU * (u - 0.05)), 1.2 * sin(TAU * u), -2.5 * cos(2 * TAU * (u - 0.3))
	end,
	function(u)
		-- lowest at the middle of each diagonal's stance (0.16, 0.66), highest in the float; the nose
		-- dips as it lands, the body rolls a little toward the diagonal it stands on
		return -0.24 * cos(2 * TAU * (u - 0.16)), 1.6 * sin(2 * TAU * (u - 0.16)), 1.4 * sin(TAU * (u - 0.16)), 2 - 2 * cos(2 * TAU * (u - 0.26))
	end,
	function(u)
		return 0.2 * cos(TAU * (u - 0.8)), 6 * cos(TAU * (u + 0.08)), 0, 9 * cos(TAU * (u - 0.85)) - 10
	end,
	function(u) -- full gallop: a little flatter, neck stretched further out
		return 0.2 * cos(TAU * (u - 0.8)), 5 * cos(TAU * (u + 0.08)), 0, 8 * cos(TAU * (u - 0.85)) - 15
	end,
}
-- leg folds while in the air, at swing progress p (0 = lift-off, 1 = touch-down), degrees at a full
-- gallop (scaled by the gait's fold)
local FRONT = {
	hip = { { 0, 0 }, { 0.2, -2 }, { 0.6, 3 }, { 1, 0 } },
	j1 = { { 0, 0 }, { 0.25, 15 }, { 0.5, 40 }, { 0.68, 75 }, { 0.86, 12 }, { 1, 0 } },      -- elbow: forearm reaches
	j2 = { { 0, 0 }, { 0.2, -95 }, { 0.45, -110 }, { 0.68, -95 }, { 0.86, -10 }, { 1, 0 } }, -- knee: cannon tucks back
	j3 = { { 0, 0 }, { 0.2, -40 }, { 0.45, -45 }, { 0.68, -30 }, { 0.86, -5 }, { 1, 0 } },   -- fetlock curls
}
local HIND = {
	hip = { { 0, 0 }, { 0.15, -6 }, { 0.6, 2 }, { 1, 0 } },                                 -- kick back, then reach
	j1 = { { 0, 0 }, { 0.15, 0 }, { 0.45, -40 }, { 0.7, -30 }, { 0.9, -5 }, { 1, 0 } },      -- stifle
	j2 = { { 0, 0 }, { 0.15, -5 }, { 0.45, 55 }, { 0.7, 50 }, { 0.9, 10 }, { 1, 0 } },       -- hock: cannon under the belly
	j3 = { { 0, 0 }, { 0.15, -35 }, { 0.45, -40 }, { 0.7, -20 }, { 0.9, 0 }, { 1, 0 } },     -- fetlock flick
}
-- legs tucked in a jump (hip, joint 1, 2, 3): fronts fold at the knee, hinds swing under the belly
local TUCK_FRONT = { math.rad(25), math.rad(45), math.rad(-115), math.rad(-40) }
local TUCK_HIND = { math.rad(20), math.rad(-45), math.rad(80), math.rad(-30) }
local LEG_JOINTS = { F = { "Elbow", "Knee", "Fetlock" }, B = { "Stifle", "Hock", "Fetlock" } }
-- per-horse animation state. A plain table, cleared when a horse leaves: Roblox may collect an
-- Instance used as a weak key while the Instance still exists, which reset the horse (new seed,
-- phase 0) every few seconds - the idle "chop"
local state = {}

local function lerp(a, b, t)
	return a + (b - a) * t
end
local function smooth(x)
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end
local function lerpPhase(a, b, t) -- the short way round the cycle
	return (a + ((b - a + 0.5) % 1 - 0.5) * t) % 1
end

-- smooth curve through {p, degrees} keys (Catmull-Rom; flat at both ends)
local function curve(keys, p)
	local n = #keys
	for i = 1, n - 1 do
		local p0, p1 = keys[i][1], keys[i + 1][1]
		if p <= p1 then
			local h = p1 - p0
			local t = math.clamp((p - p0) / h, 0, 1)
			local function slope(j)
				if j <= 1 or j >= n then
					return 0
				end
				return (keys[j + 1][2] - keys[j - 1][2]) / (keys[j + 1][1] - keys[j - 1][1]) * h
			end
			local t2, t3 = t * t, t * t * t
			return (2 * t3 - 3 * t2 + 1) * keys[i][2] + (t3 - 2 * t2 + t) * slope(i)
				+ (3 * t2 - 2 * t3) * keys[i + 1][2] + (t3 - t2) * slope(i + 1)
		end
	end
	return keys[n][2]
end

-- the two gaits to mix and how much of the second: each change eases (smoothstep) over a band of speed
local BANDS = { { 9, 14 }, { 27, 34 }, { Config.FastSpeed - 4, Config.FastSpeed + 4 } } -- walk-trot, trot-gallop, gallop-full
local function gaitAt(speed)
	for i, band in BANDS do
		if speed < band[1] then
			return i, i, 0
		elseif speed < band[2] then
			return i, i + 1, smooth((speed - band[1]) / (band[2] - band[1]))
		end
	end
	return #GAITS, #GAITS, 0
end
local function strideOf(g, speed) -- studs covered per cycle
	return lerp(g.stride[1], g.stride[2], math.clamp((speed - g.speeds[1]) / (g.speeds[2] - g.speeds[1]), 0, 1))
end

-- like clamp, but eases in over the last 30% so a leg never stops dead at its limit
local function softClamp(x, limit)
	local k = 0.7 * limit
	local ax = math.abs(x)
	if ax <= k or limit <= 0 then
		return math.clamp(x, -math.max(limit, 0), math.max(limit, 0))
	end
	return math.sign(x) * (k + (limit - k) * math.tanh((ax - k) / (limit - k)))
end
-- a hoof in the air, p = 0..1: from ground/2 behind to ground/2 ahead (smoothstep), leaving and
-- landing at slope m (the planted speed) through two short terms that fade out fast - a small
-- follow-through after lift-off and a small paw-back before landing, no velocity jump, no big whip
local function swingX(ground, m, p)
	local q = 1 - p
	return ground * (smooth(p) - 0.5) + m * p * q ^ 6 - m * q * p ^ 6
end

-- leg pose with the hoof moved x studs forward (from where it stands) and lift studs above the
-- ground. Returns hip, joint 1, 2, 3 rotations (radians, from the modelled pose) and how far the
-- shoulder / hip slides along the body toward the hoof (like a scapula: a longer reach); the hoof
-- stays level.
local SLIDE = 0.35
local function pose(leg, x, lift, heave, pitch)
	local slide = math.clamp(x * 0.2, -SLIDE, SLIDE)
	x += leg.fetX - slide
	local y = lift + leg.fetY - (leg.height + heave + leg.fwd * sin(pitch))
	local a, b = leg.a, leg.b
	-- beyond what the straight leg reaches the hoof slides a little rather than leave the ground
	x = softClamp(x, math.sqrt(math.max(0, (0.985 * (a + b)) ^ 2 - y * y)))
	local d = math.clamp(math.sqrt(x * x + y * y), math.abs(a - b) + 0.01, a + b - 0.001)
	local phi = math.acos(math.clamp((d * d - a * a - b * b) / (2 * a * b), -1, 1)) * leg.sign
	local upper = math.atan2(x, -y) - math.atan2(b * sin(phi), a + b * cos(phi))
	local hip, bend = upper - leg.upper0 - pitch, phi - leg.bend0
	local j1 = leg.ik == 1 and bend or 0
	local j2 = leg.ik == 2 and bend or 0
	return hip, j1, j2, -(pitch + hip + j1 + j2), slide
end

local function setup(horse, root)
	local legs = {}
	for _, key in { "F_L", "F_R", "B_L", "B_R" } do
		local hip = root:FindFirstChild("Hip_" .. key)
		local j = {}
		for i, name in LEG_JOINTS[key:sub(1, 1)] do
			j[i] = root:FindFirstChild(name .. "_" .. key)
		end
		if not (hip and j[1] and j[2] and j[3] and hip:GetAttribute("A")) then
			return nil -- not streamed in / rigged yet
		end
		local bend0 = hip:GetAttribute("Bend0")
		legs[key] = {
			key = key, hip = hip, j1 = j[1], j2 = j[2], j3 = j[3], front = key:sub(1, 1) == "F",
			ik = hip:GetAttribute("IkJoint"), a = hip:GetAttribute("A"), b = hip:GetAttribute("B"),
			upper0 = hip:GetAttribute("Upper0"), bend0 = bend0, sign = bend0 < -0.02 and -1 or 1,
			height = hip:GetAttribute("Height"), fwd = hip:GetAttribute("Fwd"),
			fetX = hip:GetAttribute("FetX"), fetY = hip:GetAttribute("FetY"),
		}
	end
	local body, seat = root:FindFirstChild("Body"), horse:FindFirstChild("Saddle")
	local st = {
		legs = legs, u = 0, v = 0, yaw = 0, w = 0, heave = 0, tail = 0, tailVel = 0, lean = 0, turnHead = 0,
		charge = 0, air = 0, wasAirborne = false, landT = 1, seatDy = 0,
		seed = math.random() * 100,
		body = body, neck = root:FindFirstChild("Neck"), seat = seat,
		head = root:FindFirstChild("Head"), tailM = root:FindFirstChild("Tail"),
		-- the saddle in the body joint's frame (rider = saddle; read before the first pose)
		seatAt = if body and seat then (root.CFrame * body.C0):PointToObjectSpace(seat.Position) else Vector3.zero,
	}
	state[horse] = st
	return st
end

-- R6 rider pose: a posed rig, exactly (Config.RiderPose). Each joint's Transform is worked out so
-- its limb lands where it sat on the rig (whatever the joint's own C0 / C1), and the torso where it
-- sat on the horse. Set at render time and again after the Animator has run (PreSimulation: it
-- resets every joint of a rig it animates), so it wins over the default sit. The arm named by the
-- rider's RiderFreeArm attribute is left alone (another script holds something with it); another
-- script can lean / twist the body through shared.RiderLean[character] (a rotation in torso space;
-- the one used is left in shared.RiderLeanApplied so it can line things up with it).
local riderJoints = {}
local function setJoint(motor, t)
	if motor and motor.Enabled then
		motor.Transform = t
		riderJoints[motor] = t
	end
end
RunService.PreSimulation:Connect(function()
	for motor, t in riderJoints do
		motor.Transform = t
	end
end)
-- the Transform that puts the joint's Part1 at `rel` (in Part0's space): Part1 = Part0 * C0 * T * C1^-1
local function reachFor(motor, rel)
	return motor.C0:Inverse() * rel * motor.C1
end
local LIMB_JOINT = { Head = "Neck", ["Left Arm"] = "Left Shoulder", ["Right Arm"] = "Right Shoulder",
	["Left Leg"] = "Left Hip", ["Right Leg"] = "Right Hip" }
shared.RiderLean = shared.RiderLean or {}
shared.RiderLeanApplied = shared.RiderLeanApplied or {}
local function poseRider(char, st)
	local torso = char.Torso
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local rootJoint = hrp and hrp:FindFirstChild("RootJoint")
	local horseTorso = st.body and st.body.Part1
	if not rootJoint or not horseTorso then
		return
	end
	local lean = shared.RiderLean[char] or CFrame.identity
	shared.RiderLeanApplied[char] = lean
	-- (the saddle is welded to the horse's torso, so this holds however the horse moves)
	setJoint(rootJoint, reachFor(rootJoint, hrp.CFrame:ToObjectSpace(horseTorso.CFrame * Config.RiderPose.Torso * lean)))
	local freeArm = char:GetAttribute("RiderFreeArm")
	for limb, jointName in LIMB_JOINT do
		if limb ~= freeArm then
			local j = torso:FindFirstChild(jointName)
			if j and j.Part1 then
				setJoint(j, reachFor(j, Config.RiderPose[limb]))
			end
		end
	end
end

local function animate(horse, dt, now)
	local root = horse:FindFirstChild("Root")
	local st = root and (state[horse] or setup(horse, root))
	if not st then
		return
	end
	-- forward speed (turning on the spot counts as walking)
	-- every input eases toward its new value (exponential, frame-rate independent), so speeding up,
	-- slowing down, turning and stopping all blend in instead of snapping
	local preview = horse:GetAttribute("PreviewSpeed")
	local function ease(rate)
		return if preview then 1 else 1 - math.exp(-rate * dt)
	end
	local v = preview or root.AssemblyLinearVelocity:Dot(root.CFrame.LookVector)
	st.v += (v - st.v) * ease(6)
	st.yaw += ((preview and 0 or root.AssemblyAngularVelocity.Y) - st.yaw) * ease(5)
	local speed = math.max(math.abs(st.v), math.abs(st.yaw) * 2.5)
	st.w += (smooth(speed / 1.5) - st.w) * ease(4)
	local w, idle = smooth(st.w), 1 - smooth(st.w)

	local i, j, t = gaitAt(speed)
	local ga, gb = GAITS[i], GAITS[j]
	local stride = lerp(strideOf(ga, speed), strideOf(gb, speed), t)
	local duty, fold, lift = lerp(ga.duty, gb.duty, t), lerp(ga.fold, gb.fold, t), lerp(ga.lift, gb.lift, t)
	st.u = horse:GetAttribute("PreviewPhase") or (st.u + (st.v < -0.2 and -1 or 1) * speed / stride * dt) % 1
	local u = st.u

	local h1, p1, r1, n1 = BODY[i](u)
	local h2, p2, r2, n2 = BODY[j](u)
	local heave = (lerp(h1, h2, t) - lerp(ga.crouch, gb.crouch, t)) * w
	local pitch = rad(lerp(p1, p2, t)) * w
	-- lean into turns (eased in and out)
	st.lean += (rad(math.clamp(math.deg(st.yaw) * st.v * 0.0025, -9, 9)) - st.lean) * ease(4)
	local roll = rad(lerp(r1, r2, t)) * w + st.lean
	local neck = rad(lerp(n1, n2, t)) * w

	-- jump: your own horse crouches (haunches down) while the jump charges; any horse off the ground
	-- tucks its legs and tips up on the climb / down on the fall, and gives a little as it lands
	local charge = if riding and riding.horse == horse then riding.charge or 0 else 0
	st.charge += (charge - st.charge) * ease(10)
	local airborne = not preview and groundGap(horse, root) > 0.3
	st.air += ((if airborne then 1 else 0) - st.air) * ease(if airborne then 10 else 18)
	if st.wasAirborne and not airborne then
		st.landT = 0
	end
	st.wasAirborne = airborne
	st.landT += dt
	local land = if st.landT < 0.35 then sin(math.pi * st.landT / 0.35) else 0
	local air = smooth(st.air)
	local climb = math.clamp(root.AssemblyLinearVelocity.Y / 40, -1, 1) * air
	heave += -0.35 * st.charge - 0.25 * land
	pitch += rad(4) * st.charge + rad(12) * climb
	neck += -rad(6) * climb

	-- struck (another script sets JoltAt = server time, JoltPower ~0.3-1.5): the body and rider rock
	-- back and to the side, then settle
	local joltAt = horse:GetAttribute("JoltAt")
	if joltAt then
		local jt = workspace:GetServerTimeNow() - joltAt
		if jt >= 0 and jt < 0.7 then
			local k = sin(math.pi * math.min(jt / 0.12, 1) * 0.5) * math.exp(-jt * 6) * (horse:GetAttribute("JoltPower") or 1)
			pitch += rad(14) * k
			roll -= rad(10) * k
			neck += rad(10) * k
		end
	end

	-- limping (attribute Limp, 0-2): the body drops each time weight comes onto the bad leg
	local limp = horse:GetAttribute("Limp") or 0
	if limp > 0 then
		heave -= 0.12 * math.min(limp, 2) * math.abs(sin(TAU * u)) * w
	end

	-- legs
	local ground = stride * duty -- how far the body travels over a planted hoof
	for key, leg in st.legs do
		local lu = (u - lerpPhase(ga.off[key], gb.off[key], t)) % 1
		local hip, j1, j2, j3, slide
		if lu < duty then -- planted: the body moves over the hoof
			hip, j1, j2, j3, slide = pose(leg, ground * (0.5 - lu / duty), 0, heave, pitch)
		else -- in the air: an arc from behind to ahead of the hip, plus the keyed folds
			local p = (lu - duty) / (1 - duty)
			local keys = leg.front and FRONT or HIND
			-- leave and meet the ground at the planted speed and rise / settle from zero (sin^2), so
			-- nothing jumps at lift-off or landing: the hoof follows through after push-off and paws
			-- back before it lands
			local x = swingX(ground, -ground * (1 - duty) / duty, p)
			hip, j1, j2, j3, slide = pose(leg, x, lift * sin(math.pi * p) ^ 2, heave, pitch)
			hip += rad(curve(keys.hip, p)) * fold
			j1 += rad(curve(keys.j1, p)) * fold
			j2 += rad(curve(keys.j2, p)) * fold
			j3 += rad(curve(keys.j3, p)) * fold
		end
		-- standing still: hooves stay where they stand and the legs give with the body (crouch,
		-- landing); moving blends into the gait
		local sh, s1, s2, s3, ss = pose(leg, 0, 0, heave, pitch)
		hip, j1, j2, j3, slide = lerp(sh, hip, w), lerp(s1, j1, w), lerp(s2, j2, w), lerp(s3, j3, w), lerp(ss, slide, w)
		if air > 0 then -- off the ground: legs tucked
			local tuck = if leg.front then TUCK_FRONT else TUCK_HIND
			hip, j1, j2, j3 = lerp(hip, tuck[1], air), lerp(j1, tuck[2], air), lerp(j2, tuck[3], air), lerp(j3, tuck[4], air)
		end
		-- (a leg whose Motor6Ds another script disables - a ragdolled leg - ignores these)
		leg.hip.Transform = CFrame.new(0, 0, -slide) * CFrame.Angles(hip, 0, 0)
		leg.j1.Transform = CFrame.Angles(j1, 0, 0)
		leg.j2.Transform = CFrame.Angles(j2, 0, 0)
		leg.j3.Transform = CFrame.Angles(j3, 0, 0)
	end

	-- body, neck, head
	local breathe = 0.03 * sin(now * 1.6 + st.seed) * idle
	if st.body then
		local bodyCF = CFrame.new(0, heave + breathe, 0) * CFrame.Angles(pitch, 0, roll)
		st.body.Transform = bodyCF
		st.seatDy = (bodyCF * st.seatAt).Y - st.seatAt.Y -- how far the body lifts the rider (camera steadying)
	end
	local look = (rad(5) * sin(now * 0.4 + st.seed) + rad(2) * sin(now * 1.1 + st.seed * 2)) * idle
	st.turnHead += (math.clamp(st.yaw * 0.12, -0.25, 0.25) - st.turnHead) * ease(3) -- looks into the turn
	local turnHead = st.turnHead + rad(8) * sin(now * 0.23 + st.seed) * idle
	if st.neck then
		st.neck.Transform = CFrame.Angles(neck + look, turnHead, 0)
	end
	if st.head then
		st.head.Transform = CFrame.Angles(-0.6 * neck + rad(4) * sin(now * 0.7 + st.seed) * idle, 0, 0)
	end

	-- tail: lifts with speed, lags behind the bounce (spring), swishes now and then when standing
	if st.tailM then
		local heaveVel = (heave - st.heave) / math.max(dt, 1e-3)
		st.heave = heave
		local target = -rad(lerp(ga.tail, gb.tail, t)) * w - math.clamp(heaveVel, -3, 3) * 0.15
		st.tailVel += ((target - st.tail) * 60 - st.tailVel * 10) * math.min(dt, 0.05)
		st.tail += st.tailVel * math.min(dt, 0.05)
		local swish = rad(18) * sin(now * 4.5) * math.max(0, sin(now * 0.5 + st.seed)) ^ 4 * idle
			+ rad(5) * sin(TAU * u) * w
		st.tailM.Transform = CFrame.Angles(st.tail, swish, 0)
	end

	-- hoofbeats (Config.Hoofbeats): the trot loop while trotting, cross-fading into the gallop loop
	-- for the run; faster / slower with the speed; silent standing, walking or in the air
	local H = Config.Hoofbeats
	if not st.hooves then
		st.hooves = {}
		for name, cfg in H do
			local s = Instance.new("Sound")
			s.Name = "Hooves" .. name
			s.SoundId = "rbxassetid://" .. cfg.Id
			s.Looped = true
			s.Volume = 0
			s.RollOffMinDistance, s.RollOffMaxDistance = 8, 160
			s.Parent = root
			st.hooves[name] = s
		end
	end
	local gv = math.abs(st.v)
	local gallop = smooth((gv - H.Gallop.From[1]) / (H.Gallop.From[2] - H.Gallop.From[1]))
	local loud = {
		Trot = smooth((gv - H.Trot.From[1]) / (H.Trot.From[2] - H.Trot.From[1])) * (1 - gallop),
		Gallop = gallop,
	}
	for name, s in st.hooves do
		local k = loud[name] * (1 - air)
		s.Volume = H[name].Volume * k
		s.PlaybackSpeed = math.clamp(gv / H[name].Speed, 0.7, 1.4)
		if k > 0.01 and not s.IsPlaying then
			s:Play()
		elseif k <= 0.01 and s.IsPlaying then
			s:Pause()
		end
	end

	-- dust at the hooves while the horse slides (a drift: moving fast with its travel well off its
	-- nose) - every horse, so everyone sees everyone's drifts
	local D = Config.Drift
	local fv = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z)
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	local slide = 0
	if fv.Magnitude > D.DustSpeed and look.Magnitude > 0.1 then
		local slip = math.deg(math.acos(math.clamp(fv.Unit:Dot(look.Unit), -1, 1)))
		slide = math.clamp((slip - D.DustSlip) / 15, 0, 1) * math.clamp((fv.Magnitude - D.DustSpeed) / 10, 0, 1) * (1 - air)
	end
	if slide > 0 and not st.dust then
		st.dust = {}
		for _, leg in st.legs do
			local hoof = leg.j3.Part1
			if hoof then
				local e = Instance.new("ParticleEmitter")
				e.Name = "DriftDust"
				e.Texture = "rbxasset://textures/particles/smoke_main.dds"
				e.Color = ColorSequence.new(D.DustColor)
				e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 2.6) })
				e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
				e.Lifetime = NumberRange.new(0.6, 1.1)
				e.Speed = NumberRange.new(1.5, 4)
				e.SpreadAngle = Vector2.new(70, 70)
				e.Rotation = NumberRange.new(0, 360)
				e.RotSpeed = NumberRange.new(-40, 40)
				e.Acceleration = Vector3.new(0, 1.5, 0)
				e.Drag = 2
				e.EmissionDirection = Enum.NormalId.Top
				e.Rate = 0
				e.Parent = hoof
				table.insert(st.dust, e)
			end
		end
	end
	if st.dust then
		for _, e in st.dust do
			e.Rate = 35 * slide
		end
	end

	-- the rider (R6 only; R15 keeps Roblox's sit pose): the posed rig (poseRider), unless the horse
	-- has a RideAnimation for it
	local occupant = st.seat and st.seat.Occupant
	local char = occupant and occupant.Parent
	if char and char:FindFirstChild("Torso") and not horse:GetAttribute("RideAnimation") then
		poseRider(char, st)
	end
end

-- riding drives physics constraints: before each simulation step
RunService.PreSimulation:Connect(ride)
-- animation runs on render time: the simulation step comes in uneven chunks (12.5 / 16.7 / 20.8 ms)
-- and stepping the legs by it made them stutter against the steady frame rate. A render step at
-- Character priority, so a script that poses a held item from the rider's torso can bind after it
-- (Character + 1) and find the rider already posed
RunService:BindToRenderStep("HorseAnimate", Enum.RenderPriority.Character.Value, function(dt)
	local now = os.clock()
	table.clear(riderJoints)
	for _, horse in CollectionService:GetTagged(Config.Tag) do
		animate(horse, dt, now)
	end
	-- the rider's camera follows the rider, who sits on the bouncing body: cancel most of the bounce
	local st = riding and state[riding.horse]
	if st then
		riding.hum.CameraOffset = Vector3.new(0, -st.seatDy * Config.CameraSteady, 0)
	end
end)
CollectionService:GetInstanceRemovedSignal(Config.Tag):Connect(function(horse)
	state[horse] = nil
end)
