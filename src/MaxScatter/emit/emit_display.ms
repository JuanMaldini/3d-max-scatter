/*  MaxScatter -- emitter B (proxy display) + the world gizmo

    Proxy display: one node in the scene. The helper draws every item as a
    single cached TriMesh via getDisplayMesh -- Box / Cone / Point cloud, one
    toggle for all items -- and the REAL instances exist only between
    #preRender and #postRender. Scales far beyond real nodes, at the cost of
    interactive rendering (IPR won't re-fire callbacks).

    Gizmo: the scatter object itself displays as the text "MaxScatter" inside
    a containing rectangle, white. The geometry is BAKED (emit/gizmo_data.ms,
    regenerate with build/bake_gizmo.ms), so building it touches no scene node
    and getDisplayMesh can ask for it directly, at any point in the object's
    life. It used to be built from a temporary Text node on the first regen,
    which is why a freshly created helper drew a placeholder bar until some
    parameter changed.

    Session cache only: placements are rebuilt on file open (#filePostOpen in
    pipeline.ms) from the persistent paramblocks.
*/

global MaxScatter

struct MaxScatter_EmitDisplay
(
    entries = #(),      -- per owner: #(nodeHandle, srcs, places, mesh, renderedRoots)
    gizmoM  = undefined,
    gizmoW  = 1.0,      -- width of the cached gizmo, for icon-size scaling

    -- ---------------------------------------------------------------- entries

    fn findEntry h =
    (
        local f = 0
        for i = 1 to entries.count while f == 0 do
            if entries[i][1] == h do f = i
        f
    ),

    fn dropEntry h =
    (
        local i = this.findEntry h
        if i > 0 do deleteItem entries i
        ok
    ),

    fn setEntry h srcs places msh =
    (
        local i = this.findEntry h
        if i > 0 then ( entries[i][2] = srcs; entries[i][3] = places; entries[i][4] = msh )
        else append entries #(h, srcs, places, msh, undefined)
        ok
    ),

    fn meshFor h =
    (
        local i = this.findEntry h
        if i > 0 then entries[i][4] else undefined
    ),

    -- ------------------------------------------------------------------ gizmo

    /* Append one axis-aligned box to vert/face arrays. Returns nothing. */
    fn addBox verts faces mn mx =
    (
        local base = verts.count
        append verts [mn.x,mn.y,mn.z]; append verts [mx.x,mn.y,mn.z]
        append verts [mx.x,mx.y,mn.z]; append verts [mn.x,mx.y,mn.z]
        append verts [mn.x,mn.y,mx.z]; append verts [mx.x,mn.y,mx.z]
        append verts [mx.x,mx.y,mx.z]; append verts [mn.x,mx.y,mx.z]
        for f in #([1,3,2],[1,4,3],[5,6,7],[5,7,8],[1,2,6],[1,6,5],[2,3,7],[2,7,6],[3,4,8],[3,8,7],[4,1,5],[4,5,8]) do
            append faces (f + [base,base,base])
        ok
    ),

    /*  The world sign, normalized to 1.0 wide. Pure -- no scene node, no font
        lookup -- so getDisplayMesh may call it, which is what makes the sign
        appear the instant a helper is created.

        The bare-rectangle branch only runs if gizmo_data.ms failed to load:
        getDisplayMesh must never return undefined, and an unreadable icon is
        a better failure than an object with no visible presence at all.  */
    fn gizmo =
    (
        if gizmoM == undefined or gizmoM.numVerts == 0 do
        (
            local verts = #(), faces = #()
            local d = try (MaxScatter.gizmoData) catch undefined
            if d != undefined then ( verts = d.verts; faces = d.faces; gizmoW = d.width )
            else
            (
                this.addBox verts faces [-0.5, -0.15, 0.0] [0.5, 0.15, 0.01]
                gizmoW = 1.0
                MaxScatter.log "gizmo_data.ms not loaded -- drawing a plain rectangle"
            )
            gizmoM = TriMesh()
            setMesh gizmoM verts:verts faces:faces
        )
        gizmoM
    ),

    -- ----------------------------------------------------------- proxy meshes

    /* Local-space surface points of one source unit, for the point cloud. */
    fn localSurfacePoints src count =
    (
        local geo = for n in (MaxScatter.emitNodes.subtree src) \
            where isKindOf n GeometryClass collect n
        local pts = MaxScatter.sampling.sampleSurfaces geo count
        local inv = inverse src.transform
        for t in pts collect (t[1] * inv)
    ),

    /*  The proxy mesh. prxMode: 1 Box, 2 Cone, 3 Point cloud (pcPoints per
        item, like Corona's previz density). pct thins the DISPLAY only; the
        render always materialises the full list. ownerInv converts world
        placements into the helper's local space, so the icon stays movable.  */
    fn buildMesh srcs places prxMode pct pcPoints ownerInv:(matrix3 1) =
    (
        local bbs = for s in srcs collect (MaxScatter.emitNodes.unitLocalBBox s)
        local pcl = if prxMode == 3 then
            (for s in srcs collect (this.localSurfacePoints s (amax 1 pcPoints))) else undefined

        local verts = #(), faces = #()
        local step = if pct >= 100 then 1.0 else (100.0 / (amax 1.0 (pct as float)))
        local i = 1.0
        while i <= places.count do
        (
            local k = i as integer
            local m  = places[k][1] * ownerInv   -- world -> helper local
            local si = places[k][2]
            local a = bbs[si][1], b = bbs[si][2]

            case prxMode of
            (
                2:  -- cone: apex up, 8-side base at the bbox floor
                (
                    local base = verts.count
                    local cx = (a.x + b.x) * 0.5, cy = (a.y + b.y) * 0.5
                    local rx = (b.x - a.x) * 0.5, ry = (b.y - a.y) * 0.5
                    for s = 0 to 7 do
                        append verts ([cx + rx * (cos (s * 45.0)), cy + ry * (sin (s * 45.0)), a.z] * m)
                    append verts ([cx, cy, b.z] * m)   -- apex (9)
                    append verts ([cx, cy, a.z] * m)   -- base centre (10)
                    for s = 1 to 8 do
                    (
                        local s2 = if s == 8 then 1 else s + 1
                        append faces ([s, s2, 9]  + [base,base,base])
                        append faces ([s2, s, 10] + [base,base,base])
                    )
                )
                3:  -- point cloud: one tiny triangle per sampled surface point
                (
                    local e = (distance a b) * 0.008
                    for p in pcl[si] do
                    (
                        local base = verts.count
                        append verts (p * m)
                        append verts ((p + [e, 0, e * 0.5]) * m)
                        append verts ((p + [0, e, e]) * m)
                        append faces ([1,2,3] + [base,base,base])
                    )
                )
                default: this.addBox verts faces a b   -- box (in unit space)...
            )

            -- box mode needs the transform applied (addBox emits untransformed)
            if prxMode != 2 and prxMode != 3 do
            (
                local nv = verts.count
                for v = nv - 7 to nv do verts[v] = verts[v] * m
            )

            i += step
        )

        local msh = TriMesh()
        if verts.count > 0 do setMesh msh verts:verts faces:faces
        msh
    ),

    -- ------------------------------------------------------------ render time

    /* Materialise real units for the frame, then remove them afterwards. */
    fn renderStart =
    (
        with undo off
            for e in entries do
            (
                local owner = maxOps.getNodeByHandle e[1]
                if isValidNode owner and e[3] != undefined do
                (
                    -- parent to the hidden container, not the icon
                    local h = try (owner.baseObject.itemHolder) catch undefined
                    if not (isValidNode h) do h = owner
                    e[5] = MaxScatter.emitNodes.emit e[2] e[3] h mode:1
                )
            )
        ok
    ),

    fn renderEnd =
    (
        with undo off
            for e in entries do
            (
                if e[5] != undefined do
                (
                    local all = #()
                    for n in e[5] where isValidNode n do
                        join all (MaxScatter.emitNodes.subtree n)
                    if all.count > 0 do delete all
                    e[5] = undefined
                )
            )
        ok
    )
)

MaxScatter.emitDisplay = MaxScatter_EmitDisplay()
