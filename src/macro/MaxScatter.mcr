/*  MaxScatter -- toolbar / menu entry

    Creates a MaxScatter object in the scene and jumps to the Modify panel.
    The object is also available under Create > Helpers > MaxScatter.
*/

global MaxScatter

macroScript MaxScatter_Create
    category:"MaxScatter"
    tooltip:"Create MaxScatter object"
    buttonText:"MaxScatter"
(
    on execute do
    (
        if MaxScatter == undefined do
        (
            local p = (getDir #userScripts) + "\\MaxScatter\\init.ms"
            if doesFileExist p then fileIn p
            else format "[MaxScatter] not found at %\n" p
        )

        if (classOf MaxScatterObj) == #Class or MaxScatter != undefined then
        (
            local o = MaxScatterObj()
            o.name = uniqueName "MaxScatter_"
            o.wirecolor = white
            select o
            max modify mode
        )
        else messageBox "MaxScatter could not be loaded.\nCheck the MAXScript Listener." title:"MaxScatter"
    )
)
