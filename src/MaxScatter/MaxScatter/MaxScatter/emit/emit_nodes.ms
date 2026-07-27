/*  MaxScatter -- emitter A: real instance nodes

    Consumes the core's placement list and materialises it as real Max
    instances parented to the scatter object. Renders in every engine
    including IPR, exports, and gets undo and per-item selection for free.

    Sources can be single meshes, GROUPS or HIERARCHIES: a unit is the whole
    subtree cloned as instances with its structure preserved. Every unit root
    carries a user prop ("msK" = source node handle) so units are bucketed and
    REUSED between regenerations -- dragging a spinner moves nodes instead of
    rebuilding the scene graph.
*/

global MaxScatter

struct MaxScatter_EmitNodes
(
    fn subtree n =
    (
        local a = #(n)
        for c in n.children do join a (this.subtree c)
        a
    ),

    /* Unit bbox in the source's pivot space, spanning the whole subtree. */
    fn unitLocalBBox src =
    (
        local mn = [1e9,1e9,1e9], mx = [-1e9,-1e9,-1e9]
        for n in (this.subtree src) do
        (
            local bb = nodeGetBoundingBox n src.transform
            mn.x = amin mn.x bb[1].x; mn.y = amin mn.y bb[1].y; mn.z = amin mn.z bb[1].z
            mx.x = amax mx.x bb[2].x; mx.y = amax mx.y bb[2].y; mx.z = amax mx.z bb[2].z
        )
        #(mn, mx)
    ),

    /* Display modes: 1 Full, 2 Box, 3 Wire box (box + see-through). */
    fn applyDisplay root mode =
    (
        for n in (this.subtree root) do
        (
            n.boxMode = mode >= 2
            n.xray    = mode == 3
        )
    ),

    fn restyle holder mode =
    (
        if isValidNode holder do
            for c in holder.children do this.applyDisplay c mode
        ok
    ),

    fn clear holder =
    (
        if isValidNode holder do
        (
            local all = #()
            for c in holder.children do join all (this.subtree c)
            if all.count > 0 do delete all
        )
        ok
    ),

    /* One unit: plain instance for single meshes, subtree clone otherwise. */
    fn makeUnit src holder =
    (
        local root
        if src.children.count == 0 and not (isGroupHead src) then
        (
            root = instance src
        )
        else
        (
            local nn
            maxOps.cloneNodes (this.subtree src) cloneType:#instance newNodes:&nn
            root = nn[1]
        )
        root.parent = holder
        setUserProp root "msK" (src.inode.handle as string)
        root
    ),

    /*  placements: array of #(matrix3, sourceIndex) -- the index points into
        the sources array, chosen by the core's weighted pick.  */
    fn emit sources placements holder mode:1 =
    (
        local out = #()
        if sources.count > 0 and isValidNode holder do
        (
            local keys = for s in sources collect (s.inode.handle as string)

            -- bucket existing unit roots by their source key for reuse
            local buckets = for s in sources collect #()
            local trash = #()
            for c in holder.children do
            (
                local hit = findItem keys (getUserProp c "msK")
                if hit > 0 then append buckets[hit] c else append trash c
            )

            /*  Per-bucket cursors instead of shrinking the arrays: assigning
                .count on an array of NODES triggers MAXScript's mapped
                property assignment (tries to set .count on every node).  */
            local btop = for b in buckets collect b.count

            out.count = placements.count
            for i = 1 to placements.count do
            (
                local idx = placements[i][2]
                local n
                if btop[idx] > 0 then ( n = buckets[idx][btop[idx]]; btop[idx] -= 1 )
                else n = this.makeUnit sources[idx] holder
                n.transform = placements[i][1]
                this.applyDisplay n mode
                out[i] = n
            )

            -- leftovers from shrunk counts or removed sources, whole subtrees
            for k = 1 to buckets.count do
                for j = 1 to btop[k] do append trash buckets[k][j]
            if trash.count > 0 do
            (
                local all = #()
                for t in trash do join all (this.subtree t)
                delete all
            )
        )
        out
    )
)

MaxScatter.emitNodes = MaxScatter_EmitNodes()
