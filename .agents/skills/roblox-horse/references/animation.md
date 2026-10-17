# How the horse moves

Everything below lives in [HorseClient](../scripts/client/HorseClient.client.luau). Read this
before changing gaits, speeds or poses.

## Two loops

- **Riding** (`RunService.PreSimulation`, your horse only): reads the seated Humanoid's
  `MoveDirection`, un-rotates it by the camera yaw into stick input, and sets the Root's `Gait`
  (`LinearVelocity`, horizontal plane only) and `Heading` (`AlignOrientation`). Gravity and jumps
  stay physical: a jump is one upward impulse.
- **Animation** (`BindToRenderStep` at `Character` priority, every horse): reads each horse's
  velocity and sets Motor6D `Transform`s. It runs on render time on purpose - the physics step
  arrives in uneven 12.5 / 16.7 / 20.8 ms chunks and stepping legs by it made them stutter.

## Gaits

After Richard Williams' horse walk, trot and gallop (*The Animator's Survival Kit*):

| Gait | Speed (studs/s) | Hoof down (duty) | Footfall (cycle phase) |
| --- | --- | --- | --- |
| Walk | 0-11 | 55% | hind L 0, front L .25, hind R .5, front R .75 (4 beats) |
| Trot | 11-30 | 32% | diagonal pairs together, a float between |
| Gallop | 31-50 | 24% | hind R 0, hind L .12, front R .29, front L .38, then all four in the air |
| Full gallop | 50-69 | 20% | as gallop, longer and flatter |

- **Stride** (studs per cycle) grows with speed inside each gait; the cycle advances by
  `speed / stride`, so a planted hoof moves exactly with the ground - nothing slides.
- **Blending**: between gaits the parameters and footfall phases ease (smoothstep) across a band
  of speed (9-14, 27-34, FastSpeed +/- 4). Speed, turn rate, lean and head turn ease
  exponentially, so starting, stopping and turning never snap.
- Speeds are tied to `HorseConfig`: scale the `GAITS` speed ranges with big speed changes and the
  strides by about the square root, so legs cycle faster rather than over-reach.

## Legs

- **Planted**: 2-bone IK in the side plane from the hip to the joint that gives (front: elbow,
  hind: hock) to the fetlock; the hoof stays level. The measurements come from HorseServer
  (attributes on each `Hip_*` motor). Out of reach, `softClamp` eases the hoof instead of
  stopping it dead; the shoulder / hip slides up to 0.35 studs along the body (`SLIDE`, like a
  scapula) for a longer reach.
- **In the air**: the hoof travels from behind to ahead on `swingX` - it leaves and meets the
  ground at the planted speed (small follow-through and paw-back, no velocity jump) - and lifts
  on a sin^2 arc. Keyed Catmull-Rom curves (`FRONT`, `HIND`) add the real folds: the front knee
  tucks the cannon back then the forearm reaches; the hind leg kicks back, then stifle and hock
  fold it under the belly. `fold` scales them per gait.
- **Jump**: while charging, your horse crouches (haunches down); off the ground every horse tucks
  its legs (`TUCK_FRONT`, `TUCK_HIND`), tips up on the climb and down on the fall, and gives a
  little on landing.
- **Standing**: hooves stay put and the legs bend with the body (crouch, breathing, landing).

## Body, head, tail

Each gait's `BODY` function returns heave, pitch, roll and neck angle for the cycle phase `u`:
walk - small double nod and roll; trot - lowest mid-stance of each diagonal, highest in the
float, nose dips on landing; gallop - chest up / rear down as the hinds land, then the reverse.
Turns add a lean (into the turn) and a head turn; the tail lifts with speed, lags the bounce on a
spring and swishes now and then while standing. Idle adds breathing, slow look-arounds and nods
(per-horse random seed, so a herd doesn't move in sync).

## Sound, dust, camera, rider

- **Hoofbeats**: two looped sounds per horse (`HorseConfig.Hoofbeats`); trot fades in over 11-17,
  gallop over 28-34 (and the trot out); playback speed follows the speed; silent in the air.
- **Drift dust**: four `ParticleEmitter`s on the hooves, made the first time a horse slides; rate
  follows how fast and how far off its nose it slides.
- **Camera**: `Humanoid.CameraOffset` cancels `CameraSteady` (80%) of the saddle's bounce.
- **Rider (R6)**: `Config.RiderPose` holds the torso relative to the horse's Torso piece and each
  limb relative to the rider's torso, read off a posed rig. `reachFor` turns each into a joint
  `Transform` whatever the joint's C0 / C1. To change it: sit an R6 rig on the horse in Edit mode,
  pose its joints (C0 / C1), read `horseTorso.CFrame:ToObjectSpace(rigTorso.CFrame)` and
  `rigTorso.CFrame:ToObjectSpace(limb.CFrame)` per limb, and paste them into `RiderPose`.

## Inspecting a pose

Set `PreviewSpeed` (studs/s) and `PreviewPhase` (0-1) on a horse model in a playtest and hold the
camera still: the horse freezes in that pose. Step `PreviewPhase` to check a whole cycle (hooves
on the ground, no knee bent backwards, no hoof below the floor).
