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

/*  ---- Bucket cache --------------------------------------------------------

    emit() below reuses existing unit roots instead of rebuilding the scene
    graph, and it used to work out which root belongs to which source by
    reading the "msK" user prop off every child of the holder, on every regen.
    That is a string parse per item per tick, and a spinner drag fires ticks
    continuously -- so the bucketing cost scaled with the item count on a path
    where nothing about the buckets had actually changed.

    emit() already knows the finished buckets when it returns, so they are kept
    here and revalidated on the next call instead: same sources in the same
    order, same number of children under the holder, every cached root still a
    valid node. Anything else falls back to the user-prop scan, which stays the
    source of truth -- it is what handles a scene reopened from disk, an undo,
    and items the user deleted or re-parented by hand.

    Keyed by the holder's node handle. Reset on hot-reload (the array below is
    rebuilt), dropped by clear(), and pruned by the regen timer once the holder
    is gone.

    Entry: #(holderHandle, sourceKeys, buckets)
*/
global MaxScatter_emitBuckets
global MaxScatter_emitBucketsFind
global MaxScatter_emitBucketsDrop

MaxScatter_emitBuckets = #()

fn MaxScatter_emitBucketsFind h =
(
    local idx = 0
    for i = 1 to MaxScatter_emitBuckets.count do
        if MaxScatter_emitBuckets[i][1] == h do ( idx = i; exit )
    idx
)

fn MaxScatter_emitBucketsDrop h =
(
    local i = MaxScatter_emitBucketsFind h
    if i > 0 do deleteItem MaxScatter_emitBuckets i
    ok
)

/*  ---- Park pool -----------------------------------------------------------

    Deleting a unit is cheap; CREATING one is not. Measured on a 1495-item path
    scatter: repositioning the same count costs ~193 ms, shrinking to 747 costs
    ~225 ms, growing back to 1495 costs ~549 ms. The whole difference is
    `instance` / `cloneNodes`.

    Dragging the spacing spinner shrinks and grows the count over and over, so
    the old code deleted units and then paid full price to build the same units
    again a moment later. Instead the surplus is PARKED: hidden and moved under
    a per-scatter pool node, then revived on the next growth. A clone is only
    built when the pool has nothing left for that source.

    Why a separate pool node rather than leaving them under the item holder:
      - Bake detaches holder.children (plugin/scatter_helper.ms), and parked
        units are not part of the scatter -- they must not come along.
      - The bucket cache above validates against holder.children.count, and
        parked units would break that count.

    Parked nodes are still scene nodes, so they are NOT allowed to accumulate:
    they are really deleted once the scatter has been idle (drained by the regen
    timer), when the source list changes, on clear(), before a file save, and
    before a render.

    Entry: #(holderHandle, poolNode, sourceKeys, buckets, lastTouchMs)
*/
global MaxScatter_emitPool
global MaxScatter_emitPoolFind
global MaxScatter_emitPoolDrain
global MaxScatter_emitPoolDrainAll
global MaxScatter_emitPoolIdleMs
global MaxScatter_emitPoolMax

MaxScatter_emitPool      = #()
MaxScatter_emitPoolIdleMs = 4000     -- idle this long and the pool is deleted
MaxScatter_emitPoolMax    = 20000    -- hard cap on parked units per source

fn MaxScatter_emitPoolFind h =
(
    local idx = 0
    for i = 1 to MaxScatter_emitPool.count do
        if MaxScatter_emitPool[i][1] == h do ( idx = i; exit )
    idx
)

/* Really delete everything parked for one holder, and the pool node itself. */
fn MaxScatter_emitPoolDrain h =
(
    local i = MaxScatter_emitPoolFind h
    if i > 0 do
    (
        local e = MaxScatter_emitPool[i]
        local all = #()
        for b in e[4] do
            for n in b where isValidNode n do
                join all (MaxScatter.emitNodes.subtree n)
        if all.count > 0 do try (delete all) catch()
        if isValidNode e[2] do try (delete e[2]) catch()
        deleteItem MaxScatter_emitPool i
    )
    ok
)

fn MaxScatter_emitPoolDrainAll =
(
    for i = MaxScatter_emitPool.count to 1 by -1 do
        try (MaxScatter_emitPoolDrain MaxScatter_emitPool[i][1]) catch()
    ok
)

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
            MaxScatter_emitBucketsDrop holder.inode.handle
            MaxScatter_emitPoolDrain  holder.inode.handle
            local all = #()
            for c in holder.children do join all (this.subtree c)
            if all.count > 0 do delete all
        )
        ok
    ),

    /*  The pool entry for one holder, or undefined.

        Accepted only while it still matches the source list -- a changed list
        means the parked units are for sources that may no longer exist, and
        sorting that out is not worth it next to just rebuilding. create:true
        makes the pool node on demand, so a scatter whose count never shrinks
        never gets one.  */
    fn poolGet holder keys create:false =
    (
        local hh = holder.inode.handle
        local i = MaxScatter_emitPoolFind hh
        if i > 0 do
        (
            local e = MaxScatter_emitPool[i]
            local good = (isValidNode e[2]) and e[3].count == keys.count
            if good do
                for k = 1 to keys.count while good do good = e[3][k] == keys[k]
            if good then return e
            MaxScatter_emitPoolDrain hh
        )
        if not create then undefined
        else
        (
            local pn = Point name:(uniqueName (holder.name + "_pool")) size:1 cross:false box:false
            pn.transform = matrix3 1
            pn.isHidden = true
            try ((MaxScatter.ensureLayer()).addNode pn) catch()
            local e = #(hh, pn, keys, (for k in keys collect #()), timeStamp())
            append MaxScatter_emitPool e
            e
        )
    ),

    /* One unit: plain instance for single meshes, subtree clone otherwise. */
    fn makeUnit src holder lay: =
    (
        local root, made
        if src.children.count == 0 and not (isGroupHead src) then
        (
            root = instance src
            made = #(root)
        )
        else
        (
            local nn
            maxOps.cloneNodes (this.subtree src) cloneType:#instance newNodes:&nn
            root = nn[1]
            made = nn
        )
        root.parent = holder
        if lay != undefined do for n in made do lay.addNode n
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
            local lay = try (MaxScatter.ensureLayer()) catch undefined
            local keys = for s in sources collect (s.inode.handle as string)
            local hh = holder.inode.handle

            /*  Buckets of existing unit roots, by source.

                Preferred path: the ones this function left behind last time,
                accepted only if the sources and the holder's children still
                line up with them. isValidNode over the cached roots is the one
                O(N) check kept -- it is a pointer test, not a string parse, and
                without it a node the user deleted would reach `n.transform =`
                below and throw the whole regen away.  */
            local buckets = undefined
            local ci = MaxScatter_emitBucketsFind hh
            if ci > 0 do
            (
                local cKeys = MaxScatter_emitBuckets[ci][2]
                local cBuck = MaxScatter_emitBuckets[ci][3]
                local good = cKeys.count == keys.count and cBuck.count == keys.count
                if good do
                    for i = 1 to keys.count while good do good = cKeys[i] == keys[i]
                if good do
                (
                    local n = 0
                    for b in cBuck do n += b.count
                    good = n == holder.children.count
                )
                if good do
                    for b in cBuck while good do
                        for c in b while good do good = isValidNode c
                if good then buckets = cBuck
                else deleteItem MaxScatter_emitBuckets ci
            )

            local trash = #()
            if buckets == undefined do
            (
                buckets = for s in sources collect #()
                for c in holder.children do
                (
                    local hit = findItem keys (getUserProp c "msK")
                    if hit > 0 then append buckets[hit] c else append trash c
                )
            )

            /*  Per-bucket cursors instead of shrinking the arrays: assigning
                .count on an array of NODES triggers MAXScript's mapped
                property assignment (tries to set .count on every node).  */
            local btop = for b in buckets collect b.count

            -- the buckets as they will stand after this pass, for the cache
            local kept = for s in sources collect #()

            -- units parked by an earlier shrink, if this scatter has any
            local pool = this.poolGet holder keys

            out.count = placements.count
            for i = 1 to placements.count do
            (
                local idx = placements[i][2]
                local n
                if btop[idx] > 0 then ( n = buckets[idx][btop[idx]]; btop[idx] -= 1 )
                else
                (
                    /*  Revive before cloning. applyDisplay runs on this branch
                        only: a unit that was already under the holder is
                        already in the right display mode (dispMode's own
                        handler calls restyle), so re-walking its subtree and
                        rewriting boxMode/xray for every item on every regen was
                        pure waste. A revived unit was NOT under the holder when
                        restyle last ran, so it does need it.  */
                    local pb = if pool != undefined then pool[4][idx] else undefined
                    if pb != undefined and pb.count > 0 then
                    (
                        n = pb[pb.count]
                        deleteItem pb pb.count
                        for x in (this.subtree n) do x.isHidden = false
                        n.parent = holder
                    )
                    else n = this.makeUnit sources[idx] holder lay:lay
                    this.applyDisplay n mode
                )
                n.transform = placements[i][1]
                append kept[idx] n
                out[i] = n
            )

            /*  Surplus from a shrunk count: park it for the next growth rather
                than delete it. Anything in `trash` came from the user-prop scan
                without matching a current source, so it belongs to no source
                and is deleted outright.  */
            for k = 1 to buckets.count do
                if btop[k] > 0 do
                (
                    if pool == undefined do pool = this.poolGet holder keys create:true
                    local pb = pool[4][k]
                    for j = 1 to btop[k] do
                    (
                        local n = buckets[k][j]
                        if pb.count < MaxScatter_emitPoolMax then
                        (
                            for x in (this.subtree n) do x.isHidden = true
                            n.parent = pool[2]
                            append pb n
                        )
                        else append trash n
                    )
                )
            if pool != undefined do pool[5] = timeStamp()

            if trash.count > 0 do
            (
                local all = #()
                for t in trash do join all (this.subtree t)
                delete all
            )

            -- what the next regen starts from, instead of re-reading user props
            local ci2 = MaxScatter_emitBucketsFind hh
            if ci2 > 0 then MaxScatter_emitBuckets[ci2] = #(hh, keys, kept)
            else append MaxScatter_emitBuckets #(hh, keys, kept)
        )
        out
    )
)

MaxScatter.emitNodes = MaxScatter_EmitNodes()
