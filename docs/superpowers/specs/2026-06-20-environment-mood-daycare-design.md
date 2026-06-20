# Visuals & Atmosphere — Slice 1: Environment + Mood (Derelict Daycare)

- **Date:** 2026-06-20
- **Status:** Approved (user said "continue autonomously"); spec + build order combined.
- **Thread:** Visuals & atmosphere (first of several: this slice = environment + mood; later slices = the monster model + jumpscare, then audio, then depth/difficulty).
- **Depends on:** the bunny MVP (merged to `main`). This slice MUST NOT break the bunny — markers stay non-collidable, connectivity is re-verified all-pairs, and no `MonsterService`/`BunnyFSM` code changes.

---

## 1. Goal

Turn the abstract greybox into a **dim, dressed, derelict daycare** that reads as a real, scary place — so the verified systems finally feel like a game. Setting/tone decided in brainstorming: **corrupted-mascot-bunny in a derelict daycare**, **dim with flickering pools of practical light** (the flashlight is your lifeline, not your only sight). This slice is the environment + lighting only; the bunny stays the placeholder rig (its model is the next slice).

This is mostly Studio content (built via the MCP, saved into the place) plus one small client script for the light flicker.

---

## 2. Layout — the daycare floorplan

A ~120×120 footprint reshaped into recognizable rooms connected as a maze with a loop. Top-down concept:

```
  NW ┌──────────────┬────────────────┐ NE
     │  NAP ROOM    │    OFFICE      │
     │  cots        ·   (SAFE ROOM)  │     · = doorway
     ├──────┐···┌───┴────·───────────┤
     │      ·   │      HALLWAY        │
     │ PLAY ROOM·   ┌────·────────────┤
     │ shelves/toys │   │  BATHROOM   │
     ├──────·───────┴───┴─────────────┤
     │  FOYER       ·                 │
     │  (START)     →    EXIT  ▣      │
  SW └──────────────┴─────────────────┘ SE
```

- **Rooms:** Foyer (start), Play Room (toy clutter + shelves = LoS cover), Nap Room (rows of cots), Hallway spine, dead-end Bathroom (tension nook), Office (= the SafeRoom refuge). Back **Exit** for escape.
- **Loop:** Foyer → Play → Nap → Hall → Office → Foyer, so breaking sight and circling works.
- **Markers re-placed, all `CanCollide=false`:** `PlayerStart`→Foyer, `SafeRoom`→Office, `ExitDoor`→Exit, 5 `KeySpot`s one-per-area, 5 `PatrolPoint`s one-per-area (bunny tours the whole daycare), `MonsterSpawn`→Nap Room.
- **Doorways ≥ 8 studs wide** so the `AgentRadius = 2` bunny paths through after props are placed.
- **Hard gate:** after the full dress (walls + collidable props), re-run the all-pairs pathfinding check (spawn + every PatrolPoint + PlayerStart→Exit + spawn→SafeRoom) — all must be `Success`, or widen the offending doorway/move the prop.

---

## 3. Materials & palette

Grimy faded pastels, per room, so each space reads distinctly — no asset uploads, just `Material` + `Color` (and `MaterialVariant`-free; Plaster/Concrete/Wood/Brick built-ins):

| Surface | Material | Color (grimy pastel) |
| --- | --- | --- |
| Foyer walls | Plaster | faded mint `(150,170,160)` darkened |
| Play Room walls | Plaster | faded pink/peach `(180,150,150)` darkened |
| Nap Room walls | Plaster | faded blue `(140,150,170)` darkened |
| Hallway walls | Concrete | grey-green `(120,125,120)` |
| Bathroom walls | SmoothPlastic | dingy off-white `(170,170,165)` |
| Office walls | WoodPlanks | warm tan `(150,130,100)` |
| Floors | Pebble / Fabric | worn grey-brown `(95,90,85)` |
| Ceiling | Slate | near-black `(35,35,40)` |

Grime = lower brightness + a few darker "stain" decal-parts (flat dark quads on walls/floor) scattered. The Office is slightly warmer to read as "safer."

---

## 4. Props (parts-built; no meshes this slice)

Simple primitives (boxes/cylinders/wedges) — enough to read, not photoreal. **Collision rule (critical for the bunny):** only large LoS-cover props are `CanCollide=true` (shelves, cots, reception desk); small clutter (toy blocks, debris) is `CanCollide=false` so it can't strand the navmesh. Collidable props are kept clear of doorways; connectivity is re-verified after.

- **Play Room:** 2–3 low shelves (cover), a play mat (flat part), scattered toy blocks (small colored cubes, non-collidable), a ball-pit frame.
- **Nap Room:** 4–6 small cots (low slab + thin legs), a couple knocked over.
- **Foyer:** reception desk (cover), a wall of cubbies (small boxes), a **hero prop**: a stylized parts-built **corrupted bunny mascot statue/sign** (tall, long ears, off-color) that establishes the fiction.
- **Bathroom:** tiny sinks / a low stall divider.
- **Office:** desk + chair + a shelf.
- **Scatter:** a few tipped tiny chairs and toy debris across rooms.

---

## 5. Lighting & mood

The mood is "dim with flickering pools." Two layers — static place lighting (set once on services) and animated flicker (one client script).

**Static (Lighting service + post-FX, set via MCP, saved with place):**
- `Lighting.Brightness ≈ 1`, `Ambient ≈ (20,20,26)`, `OutdoorAmbient ≈ (15,15,20)`, `ClockTime = 0` (night), `EnvironmentDiffuseScale`/`EnvironmentSpecularScale` low, slight negative `ExposureCompensation`.
- `Atmosphere` (fog): `Density ≈ 0.4`, cold-grey `Color`, some `Haze`/`Glare` — so distance fades to black and the flashlight beam reads.
- `ColorCorrection`: slight desaturation, cold (blue-green) `TintColor`, raised `Contrast`, lowered `Brightness`.
- **Practical lights:** broken ceiling fixtures (a handful of `PointLight`/`SurfaceLight` in small fixture parts) casting pools. Some steady (dim safe pools), some tagged `FlickerLight` (unreliable). The Office (SafeRoom) gets a steadier, slightly warmer light — a subtle "safer here" read.

**Animated flicker (code):** a client `FlickerController` oscillates each `FlickerLight` brightness (and occasionally toggles it off) for a broken-fluorescent effect.

The existing **flashlight** becomes central — in this darkness it's how you see.

---

## 6. Code additions (the only repo changes)

Small, follows all conventions:

- **`Tags.FlickerLight`** — new tag constant for flickering practical lights.
- **`Config.Lighting`** — new frozen section for the FLICKER animation tunables the code uses (the static lighting values live on the place instances, not Config): `FlickerSpeed` (rad/s base), `FlickerMinScale` (brightness floor as a fraction), `FlickerOffChance` (per-tick chance a fixture briefly cuts out), `FlickerOffTime` (seconds it stays out).
- **`FlickerController.client.luau`** — client-only (an uncontested local visual effect, allowed client-side per CLAUDE.md): `Discovery.observe(Tags.FlickerLight, …)` to track tagged lights; each frame, drive each light's `Brightness` from its base × a per-light noise/sine flicker using `Config.Lighting` params, with the occasional brief blackout. Renders only.

No changes to `MonsterService`/`BunnyFSM`/`SpawnService`/etc.

---

## 7. Build order

1. **Geometry:** clear `MazeMarkers`; build floor + room walls (with ≥8-stud doorways) + ceiling per the floorplan; re-place all markers (non-collidable). Verify all-pairs connectivity (hard gate).
2. **Materials/palette:** apply per-room `Material`+`Color` to walls/floors/ceiling; add a few stain quads.
3. **Props:** place the per-room props (collision rule above), incl. the hero bunny statue. **Re-verify all-pairs connectivity** after collidable props.
4. **Lighting:** set Lighting/Atmosphere/ColorCorrection; place practical-light fixtures (tag the flickering ones `FlickerLight`).
5. **Code:** add `Tags.FlickerLight`, `Config.Lighting`, `FlickerController.client.luau`; StyLua + Selene clean; Rojo syncs to Studio.
6. **Save the place** (Workspace + Lighting content isn't Rojo-synced).

---

## 8. Testing / definition of done

- **Connectivity (hard gate):** all-pairs pathfinding `Success` (spawn↔every PatrolPoint, PlayerStart→Exit, spawn→SafeRoom) after the full dress.
- **Bunny still works:** in a Play session, the bunny patrols the daycare (moves, tours), chases on detection, and catches → respawn. (No code change, but the new layout must not regress it.)
- **Flicker works:** `FlickerLight` fixtures visibly flicker; steady lights don't; Office light is steady/warm.
- **Mood reads (screenshots via MCP):** the maze is dark and dressed; rooms are distinguishable; fog fades distance to black; the flashlight cuts a readable beam; pools of practical light are visible.
- **Lint:** StyLua + Selene clean for the new code.
- **Place saved.**

---

## 9. Out of scope (later slices)

- The monster **model** (the bunny stays the placeholder cube — next visual slice) and the real **jumpscare**.
- **Audio** (footsteps, ambient, monster cues) — its own thread.
- High-detail **meshes**, uploaded textures/decals/`SurfaceAppearance`, toolbox assets.
- **Depth/difficulty** threads.
