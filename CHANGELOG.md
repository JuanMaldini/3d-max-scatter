# Changelog

All notable changes to this project are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning follows [SemVer](https://semver.org/).

## [Unreleased]

### Added
- Modular bootstrap (`init.ms`) loading all modules in dependency order.
- Pure core: area-weighted surface sampling across multiple surfaces (UVs
  come free from the barycentrics), deterministic seeding, placement matrices.
- **MaxScatter scene object** — a scripted helper plugin (`MaxScatterObj`).
  Parameters live in paramblocks, persist inside the .max file, and are edited
  in the Modify panel; every change regenerates automatically. Also available
  under Create > Helpers > MaxScatter. Moving the helper moves the whole set.
- Multiple sources, each with an appearance probability 0-1 per scattered
  point: probabilities summing under 1 leave the remainder empty; over 1 they
  act as relative weights. Multiple surfaces, sampled evenly by area.
- **Per-source transforms** (edited for the source selected in the list):
  rotation XYZ min/max, uniform or per-axis XYZ scale, Z offset along the
  item's up axis. Global align-to-normal.
- **Filters**: slope limit (degrees), altitude limit (world Z), include and
  exclude closed splines (XY area test).
- **Density map**: any texturemap; luminance drives keep probability, with
  Amount / Invert / Gamma / Tile controls. Needs UVs on the surface.
- **Camera culling**: pick a camera, FOV pad (+/- degrees), keep distance
  behind the camera, optional far limit. Culling bakes at regen time.
- **Display modes**: Full / Box / Wire box — restyle existing instances
  without resampling. Bake button detaches instances from the scatter.
- **Spline path distribution**: open/closed splines as paths, density per
  length unit, lateral Spread, align-to-path (item X follows the tangent,
  like a Sweep). The UI enables Surface vs Spline sections per mode.
- **Group / hierarchy sources**: a source can be a group or a parented
  hierarchy; the whole subtree scatters as one unit (instanced, reused).
- **Auto re-cull**: moving the picked camera regenerates every scatter that
  uses it — no parameter touch needed.
- **Proxy emitter (render-time)**: one display mesh for all items — Box /
  Cone / Point cloud (points-per-item density like Corona's previz) with
  Display % thinning — real instances exist only between #preRender and
  #postRender. Trades IPR for viewport scale.
- **World gizmo**: the object displays as the text "MaxScatter" inside a
  white containing rectangle (min 1 m wide).
- Emitter A — real Max instances, undo-wrapped, with **node reuse** between
  regenerations (spinner drags move nodes instead of rebuilding).
- Modularised: all regen logic lives in `core/pipeline.ms` (hot-reloadable);
  the plugin file is a thin shell of paramblocks + rollouts.
- Dev logging to `(getDir #temp)\MaxScatter.log`, enabled only in dev sessions.
- `build/dev_link.ps1` junction installer (+ startup stub so saved scenes load
  the plugin class) and `build/dev_reload.ms` hot reload.
- MIT license.

### Verified
- Persistence: save / reset / reload keeps all params and instances; values
  keep driving the result after reload.
- Exclude spline: 0 instances inside the excluded circle.
- Node reuse: 1336/1350 nodes recycled on a seed change (138 ms @ 1500 pts).
- Camera culling: 0 instances outside the padded frustum.
- Renders with real instances confirmed in FStorm and Corona (V-Ray pending,
  same instancing path).

### MAXScript gotchas hit (documented for contributors)
- `off` and `where` are reserved words — invalid as variable/parameter names.
- Assigning `.count` on an array of nodes triggers mapped property assignment
  (tries to set `.count` on each node) instead of resizing the array.
- File-level variables are file-local: every module must declare
  `global MaxScatter` explicitly.
- Creating helper scene nodes from inside a scripted plugin's own creation
  context (`on attachedToNode`) can yield empty snapshots — build shared
  meshes from the pipeline instead.

[Unreleased]: https://github.com/JuanMaldini/3d-max-scatter/commits/main
