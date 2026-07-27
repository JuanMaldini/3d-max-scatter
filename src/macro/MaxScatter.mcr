/*  MaxScatter -- toolbar / menu entry

    Click the button, then click anywhere in a viewport: the helper is placed
    at that point (the plugin's own create tool handles the click). Icon files
    MaxScatter_<size>.png live in usericons.
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
            local p = (getDir #userScripts) + "\\MaxScatter\\init.ms"
            if doesFileExist p then fileIn p
            else format "[MaxScatter] not found at %\n" p
        )

        if (classOf MaxScatterObj) != undefined or MaxScatter != undefined then
            startObjectCreation MaxScatterObj
        else messageBox "MaxScatter could not be loaded.\nCheck the MAXScript Listener." title:"MaxScatter"
    )
)
