/*  MaxScatter -- post-install (runs from inside the .mzp)

    The files are already in place (treecopy/copy in mzp.run). This script:
    1. writes the startup stub -- scripted plugin classes must exist BEFORE a
       saved scene that uses them is opened, or its objects load as Missing
       Plugin;
    2. loads the plugin right now, so there is no restart needed.
*/

(
    local stubDir = getDir #userStartupScripts
    local stub = stubDir + "\\MaxScatter_startup.ms"
    if not (doesFileExist stubDir) do makeDir stubDir all:true

    local f = createFile stub
    if f != undefined do
    (
        format "-- MaxScatter: load the plugin class before any scene opens\n" to:f
        format "(\n" to:f
        format "    local p = (getDir #userScripts) + \"\\\\MaxScatter\\\\init.ms\"\n" to:f
        format "    if doesFileExist p do fileIn p\n" to:f
        format ")\n" to:f
        close f
    )

    local initPath = (getDir #userScripts) + "\\MaxScatter\\init.ms"
    if doesFileExist initPath then
    (
        fileIn initPath
        local ver = try ( MaxScatter.version ) catch ( "?" )
        format "[MaxScatter] v% installed. Create panel > Helpers > MaxScatter, or add the toolbar button (category MaxScatter).\n" ver
        messageBox ("MaxScatter v" + ver + " installed / updated.\n\nCreate panel > Helpers > MaxScatter\nToolbar button: category \"MaxScatter\"") title:"MaxScatter"
    )
    else
    (
        format "[MaxScatter] install problem: % not found\n" initPath
        messageBox ("MaxScatter install FAILED:\n" + initPath + " not found.\nCheck the MAXScript Listener.") title:"MaxScatter"
    )
)
