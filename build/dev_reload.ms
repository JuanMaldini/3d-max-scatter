/*  MaxScatter -- dev hot reload

    Reloads every module from the junctioned source and reopens the UI.
    Bind this to a keyboard shortcut: Customize > Hotkeys > Category "MaxScatter".

    Run from the repo, or from the installed junction -- both resolve the same files.
*/

global MaxScatter_openUI

(
    local here = getFilenamePath (getSourceFileName())          -- ...\build\
    local repoSrc = here + "..\\src\\MaxScatter\\init.ms"
    local installed = (getDir #userScripts) + "\\MaxScatter\\init.ms"

    local target = if doesFileExist repoSrc then repoSrc else installed

    if doesFileExist target then
    (
        fileIn target
        MaxScatter.devLog = true   -- dev sessions log to (getDir #temp)\MaxScatter.log
    )
    else
        format "[MaxScatter] no init.ms found (tried % and %)\n" repoSrc installed
)
