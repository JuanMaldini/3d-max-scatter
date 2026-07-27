/*  MaxScatter -- placement matrices

    Pure: sample point + normal + params in, matrix3 out. Never touches the
    scene. This is the boundary the emitters consume, so both emitters stay
    interchangeable.

    Composition order (applied to the item): scale -> rotate XYZ -> base
    orientation, then the offset slides it along its own up axis.
*/

global MaxScatter

struct MaxScatter_PlaceParams
(
    alignN = 1.0,
    rxMin = 0.0, rxMax = 0.0,
    ryMin = 0.0, ryMax = 0.0,
    rzMin = 0.0, rzMax = 360.0,
    uniScale = true,
    sMin  = 1.0, sMax  = 1.0,                       -- uniform
    sxMin = 1.0, sxMax = 1.0,                       -- per-axis
    syMin = 1.0, syMax = 1.0,
    szMin = 1.0, szMax = 1.0,
    zoMin = 0.0, zoMax = 0.0                        -- offset along local up
)

struct MaxScatter_Transform
(
    fn rnd lo hi = ( if lo == hi then lo else random lo hi ),

    fn placement pos nrm pp tangent:undefined alignPath:false =
    (
        local up, xa, ya
        if alignPath and tangent != undefined then
        (
            -- path frame: X along the tangent, like a Sweep
            up = [0,0,1]
            local t2 = tangent - up * (dot tangent up)
            if (length t2) < 1e-4 then t2 = [1,0,0]
            xa = normalize t2
            ya = normalize (cross up xa)
        )
        else
        (
            -- blend the surface normal toward world Z; align 1.0 = fully on the surface
            up = (normalize nrm) * pp.alignN + [0,0,1] * (1.0 - pp.alignN)
            if (length up) < 1e-4 then up = [0,0,1] else up = normalize up

            -- any reference vector not parallel to up
            local refv = if (abs (dot up [0,0,1])) > 0.999 then [1,0,0] else [0,0,1]
            xa = normalize (cross refv up)
            ya = normalize (cross up xa)
        )

        local m = matrix3 xa ya up pos

        local rot = (rotateXMatrix (this.rnd pp.rxMin pp.rxMax)) * \
                    (rotateYMatrix (this.rnd pp.ryMin pp.ryMax)) * \
                    (rotateZMatrix (this.rnd pp.rzMin pp.rzMax))

        local sv
        if pp.uniScale then
        (
            local s = this.rnd pp.sMin pp.sMax
            sv = [s, s, s]
        )
        else sv = [this.rnd pp.sxMin pp.sxMax, this.rnd pp.syMin pp.syMax, this.rnd pp.szMin pp.szMax]

        m = (scaleMatrix sv) * rot * m

        -- NB: `off` is a reserved word in MAXScript (on/off literals)
        local zoff = this.rnd pp.zoMin pp.zoMax
        if zoff != 0.0 do m.translation += (normalize m.row3) * zoff

        m
    )
)

MaxScatter.transform = MaxScatter_Transform()
