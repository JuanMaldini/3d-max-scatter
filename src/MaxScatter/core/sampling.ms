/*  MaxScatter -- surface sampling

    Pure: takes a node, returns sample points. Never touches the scene.
    Points are area-weighted so triangle density does not bias the result.

    Returns an array of #(position, normal), both in world space.
*/

global MaxScatter

/*  Sweep-style options for scattering along a path. Defaults reproduce the
    plain random-by-length behaviour, so an untouched scatter is unaffected.  */
struct MaxScatter_PathOpts
(
    even       = false,   -- space by distance instead of by count
    spacing    = 100.0,   -- world units between items when even
    trimS      = 0.0,     -- usable run, 0..1 of the curve length
    trimE      = 1.0,
    offX       = 0.0,     -- constant lateral offset from the axis
    offZ       = 0.0,     -- constant vertical offset
    stagger    = false,   -- alternate sides, like fence posts
    stagDist   = 0.0,
    roll       = 0.0,     -- fixed spin around the path axis, degrees
    bank       = 0.0,     -- 0..1, lean into the curve
    scaleStart = 1.0,     -- scale ramp from the start to the end of the run
    scaleEnd   = 1.0,
    scaleLat   = 0.0      -- 0..1, shrink with distance from the axis
)

struct MaxScatter_Sampling
(
    /* Total world-space surface area of a node, used to turn density into a count. */
    fn surfaceArea node =
    (
        local total = 0.0
        if isValidNode node do
        (
            local tm = snapshotAsMesh node
            for i = 1 to tm.numFaces do
            (
                local f  = getFace tm i
                local v1 = getVert tm f.x
                total += 0.5 * length (cross ((getVert tm f.y) - v1) ((getVert tm f.z) - v1))
            )
            free tm
        )
        total
    ),

    /* Combined area of several nodes -- used to turn density into a count. */
    fn surfaceAreaMany nodes =
    (
        local total = 0.0
        for n in nodes where isValidNode n do total += this.surfaceArea n
        total
    ),

    fn sampleSurface node count =
    (
        local out = #()
        if count > 0 and isValidNode node do
        (
            local tm = snapshotAsMesh node
            local nf = tm.numFaces
            if nf > 0 do
            (
                -- cumulative area table for weighted face picking
                local cum = #()
                cum.count = nf
                local total = 0.0
                for i = 1 to nf do
                (
                    local f  = getFace tm i
                    local v1 = getVert tm f.x
                    total += 0.5 * length (cross ((getVert tm f.y) - v1) ((getVert tm f.z) - v1))
                    cum[i] = total
                )

                if total > 0.0 do
                (
                    local hasUV = (getNumTVerts tm) > 0
                    out.count = count
                    for k = 1 to count do
                    (
                        local r = random 0.0 total

                        -- binary search for the first face whose cumulative area reaches r
                        local lo = 1, hi = nf, idx = nf
                        while lo <= hi do
                        (
                            local mid = (lo + hi) / 2
                            if cum[mid] >= r then ( idx = mid; hi = mid - 1 ) else lo = mid + 1
                        )

                        local f  = getFace tm idx
                        local v1 = getVert tm f.x
                        local v2 = getVert tm f.y
                        local v3 = getVert tm f.z

                        -- uniform point in triangle; the same barycentrics give the UV for free
                        local r1 = sqrt (random 0.0 1.0)
                        local r2 = random 0.0 1.0
                        local ba = 1.0 - r1
                        local bb = r1 * (1.0 - r2)
                        local bc = r1 * r2
                        local p  = v1 * ba + v2 * bb + v3 * bc

                        local uv = undefined
                        if hasUV do
                        (
                            local tf = getTVFace tm idx
                            uv = (getTVert tm tf.x) * ba + (getTVert tm tf.y) * bb + (getTVert tm tf.z) * bc
                        )

                        out[k] = #(p, (getFaceNormal tm idx), uv)
                    )
                )
            )
            free tm
        )
        out
    ),

    /*  Spline paths: resolve shapes into (node, splineIdx, length) triplets,
        converting parametric shapes on temp copies. Returns
        #(items, tempNodes, totalLength); caller must delete tempNodes.  */
    fn splineItems shapes =
    (
        local items = #(), temps = #(), total = 0.0
        for sh in shapes where isValidNode sh do
        (
            local src = sh
            local ok = (try (numSplines src) catch 0) > 0
            if not ok do
            (
                local tmp = copy sh
                convertToSplineShape tmp
                append temps tmp
                src = tmp
                ok = (try (numSplines src) catch 0) > 0
            )
            if ok do
                for s = 1 to (numSplines src) do
                (
                    local len = curveLength src s
                    if len > 0.0 do ( append items #(src, s, len); total += len )
                )
        )
        #(items, temps, total)
    ),

    fn splineLengthMany shapes trimS:0.0 trimE:1.0 =
    (
        local si = this.splineItems shapes
        if si[2].count > 0 do delete si[2]
        si[3] * (amax 0.0 (trimE - trimS))
    ),

    /*  Sampling along spline paths, Sweep-style. Tuple layout:
            #(pos, normal, uv, tangent, scaleMul, rollDeg)
        Normal is world up (the placement frame comes from the tangent);
        scaleMul and rollDeg carry the per-item results of the path options
        so the transform module stays free of path knowledge.

        opt is a MaxScatter_PathOpts; count is ignored when opt.even is on,
        because spacing then decides how many fit.  */
    fn sampleSplines shapes count spread opt:undefined =
    (
        if opt == undefined do opt = MaxScatter_PathOpts()
        local out = #()
        local tS = amax 0.0 (amin 1.0 opt.trimS)
        local tE = amax 0.0 (amin 1.0 opt.trimE)
        if tE < tS do ( local sw = tS; tS = tE; tE = sw )
        local frac = tE - tS

        local si = this.splineItems shapes
        local items = si[1], temps = si[2], total = si[3]
        if items.count > 0 and total > 0.0 and frac > 0.0 and (count > 0 or opt.even) do
        (
            -- how many go on each spline: by spacing, or split by length
            local alloc = #()
            alloc.count = items.count
            if opt.even then
            (
                local sp = amax 1e-4 opt.spacing
                for i = 1 to items.count do
                    alloc[i] = amax 1 (((items[i][3] * frac) / sp) as integer)
            )
            else
            (
                local used = 0
                for i = 1 to items.count do
                (
                    alloc[i] = ((count * items[i][3] / total) as integer)
                    used += alloc[i]
                )
                local i = 1
                while used < count do
                (
                    alloc[i] += 1; used += 1
                    i = if i == items.count then 1 else i + 1
                )
            )

            -- widest lateral reach, so the lateral scale falloff has a scale
            local maxLat = (abs opt.offX) + (abs spread) + (if opt.stagger then (abs opt.stagDist) else 0.0)

            for j = 1 to items.count do
            (
                local sh = items[j][1], sp = items[j][2]
                local cnt = alloc[j]
                for k = 1 to cnt do
                (
                    -- fraction along the trimmed run: evenly spaced or random
                    local f = if opt.even then
                            (tS + frac * ((k - 0.5) / (cnt as float)))
                        else (random tS tE)

                    local prm = lengthToPathParam sh sp f
                    local pos = pathInterp sh sp prm
                    local tang = normalize (pathTangent sh sp prm)

                    local perp = cross tang [0,0,1]
                    if (length perp) < 1e-4 then perp = [1,0,0] else perp = normalize perp

                    -- lateral: fixed offset + alternating side + random spread
                    local lat = opt.offX
                    if opt.stagger do lat += (if (mod k 2) == 1 then opt.stagDist else -opt.stagDist)
                    if spread != 0.0 do lat += (random (-spread) spread)
                    if lat != 0.0 do pos += perp * lat
                    if opt.offZ != 0.0 do pos.z += opt.offZ

                    -- scale: lerp along the run, then shrink with lateral distance
                    local u = if frac > 0.0 then ((f - tS) / frac) else 0.0
                    local sc = opt.scaleStart + (opt.scaleEnd - opt.scaleStart) * u
                    if opt.scaleLat > 0.0 and maxLat > 1e-6 do
                        sc *= 1.0 - opt.scaleLat * (amin 1.0 ((abs lat) / maxLat))
                    if sc < 1e-4 do sc = 1e-4

                    -- bank into the turn: signed change of tangent around world Z
                    local roll = opt.roll
                    if opt.bank != 0.0 do
                    (
                        local f2 = amin 1.0 (f + 0.01)
                        local t2 = normalize (pathTangent sh sp (lengthToPathParam sh sp f2))
                        roll += -((cross tang t2).z) * 90.0 * opt.bank
                    )

                    append out #(pos, [0,0,1], undefined, tang, sc, roll)
                )
            )
        )
        if temps.count > 0 do delete temps
        out
    ),

    /*  Sample across several surfaces. The count is split proportionally to
        each surface's area so density stays even, remainder round-robin.
        Draw order is stable, which keeps the seed reproducible.  */
    fn sampleSurfaces nodes count =
    (
        local out = #()
        local valid = for n in nodes where isValidNode n collect n
        if valid.count == 1 then out = this.sampleSurface valid[1] count
        else if valid.count > 1 and count > 0 do
        (
            local areas = for n in valid collect (this.surfaceArea n)
            local total = 0.0
            for a in areas do total += a
            if total > 0.0 do
            (
                local alloc = #()
                alloc.count = valid.count
                local used = 0
                for i = 1 to valid.count do
                (
                    alloc[i] = ((count * areas[i] / total) as integer)
                    used += alloc[i]
                )
                local i = 1
                while used < count do
                (
                    alloc[i] += 1
                    used += 1
                    i = if i == valid.count then 1 else i + 1
                )
                for i = 1 to valid.count do
                    join out (this.sampleSurface valid[i] alloc[i])
            )
        )
        out
    )
)

MaxScatter.sampling = MaxScatter_Sampling()
