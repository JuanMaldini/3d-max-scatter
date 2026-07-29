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
- **Density map**: any texturemap; one luminance sample per point drives both
  keep probability (Amount) and item size (Scale), with Invert / Gamma / Tile.
  The two are independent: Amount 0 + Scale 1 varies size without changing the
  count, which is how a soft gradient gets an edge that fades instead of
  cutting. Same thin/shrink pair the include/exclude spline masks already had.
  Needs UVs on the surface.
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
- **Regen debounce**: param handlers and the camera watcher queue into a
  150 ms UI timer that collapses bursts into one regeneration — dragging a
  spinner or navigating a camera viewport no longer freezes Max (a 20-tick
  camera drag went from ~2.6 s of blocking regens to 5 ms of queueing).
- `build.bat` (repo root) packages `dist/MaxScatter.mzp` via
  `build/build_mzp.ps1`; version read from `core/ns.ms` and stamped into
  `PackageContents.xml`. The .mzp installs by viewport drag & drop, writes the
  startup stub and loads without restart.
- Dev logging to `(getDir #temp)\MaxScatter.log`, enabled only in dev sessions.
- `build/dev_link.ps1` junction installer (+ startup stub so saved scenes load
  the plugin class) and `build/dev_reload.ms` hot reload.
- MIT license.

### Fixed
- **Dragging the `.mzp` into a viewport did nothing at all.** `Compress-Archive`
  on Windows PowerShell 5.1 stores zip entry paths with BACKSLASH separators,
  which ZIP APPNOTE 4.4.17.1 forbids ("All slashes MUST be forward slashes").
  Max's .mzp extractor therefore saw one flat filename per entry
  (`Contents\scripts\MaxScatter\init.ms`) instead of a tree, found no
  `Contents\` to install from, and the drop silently did nothing.
  `build/build_mzp.ps1` now writes entries through `ZipArchive.CreateEntry`
  with normalised separators, and fails the build if any entry ever contains a
  backslash again.
- **Installing over a previous release copied zero files** and reported only
  "nothing was copied into ...". MAXScript's `copyFile` does not overwrite: with
  a destination that already exists it copies nothing and returns false. The
  installer called it directly, so only a first install into an empty folder
  ever worked — every upgrade failed. `install.ms` now clears each destination
  (read-only flag included) before copying, applies the same treatment to
  `PackageContents.xml` and the toolbar icons, which were never replaced either,
  and names the files it could not write instead of just counting zero.
- **Main menu missing on 3ds Max 2025-2027.** 2025 deleted `menuMan`; menus are
  now declared from a `#cuiRegisterMenus` callback that the host calls when it
  builds a menu configuration. The old imperative `menuMan` block silently
  threw into its own `catch`, so the installer reported success with no menu on
  the bar. `ui/menu.ms` now feature-detects `maxOps.GetICuiMenuMgr()` and takes
  the callback path on 2025+, the legacy path on 2024 and earlier. Because
  `scripts/startup/*.ms` runs *after* `#cuiRegisterMenus` has already fired, the
  first install of the session also asks the manager for one
  `LoadConfiguration` so the chain re-fires with our handler registered.
- The `.mzp` install popup reports the real menu and plugin-class state instead
  of claiming success unconditionally.

### Changed
- `build/dev_link.ps1` auto-detects every installed 3ds Max profile and links
  into all of them (2024 and 2027 side by side); `-MaxVersion` still narrows it
  to one or a list. It also replaces a copied `.mzp` install with the junction
  rather than failing, and `-Remove` cleans up both kinds.

### Verified
- Persistence: save / reset / reload keeps all params and instances; values
  keep driving the result after reload.
- Exclude spline: 0 instances inside the excluded circle.
- Node reuse: 1336/1350 nodes recycled on a seed change (138 ms @ 1500 pts).
- Camera culling: 0 instances outside the padded frustum.
- Renders with real instances confirmed in FStorm and Corona (V-Ray pending,
  same instancing path).

### MAXScript gotchas hit (documented for contributors)
- `copyFile` does not overwrite: it returns false when the destination exists,
  so a copy loop over an existing install silently copies nothing. Delete first.
- `off` and `where` are reserved words — invalid as variable/parameter names.
- Assigning `.count` on an array of nodes triggers mapped property assignment
  (tries to set `.count` on each node) instead of resizing the array.
- File-level variables are file-local: every module must declare
  `global MaxScatter` explicitly.
- Creating helper scene nodes from inside a scripted plugin's own creation
  context (`on attachedToNode`) can yield empty snapshots — build shared
  meshes from the pipeline instead.
- `when` handler bodies cannot capture outer locals: a name that only becomes
  a global later in the load order (the plugin class) must be pre-declared
  `global`, or the cold-start compile fails with "No outer local variable
  references permitted here".

[Unreleased]: https://github.com/JuanMaldini/3d-max-scatter/commits/main
