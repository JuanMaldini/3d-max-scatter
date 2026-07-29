/*  MaxScatter -- .mzp installer

    Runs from inside the extracted .mzp. Everything is laid out here already in
    package shape (PackageContents.xml + Contents\...), so this script's job is
    to move that tree to where Max looks for application packages, and to load
    it immediately so there is no restart before first use.

        %APPDATA%\Autodesk\ApplicationPlugins\MaxScatter

    Per-user rather than %ALLUSERSPROFILE%: Max scans both and this one needs no
    administrator rights, so a drag-and-drop install never hits an elevation
    prompt it cannot answer.

    One package covers 2024-2027 -- PackageContents.xml decides which releases
    load it. The only per-version step is the toolbar PNGs, which Max resolves
    against each release's own usericons folder.
*/

(
    local srcDir  = getFilenamePath (getSourceFileName())
    local appData = systemTools.getEnvVariable "APPDATA"
    local pkgRoot = appData + "\\Autodesk\\ApplicationPlugins\\MaxScatter"

    fn msFail msg =
    (
        format "[MaxScatter] install FAILED: %\n" msg
        messageBox ("MaxScatter install FAILED:\n\n" + msg + \
            "\n\nSee the MAXScript Listener for details.") title:"MaxScatter"
        false
    )

    /*  Destinations that could not be written, so the failure popup can name
        them instead of only saying that nothing happened.  */
    local copyFails = #()

    /*  Replace one file.

        MAXScript's copyFile does NOT overwrite: handed a destination that
        already exists it copies nothing and returns false. This installer used
        to call it directly, on the assumption that files were "overwritten in
        place" -- so a first install into an empty folder worked, and every
        install OVER a previous release copied zero files and reported only
        "nothing was copied into ...". Clearing the destination first is what
        makes an upgrade possible at all.

        Only individual files are ever deleted, never a folder: a recursive
        delete inside the user's profile is a far worse thing to get wrong than
        a stale module, and init.ms only loads the modules it names, so a
        leftover file is inert.  */
    fn copyOver src dst =
    (
        if doesFileExist dst do
        (
            try ( setFileAttribute dst #readOnly false ) catch()
            try ( deleteFile dst ) catch()
        )
        local done = copyFile src dst
        if not done do append copyFails dst
        done
    )

    /*  Copy a directory tree, returning the number of files copied.

        Iterative, with an explicit worklist, rather than recursive: a `fn`
        defined inside a block cannot reliably call itself in MAXScript without
        being pre-declared, and a worklist has no such rule to remember.

        NB: parameter names avoid MAXScript's reserved words. `from` and `to`
        read perfectly here and are both keywords (`for i = 1 to n`), which is
        the same trap already noted for `where` in core/ns.ms.  */
    fn copyTree srcRoot dstRoot =
    (
        local n = 0
        local pending = #( #(srcRoot, dstRoot) )
        while pending.count > 0 do
        (
            local job = pending[pending.count]
            deleteItem pending pending.count
            -- getDirectories hands back a trailing separator; appending a
            -- wildcard to that yields a path Max will not match
            local s = trimRight job[1] "\\"
            local d = trimRight job[2] "\\"

            makeDir d all:true
            for fl in (getFiles (s + "\\*.*")) do
                if copyOver fl (d + "\\" + (filenameFromPath fl)) do n += 1

            for sub in (getDirectories (s + "\\*")) do
            (
                local parts = filterString sub "\\"
                append pending #(sub, d + "\\" + parts[parts.count])
            )
        )
        n
    )

    local ok = true

    -- Sanity: the .mzp must have extracted in package shape.
    if not (doesFileExist (srcDir + "PackageContents.xml")) then
        ok = msFail ("PackageContents.xml not found in " + srcDir + \
            "\nThe .mzp did not extract as expected.")
    else if (getDirectories (srcDir + "Contents\\*")).count == 0 then
        ok = msFail ("no Contents\\ folder in " + srcDir + \
            "\nThe .mzp did not extract as expected.")

    /*  Replace a development install rather than refusing to run.

        build\dev_link.ps1 fills the package with junctions into the git
        checkout, and copying onto those would write the release straight into
        the working tree. Unlinking them first solves that: `rmdir` WITHOUT /s
        removes a junction and never touches what it points at, and on a real
        directory it simply fails because the directory is not empty -- exactly
        the behaviour wanted, so it is safe to fire at every candidate path.

        Refusing here used to be the behaviour, and it was wrong: it broke the
        one loop that matters -- build, drag, installed -- to guard a case the
        installer can just handle.  */
    local wasDevLink = doesFileExist (pkgRoot + "\\DEV_LINK")
    if ok and wasDevLink do
    (
        format "[MaxScatter] replacing the development link at %\n" pkgRoot
        for sub in #("Contents\\scripts\\MaxScatter", "Contents\\macroscripts",
                     "Contents\\cui", "Contents\\icons") do
            try ( HiddenDOSCommand ("rmdir \"" + pkgRoot + "\\" + sub + "\"") \
                startpath:(getDir #temp) )
            catch()
        deleteFile (pkgRoot + "\\DEV_LINK")
    )

    if ok do
    (
        /*  Retire the pre-package layout. Left in place it would load every
            module a second time from scripts\startup, on top of the package.  */
        for p in #((getDir #userStartupScripts) + "\\MaxScatter_startup.ms",
                   (getDir #userMacros) + "\\MaxScatter.mcr") do
            if doesFileExist p do
                ( deleteFile p; format "[MaxScatter] removed legacy file %\n" p )

        local copied = 0
        try
        (
            makeDir pkgRoot all:true
            /*  The manifest decides which Max releases load the package, so a
                silent failure here would leave the old one deciding.  */
            if not (copyOver (srcDir + "PackageContents.xml") (pkgRoot + "\\PackageContents.xml")) do
                format "[MaxScatter] could not replace %\\PackageContents.xml\n" pkgRoot
            copied = copyTree (srcDir + "Contents") (pkgRoot + "\\Contents")
        )
        catch ( ok = msFail ("could not write to " + pkgRoot + "\n" + (getCurrentException() as string)) )

        /*  Name the files that refused to be written: "nothing was copied" on
            its own gave no way to tell a permissions problem from an empty
            source from copyFile's refusal to overwrite.  */
        if ok and copied == 0 do
        (
            local detail = ""
            if copyFails.count > 0 then
            (
                for i = 1 to (amin 5 copyFails.count) do detail += "\n  " + copyFails[i]
                if copyFails.count > 5 do
                    detail += "\n  ... and " + ((copyFails.count - 5) as string) + " more"
                detail = "\n\nCould not write:" + detail
            )
            else detail = "\n\nNo files were found to copy from " + srcDir + "Contents"
            ok = msFail ("nothing was copied into " + pkgRoot + detail)
        )
        if ok do format "[MaxScatter] % files -> %\n" copied pkgRoot

        -- toolbar icons: per release, where iconName: is resolved
        if ok do try
        (
            local icons = getDir #userIcons
            makeDir icons all:true
            -- copyOver, not copyFile: the icons already sitting there from a
            -- previous install would otherwise never be replaced
            for f in (getFiles (pkgRoot + "\\Contents\\icons\\MaxScatter_*.png")) do
                copyOver f (icons + "\\" + (filenameFromPath f))
        )
        catch ( format "[MaxScatter] icons not installed: %\n" (getCurrentException()) )
    )

    if ok do
    (
        local initPath = pkgRoot + "\\Contents\\scripts\\MaxScatter\\init.ms"
        if not (doesFileExist initPath) then ok = msFail (initPath + " missing after copy")
        else
        (
            fileIn initPath
            local ver = try ( MaxScatter.version ) catch ( "?" )

            /*  Report what actually landed instead of assuming. The menu is the
                part that can fail on its own: the package's .mnx is only read
                when Max starts, so in THIS session the menu has to be built by
                script -- and an install popup that claims success while the
                menu is missing is worse than no popup.  */
            local hasMenu  = try ( MaxScatter.menu.installNow() ) catch false
            local hasClass = (classOf MaxScatterObj) != undefined

            format "[MaxScatter] v% installed for max % -- menu:% class:%\n" \
                ver ((maxVersion())[1]) hasMenu hasClass

            messageBox ("MaxScatter v" + ver + " installed / updated.\n\n" + \
                "Create panel > Helpers > MaxScatter\n" + \
                (if hasMenu then "Main menu: MaxScatter\n" else \
                    "Main menu: appears after you restart 3ds Max.\n") + \
                "Toolbar button: Customize UI > Toolbars > category \"MaxScatter\"\n\n" + \
                "Installed to:\n" + pkgRoot + \
                (if wasDevLink then \
                    "\n\nThis replaced a development link.\nRe-run build\\dev_link.ps1 to go back to editing from the repo." \
                 else "")) \
                title:"MaxScatter"
        )
    )
)
