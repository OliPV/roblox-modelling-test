# Horse model and rig

## Pieces HorseServer expects

A Model tagged `Horse` (HorseConfig.Tag), any facing, any position:

| Piece | Name | Notes |
| --- | --- | --- |
| Body | `Torso` | a Part, or a Model (its biggest part is used) |
| Neck | `Neck` | Part or Model; forward = from Torso toward Neck |
| Head | `Head` | Part or Model, joined to the neck |
| Tail | `Tail` | optional |
| Legs | `F-Top-Leg-L`, `F-Middle-Leg-L`, `F-Bottom-Leg-L`, `F-Hoof-Leg-L` | 4 segments per leg, `F`/`B` front/back, `L`/`R` |

Each leg segment's longest axis should run along the leg; joints go at the middle of where two
segments overlap, the hip a third of the way down the top segment. Anything else in the model
(mane, eyes, saddle props) is welded to the Torso, or to the Neck / Head part it sits in.
Missing pieces are reported in Output as `HorseServer: ...` and that leg stays stiff.

## What the rig adds at run time

- `Root`: an invisible box (torso length, horse width, hooves to back) that carries all the
  physics; every visible part becomes massless, non-colliding and unanchored.
- `Gait` (`LinearVelocity`, horizontal plane) and `Heading` (`AlignOrientation`) on the Root.
- Motor6Ds in the Root: `Body`, `Neck`, `Head`, `Tail`, and per leg `Hip_<F|B>_<L|R>` plus
  `Elbow`/`Knee`/`Fetlock` (front) or `Stifle`/`Hock`/`Fetlock` (hind). Each `Hip_*` carries the
  leg's IK measurements as attributes: `IkJoint`, `A`, `B`, `Upper0`, `Bend0`, `Height`, `Fwd`,
  `FetX`, `FetY`.
- `Saddle`: a Seat on the middle of the back that only the **Ride** prompt fills (`CanTouch` off).
- Network ownership goes to the rider while seated and back to the server when they get off.

Other proportions work - the IK uses each horse's own measurements - but stride lengths and
body motion were tuned on the bundled horse; check a new body with `PreviewSpeed` poses.

## The bundled horse

[HorseModel](../scripts/shared/Horse/HorseModel.luau) rebuilds a Parts horse from a data table,
so the template ships no model files. Three of the original pieces were Unions; a script can't
rebuild CSG geometry, so they were separated and kept as two things: an invisible core box with
the Union's exact size and placement (`Torso`, `NeckCore`, `HeadCore` - what the rig measures, so
joints, saddle and rider pose stay identical) and plain visible parts in the Union's colour.

To recapture a restyled horse:
1. Duplicate it, and on the copy select every Union and use **Separate** (repeat for nested ones;
   negative parts must not remain).
2. In a command bar or MCP `execute_luau`, read every part's size, colour, material, transparency
   and `frame:ToObjectSpace(part.CFrame)`, where `frame` faces from the Torso toward the Neck and
   sits at the bottom centre of the whole horse. Use the original Unions' boxes for the invisible
   cores and give the separated parts the Union's colour (Unions usually ignore part colours).
3. Paste the rows into `PARTS`, delete the copy, and re-check the rider pose and a few
   `PreviewSpeed` poses.

Keep the developer's placed horse untouched while doing this; work on the copy only.
