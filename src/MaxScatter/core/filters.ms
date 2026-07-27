/*  MaxScatter -- point filters

    Pure predicates over sample points: slope, altitude, spline areas, density
    map. The regen loop calls these to decide whether a sampled point survives.

    Spline areas work on the XY projection: closed splines become world-space
    polygons once per regen, then each point runs a crossing test.
*/

global MaxScatter

struct MaxScatter_Filters
(
    /* One polygon per closed spline of one SplineShape-compatible node. */
    fn polysFromSplineShape sh steps =
    (
        local polys = #()
        for s = 1 to (numSplines sh) do
            if isClosed sh s do
            (
                local poly = #()
                poly.count = steps
                for i = 1 to steps do
                    poly[i] = interpCurve3D sh s ((i - 1) / (steps as float))
                append polys poly
            )
        polys
    ),

    /*  World-space polygons for every closed spline in the given shapes.
        Parametric shapes (Circle, Rectangle...) are converted on a temp copy.  */
    fn shapePolys shapes steps:24 =
    (
        local polys = #()
        for sh in shapes where isValidNode sh do
        (
            local got = try ( this.polysFromSplineShape sh steps ) catch undefined
            if got == undefined do
            (
                local tmp = copy sh
                convertToSplineShape tmp
                got = try ( this.polysFromSplineShape tmp steps ) catch #()
                delete tmp
            )
            join polys got
        )
        polys
    ),

    /* Even-odd crossing test on XY. */
    fn pointInPoly p poly =
    (
        local inside = false
        local j = poly.count
        for i = 1 to poly.count do
        (
            if ((poly[i].y > p.y) != (poly[j].y > p.y)) and \
               (p.x < (poly[j].x - poly[i].x) * (p.y - poly[i].y) / (poly[j].y - poly[i].y) + poly[i].x) do
                inside = not inside
            j = i
        )
        inside
    ),

    fn inAnyPoly p polys =
    (
        local hit = false
        for poly in polys while not hit do hit = this.pointInPoly p poly
        hit
    ),

    /*  ---- Distance masks -------------------------------------------------

        A curve is #(points, closed, bbMin, bbMax). Unlike the polygon test
        above these accept OPEN splines: what matters is the distance from the
        point to the curve, so a stroke drawn across a surface pushes items
        away exactly like a closed area does.

        Masks return 0..1: 0 = the point is out, 1 = fully in, values between
        are the falloff band where the regen loop thins and shrinks items.  */

    fn curvesFromSplineShape sh steps =
    (
        local out = #()
        for s = 1 to (numSplines sh) do
        (
            local cl = isClosed sh s
            -- closed curves wrap (last segment closes the loop), open ones
            -- need the endpoint, hence one extra sample
            local n = if cl then steps else steps + 1
            local pts = #()
            pts.count = n
            local mn = [1e30, 1e30, 0], mx = [-1e30, -1e30, 0]
            for i = 1 to n do
            (
                local q = interpCurve3D sh s ((i - 1) / (steps as float))
                pts[i] = q
                if q.x < mn.x do mn.x = q.x
                if q.y < mn.y do mn.y = q.y
                if q.x > mx.x do mx.x = q.x
                if q.y > mx.y do mx.y = q.y
            )
            if n > 1 do append out #(pts, cl, mn, mx)
        )
        out
    ),

    fn shapeCurves shapes steps:24 =
    (
        local out = #()
        for sh in shapes where isValidNode sh do
        (
            local got = try ( this.curvesFromSplineShape sh steps ) catch undefined
            if got == undefined do
            (
                local tmp = copy sh
                convertToSplineShape tmp
                got = try ( this.curvesFromSplineShape tmp steps ) catch #()
                delete tmp
            )
            join out got
        )
        out
    ),

    /* Distance from (px,py) to the segment a-q, XY only.
       NB: `by` is reserved (for..by), hence the q names for the second end. */
    fn segDist2D px py ax ay qx qy =
    (
        local vx = qx - ax, vy = qy - ay
        local wx = px - ax, wy = py - ay
        local vv = vx * vx + vy * vy
        local t = if vv <= 1e-12 then 0.0 else (wx * vx + wy * vy) / vv
        if t < 0.0 do t = 0.0
        if t > 1.0 do t = 1.0
        local dx = wx - vx * t, dy = wy - vy * t
        sqrt (dx * dx + dy * dy)
    ),

    fn curveDist p c =
    (
        local pts = c[1], n = pts.count
        local best = 1e30
        local last = if c[2] then n else n - 1
        for i = 1 to last do
        (
            local j = if i == n then 1 else i + 1
            local d = this.segDist2D p.x p.y pts[i].x pts[i].y pts[j].x pts[j].y
            if d < best do best = d
        )
        best
    ),

    /* 1 past the falloff band, 0 at or before the boundary, linear between. */
    fn ramp x fall =
    (
        if fall <= 0.0 then ( if x >= 0.0 then 1.0 else 0.0 )
        else ( if x <= 0.0 then 0.0 else if x >= fall then 1.0 else x / fall )
    ),

    fn outsideBox p c pad =
    (
        p.x < c[3].x - pad or p.x > c[4].x + pad or \
        p.y < c[3].y - pad or p.y > c[4].y + pad
    ),

    /*  Union of the include regions. Closed splines mean their interior, inset
        by dist; open ones mean a corridor of half-width dist along the stroke.
        No curves at all means "no restriction".  */
    fn inclMask p curves dist fall =
    (
        if curves.count == 0 then 1.0
        else
        (
            local best = 0.0
            for c in curves while best < 1.0 do
            (
                local m = 0.0
                if not (this.outsideBox p c (dist + fall)) do
                (
                    local d = this.curveDist p c
                    local x = if c[2] then
                            ((if this.pointInPoly p c[1] then d else -d) - dist)
                        else (dist - d)
                    m = this.ramp x fall
                )
                if m > best do best = m
            )
            best
        )
    ),

    /*  Intersection of the keep-out regions: every exclude curve pushes items
        away by dist, then releases them over the falloff band.  */
    fn exclMask p curves dist fall =
    (
        local best = 1.0
        for c in curves while best > 0.0 do
            if not (this.outsideBox p c (dist + fall)) do
            (
                local d = this.curveDist p c
                local sd = if c[2] and (this.pointInPoly p c[1]) then -d else d
                local m = this.ramp (sd - dist) fall
                if m < best do best = m
            )
        best
    ),

    /* Angle between the surface normal and world up, in degrees. 0 = flat. */
    fn slopeDeg nrm = ( acos (amax -1.0 (amin 1.0 (normalize nrm).z)) )
)

MaxScatter.filters = MaxScatter_Filters()
