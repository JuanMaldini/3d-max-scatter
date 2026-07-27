/*  MaxScatter -- regeneration pipeline

    Everything that happens between "a parameter changed" and "the scene is
    up to date" lives here, OUTSIDE the plugin clause, so it hot-reloads
    without touching saved scenes. The plugin file stays a thin shell:
    paramblocks + rollouts + one call into this module.

    Also owns the session-level machinery: camera watchers (auto re-cull when
    the picked camera moves), render-time callbacks for emitter B, and the
    file-open rebuild.
*/

global MaxScatter
global MaxScatterObj_regen
global MaxScatter_rtRestyle
global MaxScatter_camWatch
global MaxScatter_rtPre
global MaxScatter_rtPost
global MaxScatter_postOpen

struct MaxScatter_Pipeline
(
    defXform = "0,0,0,0,0,360,1,0.9,1.1,1,1,1,1,1,1,0,0",

    fn strToPP s alignN:1.0 =
    (
        local v = for x in (filterString (s as string) ",") collect (x as float)
        if v.count < 17 do
            v = for x in (filterString this.defXform ",") collect (x as float)
        MaxScatter_PlaceParams alignN:alignN \
            rxMin:v[1] rxMax:v[2] ryMin:v[3] ryMax:v[4] rzMin:v[5] rzMax:v[6] \
            uniScale:(v[7] > 0.5) sMin:v[8] sMax:v[9] \
            sxMin:v[10] sxMax:v[11] syMin:v[12] syMax:v[13] szMin:v[14] szMax:v[15] \
            zoMin:v[16] zoMax:v[17]
    ),

    fn ppToStr pp =
    (
        (pp.rxMin as string) + "," + (pp.rxMax as string) + "," + \
        (pp.ryMin as string) + "," + (pp.ryMax as string) + "," + \
        (pp.rzMin as string) + "," + (pp.rzMax as string) + "," + \
        (if pp.uniScale then "1" else "0") + "," + \
        (pp.sMin  as string) + "," + (pp.sMax  as string) + "," + \
        (pp.sxMin as string) + "," + (pp.sxMax as string) + "," + \
        (pp.syMin as string) + "," + (pp.syMax as string) + "," + \
        (pp.szMin as string) + "," + (pp.szMax as string) + "," + \
        (pp.zoMin as string) + "," + (pp.zoMax as string)
    ),

    /* p is the plugin instance. Returns the number of items placed. */
    fn regen p =
    (
        local made = 0
        try if MaxScatter != undefined do
        (
            local deps = refs.dependentNodes p
            local owner = if deps.count > 0 then deps[1] else undefined
            if isValidNode owner do
            (
                MaxScatter.emitDisplay.buildGizmo()   -- no-op once cached
                local srcs = #(), wts = #(), pps = #()
                for i = 1 to p.srcNodes.count do
                    if isValidNode p.srcNodes[i] do
                    (
                        append srcs p.srcNodes[i]
                        append wts (if i <= p.srcWeights.count then p.srcWeights[i] else 1.0)
                        local xs = if i <= p.srcXforms.count then p.srcXforms[i] else ""
                        append pps (this.strToPP xs alignN:p.alignN)
                    )
                local surfs = for s in p.surfNodes    where isValidNode s collect s
                local paths = for s in p.pathSplines  where isValidNode s collect s
                local onSpline = p.distMode == 2

                undo "MaxScatter" on
                (
                    if srcs.count == 0 or (not onSpline and surfs.count == 0) \
                        or (onSpline and paths.count == 0) then
                    (
                        MaxScatter.emitNodes.clear owner
                        MaxScatter.emitDisplay.dropEntry owner.inode.handle
                    )
                    else
                    (
                        MaxScatter.rng.reseed p.seedVal

                        -- density means per-area on surfaces, per-length on paths
                        local n = if not p.useDensity then p.numItems
                            else if onSpline then
                                (amax 1 (((MaxScatter.sampling.splineLengthMany paths) * p.density) as integer))
                            else
                                (amax 1 (((MaxScatter.sampling.surfaceAreaMany surfs) * p.density) as integer))

                        local totalW = 0.0
                        for w in wts do totalW += w

                        local inclPolys = MaxScatter.filters.shapePolys \
                            (for s in p.inclSplines where isValidNode s collect s)
                        local exclPolys = MaxScatter.filters.shapePolys \
                            (for s in p.exclSplines where isValidNode s collect s)

                        local dmap = undefined
                        if not onSpline and p.densityMap != undefined do
                            dmap = try (renderMap p.densityMap size:[256,256] filter:true) catch undefined

                        -- camera culling prep (re-baked automatically by the cam watcher)
                        local camInv = undefined, tHalf = 0.0, tVert = 0.0
                        if isValidNode p.camNode do
                        (
                            camInv = inverse p.camNode.transform
                            local fovH = (try (p.camNode.fov) catch 45.0) + p.fovPad
                            fovH = amax 1.0 (amin 175.0 fovH)
                            tHalf = tan (fovH / 2.0)
                            tVert = tHalf * (renderHeight as float / renderWidth)
                        )

                        local samples = if onSpline then
                                MaxScatter.sampling.sampleSplines paths n p.pathSpread
                            else
                                MaxScatter.sampling.sampleSurfaces surfs n

                        local places = #()
                        if totalW > 0.0 do
                        (
                            local span = amax 1.0 totalW
                            for i = 1 to samples.count do
                            (
                                local sp = samples[i][1]
                                local keep = true

                                if not onSpline and p.useSlope do
                                (
                                    local a = MaxScatter.filters.slopeDeg samples[i][2]
                                    keep = a >= p.slopeMin and a <= p.slopeMax
                                )
                                if keep and p.useAlt do
                                    keep = sp.z >= p.altMin and sp.z <= p.altMax

                                if keep and camInv != undefined do
                                (
                                    local pl = sp * camInv
                                    local d = -pl.z
                                    if d < -p.backDist then keep = false
                                    else if p.useFar and d > p.farDist then keep = false
                                    else if d > 0.0 do
                                        keep = (abs pl.x) <= d * tHalf and (abs pl.y) <= d * tVert
                                )

                                if keep and inclPolys.count > 0 do
                                    keep = MaxScatter.filters.inAnyPoly sp inclPolys
                                if keep and exclPolys.count > 0 do
                                    keep = not (MaxScatter.filters.inAnyPoly sp exclPolys)

                                if keep and dmap != undefined and samples[i][3] != undefined do
                                (
                                    local uv = samples[i][3] * p.mapTile
                                    local u = mod uv.x 1.0; if u < 0.0 do u += 1.0
                                    local vv = mod uv.y 1.0; if vv < 0.0 do vv += 1.0
                                    local px = getPixels dmap [int (u * 255), int ((1.0 - vv) * 255)] 1
                                    local lum = (px[1].r + px[1].g + px[1].b) / 765.0
                                    if p.mapGamma != 1.0 do lum = lum ^ p.mapGamma
                                    if p.mapInvert do lum = 1.0 - lum
                                    keep = (random 0.0 1.0) <= (1.0 - p.mapAmount + lum * p.mapAmount)
                                )

                                if keep do
                                (
                                    -- appearance probability: sums under 1 leave empty
                                    -- ground, over 1 they act as relative weights
                                    local r = random 0.0 span
                                    local idx = 0
                                    local acc = 0.0
                                    for k = 1 to wts.count do
                                    (
                                        acc += wts[k]
                                        if acc >= r do ( idx = k; exit )
                                    )
                                    if idx > 0 do
                                    (
                                        local tang = if samples[i].count >= 4 then samples[i][4] else undefined
                                        local m = MaxScatter.transform.placement sp samples[i][2] pps[idx] \
                                            tangent:tang alignPath:(onSpline and p.alignPath)
                                        append places #(m, idx)
                                    )
                                )
                            )
                        )
                        if dmap != undefined do ( try (close dmap) catch() )

                        if p.emitMode == 2 then
                        (
                            -- emitter B: proxy mesh in viewport, real nodes only at render
                            MaxScatter.emitNodes.clear owner
                            MaxScatter.emitDisplay.buildGizmo()
                            local msh = MaxScatter.emitDisplay.buildMesh srcs places \
                                p.prxMode p.dispPct p.pcPoints
                            MaxScatter.emitDisplay.setEntry owner.inode.handle srcs places msh
                            p.rtTick += 1   -- pb change -> display invalidate
                            made = places.count
                        )
                        else
                        (
                            MaxScatter.emitDisplay.dropEntry owner.inode.handle
                            made = (MaxScatter.emitNodes.emit srcs places owner mode:p.dispMode).count
                        )
                    )
                )
            )
        )
        catch
        (
            if MaxScatter != undefined do
                MaxScatter.logErr "regen" (getCurrentException())
        )
        made
    )
)

MaxScatter.pipeline = MaxScatter_Pipeline()

/* Thin, stable entry point the plugin calls. */
fn MaxScatterObj_regen p =
(
    if MaxScatter != undefined and MaxScatter.pipeline != undefined then
        MaxScatter.pipeline.regen p
    else 0
)

/*  Proxy display style changed (mode / % / point density): rebuild the mesh
    from the cached placements, no resampling.  */
fn MaxScatter_rtRestyle p =
(
    try
    (
        local deps = refs.dependentNodes p
        if deps.count > 0 and isValidNode deps[1] do
        (
            local h = deps[1].inode.handle
            local i = MaxScatter.emitDisplay.findEntry h
            if i > 0 then
            (
                local e = MaxScatter.emitDisplay.entries[i]
                e[4] = MaxScatter.emitDisplay.buildMesh e[2] e[3] p.prxMode p.dispPct p.pcPoints
                p.rtTick += 1
            )
            else MaxScatterObj_regen p   -- no cache yet (fresh session)
        )
    )
    catch ( if MaxScatter != undefined do MaxScatter.logErr "rtRestyle" (getCurrentException()) )
)

/*  Auto re-cull: one change handler per camera in use; moving the camera
    regenerates every scatter that picked it.  */
fn MaxScatter_camWatch =
(
    deleteAllChangeHandlers id:#MaxScatterCamW
    local cams = #()
    if (classOf MaxScatterObj) != undefined do
        for pb in (getClassInstances MaxScatterObj) where (isValidNode pb.camNode) do
            appendIfUnique cams pb.camNode
    for cam in cams do
        when transform cam changes id:#MaxScatterCamW c do
        (
            for pb in (getClassInstances MaxScatterObj) where pb.camNode == c do
                MaxScatterObj_regen pb
        )
    ok
)

fn MaxScatter_rtPre  = ( try (MaxScatter.emitDisplay.renderStart()) catch (MaxScatter.logErr "rtPre"  (getCurrentException())) )
fn MaxScatter_rtPost = ( try (MaxScatter.emitDisplay.renderEnd())   catch (MaxScatter.logErr "rtPost" (getCurrentException())) )

/* On file open: rebuild emitter-B caches from the persisted params, rewire watchers. */
fn MaxScatter_postOpen =
(
    try
    (
        if (classOf MaxScatterObj) != undefined do
            for pb in (getClassInstances MaxScatterObj) where pb.emitMode == 2 do
                MaxScatterObj_regen pb
        MaxScatter_camWatch()
    )
    catch ( MaxScatter.logErr "postOpen" (getCurrentException()) )
)

callbacks.removeScripts id:#MaxScatterRT
callbacks.addScript #preRender    "MaxScatter_rtPre()"   id:#MaxScatterRT
callbacks.addScript #postRender   "MaxScatter_rtPost()"  id:#MaxScatterRT
callbacks.addScript #filePostOpen "MaxScatter_postOpen()" id:#MaxScatterRT
