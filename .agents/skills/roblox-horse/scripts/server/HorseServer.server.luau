-- Makes every model tagged "Horse" rideable when the game starts (and any tagged later). The model
-- itself is not changed in Studio; everything here is built at run time:
--   Root      invisible box that carries the physics (the visible pieces become massless, no-collide)
--   Gait      LinearVelocity  } set by the rider's client (it owns the horse's physics while riding)
--   Heading   AlignOrientation}
--   Body / Neck / Head / Tail, and per leg Hip + Elbow/Knee/Fetlock (front) or Stifle/Hock/Fetlock
--             (hind): Motor6Ds that HorseClient animates. Each Hip carries the leg's measurements
--             (attributes) that HorseClient needs to keep a hoof planted on the ground.
--   Saddle    Seat the rider sits on (only through the "Ride" prompt, never by touching it)
-- Expected pieces: Torso, Neck, Head (parts or models), Tail, and legs named
-- "<F|B>-<Top|Middle|Bottom|Hoof>-Leg-<L|R>"; anything else is welded on. If no tagged horse is in
-- Workspace, the bundled one (HorseModel) is built near the spawn (HorseConfig.SpawnBundledHorse).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HorseShared = ReplicatedStorage:WaitForChild("GameShared"):WaitForChild("Horse")
local Config = require(HorseShared:WaitForChild("HorseConfig"))
local HorseModel = require(HorseShared:WaitForChild("HorseModel"))

local SEGMENTS = { "Top", "Middle", "Bottom", "Hoof" }
local JOINTS = { F = { "Elbow", "Knee", "Fetlock" }, B = { "Stifle", "Hock", "Fetlock" } } -- between the segments
local CORNERS = {}
for _, x in { -1, 1 } do
	for _, y in { -1, 1 } do
		for _, z in { -1, 1 } do
			table.insert(CORNERS, Vector3.new(x, y, z) / 2)
		end
	end
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z).Unit
end

-- a piece may be a part or a model of parts: use its biggest part
local function mainPart(inst)
	if not inst or inst:IsA("BasePart") then
		return inst
	end
	local best, vol = nil, -1
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") and d.Size.X * d.Size.Y * d.Size.Z > vol then
			best, vol = d, d.Size.X * d.Size.Y * d.Size.Z
		end
	end
	return best
end

-- min / max corner of the parts, in `frame`'s space
local function extents(parts, frame)
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, p in parts do
		for _, c in CORNERS do
			local q = frame:PointToObjectSpace(p.CFrame:PointToWorldSpace(c * p.Size))
			lo, hi = lo:Min(q), hi:Max(q)
		end
	end
	return lo, hi
end

-- the end of the part's longest axis that is nearer `target` (where a joint goes)
local function endNear(part, target)
	local s = part.Size
	local axis = (s.X >= s.Y and s.X >= s.Z) and Vector3.xAxis or (s.Y >= s.Z and Vector3.yAxis or Vector3.zAxis)
	local half = axis * (axis:Dot(s) / 2)
	local a, b = part.CFrame:PointToWorldSpace(half), part.CFrame:PointToWorldSpace(-half)
	return if (a - target).Magnitude < (b - target).Magnitude then a else b
end

local function rig(horse)
	if not horse:IsA("Model") or horse:FindFirstChild("Root") or not horse:IsDescendantOf(workspace) then
		return
	end
	local torso = mainPart(horse:FindFirstChild("Torso"))
	local neckPart = mainPart(horse:FindFirstChild("Neck"))
	local tail = mainPart(horse:FindFirstChild("Tail"))
	if not torso or not neckPart then
		warn("HorseServer: " .. horse:GetFullName() .. " needs a Torso and a Neck")
		return
	end
	local fwd = flat(neckPart.Position - torso.Position)
	local rot = CFrame.lookAt(Vector3.zero, fwd) -- -Z = forward, X = the horse's right side
	local frame = rot + torso.Position
	local function at(pos)
		return CFrame.new(pos) * rot
	end

	local all, legs = {}, {}
	for _, p in horse:GetDescendants() do
		if p:IsA("BasePart") then
			table.insert(all, p)
			local fb, seg, lr = p.Name:match("^([FB])%-(%a+)%-Leg%-([LR])$")
			if fb and table.find(SEGMENTS, seg) then
				legs[fb .. "_" .. lr] = legs[fb .. "_" .. lr] or {}
				legs[fb .. "_" .. lr][table.find(SEGMENTS, seg)] = p
			end
		end
	end
	local allLo, allHi = extents(all, frame)
	local tLo, tHi = extents({ torso }, frame)

	-- Root: as long as the torso, as wide as the horse, from the hooves to the back
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(math.max(allHi.X - allLo.X, 2), tHi.Y - allLo.Y, tHi.Z - tLo.Z)
	root.CFrame = frame * CFrame.new((tLo.X + tHi.X) / 2, (allLo.Y + tHi.Y) / 2, (tLo.Z + tHi.Z) / 2)
	root.Transparency = 1
	root.Anchored = true
	root.CanTouch = false
	root.RootPriority = 127
	root.CustomPhysicalProperties = PhysicalProperties.new(1, 0, 0, 100, 100) -- no friction: the Gait drives it
	root.Parent = horse
	horse.PrimaryPart = root

	local done = { [torso] = true, [neckPart] = true }
	local function motor(name, part0, part1, cf)
		local m = Instance.new("Motor6D")
		m.Name = name
		m.Part0, m.Part1 = part0, part1
		m.C0, m.C1 = part0.CFrame:ToObjectSpace(cf), part1.CFrame:ToObjectSpace(cf)
		m.Parent = root
		done[part1] = true
		return m
	end
	local function weld(to, p)
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = to, p
		w.Parent = p
		done[p] = true
	end

	local head, neck = horse:FindFirstChild("Head"), horse:FindFirstChild("Neck")
	local headPart = mainPart(head)
	motor("Body", root, torso, at(torso.Position))
	motor("Neck", torso, neckPart, at(endNear(neckPart, torso.Position)))
	if headPart and headPart ~= neckPart then
		motor("Head", neckPart, headPart, at(endNear(headPart, neckPart.Position)))
	end
	if tail then
		motor("Tail", torso, tail, at(endNear(tail, torso.Position)))
	end

	-- side-plane coordinates (forward, up) relative to the torso centre; angles from straight down, + = forward
	local function side(p)
		local q = frame:PointToObjectSpace(p)
		return Vector2.new(-q.Z, q.Y)
	end
	local function down(v)
		return math.atan2(v.X, -v.Y)
	end
	for key, seg in legs do
		local fb = key:sub(1, 1)
		if seg[1] and seg[2] and seg[3] and seg[4] then
			-- hip: a third of the way down the top piece (the big shoulder / haunch block then turns
			-- inside the body instead of swinging out); a joint: the middle of where two pieces overlap
			-- (the hoof is wider than tall, so the fetlock is the cannon's lower end)
			local above = seg[1].Position + Vector3.yAxis * 100
			local points = { endNear(seg[1], above):Lerp(seg[1].Position, 0.6) }
			local hip = motor("Hip_" .. key, torso, seg[1], at(points[1]))
			for i = 2, 4 do
				local parent, child = seg[i - 1], seg[i]
				points[i] = if i == 4
					then endNear(parent, child.Position)
					else endNear(parent, child.Position):Lerp(endNear(child, parent.Position), 0.5)
				motor(JOINTS[fb][i - 1] .. "_" .. key, parent, child, at(points[i]))
			end
			-- measurements for planting the hoof: a 2-bone leg from the hip to the joint that gives
			-- (front: elbow, hind: hock) and from there to the fetlock; the hoof below the fetlock is
			-- kept level, so the fetlock sits at a fixed height over a planted hoof
			local ik = fb == "F" and 1 or 2
			local h, k, f = side(points[1]), side(points[ik + 1]), side(points[4])
			local upper, lower = k - h, f - k
			hip:SetAttribute("IkJoint", ik)
			hip:SetAttribute("A", upper.Magnitude)
			hip:SetAttribute("B", lower.Magnitude)
			hip:SetAttribute("Upper0", down(upper))
			hip:SetAttribute("Bend0", down(lower) - down(upper))
			hip:SetAttribute("Height", h.Y - allLo.Y) -- hip over the ground
			hip:SetAttribute("Fwd", h.X) -- hip ahead of the body's pivot
			hip:SetAttribute("FetX", f.X - h.X) -- fetlock ahead of the hip
			hip:SetAttribute("FetY", f.Y - allLo.Y) -- fetlock over the ground
		else
			warn("HorseServer: leg " .. key .. " of " .. horse.Name .. " is missing a segment; welded stiff")
		end
	end
	for _, p in all do
		if not done[p] then
			local to = torso
			if headPart and head and p:IsDescendantOf(head) then
				to = headPart
			elseif neck and p:IsDescendantOf(neck) or head and p:IsDescendantOf(head) then
				to = neckPart
			end
			weld(to, p)
		end
	end

	-- saddle on the middle of the back, facing forward
	local seat = Instance.new("Seat")
	seat.Name = "Saddle"
	seat.Size = Vector3.new(math.max(tHi.X - tLo.X, 1), 0.2, 2)
	seat.CFrame = frame * CFrame.new((tLo.X + tHi.X) / 2, tHi.Y + 0.1, (tLo.Z + tHi.Z) / 2 - 0.3)
	seat.Transparency = 1
	seat.CanCollide = false
	seat.CanTouch = false -- nobody sits by bumping into it; the prompt seats you
	seat.Parent = horse
	weld(torso, seat)

	local att = Instance.new("Attachment")
	att.Name = "RootAttachment"
	att.Parent = root
	local gait = Instance.new("LinearVelocity")
	gait.Name = "Gait"
	gait.Attachment0 = att
	gait.RelativeTo = Enum.ActuatorRelativeTo.World
	gait.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	gait.PrimaryTangentAxis = Vector3.xAxis
	gait.SecondaryTangentAxis = Vector3.zAxis
	gait.PlaneVelocity = Vector2.zero
	gait.MaxForce = 1e6
	gait.Parent = root
	local heading = Instance.new("AlignOrientation")
	heading.Name = "Heading"
	heading.Mode = Enum.OrientationAlignmentMode.OneAttachment
	heading.Attachment0 = att
	heading.CFrame = rot
	heading.MaxTorque = 1e7
	heading.Responsiveness = 40
	heading.Parent = root

	for _, p in all do
		p.Anchored = false
		p.CanCollide = false
		p.CanTouch = false
		p.Massless = true
	end
	seat.Massless = true
	root.Anchored = false
	pcall(function()
		horse.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Ride"
	prompt.ObjectText = horse.Name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = Config.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = root

	prompt.Triggered:Connect(function(player)
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 and not seat.Occupant and not hum.SeatPart then
			seat:Sit(hum)
		end
	end)

	-- (HorseClient sets the rider down beside the horse when they get off)
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local hum = seat.Occupant
		if hum then
			prompt.Enabled = false
			local player = Players:GetPlayerFromCharacter(hum.Parent)
			if player then
				pcall(root.SetNetworkOwner, root, player)
			end
			return
		end
		-- got off: stand still facing the same way, the server takes the physics back
		prompt.Enabled = true
		gait.PlaneVelocity = Vector2.zero
		heading.CFrame = CFrame.lookAt(Vector3.zero, flat(root.CFrame.LookVector))
		pcall(root.SetNetworkOwner, root, nil)
	end)
end

for _, horse in CollectionService:GetTagged(Config.Tag) do
	task.spawn(rig, horse)
end
CollectionService:GetInstanceAddedSignal(Config.Tag):Connect(rig)

-- no horse placed in the world: build the bundled one by the spawn (it is tagged, so it rigs itself)
if Config.SpawnBundledHorse then
	local placed = false
	for _, horse in CollectionService:GetTagged(Config.Tag) do
		placed = placed or horse:IsDescendantOf(workspace)
	end
	if not placed then
		local spawnPoint = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
		local base = if spawnPoint then spawnPoint.Position + Vector3.yAxis * spawnPoint.Size.Y / 2 else Vector3.zero
		local at = base + Config.SpawnOffset
		HorseModel.build(CFrame.lookAt(at, at + Config.SpawnFacing)).Parent = workspace
	end
end
