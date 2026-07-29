/*  MaxScatter -- main menu entry

    3ds Max has two menu systems and MaxScatter covers both:

    - 2024 and earlier: the legacy `menuMan`, built imperatively at load time.
      This file does it.
    - 2025 and later:   `menuMan` is GONE. The host assembles menus from menu
      configurations, and a plugin declares its entry in a .mnx registered as a
      package component -- Contents/cui/MaxScatter.mnx does that, with no script
      involved, which is why it survives workspace switches and CUI resets.

    So on 2025+ there is normally nothing to do here. The one case that still
    needs code is the session in which MaxScatter was just installed: the
    package's .mnx is only read when Max starts, so a fresh .mzp install would
    otherwise leave the user staring at a missing menu until a restart. For that
    session only, we register a #cuiRegisterMenus handler and ask for one
    configuration reload to fire it.

    That reload is deliberately NOT the normal path. #cuiRegisterMenus fires
    early in startup, before any user script runs, so a script-registered
    handler always misses the initial build and has to force a full menu-bar
    rebuild to catch up -- once per launch, for every launch. Declaring the menu
    in the package moves the work to where the host already does it.

    Reference: MAXtoA.mnx (top-level menu via package .mnx) and the shipped
    ApplicationPlugins/CivilViewIO scripts (the 2025+ callback API).
*/

global MaxScatter
global MaxScatter_menuCB

/*  Stable GUIDs, lowercase to match the .mnx. These identify our items across
    sessions and workspace switches -- never regenerate them, or old workspaces
    keep a dead entry.  */
global MaxScatter_menuId    = "7bfc7fee-410e-447b-9179-65eb0c6f38b3"
global MaxScatter_menuActId = "0b32d450-dac0-4aa4-ab71-89c464219841"

/*  3ds Max's own Help menu -- we insert just before it so MaxScatter lands at
    the right end of the bar instead of after Help.  */
global MaxScatter_helpMenuId = "cee8f758-2199-411b-81e7-d3ff4a80d143"

/*  The action is addressed as "<macroScript name>`<category>" in the
    macroScript action table (647394).  */
global MaxScatter_menuAction = "MaxScatter_Create`MaxScatter"

/*  Must be a global fn taking no arguments: callback bodies cannot capture
    outer locals, and the manager arrives through notificationParam().  */
fn MaxScatter_menuCB =
(
    local done = false
    try
    (
        local mgr = callbacks.notificationParam()
        if mgr != undefined do
        (
            -- idempotent: the host may fire this more than once per session
            if (mgr.GetMenuItemById MaxScatter_menuId) != undefined then done = true
            else
            (
                local bar = mgr.mainMenuBar
                local sub = if (mgr.GetMenuItemById MaxScatter_helpMenuId) == undefined then
                        (bar.CreateSubMenu MaxScatter_menuId "MaxScatter")
                    else
                        (bar.CreateSubMenu MaxScatter_menuId "MaxScatter" beforeId:MaxScatter_helpMenuId)
                if sub != undefined do
                (
                    sub.CreateAction MaxScatter_menuActId 647394 MaxScatter_menuAction
                    done = true
                )
            )
        )
    )
    catch ( if MaxScatter != undefined do MaxScatter.logErr "menuCB" (getCurrentException()) )
    done
)

struct MaxScatter_Menu
(
    /*  The 2025+ manager, or undefined on 2024 and earlier. Feature detection
        rather than a version number: the day Autodesk moves this again, the
        legacy branch is still the honest fallback.  */
    fn cuiMgr = ( try ( maxOps.GetICuiMenuMgr() ) catch undefined ),

    fn installLegacy =
    (
        local ok = false
        try
        (
            if (menuMan.findMenu "MaxScatter") != undefined then ok = true
            else
            (
                local m = menuMan.createMenu "MaxScatter"
                local ai = menuMan.createActionItem "MaxScatter_Create" "MaxScatter"
                if ai != undefined do
                (
                    m.addItem ai -1
                    (menuMan.getMainMenuBar()).addItem (menuMan.createSubMenuItem "MaxScatter" m) -1
                    menuMan.updateMenuBar()
                    ok = true
                )
            )
        )
        catch ( if MaxScatter != undefined do MaxScatter.logErr "menu(legacy)" (getCurrentException()) )
        ok
    ),

    /*  Catch-up path for the install session only -- see the file header. Costs
        a full menu-bar rebuild, so it must stay behind the "already there?"
        check in install().  */
    fn installCui mgr =
    (
        local ok = false
        try
        (
            -- register first, so the reload below rebuilds our entry
            callbacks.removeScripts id:#MaxScatterMenu
            callbacks.addScript #cuiRegisterMenus "MaxScatter_menuCB()" id:#MaxScatterMenu

            mgr.LoadConfiguration (mgr.GetCurrentConfiguration())
            ok = (mgr.GetMenuItemById MaxScatter_menuId) != undefined
        )
        catch ( if MaxScatter != undefined do MaxScatter.logErr "menu(cui)" (getCurrentException()) )
        ok
    ),

    /*  Called at plugin load, every session. Returns true when the MaxScatter
        menu is on the bar.

        On 2025+ this deliberately does NOT build anything: the package's .mnx
        owns the menu, and the plugin loads from a post-start-up component that
        can run either side of the host's menu build, so forcing a rebuild here
        would mean paying for one at every single launch to win a race we do not
        need to enter. It reports what it finds and leaves the menu alone.  */
    fn install =
    (
        local mgr = this.cuiMgr()
        if mgr == undefined then this.installLegacy()   -- 2024: menuMan, per session
        else (try ((mgr.GetMenuItemById MaxScatter_menuId) != undefined) catch false)
    ),

    /*  Installer only. A .mzp install has no restart behind it, so the package's
        .mnx has not been read yet and the menu genuinely has to be built by
        script for this one session -- the .mnx takes over from the next launch.  */
    fn installNow =
    (
        local mgr = this.cuiMgr()
        if mgr == undefined then this.installLegacy()
        else if (try ((mgr.GetMenuItemById MaxScatter_menuId) != undefined) catch false) then true
        else this.installCui mgr
    ),

    fn remove =
    (
        try
        (
            local mgr = this.cuiMgr()
            if mgr != undefined then
            (
                callbacks.removeScripts id:#MaxScatterMenu
                local it = mgr.GetMenuItemById MaxScatter_menuId
                if it != undefined do ( mgr.mainMenuBar.DeleteItem MaxScatter_menuId )
            )
            else
            (
                local m = menuMan.findMenu "MaxScatter"
                if m != undefined do ( menuMan.unRegisterMenu m; menuMan.updateMenuBar() )
            )
        )
        catch()
        ok
    )
)

MaxScatter.menu = MaxScatter_Menu()
