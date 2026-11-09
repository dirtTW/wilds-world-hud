--[[
    MH World UI for Monster Hunter Wilds  (native HUD reskin, no ImGui / no d2d)
    ==============================================================================
    Targets the game's OWN HUD:  app.GUI020003 (gui_id 51)
      PNL_gaugeMode00/PNL_gauge00/PNL_gaugeMatBase/mat_gauge00..01   health fill
      PNL_gaugeMode00/PNL_gaugeEtc/PNL_gaugeRedIn/.../s9g_gaugeRed    recoverable HP
      PNL_gaugeMode00/PNL_frame/.../mat_base00                        bar frame
      PNL_gaugeMode01/PNL_gaugeEasy/PNL_gaugeEasy01/mat_gauge00..03   stamina fill

    Colours are re-applied every frame: the game rewrites gauge colours from state.
]]

local M = {}
M.enabled = true
M.debug   = true

M.health_gui_id = 51

-- Wilds' gauge panel (PNL_Pat00) holds the health gauge, the stamina gauge and several
-- extra ornaments, plus PNL_StateIcons (the status / buff icons). Everything in it is
-- hidden except the state icons, so new ornaments cannot leak through.
M.keep_icon_panel = "PNL_StateIcons"

-- NOTE: do not name this `log` - it shadows the global log module.
local function plog(msg)
    if M.debug then log.info("[MHWorldUI] " .. tostring(msg)) end
end

local warned = {}
local function plog_once(key, msg)
    if warned[key] then return end
    warned[key] = true
    plog(msg)
end

local control_type, material_type
local canvas, mats, gauges_hidden
local active = false
local frame_no = 0
local broken = false

plog("script loaded")

local function init_types()
    if control_type ~= nil then return true end
    local ok = pcall(function()
        control_type  = sdk.typeof("via.gui.Control")
        material_type = sdk.typeof("via.gui.Material")
    end)
    if not ok or control_type == nil or material_type == nil then
        plog_once("types", "ERROR: via.gui types unavailable")
        broken = true
        return false
    end
    return true
end

local function find_hud()
    local gm = sdk.get_managed_singleton("app.GUIManager")
    if gm == nil then plog_once("gm", "wait: app.GUIManager nil") return nil end

    local hudman = gm:call("get_HudDisplayManager")
    if hudman == nil then plog_once("hm", "wait: HudDisplayManager nil") return nil end

    local ok, disp = pcall(function()
        return hudman:call("findDisplayControl", M.health_gui_id)
    end)
    if not ok then plog_once("fdc_err", "ERROR findDisplayControl: " .. tostring(disp)) return nil end
    if disp == nil then plog_once("fdc", "wait: health HUD not instantiated") return nil end

    local ok2, ctrl = pcall(function() return disp:get_field("_TargetControl") end)
    if not ok2 or ctrl == nil then plog_once("tc", "wait: _TargetControl nil") return nil end
    return ctrl
end

local function get(node, name, t)
    if node == nil then return nil end
    local ok, res = pcall(function()
        return node:call("getObject(System.String, System.Type)", name, t)
    end)
    if ok then return res end
    return nil
end

-- depth-first search under `node` for a child of `want_type` whose name contains `part`
-- (array idiom used by this engine's Lua: get_Count() / get_Item(i), 0-based)
local function find_first(node, want_type, part)
    if node == nil then return nil end

    local ok_t, tn = pcall(function() return node:get_type_definition():get_full_name() end)
    if ok_t and tn == want_type then
        local ok_n, nm = pcall(function() return node:get_Name() end)
        if ok_n and nm and string.find(string.lower(nm), string.lower(part), 1, true) then
            return node
        end
    end

    local ok_c, kids = pcall(function()
        return node:call("getChildren", sdk.typeof("via.gui.PlayObject"))
    end)
    if not ok_c or kids == nil then return nil end

    local ok_n2, count = pcall(function() return kids:get_Count() end)
    if not ok_n2 or not count then return nil end

    for i = 0, count - 1 do
        local ok_i, child = pcall(function() return kids:get_Item(i) end)
        if ok_i and child ~= nil then
            local hit = find_first(child, want_type, part)
            if hit ~= nil then return hit end
        end
    end
    return nil
end

local function build_mats(root)
    local pat = get(root, "PNL_Pat00", control_type)
    if pat == nil then plog_once("pat", "ERROR: PNL_Pat00 missing") return nil end

    -- one-time geometry probe: log the native gauge's own screen position so the d2d
    -- bars can be aligned to the game's layout instead of a hand-tuned fraction.
    local function probe(label, node)
        if node == nil then return end
        local ok, p = pcall(function() return node:call("get_GlobalPosition") end)
        if not ok or p == nil then return end
        local okx, x = pcall(function() return p:get_field("x") end)
        local oky, y = pcall(function() return p:get_field("y") end)
        plog(string.format("geom %s = %.1f,%.1f", label, tonumber(x) or -1, tonumber(y) or -1))
    end

    local o = {}
    local hp_mode  = get(pat, "PNL_gaugeMode00", control_type)
    probe("hp_mode", hp_mode)
    probe("pat", pat)
    probe("root", root)
    local hp_gauge = get(hp_mode, "PNL_gauge00", control_type)
    local hp_base  = get(hp_gauge, "PNL_gaugeMatBase", control_type)
    o.hp_fill  = get(hp_base, "mat_gauge00", material_type)
    o.hp_fill2 = get(hp_base, "mat_gauge01", material_type)

    local hp_frame = get(hp_mode, "PNL_frame", control_type)
    o.hp_frame     = get(hp_frame, "mat_base00", material_type)

    local hp_etc = get(hp_mode, "PNL_gaugeEtc", control_type)
    local red_in = get(hp_etc, "PNL_gaugeRedIn", control_type)
    -- the exact child name differs from the C# dump in some states, so search the subtree
    o.hp_red = find_first(red_in, "via.gui.Scale9Grid", "gaugeRed")
        or find_first(hp_etc, "via.gui.Scale9Grid", "Red")
        or find_first(hp_etc, "via.gui.Scale9GridV2", "Red")
    plog_once("red_dbg", string.format("red_in=%s red=%s", tostring(red_in ~= nil), tostring(o.hp_red ~= nil)))

    local st_mode = get(pat, "PNL_gaugeMode01", control_type)
    probe("st_mode", st_mode)
    local st_easy = get(st_mode, "PNL_gaugeEasy", control_type)
    local st_base = get(st_easy, "PNL_gaugeEasy01", control_type)
    o.st_fill     = get(st_base, "mat_gauge00", material_type)

    plog(string.format("resolved hp=%s hp2=%s frame=%s red=%s sta=%s",
        tostring(o.hp_fill ~= nil), tostring(o.hp_fill2 ~= nil), tostring(o.hp_frame ~= nil),
        tostring(o.hp_red ~= nil), tostring(o.st_fill ~= nil)))

    if o.hp_fill == nil and o.st_fill == nil then return nil end
    o._pat = pat
    o._root = root
    return o
end

-- Hide every child of `parent` whose name does not contain `keep`, one level deep is not
-- enough for the gauge panel, so this recurses but stops at the kept subtree.
local function hide_children_except(parent, keep)
    if parent == nil then return end
    local ok, kids = pcall(function()
        return parent:call("getChildren", sdk.typeof("via.gui.PlayObject"))
    end)
    if not ok or kids == nil then return end
    local okc, count = pcall(function() return kids:get_Count() end)
    if not okc or not count then return end
    for i = 0, count - 1 do
        local ok_i, child = pcall(function() return kids:get_Item(i) end)
        if ok_i and child ~= nil then
            local ok_n, nm = pcall(function() return child:get_Name() end)
            local name = ok_n and tostring(nm) or ""
            if keep ~= nil and string.find(name, keep, 1, true) then
                -- keep this subtree untouched (status / buff icons)
            else
                local ok_s = pcall(function() child:call("set_ForceInvisible", true) end)
                if ok_s then hide_children_except(child, keep) end
            end
        end
    end
end

-- hide a whole HUD element via the game's own display manager (cleaner than node hiding)
local function hide_hud_element(type_name, display_name)
    local types = sdk.find_type_definition("app.GUIHudDef.TYPE")
    local displays = sdk.find_type_definition("app.GUIHudDef.DISPLAY")
    if types == nil or displays == nil then return false end
    local tf = types:get_field(type_name)
    local df = displays:get_field(display_name)
    if tf == nil or df == nil then return false end
    local gm = sdk.get_managed_singleton("app.GUIManager")
    if gm == nil then return false end
    local hudman = gm:call("get_HudDisplayManager")
    if hudman == nil then return false end
    local ok = pcall(function()
        hudman:call("setHudDisplay", tf:get_data(), df:get_data())
    end)
    return ok
end


-- Walk a node tree and set ForceInvisible on every child (used to give the vanilla HUD back).
local function set_visible_recursive(parent, visible, keep)
    if parent == nil then return end
    local ok, kids = pcall(function()
        return parent:call("getChildren", sdk.typeof("via.gui.PlayObject"))
    end)
    if not ok or kids == nil then return end
    local okc, count = pcall(function() return kids:get_Count() end)
    if not okc or not count then return end
    for i = 0, count - 1 do
        local ok_i, child = pcall(function() return kids:get_Item(i) end)
        if ok_i and child ~= nil then
            local ok_n, nm = pcall(function() return child:get_Name() end)
            local name = ok_n and tostring(nm) or ""
            if keep == nil or not string.find(name, keep, 1, true) then
                pcall(function() child:call("set_ForceInvisible", not visible) end)
                set_visible_recursive(child, visible, keep)
            end
        end
    end
end

local function apply()
    if not M.enabled or broken then return end
    frame_no = frame_no + 1

    if canvas == nil then
        if frame_no % 60 ~= 0 then return end
        if not init_types() then return end
        canvas = find_hud()
        if canvas == nil then return end
        mats = build_mats(canvas)
        if mats == nil then canvas = nil return end
    end

    -- Vanilla mode: give the game's own HUD back and stop hiding its nodes.
    if M.vanilla then
        if not M.vanilla_done or frame_no % 120 == 0 then
            M.vanilla_done = true
            hide_hud_element("HEALTH", "DEFAULT")
            hide_hud_element("STAMINA", "DEFAULT")
            hide_hud_element("SHARPNESS", "DEFAULT")
            if mats and mats._pat then set_visible_recursive(mats._pat, true) end
        end
        _G.MHW_HUD_OFF = true
        return
    elseif M.vanilla_done then
        M.vanilla_done = false
        gauges_hidden = false
        M.pat_hidden = false
    end

    -- hide the gauge nodes once, then refresh every 2 s in case the game re-shows them.
    -- (Walking the panel every frame was the main frame-time cost of this script.)
    if mats._pat and (not M.pat_hidden or frame_no % 120 == 0) then
        hide_children_except(mats._pat, M.keep_icon_panel)
        M.pat_hidden = true
    end

    -- Hide the vanilla gauges through the display manager. Re-applied every ~5 s because
    -- changing any HUD setting in the in-game menu resets these states, which makes the
    -- native stamina / sharpness gauges reappear (e.g. HUD size "Small").
    if not gauges_hidden or frame_no % 300 == 0 then
        local sharp = hide_hud_element("SHARPNESS", "HIDDEN")
        local sta   = hide_hud_element("STAMINA", "HIDDEN")
        local hp    = hide_hud_element("HEALTH", "DEFAULT")
        if sharp or sta or hp then
            gauges_hidden = true
            plog(string.format("hud display: sharp=%s sta=%s hp_default=%s",
                tostring(sharp), tostring(sta), tostring(hp)))
        end
    end

    if not active then
        active = true
        plog("ACTIVE: MH World palette applied to native HUD")
    end


    -- Follow the game's own HUD: app.GUI020003.get_IsVisible() is True in gameplay and
    -- False when the game covers/hides the player HUD (map, menus, dialogue, loading).
    -- One sampled call every 15 frames - no per-menu logic, no per-frame cost.
    if frame_no % 4 == 0 then
        local hide_ui = false
        pcall(function()
            -- cache the GUI object: resolving it through getGUI every poll was wasteful
            if M.gm == nil then M.gm = sdk.get_managed_singleton("app.GUIManager") end
            local gm = M.gm
            if gm == nil then hide_ui = true return end
            -- resolve every poll: the HUD GUI is recreated on level load, so a cached
            -- pointer keeps reporting "visible" during/after a loading screen
            local gui = gm:call("getGUI", 51)
            if gui == nil then hide_ui = true return end
            -- the game's own HUD visibility, plus the trick the Nier UI mod uses:
            -- the mouse cursor becomes available whenever a UI takes over
            if gui:call("get_IsVisible") == false then hide_ui = true end
        end)
        if hide_ui ~= M.map_open then
            M.map_open = hide_ui
            plog("ui covering hud = " .. tostring(hide_ui))
        end
    end

    _G.MHW_HUD_OFF = (M.force_off == true) or (M.map_open == true)
end

if imgui ~= nil then
    re.on_draw_ui(function()
        if not imgui.collapsing_header("MH World HUD") then return end

        imgui.text("MH World health / stamina / sharpness gauges")
        imgui.separator()

        local changed, value = imgui.checkbox("Show MH World overlay##mhw_show", M.force_off ~= true)
        if changed then M.force_off = not value end

        -- Checked = our gauges. Unchecked = the game's own gauges, and our hiding stops
        -- (the display states are restored, nothing is forced invisible any more).
        local cc, use_custom = imgui.checkbox("Use MH World HUD (custom gauges)##mhw_custom", M.vanilla ~= true)
        if cc then
            M.vanilla = not use_custom
            plog("custom HUD = " .. tostring(use_custom))
        end

        imgui.separator()
        imgui.text("Fix-ups")
        if imgui.button("Re-hide vanilla gauges##mhw_rehide") then
            gauges_hidden = false
            M.pat_hidden = false
            plog("manual re-hide requested")
        end
        imgui.same_line()
        if imgui.button("Hide overlay##mhw_hide") then
            M.force_off = true
        end
        imgui.same_line()
        if imgui.button("Show overlay##mhw_unhide") then
            M.force_off = false
        end

        imgui.separator()
        local state
        if M.vanilla then
            state = "vanilla HUD"
        elseif M.force_off then
            state = "MH World overlay hidden"
        elseif M.map_open then
            state = "MH World overlay paused (game UI open)"
        else
            state = "MH World gauges active"
        end
        imgui.text_colored("State: " .. state, 0xFF66FF66)
        imgui.text_colored("Changing a HUD setting in game restores the vanilla gauges - press Re-hide.", 0xFF66CCFF)
    end)
end

if re ~= nil and re.on_frame ~= nil then
    re.on_frame(apply)
else
    plog("ERROR: re.on_frame unavailable")
end

return M
