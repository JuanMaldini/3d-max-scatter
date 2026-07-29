# MaxScatter

Open source scattering tool for Autodesk 3ds Max.

> **Status: v1.0.0.** The core pipeline, UI and packaging are in place. See
> [the roadmap](#roadmap) for what is still open.

## Requirements

3ds Max 2024–2027. MaxScatter is pure MAXScript with no SDK or Qt binding, so
one copy serves every release; the only version-dependent code is the main-menu
entry, which uses `menuMan` on 2024 and the `#cuiRegisterMenus` callback system
that replaced it on 2025+ (see `src/MaxScatter/ui/menu.ms`).

## Install

**Users** — download the `.mzp` from [Releases](https://github.com/JuanMaldini/3d-max-scatter/releases)
and drag it into a 3ds Max viewport.

**From source** — junction the repo into Max's user scripts folder so `git pull`
updates the installed plugin:

```powershell
git clone https://github.com/JuanMaldini/3d-max-scatter.git
cd 3d-max-scatter
powershell -ExecutionPolicy Bypass -File build\dev_link.ps1
```

By default this links into **every** 3ds Max profile it finds on the machine.
Pass `-MaxVersion 2027` (or `-MaxVersion 2024,2027`) to narrow it, or `-Remove`
to uninstall.

## Usage

MaxScatter is a scene object: create it from **Create > Helpers > MaxScatter**
(or the toolbar button, **Customize UI > Toolbars**, category MaxScatter), then
edit it in the **Modify panel** like any native object. Parameters persist in
the .max file.

Add source objects — each has an appearance probability 0–1 per scattered
point (probabilities summing under 1 leave the rest empty; over 1 they act as
relative weights) — and one or more surfaces. Everything regenerates
automatically on every change; there is no Update button by design.

- **Distribution**: Surface mode (area-weighted over meshes) or Spline mode
  (along paths, with lateral Spread and align-to-path). Sources can be single
  meshes, groups or hierarchies — a group scatters as one unit.
- **Transform** edits the source selected in the Sources list: rotation XYZ
  ranges, uniform or per-axis scale, Z offset.
- **Limits**: slope (degrees) and altitude (world Z).
- **Include / Exclude splines**: closed splines define areas (XY projection).
- **Density map**: any texture; luminance drives density *and* item size, with
  Amount / Invert / Gamma / Tile / Scale. Amount and Scale are independent, so
  Amount 0 + Scale 1 varies size without changing the count — a soft gradient
  reads far better as size falloff than as thinning. The surface needs UVs.
- **Camera**: frustum culling with FOV padding, behind-camera margin and an
  optional far limit. Re-culls automatically when the camera moves.
- **Display / emitters**:
  - *Instances* (default): real nodes; Full / Box / Wire box views; renders
    everywhere including IPR. **Bake** detaches the instances.
  - *Proxy (render-time)*: one display mesh — Box / Cone / Point cloud with a
    points-per-item density and Display % thinning; the real instances exist
    only while a frame renders. Scales far beyond real nodes; no IPR.
- The scatter object shows in the world as the text **MaxScatter** inside a
  white rectangle; click it to edit everything in the Modify panel.

## Renderer compatibility

Instances are native Max nodes, so they render in **every engine** — V-Ray,
Corona, FStorm, Arnold, Scanline — including IPR, and export to any format.
Materials come from the source objects. Verified live in FStorm and Corona.
The planned display-mesh emitter (v0.2) will trade IPR compatibility for
viewport point-cloud modes; the current emitter stays the default.

## Architecture

The core is pure: it takes geometry and parameters and returns a list of
placement matrices without touching the scene. That makes it testable without a
scene, and lets the emitter be swapped without rewriting anything.

```
UI (rollouts) → params
                  ↓
   core: sample() → filter() → transform() → [ {matrix3, sourceIdx} ]
                  ↓
   emitter (interchangeable)
   ├─ emit_nodes    real Max instances        (default)
   └─ emit_display  getDisplayMesh + render-time materialisation  (planned)
```

Two emitters exist because they have very different ceilings. Real instances
render in every engine including IPR, export cleanly, and get undo and per-item
selection for free — but the scene graph node count is the wall, and a
viewport-only `Display %` is impossible (a hidden object in Max does not render,
so hiding a subset would change the render). The display-mesh emitter draws all
items as one cached mesh and materialises real instances in a `#preRender`
callback, which unlocks every previz mode at the cost of interactive rendering.

## Development

```powershell
powershell -ExecutionPolicy Bypass -File build\dev_link.ps1
```

Bind `build\dev_reload.ms` to a hotkey to reload all modules and reopen the UI
in about a second, without restarting Max.

Modules load through `src/MaxScatter/init.ms` in dependency order. Note that
MAXScript file-level variables are local to their file, so every module that
touches the namespace declares `global MaxScatter` explicitly — without it the
reference silently binds to a file-local `undefined`.

## Roadmap

- [x] **0.1-a** — modular bootstrap, scene object with persistent paramblocks
      (Modify panel), surface scatter by count or density, seed, real instances
      with node reuse, undo
- [x] **0.1-b** — multiple sources with appearance probability, multiple
      surfaces, per-source transforms (rotation XYZ, uniform/per-axis scale,
      Z offset)
- [x] **0.1-c** — include/exclude splines, slope and altitude limits
- [x] **0.1-d** — density map with Amount / Invert / Gamma / Tile
- [x] **0.1-f** — camera frustum culling (FOV pad, behind margin, far limit),
      display modes Full / Box / Wire box, bake
- [x] **0.1-b2** — group/hierarchy sources (VRayProxy also works: any
      GeometryClass node is instanceable)
- [x] **0.1-g** — spline-as-path distribution, auto re-cull on camera move
- [x] **0.2** — proxy emitter: Box / Cone / Point cloud previews with
      Display %, materialised at render time; world gizmo
- [x] **0.1-e** — `.mzp` packaging (`build.bat` → `dist/`, drag & drop install)
- [ ] **1.0** — collision avoidance, export, docs, CI

## License

[MIT](LICENSE)
