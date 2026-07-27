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
    )

    parameters pbDist rollout:rolDist
    (
        distMode   type:#integer    default:1 ui:rdoMode      -- 1 surface, 2 spline path
        useDensity type:#boolean    default:false ui:chkDens
        numItems   type:#integer    default:200 ui:spnCount
        density    type:#float      default:0.001 ui:spnDensity
        seedVal    type:#integer    default:12345 ui:spnSeed
        pathSpread type:#float      default:0.0 ui:spnSpread
        alignPath  type:#boolean    default:true ui:chkAlignP
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
        rtTick   type:#integer default:0 animatable:false invisibleInTV:true

        on emitMode set v do if not loading do MaxScatterObj_regen this
        on dispMode set v do if not loading do
        (
            local deps = refs.dependentNodes this
            if deps.count > 0 do MaxScatter.emitNodes.restyle deps[1] v
        )
        on prxMode  set v do if not loading and emitMode == 2 do MaxScatter_rtRestyle this
        on dispPct  set v do if not loading and emitMode == 2 do MaxScatter_rtRestyle this
        on pcPoints set v do if not loading and emitMode == 2 do MaxScatter_rtRestyle this
    )

    rollout rolSrc "Sources"
    (
        listbox    lbS     "" items:#() height:5
        pickbutton pbAddS  "+ Add"  width:66 across:2 filter:MaxScatter_filterSrc \
            tooltip:"Pick an object, group or hierarchy to scatter"
        button     btnDelS "Remove" width:66
        spinner    spnProb "Prob " type:#float range:[0, 1, 1] scale:0.01 fieldwidth:50 \
            tooltip:"Chance 0-1 that this item appears at each scattered point. Probabilities summing under 1 leave the rest empty."

        label      lbl2 "Surfaces" align:#left offset:[0,8]
        listbox    lbT     "" items:#() height:4
        pickbutton pbAddT  "+ Add"  width:66 across:2 filter:MaxScatter_filterGeo
        button     btnDelT "Remove" width:66

        label      lbl5 "Spline paths" align:#left offset:[0,8]
        listbox    lbP     "" items:#() height:3
        pickbutton pbAddP  "+ Add"  width:66 across:2 filter:MaxScatter_filterShape \
            tooltip:"Open or closed splines used as paths (Spline mode)"
        button     btnDelP "Remove" width:66

        label      lbl3 "Include splines" align:#left offset:[0,8]
        listbox    lbI     "" items:#() height:3
        pickbutton pbAddI  "+ Add"  width:66 across:2 filter:MaxScatter_filterShape \
            tooltip:"Closed splines: scatter only inside them"
        button     btnDelI "Remove" width:66

        label      lbl4 "Exclude splines" align:#left offset:[0,8]
        listbox    lbE     "" items:#() height:3
        pickbutton pbAddE  "+ Add"  width:66 across:2 filter:MaxScatter_filterShape \
            tooltip:"Closed splines: never scatter inside them"
        button     btnDelE "Remove" width:66

        fn refresh =
        (
            lbS.items = for i = 1 to srcNodes.count collect
            (
                local nm = if isValidNode srcNodes[i] then srcNodes[i].name else "<deleted>"
                local w  = if i <= srcWeights.count then srcWeights[i] else 1.0
                nm + "   " + (formattedPrint w format:"0.2f")
            )
            lbT.items = for s in surfNodes   collect (if isValidNode s then s.name else "<deleted>")
            lbP.items = for s in pathSplines collect (if isValidNode s then s.name else "<deleted>")
            lbI.items = for s in inclSplines collect (if isValidNode s then s.name else "<deleted>")
            lbE.items = for s in exclSplines collect (if isValidNode s then s.name else "<deleted>")
            local sel = lbS.selection
            spnProb.enabled = (sel > 0 and sel <= srcWeights.count)
            if spnProb.enabled do spnProb.value = srcWeights[sel]
            try (rolXform.loadSel()) catch()
        )

        fn syncMode =
        (
            local surf = distMode == 1
            lbT.enabled = surf;     pbAddT.enabled = surf; btnDelT.enabled = surf
            lbP.enabled = not surf; pbAddP.enabled = not surf; btnDelP.enabled = not surf
        )

        on pbAddS picked o do
        (
            if o != undefined do
            (
                srcNodes.count += 1;   srcNodes[srcNodes.count] = o
                srcWeights.count += 1; srcWeights[srcWeights.count] = 1.0
                srcXforms.count += 1;  srcXforms[srcXforms.count] = MaxScatter.pipeline.defXform
                lbS.selection = srcNodes.count
                refresh()
                MaxScatterObj_regen this
            )
            pbAddS.text = "+ Add"
        )
        on btnDelS pressed do
        (
            local sel = lbS.selection
            if sel > 0 and sel <= srcNodes.count do
            (
                for i = sel to srcNodes.count - 1 do
                (
                    srcNodes[i]   = srcNodes[i + 1]
                    srcWeights[i] = srcWeights[i + 1]
                    srcXforms[i]  = srcXforms[i + 1]
                )
                srcNodes.count -= 1; srcWeights.count -= 1; srcXforms.count -= 1
                refresh()
                MaxScatterObj_regen this
            )
        )
        on lbS selected idx do refresh()
        on spnProb changed v do
        (
            local sel = lbS.selection
            if sel > 0 and sel <= srcWeights.count do
            (
                srcWeights[sel] = v
                refresh()
                MaxScatterObj_regen this
            )
        )

        on pbAddT picked o do
        (
            if o != undefined do ( surfNodes.count += 1; surfNodes[surfNodes.count] = o; refresh(); MaxScatterObj_regen this )
            pbAddT.text = "+ Add"
        )
        on btnDelT pressed do
        (
            local sel = lbT.selection
            if sel > 0 and sel <= surfNodes.count do
            (
                for i = sel to surfNodes.count - 1 do surfNodes[i] = surfNodes[i + 1]
                surfNodes.count -= 1
                refresh(); MaxScatterObj_regen this
            )
        )

        on pbAddP picked o do
        (
            if o != undefined do ( pathSplines.count += 1; pathSplines[pathSplines.count] = o; refresh(); MaxScatterObj_regen this )
            pbAddP.text = "+ Add"
        )
        on btnDelP pressed do
        (
            local sel = lbP.selection
            if sel > 0 and sel <= pathSplines.count do
            (
                for i = sel to pathSplines.count - 1 do pathSplines[i] = pathSplines[i + 1]
                pathSplines.count -= 1
                refresh(); MaxScatterObj_regen this
            )
        )

        on pbAddI picked o do
        (
            if o != undefined do ( inclSplines.count += 1; inclSplines[inclSplines.count] = o; refresh(); MaxScatterObj_regen this )
            pbAddI.text = "+ Add"
        )
        on btnDelI pressed do
        (
            local sel = lbI.selection
            if sel > 0 and sel <= inclSplines.count do
            (
                for i = sel to inclSplines.count - 1 do inclSplines[i] = inclSplines[i + 1]
                inclSplines.count -= 1
                refresh(); MaxScatterObj_regen this
            )
        )

        on pbAddE picked o do
        (
            if o != undefined do ( exclSplines.count += 1; exclSplines[exclSplines.count] = o; refresh(); MaxScatterObj_regen this )
            pbAddE.text = "+ Add"
        )
        on btnDelE pressed do
        (
            local sel = lbE.selection
            if sel > 0 and sel <= exclSplines.count do
            (
                for i = sel to exclSplines.count - 1 do exclSplines[i] = exclSplines[i + 1]
                exclSplines.count -= 1
                refresh(); MaxScatterObj_regen this
            )
        )

        on rolSrc open do ( refresh(); syncMode() )
    )

    rollout rolDist "Distribution"
    (
        radiobuttons rdoMode "" labels:#("Surface", "Spline") columns:2
        checkbox chkDens   "Use density"
        spinner  spnCount   "Count  " type:#integer range:[1, 1000000, 200] fieldwidth:60
        spinner  spnDensity "Density" type:#float range:[0.000001, 1000, 0.001] scale:0.0001 fieldwidth:60 \
            tooltip:"Items per square unit on surfaces, per length unit on splines"
        spinner  spnSeed    "Seed   " type:#integer range:[0, 999999, 12345] fieldwidth:60
        spinner  spnSpread  "Spread " type:#float range:[0, 1e9, 0] fieldwidth:60 \
            tooltip:"Lateral jitter around the path (Spline mode)"
        checkbox chkAlignP  "Align to path" \
            tooltip:"Item X axis follows the path direction, like a Sweep"
        mapbutton mbDens "Density Map" width:100 across:2 offset:[0,6] \
            tooltip:"Luminance drives keep probability; needs UVs on the surface"
        button    btnClrD "x" width:20 offset:[0,6] tooltip:"Clear density map"
        spinner  spnMapAmt  "Amount" type:#float range:[0, 1, 1] scale:0.01 fieldwidth:48 across:2
        checkbox chkMapInv  "Invert"
        spinner  spnMapGam  "Gamma " type:#float range:[0.1, 10, 1] scale:0.05 fieldwidth:48 across:2
        spinner  spnMapTile "Tile  " type:#float range:[0.01, 1000, 1] fieldwidth:48

        fn syncEnable =
        (
            local surf = distMode == 1
            spnCount.enabled   = not useDensity
            spnDensity.enabled = useDensity
            spnSpread.enabled  = not surf
            chkAlignP.enabled  = not surf
            mbDens.enabled = surf
            btnClrD.enabled = surf
            local hasMap = surf and densityMap != undefined
            spnMapAmt.enabled = hasMap; chkMapInv.enabled = hasMap
            spnMapGam.enabled = hasMap; spnMapTile.enabled = hasMap
            try (rolSrc.syncMode()) catch()
            try
            (
                rolLim.chkSlope.enabled = surf
                rolLim.spnSlopeMin.enabled = surf and useSlope
                rolLim.spnSlopeMax.enabled = surf and useSlope
            )
            catch()
        )
        on rdoMode  changed s do syncEnable()
        on chkDens  changed v do syncEnable()
        on mbDens   picked m do syncEnable()
        on btnClrD  pressed do ( densityMap = undefined; syncEnable() )
        on rolDist open do syncEnable()
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
            local deps = refs.dependentNodes this
            if deps.count > 0 and isValidNode deps[1] do
            (
                local kids = for c in deps[1].children collect c
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

    /*  The world presence: "MaxScatter" text in a white rectangle. Cached
        meshes only -- building happens in regen / creation, never here.  */
    on getDisplayMesh do
    (
        local msh = undefined
        if emitMode == 2 do
        (
            local deps = refs.dependentNodes this
            if deps.count > 0 do msh = MaxScatter.emitDisplay.meshFor deps[1].inode.handle
        )
        if msh == undefined or msh.numVerts == 0 do msh = MaxScatter.emitDisplay.gizmo()
        msh
    )
    on useWireColor do true

    /*  NB: don't build the gizmo here -- creating helper nodes inside the
        plugin's own creation context yields an empty snapshot. The pipeline
        builds it on the first regen instead.  */
    on attachedToNode n do if not loading do n.wirecolor = white

    tool create
    (
        on mousePoint click do ( nodeTM.translation = gridPoint; #stop )
    )
)
