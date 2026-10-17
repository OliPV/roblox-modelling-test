-- The bundled horse: a Parts model (2.5 x 7.3 x 9.9 studs) rebuilt from data, so a game needs no
-- model file. HorseModel.build(cframe) returns a new Model "Horse", tagged HorseConfig.Tag, standing
-- with its hooves on cframe's position and facing cframe's LookVector. HorseServer rigs it.
--
-- Pieces follow HorseServer's naming: Torso, Neck and Head (models), Tail, and legs
-- "<F|B>-<Top|Middle|Bottom|Hoof>-Leg-<L|R>". Torso / NeckCore / HeadCore are invisible boxes the
-- size of the original Unions: the rig measures them (joints, Root, saddle, rider pose), and the
-- visible pieces of each are plain Parts in the Unions' colour. Recapture this data from Studio with
-- the snippet in references/model-and-rig.md if the horse is restyled.
local Config = require(script.Parent:WaitForChild("HorseConfig"))
local CollectionService = game:GetService("CollectionService")

-- group ("" = top level), name, size X / Y / Z, colour, material, transparency, CFrame relative to
-- the bottom centre of the horse (-Z = forward)
-- stylua: ignore start
local PARTS = {
	{ "", "Torso", 5.7607, 2.1532, 1.2962, "7e5b43", "Snow", 1, CFrame.new(-0.0097, 4.0845, 0.8465, -0.0015, 0, 1, 0, 1, 0, -1, 0, -0.0015) },
	{ "", "Barrel", 4.4646, 1.9154, 1.2962, "7e5b43", "Snow", 0, CFrame.new(-0.0106, 4.2034, 0.1984, -0.0015, 0, 1, 0, 1, 0, -1, 0, -0.0015) },
	{ "", "Belly", 2.9885, 0.2437, 1.2962, "7e5b43", "Snow", 0, CFrame.new(-0.0113, 3.1297, -0.2516, -0.0015, 0, 1, 0, 1, 0, -1, 0, -0.0015) },
	{ "", "Rump", 1.2962, 1.7714, 1.2962, "7e5b43", "Snow", 0, CFrame.new(-0.0064, 4.1314, 3.0787, -0.0015, 0, 1, 0, 1, 0, -1, 0, -0.0015) },
	{ "", "Tail", 2.8888, 0.4822, 0.5475, "5a2c0d", "Fabric", 0, CFrame.new(-0.0048, 3.584, 4.1338, -0.0006, 0.0013, 1, 0.9063, 0.4226, 0, -0.4226, 0.9063, -0.0015) },
	{ "Neck", "NeckCore", 1.8734, 3.1973, 0.7736, "7e5b43", "Snow", 1, CFrame.new(-0.0097, 5.4332, -1.9996, -0.0011, -0.001, 1, -0.6428, 0.766, 0, -0.766, -0.6428, -0.0015) },
	{ "Neck", "NeckBase", 1.343, 3.0098, 0.7736, "7e5b43", "Snow", 0, CFrame.new(-0.0097, 5.4423, -1.9888, -0.001, -0.0011, 1, -0.766, 0.6428, 0, -0.6428, -0.766, -0.0015) },
	{ "Neck", "NeckCrest", 0.4071, 3.0099, 0.7736, "7e5b43", "Snow", 0, CFrame.new(-0.0105, 4.9495, -2.5508, -0.0011, -0.001, 1, -0.6428, 0.766, 0, -0.766, -0.6428, -0.0015) },
	{ "Neck", "Mane", 3.8901, 0.4822, 0.3603, "5a2c0d", "Fabric", 0, CFrame.new(-0.0131, 5.864, -1.4444, -0.0011, 0.001, 1, 0.6428, 0.766, 0, -0.766, 0.6428, -0.0015) },
	{ "Head", "HeadCore", 2.4712, 1.5769, 0.9863, "7e5b43", "Snow", 1, CFrame.new(-0.0124, 5.8231, -3.5091, -0.0011, -0.001, 1, -0.6428, 0.766, 0, -0.766, -0.6428, -0.0015) },
	{ "Head", "Skull", 1.4476, 1.2697, 0.9862, "7e5b43", "Snow", 0, CFrame.new(-0.0117, 6.0471, -3.0975, -0.0012, -0.0008, 1, -0.5736, 0.8192, 0, -0.8192, -0.5736, -0.0015) },
	{ "Head", "Muzzle", 1.0086, 0.9006, 0.9827, "7e5b43", "Snow", 0, CFrame.new(-0.0133, 5.2033, -3.9437, -0.0011, -0.001, 1, -0.6428, 0.766, 0, -0.766, -0.6428, -0.0015) },
	{ "Head", "Ear", 0.1608, 0.3217, 0.3168, "7e5b43", "Snow", 0, CFrame.new(-0.3466, 6.9235, -3.1441, -0.0014, -0.0004, 1, -0.2588, 0.9659, 0, -0.9659, -0.2588, -0.0015) },
	{ "Head", "Ear", 0.1608, 0.3217, 0.317, "7e5b43", "Snow", 0, CFrame.new(0.3189, 6.9235, -3.1451, -0.0014, -0.0004, 1, -0.2588, 0.9659, 0, -0.9659, -0.2588, -0.0015) },
	{ "Head", "Brow", 0.1888, 0.1149, 0.6619, "7e5b43", "Snow", 0, CFrame.new(-0.3531, 6.1608, -3.5921, -0.0014, -0.0004, 1, -0.2588, 0.9659, 0, -0.9659, -0.2588, -0.0015) },
	{ "Head", "Brow", 0.1888, 0.1149, 0.6619, "7e5b43", "Snow", 0, CFrame.new(0.3502, 6.1608, -3.5931, -0.0014, -0.0004, 1, -0.2588, 0.9659, 0, -0.9659, -0.2588, -0.0015) },
	{ "Head", "Nostril", 0.2895, 0.0889, 0.1281, "7e5b43", "Snow", 0, CFrame.new(-0.3054, 5.1683, -4.3945, -0.0011, -0.001, 1, -0.6428, 0.766, 0, -0.766, -0.6428, -0.0015) },
	{ "Head", "Nostril", 0.2895, 0.0889, 0.1281, "7e5b43", "Snow", 0, CFrame.new(0.2678, 5.1683, -4.3954, -0.0011, -0.001, 1, -0.6428, 0.766, 0, -0.766, -0.6428, -0.0015) },
	{ "Head", "Eye", 0.2756, 0.2016, 0.679, "d9b69d", "Plaster", 0, CFrame.new(-0.012, 6.1834, -3.5576, -0.0015, -0.0001, 1, -0.0872, 0.9962, 0, -0.9962, -0.0872, -0.0015) },
	{ "Head", "Pupil", 0.159, 0.2017, 0.7736, "1d130e", "Glass", 0.5, CFrame.new(-0.0121, 6.1772, -3.6283, -0.0014, -0.0004, 1, -0.2588, 0.9659, 0, -0.9659, -0.2588, -0.0015) },
	{ "Head", "Mane", 1.2155, 0.3163, 0.3618, "5a2c0d", "Fabric", 0, CFrame.new(-0.0156, 6.8197, -3.1901, -0.0012, -0.0008, 1, -0.5736, 0.8192, 0, -0.8192, -0.5736, -0.0015) },
	{ "", "F-Top-Leg-L", 1.5702, 1.9555, 0.7355, "7e5b43", "Snow", 0, CFrame.new(-0.8416, 3.7292, -1.3537, -0.0014, -0.0004, 1, -0.2588, 0.9659, 0, -0.9659, -0.2588, -0.0015) },
	{ "", "F-Middle-Leg-L", 1.0224, 1.547, 0.6224, "7e5b43", "Snow", 0, CFrame.new(-0.7742, 2.4633, -1.1965, -0.0015, 0, 1, 0, 1, 0, -1, 0, -0.0015) },
	{ "", "F-Bottom-Leg-L", 0.6702, 1.409, 0.5304, "7e5b43", "Snow", 0, CFrame.new(-0.7735, 0.9815, -1.2632, -0.0015, 0, 1, 0, 1, 0, -1, 0, -0.0015) },
	{ "", "F-Hoof-Leg-L", 0.7038, 0.6038, 0.6265, "5f4433", "Wood", 0, CFrame.new(-0.8199, 0.3019, -1.5115, -0.0015, 0, 1, 0, 1, 0, -1, 0, -0.0015) },
	{ "", "F-Top-Leg-R", 1.5702, 1.9555, 0.7355, "7e5b43", "Snow", 0, CFrame.new(0.8157, 3.7292, -1.3562, -0.0014, -0.0004, 1, -0.2588, 0.9659, 0, -0.9659, -0.2588, -0.0015) },
	{ "", "F-Middle-Leg-R", 1.0224, 1.5548, 0.6008, "7e5b43", "Snow", 0, CFrame.new(0.7486, 2.4594, -1.1987, 0.0015, 0, -1, 0, 1, 0, 1, 0, 0.0015) },
	{ "", "F-Bottom-Leg-R", 0.6702, 1.4216, 0.5071, "7e5b43", "Snow", 0, CFrame.new(0.7448, 0.9812, -1.2655, 0.0015, 0, -1, 0, 1, 0, 1, 0, 0.0015) },
	{ "", "F-Hoof-Leg-R", 0.7038, 0.6038, 0.6265, "5f4433", "Wood", 0, CFrame.new(0.7938, 0.3117, -1.5139, 0.0015, 0, -1, 0, 1, 0, 1, 0, 0.0015) },
	{ "", "B-Top-Leg-L", 1.928, 2.1419, 0.7912, "7e5b43", "Snow", 0, CFrame.new(-0.8526, 3.6671, 2.8611, -0.0015, 0.0001, 1, 0.0872, 0.9962, 0, -0.9962, 0.0872, -0.0015) },
	{ "", "B-Middle-Leg-L", 1.0081, 1.6011, 0.7237, "7e5b43", "Snow", 0, CFrame.new(-0.8191, 2.3869, 2.7501, -0.0013, -0.0007, 1, -0.5, 0.866, 0, -0.866, -0.5, -0.0015) },
	{ "", "B-Bottom-Leg-L", 0.5971, 1.7444, 0.6194, "7e5b43", "Snow", 0, CFrame.new(-0.8049, 1.2976, 2.9588, -0.0014, 0.0005, 1, 0.342, 0.9397, 0, -0.9397, 0.342, -0.0015) },
	{ "", "B-Hoof-Leg-L", 0.7038, 0.6038, 0.6752, "5f4433", "Wood", 0, CFrame.new(-0.8335, 0.3522, 2.5236, -0.0015, 0, 1, 0, 1, 0, -1, 0, -0.0015) },
	{ "", "B-Top-Leg-R", 1.9263, 2.1419, 0.794, "7e5b43", "Snow", 0, CFrame.new(0.8512, 3.6767, 2.8594, 0.0015, 0.0001, -1, -0.0872, 0.9962, 0, 0.9962, 0.0872, 0.0015) },
	{ "", "B-Middle-Leg-R", 1.0081, 1.6011, 0.7256, "7e5b43", "Snow", 0, CFrame.new(0.8169, 2.387, 2.7476, 0.0013, -0.0007, -1, 0.5, 0.866, 0, 0.866, -0.5, 0.0015) },
	{ "", "B-Bottom-Leg-R", 0.5971, 1.7444, 0.5914, "7e5b43", "Snow", 0, CFrame.new(0.8134, 1.2976, 2.9564, 0.0014, 0.0005, -1, -0.342, 0.9397, 0, 0.9397, 0.342, 0.0015) },
	{ "", "B-Hoof-Leg-R", 0.7038, 0.6038, 0.6389, "5f4433", "Wood", 0, CFrame.new(0.8365, 0.3522, 2.5212, -0.0015, 0, 1, 0, 1, 0, -1, 0, -0.0015) },
}
-- stylua: ignore end

local HorseModel = {}

-- a new horse standing on `at` (its position = between the hooves on the ground), facing at.LookVector
function HorseModel.build(at: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "Horse"
	local groups = {}
	for _, row in PARTS do
		local group, name, sx, sy, sz, color, material, transparency, rel = table.unpack(row)
		local parent = model
		if group ~= "" then
			parent = groups[group]
			if not parent then
				parent = Instance.new("Model")
				parent.Name = group
				parent.Parent = model
				groups[group] = parent
			end
		end
		local p = Instance.new("Part")
		p.Name = name
		p.Size = Vector3.new(sx, sy, sz)
		p.CFrame = at * rel
		p.Color = Color3.fromHex(color)
		p.Material = Enum.Material[material]
		p.Transparency = transparency
		p.CastShadow = transparency < 1
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		p.Anchored = true -- (HorseServer unanchors everything once it has rigged the horse)
		p.Parent = parent
	end
	model.WorldPivot = at
	CollectionService:AddTag(model, Config.Tag)
	return model
end

return HorseModel
