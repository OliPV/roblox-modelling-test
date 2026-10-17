-- Horse riding settings, shared by HorseServer and HorseClient. Studs, seconds, degrees.
-- Every number here was tuned by playtesting; change them freely, the animation follows the speeds.
return {
	Tag = "Horse", -- CollectionService tag on every rideable horse model

	-- the bundled horse (HorseModel): HorseServer builds one when the game starts if no tagged horse
	-- is in Workspace yet, Offset studs from the first SpawnLocation (or the origin), facing Facing
	SpawnBundledHorse = true,
	SpawnOffset = Vector3.new(0, 0, -16),
	SpawnFacing = Vector3.new(0, 0, -1),

	-- forward speeds: W walks, Ctrl switches trot on / off, holding Shift sprints into a gallop
	WalkSpeed = 9,
	TrotSpeed = 25, -- letting go of a sprint switches trot on
	FastSpeed = 50, -- sprinting speeds up quickly to here...
	MaxSpeed = 69, -- ...then slowly to here (full gallop)
	ReverseSpeed = 6, -- backing up (hold back while standing)
	Accel = 11, -- speeding up to a walk / trot: studs/s gained per second
	SprintAccel = 15, -- speeding up while sprinting, up to FastSpeed
	TopAccel = 3.8, -- speeding up while sprinting above FastSpeed
	Settle = 15, -- slowing down to a walk / trot after a sprint
	Coast = 6, -- nothing held: speed lost per second until it stands
	Brake = 27, -- holding back: speed lost per second
	LockBrake = 56, -- horse attribute Locked = true: it pulls up this fast and can't steer

	-- stamina: sprinting uses it, walking / standing gives it back fast, trotting slowly.
	-- Run dry and you can't sprint again until it is back up to Recover.
	Stamina = {
		Max = 150,
		SprintDrain = 18, -- per second (~8 s of gallop from full)
		WalkRegen = 14, -- per second while walking or standing
		TrotRegen = 5, -- per second while trotting
		Recover = 45,
	},

	-- jump: hold Space to charge (ChargeTime seconds to full), let go to jump MinHeight (a tap) up to
	-- MaxHeight studs (the bundled horse is ~4.8 tall). Only from the ground; Cooldown s after landing
	Jump = {
		ChargeTime = 2,
		MinHeight = 2,
		MaxHeight = 7,
		Cooldown = 0.3,
	},

	-- the rider's camera cancels this share of the horse's body bounce (horse and rider still bounce;
	-- the view doesn't jerk with every trot step)
	CameraSteady = 0.8,

	TurnRateStill = 175, -- degrees per second when standing / walking slowly
	TurnRateGallop = 90, -- degrees per second at FastSpeed and above

	-- drift: at MinSpeed or more, let go of the sprint (Shift or W) and steer hard. The nose swings
	-- round at TurnRate while the horse keeps sliding the way it was going (up to MaxSlip degrees off
	-- its nose), about twice as tight as a normal turn; it carries its speed, losing only
	-- Slow + Drag x sin(slip) studs/s per second. Ends when you stop steering hard, sprint again or
	-- drop below ExitSpeed.
	Drift = {
		MinSpeed = 38,
		ExitSpeed = 20,
		TurnRate = 200,
		Grip = 4.5, -- how fast the direction of travel catches up with the nose (per second)
		MaxSlip = 40,
		Slow = 5,
		Drag = 6,
		-- dust kicked up at the hooves while any horse slides: faster than DustSpeed with its travel
		-- more than DustSlip degrees off its nose
		DustSpeed = 18,
		DustSlip = 10,
		DustColor = Color3.fromRGB(176, 152, 118),
	},

	-- HUD names by speed (first entry whose limit is above the speed). The animation walks below ~11,
	-- trots to ~30 and gallops above (slow gallop = canter, full gallop above FastSpeed)
	Gaits = {
		{ 0.5, "Standing" },
		{ 11, "Walk" },
		{ 30, "Trot" },
		{ 40, "Canter" },
		{ 50, "Gallop" },
		{ math.huge, "Full gallop" },
	},

	PromptDistance = 10,

	-- hoofbeats (free Creator Store loops by Phanaerian): the trot loop while trotting, cross-fading
	-- into the gallop loop for the run; silent at a walk and in the air. Each fades in over its From
	-- range (studs/s) and plays faster / slower with the speed (1x at Speed). Id 0 = no sound
	Hoofbeats = {
		Trot = { Id = 92630369612488, Volume = 0.7, From = { 11, 17 }, Speed = 25 }, -- "Horse Trot Loopable"
		Gallop = { Id = 118636555040923, Volume = 0.8, From = { 28, 34 }, Speed = 50 }, -- "Horse Gallop Loopable"
	},

	-- R6 riding pose, read off a posed R6 rig sitting on the bundled horse. Torso: where the rider's
	-- torso sits relative to the horse's Torso piece; the rest: where each limb sits relative to the
	-- rider's torso. HorseClient sets every R6 rider's joints to reproduce it (whatever the joints'
	-- own C0 / C1). R15 riders get Roblox's sit pose (or the horse's RideAnimation attribute).
	RiderPose = {
		Torso = CFrame.new(0.3263, 2.0375, 0, 0, 0.1736, -0.9848, 0, 0.9848, 0.1736, 1, 0, 0),
		Head = CFrame.new(0, 1.5, 0, 1, 0, 0, 0, 0.9848, -0.1736, 0, 0.1736, 0.9848),
		["Left Arm"] = CFrame.new(-0.8751, -0.1645, -0.9656, 0.9848, -0.1736, 0, 0.0996, 0.5649, -0.8192, 0.1422, 0.8067, 0.5736),
		["Right Arm"] = CFrame.new(0.8835, -0.1653, -0.9669, 0.9848, 0.1736, 0, -0.0996, 0.5649, -0.8192, -0.1422, 0.8067, 0.5736),
		["Left Leg"] = CFrame.new(-0.75, -1.7645, -0.1737, 1, 0, 0, 0, 0.9659, 0.2588, 0, -0.2588, 0.9659),
		["Right Leg"] = CFrame.new(0.75, -1.7645, -0.1737, 1, 0, 0, 0, 0.9659, 0.2588, 0, -0.2588, 0.9659),
	},
}
