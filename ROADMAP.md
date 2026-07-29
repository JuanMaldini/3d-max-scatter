# MaxScatter roadmap

Target: **3ds Max 2024-2027**, one codebase, one install.

Priorities come from a feature comparison against Forest Pack and Chaos Scatter.
The ordering rule is deliberate: cheap features that live inside modules which
already exist come first, one big differentiator comes last, and anything that
would need a new subsystem (viewport painting, per-renderer instancing APIs) is
written down as *not planned* rather than left implied.

---

## Done

- [x] **0.1** — modular bootstrap; scene object with persistent paramblocks;
      surface scatter by count or density; seed; multiple sources with per-point
      appearance probability; multiple surfaces; per-source transforms; group and
      hierarchy sources; include/exclude splines; slope and altitude limits;
      density map (Amount / Invert / Gamma / Tile); camera frustum culling with
      auto re-cull; spline-path distribution; Full / Box / Wire box display;
      bake; undo
- [x] **0.2** — proxy emitter (Box / Cone / Point cloud with Display %,
      materialised at render time); world gizmo; `.mzp` packaging

## v0.2.1 — 2024-2027 foundation

Infrastructure only, no new features. This is what makes the version range real
instead of aspirational.

- [x] **Application package.** One install at
      `%APPDATA%\Autodesk\ApplicationPlugins\MaxScatter` covering 2024-2027,
      replacing per-version `scripts` + `usermacros` + a `scripts/startup` stub.
      Per-user, so no administrator rights and no elevation prompt on a
      drag-and-drop install.
- [x] **Declarative main menu.** 2025 deleted `menuMan`. The menu is now
      declared in `Contents/cui/MaxScatter.mnx`, which the host applies whenever
      it builds a menu configuration — so it survives workspace switches and CUI
      resets with no script running. The previous fix worked but forced a full
      menu-bar rebuild at every launch to catch up with a callback that always
      fired too late. 2024 has no `.mnx` and keeps the `menuMan` path.
- [x] **Baked world gizmo.** The "MaxScatter" sign is baked vert/face data
      (`emit/gizmo_data.ms`, regenerate with `build/bake_gizmo.ms`) instead of
      being built from a temporary Text node on the first regen — which is why a
      freshly created helper used to draw a placeholder bar until some parameter
      changed. Also removes the dependency on the machine's installed fonts.
- [ ] Verified on 2024. *Not yet done: 2024 is not installed on the development
      machine.* Everything version-dependent is feature-detected rather than
      switched on a version number, but that is a design claim, not a test
      result, and it will be labelled as such until someone runs it.

## v0.3 — UI structure, then the cheap wins

### Structure first

Eight rollouts collapse to six, ordered by the pipeline itself
(sample → filter → transform → emit) so there is a right place to put
everything that comes after:

| Rollout | Absorbs |
|---|---|
| Sources | item count header |
| Distribution | **Spline options** — distributing along a path *is* distribution |
| Areas & Masks | include/exclude, and the falloff curve |
| Transform | unchanged, per source |
| Limits | **Camera** — frustum culling is a filter, not a panel of its own |
| Display | unchanged |

Hard constraint: **paramblock order and layout do not change.** Moving a slot
breaks every saved scene. Only `rollout` definitions are reordered and controls
move between them; new parameters are appended at the end, never inserted.

### Features

All of these land inside modules that already exist.

- [ ] **Item count in the UI.** There is currently no way to know how many items
      you generated. `pipeline.regen` already returns the number.
- [ ] **Jitter XY.** `transform.ms` already does this on Z (`zoMin`/`zoMax`);
      X and Y are the same code. Per source, so the serialised transform string
      grows — `strToPP` must keep reading the old shorter form.
- [ ] **Editable falloff curve.** `filters.ms` ramps linearly
      (`filters.ms:155`); replace with a curve choice (linear / smooth / ease
      in / ease out).
- [ ] **Colour map picks the source.** Today a map can only drive density. The
      same map should be able to decide *which* source appears at a point.
- [ ] **Per-surface density weight.** Multiple surfaces are already weighted by
      area; this makes the weight explicit and editable per surface.

## v1.0 — the differentiator

- [ ] **Collision avoidance.** Highest-value gap against both competitors:
      nothing serious ships without it, and today items interpenetrate. Lives
      entirely in `core/filters` + `pipeline` — no scene mutation, so it stays
      testable without a scene.
- [ ] **Clusters.** Natural grouping (woods, clumps) — a second sampling pass
      over the existing one.
- [ ] **Map types for zones and curves.** More ways to drive a region than a
      single texmap and a linear ramp.
- [ ] Optimisation pass.
- [ ] Example scene showing the feature set in one file.
- [ ] Export, docs, CI.

## Not planned

Written down so the absence is a decision rather than an oversight. Each one
needs a subsystem MaxScatter does not have, and none of them is worth starting
before v1.0 ships.

- **Painted areas.** Needs a viewport paint tool and a persistent mask channel.
  The single largest project on the comparison list.
- **Edge mode** (a dedicated border row). Forest Pack users ask for it and
  neither competitor has it, so it stays on the record as a real opening — just
  not one to spend v0.3 on.
- **Grid / hex / UV patterns.** Both competitors have them; cheap to add, but
  they compete for the same release slot as the items above.
- **Native render-engine instancing.** Would break the node-count ceiling, but
  it means one integration per engine against third-party APIs, and it trades
  away the current advantage: real Max nodes render in *every* engine, including
  IPR, and export anywhere.
- **Area from a closed mesh.** Low value while include splines cover the case.
