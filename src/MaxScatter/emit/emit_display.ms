/*  MaxScatter -- emitter B (proxy display) + the world gizmo

    Proxy display: one node in the scene. The helper draws every item as a
    single cached TriMesh via getDisplayMesh -- Box / Cone / Point cloud, one
    toggle for all items -- and the REAL instances exist only between
    #preRender and #postRender. Scales far beyond real nodes, at the cost of
    interactive rendering (IPR won't re-fire callbacks).

    Gizmo: the scatter object itself displays as the text "MaxScatter" inside
    a containing rectangle (min 1 m wide), white. Built once from a temporary
    Text+Extrude node, then cached; getDisplayMesh only ever reads caches.

    Session cache only: placements are rebuilt on file open (#filePostOpen in
    pipeline.ms) from the persistent paramblocks.
*/

global MaxScatter

struct MaxScatter_EmitDisplay
(
    entries = #(),      -- per owner: #(nodeHandle, srcs, places, mesh, renderedRoots)
    gizmoM  = undefined,
    fallbackM = undefined,

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

    /*  SCENE-MUTATING (temp Text node): never call from getDisplayMesh.
        Called from regen and from object creation, where mutation is fine.  */
    fn buildGizmo =
    (
        -- also retry if a previous attempt cached an empty mesh (e.g. built
        -- from inside the plugin's own creation context)
        if gizmoM == undefined or gizmoM.numVerts == 0 do try
        (
            local w1m = try (units.decodeValue "1m") catch 100.0

            local tn = text text:"MaxScatter" size:(w1m * 0.18)
            addModifier tn (Extrude amount:(w1m * 0.002))
            local tm = snapshotAsMesh tn
            delete tn

            local verts = #(), faces = #()

            -- text verts, centered at the origin
            local mn = [1e9,1e9,1e9], mx = [-1e9,-1e9,-1e9]
            for v = 1 to tm.numVerts do
            (
                local p = getVert tm v
                mn.x = amin mn.x p.x; mn.y = amin mn.y p.y; mn.z = amin mn.z p.z
                mx.x = amax mx.x p.x; mx.y = amax mx.y p.y; mx.z = amax mx.z p.z
            )
            local ctr = (mn + mx) * 0.5
            for v = 1 to tm.numVerts do append verts ((getVert tm v) - ctr)
            for f = 1 to tm.numFaces do append faces (getFace tm f)
            free tm

            -- containing rectangle: min 1 m wide, padded around the text
            local tw = mx.x - mn.x, th = mx.y - mn.y
            local rw = 0.5 * (amax w1m (tw * 1.25))
            local rh = 0.5 * (amax (w1m * 0.3) (th * 2.2))
            local bar = w1m * 0.02, hz = w1m * 0.002
            this.addBox verts faces [-rw, rh - bar, -hz] [ rw,  rh,       hz]   -- top
            this.addBox verts faces [-rw, -rh,      -hz] [ rw, -rh + bar, hz]   -- bottom
            this.addBox verts faces [-rw, -rh,      -hz] [-rw + bar, rh,  hz]   -- left
            this.addBox verts faces [ rw - bar, -rh,-hz] [ rw,  rh,       hz]   -- right

            local msh = TriMesh()
            setMesh msh verts:verts faces:faces
            gizmoM = msh
        )
        catch ( if MaxScatter != undefined do MaxScatter.logErr "buildGizmo" (getCurrentException()) )
        gizmoM
    ),

    /* Read-only fallback for getDisplayMesh before the gizmo exists. */
    fn gizmo =
    (
        if gizmoM != undefined and gizmoM.numVerts > 0 then gizmoM
        else
        (
            if fallbackM == undefined do
            (
                local w = try (units.decodeValue "1m") catch 100.0
                local verts = #(), faces = #()
                this.addBox verts faces [-w*0.5, -w*0.15, 0] [w*0.5, w*0.15, w*0.01]
                fallbackM = TriMesh()
                setMesh fallbackM verts:verts faces:faces
            )
            fallbackM
        )
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
        render always materialises the full list.  */
    fn buildMesh srcs places prxMode pct pcPoints =
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
            local m  = places[k][1]
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
                    e[5] = MaxScatter.emitNodes.emit e[2] e[3] owner mode:1
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
