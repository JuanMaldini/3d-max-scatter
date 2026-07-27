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

    /* Angle between the surface normal and world up, in degrees. 0 = flat. */
    fn slopeDeg nrm = ( acos (amax -1.0 (amin 1.0 (normalize nrm).z)) )
)

MaxScatter.filters = MaxScatter_Filters()
