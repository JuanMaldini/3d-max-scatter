/*  MaxScatter -- the scene object (thin shell)

    Paramblocks + rollouts only. All heavy lifting lives in core/pipeline.ms
    (hot-reloadable); this file's paramblock layout is the ONLY sacred part --
    changing it breaks saved scenes.

    The object displays as the text "MaxScatter" inside a white rectangle
    (min 1 m wide). Click it -> Modify panel. Scattered instances are its
    children, so moving the helper moves the whole set.

    Per-source transforms are serialized into srcXforms (one string per
    source, parallel to srcNodes/srcWeights); the Transform rollout edits the
    source currently selected in the Sources list.
*/

global MaxScatter
global MaxScatterObj_regen
global MaxScatter_rtRestyle
global MaxScatter_camWatch
global MaxScatter_queueCleanup
global MaxScatter_filterGeo
global MaxScatter_filterSrc
global MaxScatter_filterShape
global MaxScatter_filterCam

fn MaxScatter_filterGeo o   = ( isKindOf o GeometryClass )
fn MaxScatter_filterSrc o   = ( isKindOf o GeometryClass or isGroupHead o or o.children.count > 0 )
fn MaxScatter_filterShape o = ( isKindOf o Shape )
fn MaxScatter_filterCam o   = ( isKindOf o Camera )

plugin helper MaxScatterObj
    name:"MaxScatter"
    classID:#(0x6d735301, 0x4a4d3163)
    category:"MaxScatter"
    extends:Dummy
    version:1
(
    parameters pbData rollout:rolSrc
    (
        srcNodes    type:#nodeTab   tabSizeVariable:true subAnim:true
        srcWeights  type:#floatTab  tabSizeVariable:true
        srcXforms   type:#stringTab tabSizeVariable:true
        surfNodes   type:#nodeTab   tabSizeVariable:true subAnim:true
        pathSplines type:#nodeTab   tabSizeVariable:true subAnim:true
        inclSplines type:#nodeTab   tabSizeVariable:true subAnim:true
        exclSplines type:#nodeTab   tabSizeVariable:true subAnim:true

        /*  Hidden container the instances parent to, so the helper icon moves
            freely without dragging (or recomputing) thousands of children.  */
        itemHolder  type:#node
    )

    parameters pbDist rollout:rolDist
    (
        /*  distMode, pathSpread and alignPath keep their slot but lost their
            ui: binding: their controls now live in rolSrc / rolPath and sync
            by hand. Dropping ui: does not change the paramblock layout, so
            saved scenes still load.  */
        distMode   type:#integer    default:1                 -- 1 surface, 2 spline path
        useDensity type:#boolean    default:false ui:chkDens
        numItems   type:#integer    default:200 ui:spnCount
        density    type:#float      default:0.001 ui:spnDensity
        seedVal    type:#integer    default:12345 ui:spnSeed
        pathSpread type:#float      default:0.0
        alignPath  type:#boolean    default:true
        densityMap type:#texturemap ui:mbDens subAnim:true
        mapAmount  type:#float      default:1.0 ui:spnMapAmt
        mapInvert  type:#boolean    default:false ui:chkMapInv
        mapGamma   type:#float      default:1.0 ui:spnMapGam
        mapTile    type:#float      default:1.0 ui:spnMapTile

        on distMode   set v do if not loading do MaxScatterObj_regen this
        on useDensity set v do if not loading do MaxScatterObj_regen this
        on numItems   set v do if not loading do MaxScatterObj_regen this
        on density    set v do if not loading do MaxScatterObj_regen this
        on seedVal    set v do if not loading do MaxScatterObj_regen this
        on pathSpread set v do if not loading do MaxScatterObj_regen this
        on alignPath  set v do if not loading do MaxScatterObj_regen this
        on densityMap set v do if not loading do MaxScatterObj_regen this
        on mapAmount  set v do if not loading do MaxScatterObj_regen this
        on mapInvert  set v do if not loading do MaxScatterObj_regen this
        on mapGamma   set v do if not loading do MaxScatterObj_regen this
        on mapTile    set v do if not loading do MaxScatterObj_regen this
    )

    parameters pbXform rollout:rolXform
    (
        alignN type:#float default:1.0 ui:spnAlign
        on alignN set v do if not loading do MaxScatterObj_regen this
    )

    parameters pbLim rollout:rolLim
    (
        useSlope type:#boolean default:false ui:chkSlope
        slopeMin type:#float   default:0.0   ui:spnSlopeMin
        slopeMax type:#float   default:45.0  ui:spnSlopeMax
        useAlt   type:#boolean default:false ui:chkAlt
        altMin   type:#float   default:0.0   ui:spnAltMin
        altMax   type:#float   default:10000.0 ui:spnAltMax

        on useSlope set v do if not loading do MaxScatterObj_regen this
        on slopeMin set v do if not loading do MaxScatterObj_regen this
        on slopeMax set v do if not loading do MaxScatterObj_regen this
        on useAlt   set v do if not loading do MaxScatterObj_regen this
        on altMin   set v do if not loading do MaxScatterObj_regen this
        on altMax   set v do if not loading do MaxScatterObj_regen this
    )

    parameters pbCam rollout:rolCam
    (
        camNode  type:#node
        fovPad   type:#float   default:5.0    ui:spnPad
        backDist type:#float   default:1000.0 ui:spnBack
        useFar   type:#boolean default:false  ui:chkFar
        farDist  type:#float   default:50000.0 ui:spnFar

        on camNode  set v do if not loading do ( MaxScatterObj_regen this; MaxScatter_camWatch() )
        on fovPad   set v do if not loading do MaxScatterObj_regen this
        on backDist set v do if not loading do MaxScatterObj_regen this
        on useFar   set v do if not loading do MaxScatterObj_regen this
        on farDist  set v do if not loading do MaxScatterObj_regen this
    )

    parameters pbDisp rollout:rolDisp
    (
        emitMode type:#integer default:1     -- 1 instances, 2 proxy render-time
        dispMode type:#integer default:1     -- instances: 1 full, 2 box, 3 wire box
        prxMode  type:#integer default:1     -- proxy: 1 box, 2 cone, 3 point cloud
        dispPct  type:#integer default:100 ui:spnPct
        pcPoints type:#integer default:20  ui:spnPts
        iconSize type:#worldUnits default:100.0 ui:spnIcon
        rtTick   type:#integer default:0 animatable:false invisibleInTV:true

        on emitMode set v do if not loading do MaxScatterObj_regen this
        on dispMode set v do if not loading do
            MaxScatter.emitNodes.restyle itemHolder v
        on prxMode  set v do if not loading and emitMode == 2 do MaxScatter_rtRestyle this
        on dispPct  set v do if not loading and emitMode == 2 do MaxScatter_rtRestyle this
        on pcPoints set v do if not loading and emitMode == 2 do MaxScatter_rtRestyle this
    )

    /*  Appended blocks -- new params go at the END so existing slots keep
        their position and saved scenes keep loading.  */
    parameters pbPath rollout:rolPath
    (
        pathEven     type:#boolean    default:false ui:chkEven
        pathSpacing  type:#worldUnits default:100.0 ui:spnSpacing
        trimStart    type:#float      default:0.0 ui:spnTrimS
        trimEnd      type:#float      default:100.0 ui:spnTrimE
        pathOffX     type:#worldUnits default:0.0 ui:spnOffX
        pathOffZ     type:#worldUnits default:0.0 ui:spnOffZ
        pathStagger  type:#boolean    default:false ui:chkStag
        pathStagDist type:#worldUnits default:0.0 ui:spnStag
        pathRoll     type:#float      default:0.0 ui:spnRoll
        pathBank     type:#float      default:0.0 ui:spnBank
        pathScaleS   type:#float      default:1.0 ui:spnScS
        pathScaleE   type:#float      default:1.0 ui:spnScE
        pathScaleLat type:#float      default:0.0 ui:spnScLat

        on pathEven     set v do if not loading do ( MaxScatterObj_regen this; try (rolPath.syncEnable()) catch() )
        on pathSpacing  set v do if not loading do MaxScatterObj_regen this
        on trimStart    set v do if not loading do MaxScatterObj_regen this
        on trimEnd      set v do if not loading do MaxScatterObj_regen this
        on pathOffX     set v do if not loading do MaxScatterObj_regen this
        on pathOffZ     set v do if not loading do MaxScatterObj_regen this
        on pathStagger  set v do if not loading do ( MaxScatterObj_regen this; try (rolPath.syncEnable()) catch() )
        on pathStagDist set v do if not loading do MaxScatterObj_regen this
        on pathRoll     set v do if not loading do MaxScatterObj_regen this
        on pathBank     set v do if not loading do MaxScatterObj_regen this
        on pathScaleS   set v do if not loading do MaxScatterObj_regen this
        on pathScaleE   set v do if not loading do MaxScatterObj_regen this
        on pathScaleLat set v do if not loading do MaxScatterObj_regen this
    )

    parameters pbMask rollout:rolMask
    (
        inclDist  type:#worldUnits default:0.0 ui:spnID
        inclFall  type:#worldUnits default:0.0 ui:spnIF
        inclThin  type:#float      default:1.0 ui:spnIT
        inclScale type:#float      default:0.0 ui:spnIS
        exclDist  type:#worldUnits default:0.0 ui:spnED
        exclFall  type:#worldUnits default:0.0 ui:spnEF
        exclThin  type:#float      default:1.0 ui:spnET
        exclScale type:#float      default:0.0 ui:spnES

        on inclDist  set v do if not loading do MaxScatterObj_regen this
        on inclFall  set v do if not loading do MaxScatterObj_regen this
        on inclThin  set v do if not loading do MaxScatterObj_regen this
        on inclScale set v do if not loading do MaxScatterObj_regen this
        on exclDist  set v do if not loading do MaxScatterObj_regen this
        on exclFall  set v do if not loading do MaxScatterObj_regen this
        on exclThin  set v do if not loading do MaxScatterObj_regen this
        on exclScale set v do if not loading do MaxScatterObj_regen this
    )

    /*  The density map's scale knob, completing the thin/shrink pair every
        other mask already has (inclThin/inclScale, exclThin/exclScale). Its
        own block, appended, so pbDist keeps its slots; a parameters block may
        bind to a rollout an earlier block already uses, so the spinner still
        lives in Distribution.  */
    parameters pbMap rollout:rolDist
    (
        mapScale type:#float default:0.0 ui:spnMapScl

        on mapScale set v do if not loading do MaxScatterObj_regen this
    )

    rollout rolSrc "Sources"
    (
        radiobuttons rdoMode "Scatter on" labels:#("Surface", "Spline") columns:2 \
            tooltip:"Which list feeds the scatter. Both lists stay editable either way"

        label       lbl1 "Scatter items" align:#left offset:[0,6]
        listbox     lbS     "" items:#() height:5
        checkbutton btnAddS "+ Add"  width:66 across:2 \
            tooltip:"Click objects, groups or hierarchies to add; right-click or Esc to finish"
        button      btnDelS "Remove" width:66
        spinner    spnProb "Prob " type:#float range:[0, 1, 1] scale:0.01 fieldwidth:50 \
            tooltip:"Chance 0-1 that this item appears at each scattered point. Probabilities summing under 1 leave the rest empty."

        label       lbl2 "Surfaces" align:#left offset:[0,8]
        listbox     lbT     "" items:#() height:4
        checkbutton btnAddT "+ Add"  width:66 across:2 \
            tooltip:"Click meshes to add; right-click or Esc to finish"
        button      btnDelT "Remove" width:66

        label       lbl5 "Spline paths" align:#left offset:[0,8]
        listbox     lbP     "" items:#() height:3
        checkbutton btnAddP "+ Add"  width:66 across:2 \
            tooltip:"Click splines to add as paths; right-click or Esc to finish"
        button      btnDelP "Remove" width:66

        /* Selection-preserving refresh: repopulating a listbox resets its
           selection, which made the panel look like it lost its setup. */
        fn refresh =
        (
            local keepS = lbS.selection, keepT = lbT.selection, keepP = lbP.selection
            lbS.items = for i = 1 to srcNodes.count collect
            (
                local nm = if isValidNode srcNodes[i] then srcNodes[i].name else "<deleted>"
                local w  = if i <= srcWeights.count then srcWeights[i] else 1.0
                nm + "   " + (formattedPrint w format:"0.2f")
            )
            lbT.items = for s in surfNodes   collect (if isValidNode s then s.name else "<deleted>")
            lbP.items = for s in pathSplines collect (if isValidNode s then s.name else "<deleted>")
            if keepS > 0 and keepS <= lbS.items.count do lbS.selection = keepS
            if keepT > 0 and keepT <= lbT.items.count do lbT.selection = keepT
            if keepP > 0 and keepP <= lbP.items.count do lbP.selection = keepP
            local sel = lbS.selection
            spnProb.enabled = (sel > 0 and sel <= srcWeights.count)
            if spnProb.enabled do spnProb.value = srcWeights[sel]
            rdoMode.state = distMode
            -- which list actually feeds the scatter, without grеying anything
            -- out: both stay editable so a setup can be built in any order
            lbl2.text = if distMode == 1 then "Surfaces  (active)" else "Surfaces"
            lbl5.text = if distMode == 2 then "Spline paths  (active)" else "Spline paths"
            try (rolXform.loadSel()) catch()
        )

        on rdoMode changed s do
        (
            distMode = s
            refresh()
            try (rolDist.syncEnable()) catch()
            try (rolPath.syncEnable()) catch()
            MaxScatterObj_regen this
        )

        on btnAddS changed s do if s do
            -- duplicates allowed: repeating an item is the only way to overweight
            -- it, since Prob tops out at 1
            MaxScatter_pickInto this #sources "SCATTER ITEMS" MaxScatter_filterSrc btnAddS allowDup:true
        on btnDelS pressed do
            if MaxScatter_removeAt this #sources lbS.selection do
                ( refresh(); MaxScatterObj_regen this )
        on lbS selected idx do refresh()
        on spnProb changed v do
        (
            local sel = lbS.selection
            if sel > 0 and sel <= srcWeights.count do
            (
                local w = for x in srcWeights collect x
                w[sel] = v
                srcWeights = w
                refresh()
                MaxScatterObj_regen this
            )
        )

        on btnAddT changed s do if s do
            MaxScatter_pickInto this #surfaces "SURFACES" MaxScatter_filterGeo btnAddT
        on btnDelT pressed do
            if MaxScatter_removeAt this #surfaces lbT.selection do
                ( refresh(); MaxScatterObj_regen this )

        on btnAddP changed s do if s do
            MaxScatter_pickInto this #paths "SPLINE PATHS" MaxScatter_filterShape btnAddP
        on btnDelP pressed do
            if MaxScatter_removeAt this #paths lbP.selection do
                ( refresh(); MaxScatterObj_regen this )

        on rolSrc open do refresh()
    )

    /*  Include / exclude live in their own rollout: they are masks over the
        result, not part of choosing what to scatter on.  */
    rollout rolMask "Include / Exclude splines"
    (
        label       lbl3 "Include" align:#left
        listbox     lbI     "" items:#() height:3
        checkbutton btnAddI "+ Add"  width:66 across:2 \
            tooltip:"Scatter only here. Closed spline = its interior, open spline = a corridor along the stroke"
        button      btnDelI "Remove" width:66
        spinner spnID "Distance" type:#worldunits range:[0, 1e9, 0] fieldwidth:56 \
            tooltip:"Closed: how far inside the border items must stay. Open: half-width of the corridor"
        spinner spnIF "Falloff " type:#worldunits range:[0, 1e9, 0] fieldwidth:56 \
            tooltip:"Fade band measured inward from that boundary"
        spinner spnIT "Density " type:#float range:[0, 1, 1] scale:0.01 fieldwidth:48 across:2 \
            tooltip:"How much the falloff thins items out"
        spinner spnIS "Scale   " type:#float range:[0, 1, 0] scale:0.01 fieldwidth:48 \
            tooltip:"How much the falloff shrinks items"

        label       lbl4 "Exclude" align:#left offset:[0,10]
        listbox     lbE     "" items:#() height:3
        checkbutton btnAddE "+ Add"  width:66 across:2 \
            tooltip:"Keep items away. Works with open splines too: a stroke pushes items off it"
        button      btnDelE "Remove" width:66
        spinner spnED "Distance" type:#worldunits range:[0, 1e9, 0] fieldwidth:56 \
            tooltip:"Clear radius around the spline; closed splines also clear their interior"
        spinner spnEF "Falloff " type:#worldunits range:[0, 1e9, 0] fieldwidth:56 \
            tooltip:"Fade band measured outward from the clear radius"
        spinner spnET "Density " type:#float range:[0, 1, 1] scale:0.01 fieldwidth:48 across:2 \
            tooltip:"How much the falloff thins items out"
        spinner spnES "Scale   " type:#float range:[0, 1, 0] scale:0.01 fieldwidth:48 \
            tooltip:"How much the falloff shrinks items as they approach the spline"

        fn refresh =
        (
            local keepI = lbI.selection, keepE = lbE.selection
            lbI.items = for s in inclSplines collect (if isValidNode s then s.name else "<deleted>")
            lbE.items = for s in exclSplines collect (if isValidNode s then s.name else "<deleted>")
            if keepI > 0 and keepI <= lbI.items.count do lbI.selection = keepI
            if keepE > 0 and keepE <= lbE.items.count do lbE.selection = keepE
            local hasI = inclSplines.count > 0, hasE = exclSplines.count > 0
            spnID.enabled = hasI; spnIF.enabled = hasI
            spnIT.enabled = hasI; spnIS.enabled = hasI
            spnED.enabled = hasE; spnEF.enabled = hasE
            spnET.enabled = hasE; spnES.enabled = hasE
        )

        on btnAddI changed s do if s do
            MaxScatter_pickInto this #include "INCLUDE SPLINES" MaxScatter_filterShape btnAddI
        on btnDelI pressed do
            if MaxScatter_removeAt this #include lbI.selection do
                ( refresh(); MaxScatterObj_regen this )

        on btnAddE changed s do if s do
            MaxScatter_pickInto this #exclude "EXCLUDE SPLINES" MaxScatter_filterShape btnAddE
        on btnDelE pressed do
            if MaxScatter_removeAt this #exclude lbE.selection do
                ( refresh(); MaxScatterObj_regen this )

        on rolMask open do refresh()
    )

    rollout rolDist "Distribution"
    (
        checkbox chkDens   "Use density"
        spinner  spnCount   "Count  " type:#integer range:[1, 1000000, 200] fieldwidth:60
        spinner  spnDensity "Density" type:#float range:[0.000001, 1000, 0.001] scale:0.0001 fieldwidth:60 \
            tooltip:"Items per square unit on surfaces, per length unit on splines"
        spinner  spnSeed    "Seed   " type:#integer range:[0, 999999, 12345] fieldwidth:60
        mapbutton mbDens "Density Map" width:100 across:2 offset:[0,6] \
            tooltip:"Luminance drives keep probability; needs UVs on the surface"
        button    btnClrD "x" width:20 offset:[0,6] tooltip:"Clear density map"
        spinner  spnMapAmt  "Amount" type:#float range:[0, 1, 1] scale:0.01 fieldwidth:48 across:2
        checkbox chkMapInv  "Invert"
        spinner  spnMapGam  "Gamma " type:#float range:[0.1, 10, 1] scale:0.05 fieldwidth:48 across:2
        spinner  spnMapTile "Tile  " type:#float range:[0.01, 1000, 1] fieldwidth:48
        spinner  spnMapScl  "Scale " type:#float range:[0, 1, 0] scale:0.01 fieldwidth:48 \
            tooltip:"How much the dark areas of the map shrink items; 0 leaves size untouched. Independent of Amount, so Amount 0 + Scale 1 varies size without changing the count"

        fn syncEnable =
        (
            local surf = distMode == 1
            spnCount.enabled   = not useDensity and not (not surf and pathEven)
            spnDensity.enabled = useDensity
            mbDens.enabled = surf
            btnClrD.enabled = surf
            local hasMap = surf and densityMap != undefined
            spnMapAmt.enabled = hasMap; chkMapInv.enabled = hasMap
            spnMapGam.enabled = hasMap; spnMapTile.enabled = hasMap
            spnMapScl.enabled = hasMap
            try
            (
                rolLim.chkSlope.enabled = surf
                rolLim.spnSlopeMin.enabled = surf and useSlope
                rolLim.spnSlopeMax.enabled = surf and useSlope
            )
            catch()
        )
        on chkDens  changed v do syncEnable()
        on mbDens   picked m do syncEnable()
        on btnClrD  pressed do ( densityMap = undefined; syncEnable() )
        on rolDist open do syncEnable()
    )

    /*  Everything that only means something along a path. Spread and Align
        moved here from Distribution so path options sit in one place -- their
        params kept their paramblock slot and sync by hand.  */
    rollout rolPath "Spline options"
    (
        checkbox chkAlignP "Align to path" \
            tooltip:"Item X axis follows the path direction, like a Sweep"
        checkbox chkEven   "Space by distance" \
            tooltip:"Spacing decides how many fit; Count is ignored"
        spinner spnSpacing "Spacing " type:#worldunits range:[0.001, 1e9, 100] fieldwidth:56
        spinner spnTrimS   "Trim start %" type:#float range:[0, 100, 0] fieldwidth:48 across:2
        spinner spnTrimE   "end %" type:#float range:[0, 100, 100] fieldwidth:48

        label lblOff "Offset from the path" align:#left offset:[0,8]
        spinner spnOffX  "Side  " type:#worldunits range:[-1e9, 1e9, 0] fieldwidth:56 \
            tooltip:"Constant sideways shift; negative goes to the other side"
        spinner spnOffZ  "Height" type:#worldunits range:[-1e9, 1e9, 0] fieldwidth:56
        spinner spnSpread "Spread" type:#worldunits range:[0, 1e9, 0] fieldwidth:56 \
            tooltip:"Random sideways jitter around the path"
        checkbox chkStag "Alternate sides" offset:[0,4] \
            tooltip:"Odd items go one side, even items the other -- fences, tree rows"
        spinner spnStag  "Distance" type:#worldunits range:[0, 1e9, 0] fieldwidth:56

        label lblRot "Rotation along the path" align:#left offset:[0,8]
        spinner spnRoll "Roll  " type:#float range:[-360, 360, 0] fieldwidth:56 \
            tooltip:"Fixed spin around the path axis, degrees"
        spinner spnBank "Bank  " type:#float range:[0, 1, 0] scale:0.01 fieldwidth:56 \
            tooltip:"Lean into the curves; 0 = never, 1 = full lean"

        label lblSc "Scale along the path" align:#left offset:[0,8]
        spinner spnScS "Start " type:#float range:[0.001, 100, 1] scale:0.01 fieldwidth:48 across:2
        spinner spnScE "End   " type:#float range:[0.001, 100, 1] scale:0.01 fieldwidth:48
        spinner spnScLat "Shrink by side dist" type:#float range:[0, 1, 0] scale:0.01 fieldwidth:48 \
            tooltip:"Items further from the axis get smaller; needs Spread, Side or Alternate"

        fn syncEnable =
        (
            spnSpacing.enabled = pathEven
            spnStag.enabled = pathStagger
            local lat = pathSpread != 0.0 or pathOffX != 0.0 or pathStagger
            spnScLat.enabled = lat
            try (rolDist.syncEnable()) catch()
        )

        /* pathSpread / alignPath have no ui: binding -- sync both ways here. */
        fn loadUI =
        (
            chkAlignP.checked = alignPath
            spnSpread.value   = pathSpread
            syncEnable()
        )

        on chkAlignP changed v do ( alignPath = v; MaxScatterObj_regen this )
        on spnSpread changed v do ( pathSpread = v; syncEnable(); MaxScatterObj_regen this )
        on rolPath open do loadUI()
    )

    rollout rolXform "Transform (per source)"
    (
        spinner spnAlign "Align to normal" type:#float range:[0, 1, 1] scale:0.01 fieldwidth:50 \
            tooltip:"Global. 1 = follow the surface, 0 = stand upright"

        label lblCur "Source: -" align:#left offset:[0,6]
        label lblR "Rotation min/max (deg)" align:#left
        spinner spnRxMin "X " type:#float range:[-360, 360, 0] fieldwidth:48 across:2
        spinner spnRxMax ""   type:#float range:[-360, 360, 0] fieldwidth:48
        spinner spnRyMin "Y " type:#float range:[-360, 360, 0] fieldwidth:48 across:2
        spinner spnRyMax ""   type:#float range:[-360, 360, 0] fieldwidth:48
        spinner spnRzMin "Z " type:#float range:[-360, 360, 0]   fieldwidth:48 across:2
        spinner spnRzMax ""   type:#float range:[-360, 360, 360] fieldwidth:48

        checkbox chkUni "Uniform scale" checked:true offset:[0,6]
        spinner spnSMin  "min " type:#float range:[0.001, 100, 0.9] scale:0.01 fieldwidth:48 across:2
        spinner spnSMax  "max " type:#float range:[0.001, 100, 1.1] scale:0.01 fieldwidth:48
        spinner spnSxMin "X " type:#float range:[0.001, 100, 1] scale:0.01 fieldwidth:48 across:2
        spinner spnSxMax ""   type:#float range:[0.001, 100, 1] scale:0.01 fieldwidth:48
        spinner spnSyMin "Y " type:#float range:[0.001, 100, 1] scale:0.01 fieldwidth:48 across:2
        spinner spnSyMax ""   type:#float range:[0.001, 100, 1] scale:0.01 fieldwidth:48
        spinner spnSzMin "Z " type:#float range:[0.001, 100, 1] scale:0.01 fieldwidth:48 across:2
        spinner spnSzMax ""   type:#float range:[0.001, 100, 1] scale:0.01 fieldwidth:48

        label lblO "Z offset min/max" align:#left offset:[0,6]
        spinner spnZoMin "" type:#float range:[-1e9, 1e9, 0] fieldwidth:48 across:2
        spinner spnZoMax "" type:#float range:[-1e9, 1e9, 0] fieldwidth:48

        local loading_ui = false

        fn curSel = ( try (rolSrc.lbS.selection) catch 0 )

        fn syncScaleEnable =
        (
            local u = chkUni.checked
            spnSMin.enabled = u;      spnSMax.enabled = u
            spnSxMin.enabled = not u; spnSxMax.enabled = not u
            spnSyMin.enabled = not u; spnSyMax.enabled = not u
            spnSzMin.enabled = not u; spnSzMax.enabled = not u
        )

        fn loadSel =
        (
            local sel = curSel()
            local has = sel > 0 and sel <= srcXforms.count
            for c in #(spnRxMin, spnRxMax, spnRyMin, spnRyMax, spnRzMin, spnRzMax, chkUni, \
                       spnSMin, spnSMax, spnSxMin, spnSxMax, spnSyMin, spnSyMax, \
                       spnSzMin, spnSzMax, spnZoMin, spnZoMax) do c.enabled = has
            if has then
            (
                loading_ui = true
                local pp = MaxScatter.pipeline.strToPP srcXforms[sel]
                lblCur.text = "Source: " + \
                    (if isValidNode srcNodes[sel] then srcNodes[sel].name else "?")
                spnRxMin.value = pp.rxMin; spnRxMax.value = pp.rxMax
                spnRyMin.value = pp.ryMin; spnRyMax.value = pp.ryMax
                spnRzMin.value = pp.rzMin; spnRzMax.value = pp.rzMax
                chkUni.checked = pp.uniScale
                spnSMin.value  = pp.sMin;  spnSMax.value  = pp.sMax
                spnSxMin.value = pp.sxMin; spnSxMax.value = pp.sxMax
                spnSyMin.value = pp.syMin; spnSyMax.value = pp.syMax
                spnSzMin.value = pp.szMin; spnSzMax.value = pp.szMax
                spnZoMin.value = pp.zoMin; spnZoMax.value = pp.zoMax
                syncScaleEnable()
                loading_ui = false
            )
            else lblCur.text = "Source: -"
        )

        fn storeSel =
        (
            local sel = curSel()
            if not loading_ui and sel > 0 and sel <= srcXforms.count do
            (
                local pp = MaxScatter_PlaceParams \
                    rxMin:spnRxMin.value rxMax:spnRxMax.value \
                    ryMin:spnRyMin.value ryMax:spnRyMax.value \
                    rzMin:spnRzMin.value rzMax:spnRzMax.value \
                    uniScale:chkUni.checked \
                    sMin:spnSMin.value sMax:spnSMax.value \
                    sxMin:spnSxMin.value sxMax:spnSxMax.value \
                    syMin:spnSyMin.value syMax:spnSyMax.value \
                    szMin:spnSzMin.value szMax:spnSzMax.value \
                    zoMin:spnZoMin.value zoMax:spnZoMax.value
                srcXforms[sel] = MaxScatter.pipeline.ppToStr pp
                MaxScatterObj_regen this
            )
        )

        on spnRxMin changed v do storeSel()
        on spnRxMax changed v do storeSel()
        on spnRyMin changed v do storeSel()
        on spnRyMax changed v do storeSel()
        on spnRzMin changed v do storeSel()
        on spnRzMax changed v do storeSel()
        on chkUni   changed v do ( syncScaleEnable(); storeSel() )
        on spnSMin  changed v do storeSel()
        on spnSMax  changed v do storeSel()
        on spnSxMin changed v do storeSel()
        on spnSxMax changed v do storeSel()
        on spnSyMin changed v do storeSel()
        on spnSyMax changed v do storeSel()
        on spnSzMin changed v do storeSel()
        on spnSzMax changed v do storeSel()
        on spnZoMin changed v do storeSel()
        on spnZoMax changed v do storeSel()

        on rolXform open do loadSel()
    )

    rollout rolLim "Limits"
    (
        checkbox chkSlope "Slope (deg)"
        spinner spnSlopeMin "min " type:#float range:[0, 180, 0]  fieldwidth:48 across:2
        spinner spnSlopeMax "max " type:#float range:[0, 180, 45] fieldwidth:48
        checkbox chkAlt "Altitude (world Z)" offset:[0,6]
        spinner spnAltMin "min " type:#float range:[-1e9, 1e9, 0]     fieldwidth:60 across:2
        spinner spnAltMax "max " type:#float range:[-1e9, 1e9, 10000] fieldwidth:60

        fn syncEnable =
        (
            local surf = distMode == 1
            spnSlopeMin.enabled = surf and useSlope; spnSlopeMax.enabled = surf and useSlope
            chkSlope.enabled = surf
            spnAltMin.enabled = useAlt; spnAltMax.enabled = useAlt
        )
        on chkSlope changed v do syncEnable()
        on chkAlt   changed v do syncEnable()
        on rolLim open do syncEnable()
    )

    rollout rolCam "Camera"
    (
        pickbutton pbCam "Pick camera" width:100 across:2 filter:MaxScatter_filterCam \
            tooltip:"Cull to this camera's frustum; re-culls automatically when the camera moves"
        button btnClrC "x" width:20 tooltip:"Clear camera (no culling)"
        spinner spnPad  "FOV pad (deg)" type:#float range:[-90, 90, 5] fieldwidth:48 \
            tooltip:"Expands (+) or tightens (-) the culling frustum"
        spinner spnBack "Behind dist  " type:#float range:[0, 1e9, 1000] fieldwidth:60 \
            tooltip:"Keep instances up to this distance behind the camera (shadows, reflections)"
        checkbox chkFar "Far limit" offset:[0,4]
        spinner spnFar  "dist " type:#float range:[0, 1e9, 50000] fieldwidth:60

        fn refresh =
        (
            pbCam.text = if isValidNode camNode then camNode.name else "Pick camera"
            spnFar.enabled = useFar
        )
        on pbCam picked o do ( if o != undefined do camNode = o; refresh() )
        on btnClrC pressed do ( camNode = undefined; refresh() )
        on chkFar  changed v do refresh()
        on rolCam open do refresh()
    )

    rollout rolDisp "Display"
    (
        dropdownlist ddlEmit "Emitter" items:#("Instances", "Proxy (render-time)") width:130 \
            tooltip:"Instances: real nodes, every renderer + IPR. Proxy: one display mesh, real nodes exist only while rendering."
        dropdownlist ddlDisp "Instances view" items:#("Full", "Box", "Wire box") width:100
        dropdownlist ddlPrx  "Proxy view" items:#("Box", "Cone", "Point cloud") width:100
        spinner spnPct "Display %   " type:#integer range:[1, 100, 100] fieldwidth:44 \
            tooltip:"Thins the proxy display only; the render is always complete"
        spinner spnPts "Points/item " type:#integer range:[1, 2000, 20] fieldwidth:44 \
            tooltip:"Point cloud density per item, like Corona's previz"
        spinner spnIcon "Icon size   " type:#worldunits range:[1, 1e9, 100] fieldwidth:56 \
            tooltip:"Size of the MaxScatter sign in the viewport; drag while creating also sets it"
        button btnBake "Bake" width:100 offset:[0,8] \
            tooltip:"Detach all instances from the scatter (Instances emitter)"
        hyperLink lnkRepo "MaxScatter on GitHub" \
            address:"https://github.com/JuanMaldini/3d-max-scatter" \
            color:(color 60 190 210) hovercolor:(color 130 225 245) offset:[0,8]

        fn syncDisp =
        (
            local inst = emitMode == 1
            ddlDisp.enabled = inst
            ddlPrx.enabled  = not inst
            spnPct.enabled  = not inst
            spnPts.enabled  = not inst and prxMode == 3
            btnBake.enabled = inst
        )
        on ddlEmit selected i do ( emitMode = i; syncDisp() )
        on ddlDisp selected i do dispMode = i
        on ddlPrx  selected i do ( prxMode = i; syncDisp() )
        on btnBake pressed do
        (
            if isValidNode itemHolder do
            (
                local kids = for c in itemHolder.children collect c
                for c in kids do c.parent = undefined
                if kids.count > 0 do select kids
            )
        )
        on rolDisp open do
        (
            ddlEmit.selection = emitMode
            ddlDisp.selection = dispMode
            ddlPrx.selection  = prxMode
            syncDisp()
        )
    )

    /*  The world presence: "MaxScatter" text in a white rectangle, scaled to
        iconSize per instance (cached; rebuilt only when the size changes).
        The base mesh is baked data, so asking for it here is safe -- no scene
        node gets created and the sign is correct from the first redraw.  */
    local gzCache
    local gzKey = -1.0

    on getDisplayMesh do
    (
        local msh = undefined
        if emitMode == 2 do
        (
            local deps = refs.dependentNodes this
            if deps.count > 0 do msh = MaxScatter.emitDisplay.meshFor deps[1].inode.handle
        )
        if msh == undefined or msh.numVerts == 0 do
        (
            local base = MaxScatter.emitDisplay.gizmo()
            if gzCache == undefined or gzKey != iconSize do
            (
                local f = iconSize / (amax 0.001 MaxScatter.emitDisplay.gizmoW)
                gzCache = copy base
                for v = 1 to gzCache.numVerts do setVert gzCache v ((getVert base v) * f)
                gzKey = iconSize
            )
            msh = gzCache
        )
        msh
    )
    on useWireColor do true

    on attachedToNode n do if not loading do
    (
        n.wirecolor = white
        try ((MaxScatter.ensureLayer()).addNode n) catch()
    )

    /*  Container cleanup on delete lives in pipeline.ms (#nodePreDelete):
        the plugin's own `on deleted` fires after the paramblock detaches.  */

    /* Click places; drag before releasing sizes the sign (min 1 m). */
    tool create numPoints:2
    (
        on mousePoint click do case click of
        (
            1: nodeTM.translation = gridPoint
            2: #stop
        )
        on mouseMove click do if click == 2 do
            iconSize = amax (try (units.decodeValue "1m") catch 100.0) (length gridDist)
    )
)
