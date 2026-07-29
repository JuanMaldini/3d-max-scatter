/*  MaxScatter -- bootstrap

    Loads every module in dependency order. This is the only file anything else
    needs to know about: the macroscript, the dev reloader and the installer all
    fileIn this one.
*/

-- Must be declared here too: this file is compiled before ns.ms runs, so an
-- undeclared reference would bind to a file-local instead of the global.
global MaxScatter

(
    local root = getFilenamePath (getSourceFileName())

    local modules = #(
        "core\\ns.ms",
        "core\\rng.ms",
        "core\\sampling.ms",
        "core\\filters.ms",
        "core\\transform.ms",
        "emit\\emit_nodes.ms",
        "emit\\gizmo_data.ms",
        "emit\\emit_display.ms",
        "core\\pipeline.ms",
        "ui\\theme.ms",
        "ui\\menu.ms",
        "plugin\\scatter_helper.ms"
    )

    local failed = 0
    for m in modules do
    (
        local p = root + m
        if doesFileExist p then
        (
            try ( fileIn p )
            catch
            (
                failed += 1
                format "[MaxScatter] error loading %:\n  %\n" m (getCurrentException())
            )
        )
        else
        (
            failed += 1
            format "[MaxScatter] missing module: %\n" p
        )
    )

    if failed == 0 then
    (
        MaxScatter.rootDir = root
        format "[MaxScatter] v% loaded (% modules)\n" MaxScatter.version modules.count
    )
    else
        format "[MaxScatter] load finished with % problem(s)\n" failed

    /*  Main menu entry. On 2024 this builds it through menuMan; on 2025+ the
        package's Contents/cui/MaxScatter.mnx owns the menu and this only reports
        whether it is there yet, so a "not on the bar" result at load time is not
        an error -- the host may not have built its menu configuration yet. See
        ui/menu.ms.  */
    if failed == 0 do
        try
        (
            local legacy = (MaxScatter.menu.cuiMgr()) == undefined
            if not (MaxScatter.menu.install()) and legacy do
                format "[MaxScatter] menu not added -- use the toolbar button (Customize UI > Toolbars > MaxScatter)\n"
        )
        catch ( format "[MaxScatter] menu install skipped: %\n" (getCurrentException()) )
)
