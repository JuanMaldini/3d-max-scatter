/*  MaxScatter -- global namespace
    https://github.com/JuanMaldini/3d-max-scatter
    MIT License

    Every module hangs off the single global `MaxScatter`. File-level variables
    in MAXScript are local to their file unless declared global, so this is the
    only global the package owns.
*/

global MaxScatter

struct MaxScatterNS
(
    version   = "1.0.0",
    repoUrl   = "https://github.com/JuanMaldini/3d-max-scatter",
    rootDir   = "",

    -- module slots, filled by each module as it loads
    rng         = undefined,
    sampling    = undefined,
    filters     = undefined,
    transform   = undefined,
    emitNodes   = undefined,
    gizmoData   = undefined,
    emitDisplay = undefined,
    pipeline    = undefined,
    theme       = undefined,
    menu        = undefined,
    state       = undefined,
    pendingRegen = #(),    -- plugin instances queued by the regen debounce
    pendingCleanup = #(),  -- item containers whose scatter object was deleted

    layerName = "MaxScatter",

    /* Scene layer every MaxScatter node lives on; created on demand. */
    fn ensureLayer =
    (
        local lay = LayerManager.getLayerFromName this.layerName
        if lay == undefined do lay = LayerManager.newLayerFromName this.layerName
        lay
    ),

    logPath = (getDir #temp) + "\\MaxScatter.log",
    devLog  = false,   -- dev only: dev_reload.ms turns it on; releases ship with it off

    /* Listener always; file only while developing, so errors survive popups. */
    fn log msg =
    (
        format "[MaxScatter] %\n" msg
        if this.devLog do try
        (
            local f = openFile this.logPath mode:"a"
            if f == undefined do f = createFile this.logPath
            format "% | %\n" localTime msg to:f
            close f
        )
        catch()
    ),

    -- NB: `where` is reserved (for..where); don't use it as a parameter name
    fn logErr ctx err = ( this.log ("ERROR in " + ctx + ": " + (err as string)) )
)

MaxScatter = MaxScatterNS()
