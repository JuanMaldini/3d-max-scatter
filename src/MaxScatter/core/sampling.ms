/*  MaxScatter -- surface sampling

    Pure: takes a node, returns sample points. Never touches the scene.
    Points are area-weighted so triangle density does not bias the result.

    Returns an array of #(position, normal), both in world space.
*/

global MaxScatter

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

    fn splineLengthMany shapes =
    (
        local si = this.splineItems shapes
        if si[2].count > 0 do delete si[2]
        si[3]
    ),

    /*  Random-by-length sampling along spline paths. Tuples get a 4th element:
        the path tangent. Normal is world up; spread is a lateral jitter
        perpendicular to the path.  */
    fn sampleSplines shapes count spread =
    (
        local out = #()
        local si = this.splineItems shapes
        local items = si[1], temps = si[2], total = si[3]
        if items.count > 0 and total > 0.0 and count > 0 do
        (
            -- allocate per spline by length, remainder round-robin
            local alloc = #()
            alloc.count = items.count
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

            for j = 1 to items.count do
            (
                local sh = items[j][1], sp = items[j][2]
                for k = 1 to alloc[j] do
                (
                    local prm = lengthToPathParam sh sp (random 0.0 1.0)
                    local pos = pathInterp sh sp prm
                    local tang = normalize (pathTangent sh sp prm)
                    if spread != 0.0 do
                    (
                        local perp = cross tang [0,0,1]
                        if (length perp) < 1e-4 then perp = [1,0,0] else perp = normalize perp
                        pos += perp * (random (-spread) spread)
                    )
                    append out #(pos, [0,0,1], undefined, tang)
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
