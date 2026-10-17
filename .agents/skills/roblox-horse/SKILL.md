---
name: roblox-horse
description: "Add a rideable, procedurally animated horse to a Roblox game: walk, trot, canter and gallop, drifts, charged jumps, stamina, hoofbeats, drift dust and an R6 riding pose. Use when a game needs horses or other four-legged mounts, or to tune or debug their riding and animation."
---

# Rideable horse

A complete, playtested horse: a Parts model, a runtime rig, riding controls with a HUD and
procedural animation for every gait. No animation assets are needed - every pose is computed
from the horse's speed, so the legs never slide at any speed and other players see the same motion.

What a game gets:
- Walk, trot, canter, gallop and full gallop with blended transitions (after Richard Williams'
  horse gaits), planted hooves (2-bone IK), keyed leg folds, body heave / pitch / roll, neck nod,
  lean into turns, a spring-driven tail, idle breathing, head looks and tail swishes.
- Stamina sprint, auto-trot after a sprint, reversing, drifts (a tight slide that keeps speed)
  with dust at the hooves, charged jumps with crouch, leg tuck and landing give.
- Trot / gallop hoofbeat loops that cross-fade and follow the speed; a steadied rider camera.
- An exact R6 riding pose read off a posed rig; R15 riders use Roblox's sit pose.

## Install

Copy the scripts into the game's Rojo folders (the template maps them to `GameShared`,
`GameServer` and `GameClient`):

| From this skill | To the game |
| --- | --- |
| [scripts/shared/Horse/](scripts/shared/Horse/HorseConfig.luau) (both modules) | `src/shared/Horse/` |
| [scripts/server/HorseServer.server.luau](scripts/server/HorseServer.server.luau) | `src/server/` |
| [scripts/client/HorseClient.client.luau](scripts/client/HorseClient.client.luau) | `src/client/` |

Press Play: with no horse in Workspace, HorseServer builds the bundled horse
([HorseModel](scripts/shared/Horse/HorseModel.luau)) 16 studs in front of the first
SpawnLocation. Walk up and use the **Ride** prompt. If the game maps code elsewhere, fix the
`WaitForChild("GameShared")` lines at the top of the two scripts.

To use your own horse model, tag it `Horse`, name its pieces as in
[model-and-rig.md](references/model-and-rig.md) and set `SpawnBundledHorse = false`. More horses:
clone the model and tag each one.

## Controls

| Action | Keyboard | Gamepad |
| --- | --- | --- |
| Walk / steer / brake, back up | W A S D | Left stick |
| Trot on / off | Ctrl | Y |
| Gallop (hold; uses stamina) | Shift | L3 |
| Jump (hold to charge, release) | Space | A |
| Get off | E | B |

Touch players get on-screen buttons. Drift: at gallop speed let go of Shift (or W) and steer hard.

## Tuning

All numbers live in [HorseConfig](scripts/shared/Horse/HorseConfig.luau): speeds and
accelerations, stamina, jump heights, turn rates, drift feel and dust, hoofbeat sounds, HUD gait
names, the rider pose and the bundled-horse spawn. The animation follows the speeds; the gait
table (`GAITS` in HorseClient) is tuned for the default speeds - see
[animation.md](references/animation.md) before changing speeds by more than ~25%.

## Hooks for game code

Set attributes; HorseClient reacts on every client (times are `workspace:GetServerTimeNow()`):

| Attribute | On | Effect |
| --- | --- | --- |
| `Locked` (bool) | horse | pulls up hard, no steering or jumping (countdowns, stuns, cutscenes) |
| `SpeedCap` (number) | horse | top speed; at or below `TrotSpeed` also no sprint or drift |
| `JoltAt`, `JoltPower` | horse | a hit: body and rider rock back, then settle |
| `Limp` (0-2) | horse | the body drops on each step |
| `RideAnimation` (asset id) | horse | the rider plays it instead of the pose |
| `PreviewSpeed`, `PreviewPhase` | horse | freeze the animation at a speed / cycle phase (pose checks) |
| `RiderFreeArm` (`"Right Arm"`) | rider | leaves that arm to your script (holding a weapon) |

`shared.RiderLean[character] = CFrame` turns the rider's torso (attacks, waves). A script that
poses something from the rider's torso should bind its render step at `Character + 1`.

## Rules that matter

- The rider's client owns the horse's physics while riding (smooth, responsive). Movement is
  therefore client-trusted: if speed or position matter for scoring or combat, validate them on
  the server ([roblox-networking](../roblox-networking/SKILL.md)).
- Animation runs on render time for every horse on every client; the server never animates.
- A character's Animator resets every Motor6D after render-time code, so the rider pose is set
  again in `PreSimulation`. Keep that if you add your own poses.
- Don't anchor or weld the visible pieces yourself: HorseServer makes them massless and moves
  them through Motor6Ds; the invisible `Root` box carries the physics.

## Verify

Follow the project's QA rules, then check in a playtest:
1. Output has no `HorseServer:` warnings (missing pieces are reported by name).
2. Ride every gait to full gallop: hooves stay planted, transitions blend, hoofbeats change.
3. Drift (dust appears), charge a full jump (crouch, tuck, landing), back up, get off on the left.
4. A second client sees the same motion; R6 and R15 riders both sit correctly.
5. Use `PreviewSpeed` / `PreviewPhase` with a fixed camera to inspect single poses.

Details: [animation.md](references/animation.md) (how the motion is built and tuned) and
[model-and-rig.md](references/model-and-rig.md) (pieces, joints, bundled model data).
