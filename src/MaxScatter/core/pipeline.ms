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
global MaxScatterObj      -- the plugin class: declared so when-blocks compile
                          -- at cold start, before plugin/scatter_helper.ms loads
global MaxScatterObj_regen
global MaxScatter_rtRestyle
global MaxScatter_camWatch
global MaxScatter_selfWatch
global MaxScatter_queueCleanup
global MaxScatter_rtPre
global MaxScatter_rtPost
global MaxScatter_postOpen
global MaxScatter_preDel

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

    /*  The hidden container the instances live under -- NOT the helper node,
        so the icon moves freely without dragging the whole scatter.  */
    fn ensureHolder p owner =
    (
        local h = p.itemHolder
        if not (isValidNode h) do
        (
            h = Point name:(uniqueName (owner.name + "_items")) size:1 cross:false box:false
            h.transform = matrix3 1
            h.isHidden = true
            try ((MaxScatter.ensureLayer()).addNode h) catch()
            p.itemHolder = h
        )
        h
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
                    local holder = this.ensureHolder p owner

                    if srcs.count == 0 or (not onSpline and surfs.count == 0) \
                        or (onSpline and paths.count == 0) then
                    (
                        MaxScatter.emitNodes.clear holder
                        MaxScatter.emitDisplay.dropEntry owner.inode.handle
                    )
                    else
                    (
                        MaxScatter.rng.reseed p.seedVal

                        local popt = MaxScatter_PathOpts \
                            even:p.pathEven spacing:p.pathSpacing \
                            trimS:(p.trimStart / 100.0) trimE:(p.trimEnd / 100.0) \
                            offX:p.pathOffX offZ:p.pathOffZ \
                            stagger:p.pathStagger stagDist:p.pathStagDist \
                            roll:p.pathRoll bank:p.pathBank \
                            scaleStart:p.pathScaleS scaleEnd:p.pathScaleE \
                            scaleLat:p.pathScaleLat

                        -- density means per-area on surfaces, per-length on paths
                        local n = if not p.useDensity then p.numItems
                            else if onSpline then
                                (amax 1 (((MaxScatter.sampling.splineLengthMany paths \
                                    trimS:popt.trimS trimE:popt.trimE) * p.density) as integer))
                            else
                                (amax 1 (((MaxScatter.sampling.surfaceAreaMany surfs) * p.density) as integer))

                        local totalW = 0.0
                        for w in wts do totalW += w

                        local inclCurves = MaxScatter.filters.shapeCurves \
                            (for s in p.inclSplines where isValidNode s collect s)
                        local exclCurves = MaxScatter.filters.shapeCurves \
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
                                MaxScatter.sampling.sampleSplines paths n p.pathSpread opt:popt
                            else
                                MaxScatter.sampling.sampleSurfaces surfs n

                        /*  Per-sample RNG stream, seeded from a fixed stream of
                            its own (not from the sampling draws): sample i keeps
                            its source pick, rotation and scale no matter what
                            filters, maps or other samples do -- conditional
                            draws stopped shifting the whole layout. Only the
                            seed (or the point positions themselves) reshuffle.  */
                        MaxScatter.rng.reseed (p.seedVal + 1)
                        local sseeds = #()
                        sseeds.count = samples.count
                        for i = 1 to samples.count do sseeds[i] = random 1 0x3FFFFFF

                        local places = #()
                        if totalW > 0.0 do
                        (
                            local span = amax 1.0 totalW
                            for i = 1 to samples.count do
                            (
                                MaxScatter.rng.reseed sseeds[i]
                                /*  Drawn unconditionally and always in this
                                    order: a conditional draw would shift every
                                    later draw of the sample, so toggling a map
                                    or a falloff would reshuffle the layout.  */
                                local rMap  = random 0.0 1.0
                                local rMask = random 0.0 1.0

                                local sp = samples[i][1]
                                local keep = true
                                local scaleMul = if samples[i].count >= 5 then samples[i][5] else 1.0

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

                                /*  Spline masks. 0 culls outright; inside the
                                    falloff band the value drives how much the
                                    item thins out and shrinks, so a stroke can
                                    fade a scatter instead of cutting it.  */
                                local mi = 1.0, me = 1.0
                                if keep and inclCurves.count > 0 do
                                (
                                    mi = MaxScatter.filters.inclMask sp inclCurves p.inclDist p.inclFall
                                    if mi <= 0.0 do keep = false
                                )
                                if keep and exclCurves.count > 0 do
                                (
                                    me = MaxScatter.filters.exclMask sp exclCurves p.exclDist p.exclFall
                                    if me <= 0.0 do keep = false
                                )
                                if keep do
                                (
                                    local kp = (1.0 - p.inclThin * (1.0 - mi)) * \
                                               (1.0 - p.exclThin * (1.0 - me))
                                    if kp < 1.0 do keep = rMask <= kp
                                    scaleMul *= (1.0 - p.inclScale * (1.0 - mi)) * \
                                                (1.0 - p.exclScale * (1.0 - me))
                                    -- a zero-scale matrix is degenerate: instances
                                    -- with one collapse normals and hit renderers
                                    if scaleMul < 0.001 do scaleMul = 0.001
                                )

                                if keep and dmap != undefined and samples[i][3] != undefined do
                                (
                                    local uv = samples[i][3] * p.mapTile
                                    local u = mod uv.x 1.0; if u < 0.0 do u += 1.0
                                    local vv = mod uv.y 1.0; if vv < 0.0 do vv += 1.0
                                    local px = getPixels dmap [int (u * 255), int ((1.0 - vv) * 255)] 1
                                    local lum = (px[1].r + px[1].g + px[1].b) / 765.0
                                    if p.mapGamma != 1.0 do lum = lum ^ p.mapGamma
                                    if p.mapInvert do lum = 1.0 - lum
                                    keep = rMap <= (1.0 - p.mapAmount + lum * p.mapAmount)
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
                                        local roll = if samples[i].count >= 6 then samples[i][6] else 0.0
                                        local m = MaxScatter.transform.placement sp samples[i][2] pps[idx] \
                                            tangent:tang alignPath:(onSpline and p.alignPath) \
                                            scaleMul:scaleMul rollDeg:roll
                                        append places #(m, idx)
                                    )
                                )
                            )
                        )
                        if dmap != undefined do ( try (close dmap) catch() )

                        if p.emitMode == 2 then
                        (
                            -- emitter B: proxy mesh in viewport, real nodes only at
                            -- render. Mesh is helper-LOCAL so the icon can be moved;
                            -- the self-watcher rebuilds it after a move.
                            MaxScatter.emitNodes.clear holder
                            local msh = MaxScatter.emitDisplay.buildMesh srcs places \
                                p.prxMode p.dispPct p.pcPoints ownerInv:(inverse owner.transform)
                            MaxScatter.emitDisplay.setEntry owner.inode.handle srcs places msh
                            p.rtTick += 1   -- pb change -> display invalidate
                            made = places.count
                        )
                        else
                        (
                            MaxScatter.emitDisplay.dropEntry owner.inode.handle
                            made = (MaxScatter.emitNodes.emit srcs places holder mode:p.dispMode).count
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

/*  Regen throttle -- the anti-freeze that still tracks a drag.

    Param set handlers and the camera watcher fire on EVERY tick of a spinner
    drag or camera move; regenerating each tick freezes Max. Handlers queue
    the instance here and a 150 ms UI timer batches the ticks -- but the timer
    is NOT restarted while running, so a continuous drag regenerates every
    150 ms (live feedback) instead of only after the last tick. Synchronous
    paths (render callbacks, file open) call MaxScatter.pipeline.regen
    directly.
*/
global MaxScatter_regenTimer
global MaxScatter_regenTick

fn MaxScatter_regenTick s e =
(
    MaxScatter_regenTimer.stop()
    local lst = MaxScatter.pendingRegen
    MaxScatter.pendingRegen = #()
    for p in lst do try (MaxScatter.pipeline.regen p) catch()

    -- deferred cleanup: nodes cannot be deleted from inside `on deleted`
    local cl = MaxScatter.pendingCleanup
    MaxScatter.pendingCleanup = #()
    for h in cl where isValidNode h do try
    (
        MaxScatter.emitNodes.clear h
        delete h
    )
    catch()
    -- drop proxy caches whose scatter no longer exists
    local ent = MaxScatter.emitDisplay.entries
    for i = ent.count to 1 by -1 do
        if not (isValidNode (maxOps.getNodeByHandle ent[i][1])) do deleteItem ent i

    try (MaxScatter_selfWatch()) catch()   -- keep icon watchers in sync
    ok
)

/* Called by the plugin's `on deleted`; the timer does the actual deleting. */
fn MaxScatter_queueCleanup h =
(
    if MaxScatter != undefined do
    (
        append MaxScatter.pendingCleanup h
        MaxScatter_regenTimer.stop()
        MaxScatter_regenTimer.start()
    )
    ok
)

if MaxScatter_regenTimer != undefined do
    try ( MaxScatter_regenTimer.stop(); dotNet.removeAllEventHandlers MaxScatter_regenTimer ) catch()
MaxScatter_regenTimer = dotNetObject "System.Windows.Forms.Timer"
MaxScatter_regenTimer.interval = 150
dotNet.addEventHandler MaxScatter_regenTimer "Tick" MaxScatter_regenTick

/* Thin, stable entry point the plugin calls: queue + start the timer. The
   timer is left running if already started, so drags update live (throttle,
   not debounce). */
fn MaxScatterObj_regen p =
(
    if MaxScatter != undefined and MaxScatter.pipeline != undefined do
    (
        appendIfUnique MaxScatter.pendingRegen p
        if not MaxScatter_regenTimer.Enabled do MaxScatter_regenTimer.start()
    )
    0
)

/*  ---- List editing + pick sessions ---------------------------------------

    Lives here rather than in the rollouts so every list rollout shares one
    implementation (and so it hot-reloads). Tabs are read and written whole:
    mutating p.srcNodes[i] in place does not write back through a paramblock,
    assigning the array does.
*/
global MaxScatter_pickBusy
global MaxScatter_getTab
global MaxScatter_addTo
global MaxScatter_removeAt
global MaxScatter_pickInto
global MaxScatter_refreshUI

MaxScatter_pickBusy = false

fn MaxScatter_getTab p what = case what of
(
    #sources:  ( for x in p.srcNodes    collect x )
    #surfaces: ( for x in p.surfNodes   collect x )
    #paths:    ( for x in p.pathSplines collect x )
    #include:  ( for x in p.inclSplines collect x )
    #exclude:  ( for x in p.exclSplines collect x )
    default:   #()
)

fn MaxScatter_addTo p what o =
(
    local a = MaxScatter_getTab p what
    append a o
    case what of
    (
        #sources:
        (
            p.srcNodes = a
            local w = for x in p.srcWeights collect x
            append w 1.0
            p.srcWeights = w
            local xf = for x in p.srcXforms collect x
            append xf MaxScatter.pipeline.defXform
            p.srcXforms = xf
        )
        #surfaces:
        (
            p.surfNodes = a
            -- follow what the user just loaded, but never fight an explicit
            -- choice: only switch when the other list is empty
            if p.pathSplines.count == 0 do p.distMode = 1
        )
        #paths:
        (
            p.pathSplines = a
            if p.surfNodes.count == 0 do p.distMode = 2
        )
        #include: ( p.inclSplines = a )
        #exclude: ( p.exclSplines = a )
    )
    ok
)

fn MaxScatter_removeAt p what idx =
(
    local a = MaxScatter_getTab p what
    if idx > 0 and idx <= a.count then
    (
        deleteItem a idx
        case what of
        (
            #sources:
            (
                p.srcNodes = a
                local w = for x in p.srcWeights collect x
                if idx <= w.count do deleteItem w idx
                p.srcWeights = w
                local xf = for x in p.srcXforms collect x
                if idx <= xf.count do deleteItem xf idx
                p.srcXforms = xf
            )
            #surfaces: ( p.surfNodes   = a )
            #paths:    ( p.pathSplines = a )
            #include:  ( p.inclSplines = a )
            #exclude:  ( p.exclSplines = a )
        )
        true
    )
    else false
)

/* Rollouts refresh themselves; missing ones (old scenes) are simply skipped. */
fn MaxScatter_refreshUI p =
(
    try ( p.rolSrc.refresh() )  catch()
    try ( p.rolMask.refresh() ) catch()
    ok
)

/*  Native pick-mode: the Add checkbutton stays lit while the session runs,
    every click adds and updates immediately, right-click or Esc ends it. The
    lit button is what tells sessions apart -- an invisible stale session is
    how a pick meant for Surfaces used to land in Scatter items.  */
fn MaxScatter_pickInto p what label filterFn btn allowDup:false =
(
    if MaxScatter_pickBusy then
    (
        try ( btn.checked = false ) catch()
        displayTempPrompt "MaxScatter: right-click or Esc to finish the current pick first" 4000
    )
    else
    (
        MaxScatter_pickBusy = true
        try ( btn.checked = true ) catch()
        local go = true, added = 0
        while go do
        (
            displayTempPrompt ("MaxScatter: pick " + label + \
                " -- every click adds, right-click or Esc finishes") 60000
            local o = pickObject filter:filterFn
            if o == undefined or not (isValidNode o) then go = false
            else if not allowDup and (findItem (MaxScatter_getTab p what) o) > 0 then
                displayTempPrompt ("MaxScatter: '" + o.name + "' is already in " + label) 4000
            else
            (
                MaxScatter_addTo p what o
                added += 1
                MaxScatter_refreshUI p
                MaxScatterObj_regen p   -- live: lists and viewport track every click
            )
        )
        try ( btn.checked = false ) catch()
        MaxScatter_pickBusy = false
        displayTempPrompt ("MaxScatter: " + added as string + " added to " + label) 3000
    )
    ok
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
                e[4] = MaxScatter.emitDisplay.buildMesh e[2] e[3] p.prxMode p.dispPct p.pcPoints \
                    ownerInv:(inverse deps[1].transform)
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

/*  Proxy scatters draw in helper-local space: when the ICON itself moves,
    rebuild the cached display mesh (debounced through the regen queue).  */
fn MaxScatter_selfWatch =
(
    deleteAllChangeHandlers id:#MaxScatterSelfW
    if (classOf MaxScatterObj) != undefined do
        for pb in (getClassInstances MaxScatterObj) where pb.emitMode == 2 do
        (
            local deps = refs.dependentNodes pb
            if deps.count > 0 and isValidNode deps[1] do
                when transform deps[1] changes id:#MaxScatterSelfW n do
                    MaxScatterObj_regen n.baseObject
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
        MaxScatter_selfWatch()
    )
    catch ( MaxScatter.logErr "postOpen" (getCurrentException()) )
)

/*  Deleting a scatter must take its hidden container along. The plugin's own
    `on deleted` fires too late (paramblock already detached), so this hooks
    the pre-delete notification instead and defers the actual delete to the
    debounce timer.  */
fn MaxScatter_preDel =
(
    try
    (
        local n = callbacks.notificationParam()
        if (classOf MaxScatterObj) != undefined and (classOf n.baseObject) == MaxScatterObj do
        (
            local h = n.baseObject.itemHolder
            if isValidNode h do MaxScatter_queueCleanup h
        )
    )
    catch()
)

callbacks.removeScripts id:#MaxScatterRT
callbacks.addScript #preRender     "MaxScatter_rtPre()"   id:#MaxScatterRT
callbacks.addScript #postRender    "MaxScatter_rtPost()"  id:#MaxScatterRT
callbacks.addScript #filePostOpen  "MaxScatter_postOpen()" id:#MaxScatterRT
callbacks.addScript #nodePreDelete "MaxScatter_preDel()"  id:#MaxScatterRT
