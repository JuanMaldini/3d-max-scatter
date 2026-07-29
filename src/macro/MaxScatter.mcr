/*  MaxScatter -- toolbar / menu entry

    Click the button, then click anywhere in a viewport: the helper is placed
    at that point (the plugin's own create tool handles the click). Icon files
    MaxScatter_<size>.png live in each release's usericons folder, which is
    where Max resolves iconName:.

    The package's ComponentEntry already loads the plugin at startup, so the
    lookup below is a safety net for a broken or half-finished install -- it
    should never be the thing that loads MaxScatter.
*/

global MaxScatter

macroScript MaxScatter_Create
    category:"MaxScatter"
    tooltip:"MaxScatter — click, then click in the viewport to place"
    buttonText:"MaxScatter"
    iconName:"MaxScatter"
(
    on execute do
    (
        if MaxScatter == undefined do
        (
            local pkg = "\\Autodesk\\ApplicationPlugins\\MaxScatter\\Contents\\scripts\\MaxScatter\\init.ms"
            local candidates = #(
                (systemTools.getEnvVariable "APPDATA") + pkg,
                (systemTools.getEnvVariable "ALLUSERSPROFILE") + pkg,
                (getDir #userScripts) + "\\MaxScatter\\init.ms"   -- pre-package layout
            )
            local found = undefined
            for p in candidates while found == undefined where doesFileExist p do found = p
            if found != undefined then fileIn found
            else format "[MaxScatter] init.ms not found in any of: %\n" candidates
        )

        if (classOf MaxScatterObj) != undefined or MaxScatter != undefined then
            startObjectCreation MaxScatterObj
        else messageBox "MaxScatter could not be loaded.\nCheck the MAXScript Listener." title:"MaxScatter"
    )
)
