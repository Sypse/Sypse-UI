--[[
    Sypse UI — example.lua
    A guided tour of every feature in the library. Each tab covers one area and
    the comments explain the options, so you can copy what you need.

    Setup (Studio): put the SypseUI ModuleScript next to this LocalScript
    (e.g. both in StarterPlayerScripts) and press Play.
    Loader:  local Sypse = loadstring(game:HttpGet("<raw url to SypseUI.lua>"))()

    Tabs:
        1. Basics      toggles, checkboxes, sliders, range sliders, inputs
        2. Pickers     dropdowns (single / searchable / multi), keybinds, colours
        3. Buttons     every variant, rows, double-click confirm, dialogs, toasts
        4. Layout      sections, columns, accordions, segments, text blocks
        5. Feedback    progress, spinners, badges, stat cards (custom + live)
        6. Data        console + search bar, player grid
        7. Config      flags, config manager, save / load / export / apply
        8. Themes      theme switching, custom themes, window controls
        9. Handles     :Set / :Get / :SetVisible / :SetLocked / :OnChanged / :Destroy
]]

local Players = game:GetService("Players")
local Sypse = require(script.Parent:WaitForChild("SypseUI"))

--==============================================================================
-- WINDOW
--==============================================================================
local win = Sypse:CreateWindow({
    Title = "Sypse Example",          -- title bar text (the app icon shows its first letter)
    Version = "v1.0.6",               -- accent badge next to the title
    Subtitle = "feature tour",        -- dim mono line after the badge
    Theme = "Acrylic",                -- any name in Sypse.Themes, or a theme table
    Size = UDim2.fromOffset(980, 620),
    ToggleKey = Enum.KeyCode.RightShift,
    LiveStats = false,                -- true = FPS/ping/memory/position cards on every page
    ConfirmClose = true,              -- the ✕ button asks before destroying the UI
    ConfigFolder = "SypseExample",    -- where configs are written (memory-only without file I/O)
    Profile = "example.json",         -- the "active" profile used by the sidebar Save button
    AutosaveFlag = "autosave",        -- save the active profile on close if Flags.autosave is true
    User = { Name = "you", Sub = "example user" }, -- sidebar footer card
    Status = "ready · example",       -- status bar text
    Watermark = true,                 -- floating FPS / ping pill + keybind HUD (click it to toggle the window)
    Blur = false,                     -- background blur: false (default) | true (all themes) | "theme"
    BlurSize = 10,                    -- BlurEffect size when blur is on
    OnClose = function() print("[example] window closed") end,
})

local function toast(title, body, kind) Sypse:Notify({ Title = title, Body = body, Kind = kind }) end

--==============================================================================
-- 1. BASICS
--==============================================================================
local basics = win:AddTab({ Name = "Basics", Icon = "circle" })

local tgl = basics:AddSection("Toggles")
tgl:AddToggle({
    Name = "Plain toggle",
    Description = "Description line in mono",           -- optional second line
    Tooltip = "Hover the ? to see this. Tooltips clamp inside the window.",
    Default = true,
    Flag = "ex_toggle",                                 -- mirrors into Sypse.Flags.ex_toggle
    Callback = function(on) Sypse:Log("INFO", "Plain toggle → " .. tostring(on)) end,
})
tgl:AddToggle({ Name = "With a badge", Badge = { Text = "NEW", Kind = "accent" }, Default = false })
tgl:AddToggle({ Name = "Risky toggle", Description = "Profiles saved while this is on get the RISKY tag",
    Badge = { Text = "RISKY", Kind = "danger" }, Risky = true, Flag = "ex_risky" })
tgl:AddToggle({ Name = "Locked toggle", Description = "Faded and non-interactive", Locked = true })
tgl:AddCheckbox({ Name = "Checkbox variant", Default = true, Flag = "ex_check" })

local sld = basics:AddSection("Sliders")
sld:AddSlider({ Name = "Default slider", Min = 0, Max = 100, Default = 42, Flag = "ex_slider",
    Callback = function(v) Sypse:Log("INFO", "Slider → " .. v) end })
sld:AddSlider({ Name = "Decimal step + suffix", Min = 0, Max = 2, Step = 0.05, Default = 1, Suffix = "x" })
sld:AddSlider({ Name = "Plain value, Accent2", Min = 16, Max = 200, Default = 64, Chip = false, Color = "Accent2" })
sld:AddSlider({ Name = "Custom format", Min = 0, Max = 3600, Step = 30, Default = 90,
    Format = function(v) return string.format("%d:%02d", v // 60, v % 60) end })
sld:AddRangeSlider({ Name = "Range slider", Min = 0, Max = 180, Default = { 25, 140 }, Suffix = "°", MinGap = 5, Flag = "ex_range",
    Callback = function(lo, hi) Sypse:Log("INFO", ("Range → %d–%d"):format(lo, hi)) end })

local inp = basics:AddSection("Inputs")
inp:AddInput({ Name = "Text", Placeholder = "Type something…", Flag = "ex_text",
    OnFocusLost = function(text, enter) Sypse:Log("INFO", ("Text committed (%s): %s"):format(enter and "enter" or "blur", text)) end })
inp:AddInput({ Name = "Numeric (0–500)", Description = "Rejects non-numbers, clamps on blur", Numeric = true, Default = 120, Min = 0, Max = 500, Flag = "ex_num" })
inp:AddInput({ Name = "Password", Password = true, Default = "hunter2000", Flag = "ex_pass" })
inp:AddInput({ Name = "Multi-line", MultiLine = true, Default = "line one\nline two", Flag = "ex_notes",
    Finished = true, -- only fire Callback when focus is lost, not on every keystroke
    Callback = function(text) Sypse:Log("INFO", "Notes saved (" .. #text .. " chars)") end })

--==============================================================================
-- 2. PICKERS
--==============================================================================
local pickers = win:AddTab({ Name = "Pickers", Icon = "square" })

local dd = pickers:AddSection("Dropdowns")
local fruit = dd:AddDropdown({ Name = "Single select", Options = { "Apple", "Banana", "Cherry", "Durian" }, Default = "Banana", Flag = "ex_fruit",
    Callback = function(v) Sypse:Log("INFO", "Fruit → " .. tostring(v)) end })
dd:AddDropdown({ Name = "Searchable", Searchable = true, Placeholder = "Pick a material",
    Options = { "Plastic", "SmoothPlastic", "Neon", "Glass", "ForceField", "Metal", "DiamondPlate", "Wood", "Marble", "Granite", "Slate" } })
dd:AddDropdown({ Name = "Multi select (chips)", Multi = true, Searchable = true,
    Options = { "Head", "Torso", "Arms", "Legs", "Root" }, Default = { "Head", "Torso" }, Flag = "ex_multi",
    Callback = function(list) Sypse:Log("INFO", "Multi → " .. table.concat(list, ", ")) end })
dd:AddButtonRow({
    { Name = "Refresh single options", Callback = function()
        fruit:Refresh({ "Kiwi", "Lime", "Mango", "Banana" }, true) -- keep = true keeps "Banana" selected if still present
        toast("Options refreshed", "Kiwi, Lime, Mango, Banana", "accent")
    end },
})

local kb = pickers:AddSection("Keybinds")
local cols = kb:AddColumns(2)
cols[1]:AddKeybind({ Name = "Press mode", Default = Enum.KeyCode.G, Mode = "Press", Flag = "ex_key_press",
    Callback = function() toast("Pressed", "G fired its callback", "accent") end })
cols[2]:AddKeybind({ Name = "Toggle mode", Default = Enum.KeyCode.H, Mode = "Toggle", Flag = "ex_key_toggle",
    Callback = function(on) toast("Toggled", tostring(on), on and "ok" or "warn") end })
cols[1]:AddKeybind({ Name = "Hold mode", Default = "J", Mode = "Hold", Hint = "Hold to charge", HudName = "Charge",
    Callback = function(held) Sypse:Log("INFO", "Hold key " .. (held and "down" or "up")) end })
cols[2]:AddKeybind({ Name = "Mouse button", Default = Enum.UserInputType.MouseButton3, HUD = false, -- hidden from the HUD
    ChangedCallback = function(key) Sypse:Log("INFO", "Rebound to " .. tostring(key)) end })
kb:AddKeybind({ Name = "Menu toggle key", MenuKey = true, Flag = "ex_menukey",
    Description = "Rebinds the window toggle key itself" })
kb:AddParagraph("Click a field, then press any key or mouse button. Escape cancels, Backspace clears.")

local col = pickers:AddSection("Colour pickers")
local cp = col:AddColumns(2)
cp[1]:AddColorPicker({ Name = "With alpha", Default = Color3.fromHex("7AA2FF"), Alpha = 0.8, Flag = "ex_color",
    Callback = function(c, transparency) Sypse:Log("INFO", ("Colour → #%s @ %.2f"):format(c:ToHex(), transparency)) end })
cp[2]:AddColorPicker({ Name = "No alpha, collapsed", Default = Color3.fromHex("FF2D95"), Expanded = false, Flag = "ex_color2" })
cp[2]:AddParagraph("Click the swatch to expand or collapse a picker. HEX and A fields are editable.")

--==============================================================================
-- 3. BUTTONS, DIALOGS & TOASTS
--==============================================================================
local buttons = win:AddTab({ Name = "Buttons", Icon = "diamond" })

local variants = buttons:AddSection("Variants")
variants:AddButtonRow({
    { Name = "Primary", Variant = "Primary", Callback = function() toast("Primary", "clicked", "accent") end },
    { Name = "Secondary", Callback = function() toast("Secondary", "clicked", "accent") end },
    { Name = "Ghost", Variant = "Ghost", Callback = function() toast("Ghost", "clicked", "accent") end },
    { Name = "Danger", Variant = "Danger", Callback = function() toast("Danger", "clicked", "danger") end },
})
variants:AddButtonRow({
    { Name = "Ok", Variant = "Ok", Callback = function() toast("Ok", "clicked", "ok") end },
    { Name = "Warn", Variant = "Warn", Callback = function() toast("Warn", "clicked", "warn") end },
    { Icon = "square", Tooltip = "Icon button — Icon can be circle/square/diamond, a glyph or an image id",
        Callback = function() toast("Icon", "clicked", "accent") end },
    { Icon = "★", Tooltip = "A text glyph icon", Callback = function() toast("Star", "clicked", "accent") end },
    { Name = "Disabled", Disabled = true },
    { Name = "Right aligned", Align = "Right", Callback = function() toast("Right", "clicked", "accent") end },
})
variants:AddButton({ Name = "Double-click to confirm", DoubleClick = true, ConfirmText = "Sure? Click again",
    Callback = function() toast("Confirmed", "second click fired", "ok") end })
variants:AddButton({ Name = "Full-width button", Fill = true, Variant = "Primary", Callback = function() toast("Full width", "clicked", "accent") end })

local toasts = buttons:AddSection("Toasts")
toasts:AddButtonRow({
    { Name = "Info", Callback = function() Sypse:Notify({ Title = "Info", Body = "Kind = \"info\"", Kind = "info" }) end },
    { Name = "Ok", Variant = "Ok", Callback = function() Sypse:Notify({ Title = "Success", Body = "Kind = \"ok\"", Kind = "ok" }) end },
    { Name = "Warn", Variant = "Warn", Callback = function() Sypse:Notify({ Title = "Warning", Body = "Kind = \"warn\"", Kind = "warn" }) end },
    { Name = "Danger", Variant = "Danger", Callback = function() Sypse:Notify({ Title = "Error", Body = "Kind = \"danger\"", Kind = "danger" }) end },
    { Name = "Long (10s)", Callback = function()
        local t = Sypse:Notify({ Title = "Sticky-ish", Body = "Duration = 10 — or dismiss it with ×", Kind = "accent", Duration = 10 })
        task.delay(3, function() t.Dismiss() end) -- the handle can dismiss it early
    end },
})
toasts:AddParagraph("Toasts stack bottom-right (max 4), slide in, auto-dismiss after 4.2 s by default, and have a manual × close.")

local dialogs = buttons:AddSection("Dialogs")
dialogs:AddButtonRow({
    { Name = "Confirm dialog", Callback = function()
        win:Dialog({
            Title = "Apply changes?", Body = "A primary confirm with a cancel button.", Icon = "?",
            Confirm = { Text = "Apply", Variant = "Primary", Callback = function() toast("Applied", "confirm callback ran", "ok") end },
            Cancel = { Text = "Not now", Callback = function() toast("Cancelled", "cancel callback ran", "warn") end },
        })
    end },
    { Name = "Destructive dialog", Variant = "Danger", Callback = function()
        Sypse:Dialog({
            Title = "Delete everything?", Body = "Danger confirm. Escape also cancels.",
            Confirm = { Text = "Delete", Variant = "Danger", Callback = function() toast("Deleted", "(not really)", "danger") end },
            Cancel = { Text = "Cancel" },
        })
    end },
    { Name = "Info only", Callback = function()
        win:Dialog({ Title = "Heads up", Body = "No Cancel → a single OK button. Click the backdrop to dismiss.", Icon = "i",
            Confirm = { Text = "Got it" }, DismissOnScrim = true })
    end },
})

--==============================================================================
-- 4. LAYOUT
--==============================================================================
local layout = win:AddTab({ Name = "Layout", Icon = "square", Count = 3 })
-- Segments: sub-tabs shown in the strip at the top of the content area.
local segA = layout:AddSegment("Sections")
local segB = layout:AddSegment("Columns")
local segC = layout:AddSegment("Accordions")

local sec = segA:AddSection("Section with a badge", { Badge = { Text = "UPDATED", Kind = "ok" } })
sec:AddLabel("AddSection returns a container. Controls added to it sit under the header with a tighter gap.")
local secHandle = segA:AddSection("Section you can retitle", { Badge = { Text = "0 clicks", Kind = "dim" } })
local clicks = 0
secHandle:AddButton({ Name = "Retitle + rebadge", Callback = function()
    clicks += 1
    secHandle:SetTitle("Retitled " .. clicks .. "×")
    secHandle:SetBadge(clicks .. " clicks", clicks % 2 == 0 and "ok" or "warn")
end })
segA:AddDivider()
segA:AddLabel({ Text = "A mono label (AddLabel with Mono = true)", Mono = true, Color = "Dim" })
segA:AddSpacer(6)
segA:AddParagraph({ Title = "Paragraph with a title",
    Body = "Paragraphs wrap at the container width and use the Dim colour. Handy for credits, warnings and documentation." })

local two = segB:AddColumns(2)
two[1]:AddToggle({ Name = "Left column" })
two[2]:AddToggle({ Name = "Right column" })
local mixed = segB:AddColumns({ "1fr", 220 }, 12)  -- flexible + fixed 220 px, 12 px gap
mixed[1]:AddSlider({ Name = "Flexible column", Default = 60 })
mixed[2]:AddParagraph("Fixed 220 px column.")
local three = segB:AddColumns({ "1fr", "1fr", "1fr" })
for i = 1, 3 do three[i]:AddCheckbox({ Name = "Col " .. i }) end

local acc1 = segC:AddAccordion({ Name = "Open by default", Badge = "BETA", Open = true })
acc1:AddToggle({ Name = "Compact toggle" })
acc1:AddInput({ Name = "Compact input", Numeric = true, Default = 5 })
acc1:AddSlider({ Name = "Compact slider", Default = 30 })
acc1:AddDropdown({ Name = "Compact chips", Multi = true, Options = { "A", "B", "C" }, Default = { "A" } })
local acc2 = segC:AddAccordion({ Name = "Closed, fixed count text", Badge = { Text = "ADVANCED", Kind = "warn" }, Count = "3 items" })
acc2:AddLabel({ Text = "renderdistance = 512", Mono = true })
acc2:AddLabel({ Text = "threadpool = 4", Mono = true })
acc2:AddLabel({ Text = "unsafe_hooks = false", Mono = true })
segC:AddButtonRow({
    { Name = "Toggle second accordion", Callback = function() acc2:Toggle() end },
    { Name = "Jump to 'Sections'", Callback = function() layout:SelectSegment("Sections") end },
})

--==============================================================================
-- 5. FEEDBACK
--==============================================================================
local feedback = win:AddTab({ Name = "Feedback", Icon = "circle" })

local prog = feedback:AddSection("Progress & spinners")
local bar1 = prog:AddProgress({ Name = "With a spinner", Spinner = true, Default = 10 })
local bar2 = prog:AddProgress({ Name = "Thin spinner, Accent2 fill", Spinner = "thin", Color = "Accent2", Default = 60 })
prog:AddProgress({ Name = "Plain bar", Default = 85 })
Sypse:Every(0.25, function()                -- managed timer; Sypse:Destroy() stops it
    bar1:Set((bar1.Value + 2) % 101)
    bar2:Set((bar2.Value + 1) % 101)
end)
prog:AddSpinners("ring · thin · dots")
prog:AddSpinner("dots")                      -- a single spinner on its own row

local badges = feedback:AddSection("Badges")
badges:AddBadges({
    { Text = "ACCENT", Kind = "accent" }, { Text = "OK", Kind = "ok" }, { Text = "WARN", Kind = "warn" },
    { Text = "DANGER", Kind = "danger" }, { Text = "DIM", Kind = "dim" },
})

local stats = feedback:AddSection("Stat cards")
local cards = stats:AddStatCards({
    { Label = "Kills", Value = 0, Note = "this session" },
    { Label = "Coins", Value = "1,240", Note = "wallet", Kind = "ok" },
    { Label = "Errors", Value = 0, Note = "since start" },
    { Label = "Uptime", Value = "0s", Note = "session" },
})
local started, kills = os.clock(), 0
Sypse:Every(1, function()
    kills += math.random(0, 1)
    cards:Update(1, { Value = kills })
    cards:Update(4, { Value = math.floor(os.clock() - started) .. "s" })
end)
stats:AddButton({ Name = "Raise an error count", Variant = "Danger", Callback = function()
    local n = (tonumber(cards.Cards[3].value.Text) or 0) + 1
    cards:Update(3, { Value = n, Kind = n > 2 and "danger" or "warn", Note = n > 2 and "investigate!" or "since start" })
end })
stats:AddLabel({ Text = "Live telemetry (real FPS / ping / memory / position):", Color = "Dim" })
stats:AddLiveStats({ TargetFPS = 60, WarnFPS = 55, WarnPing = 100, Region = "server" })

--==============================================================================
-- 6. DATA
--==============================================================================
local data = win:AddTab({ Name = "Data", Icon = "square" })
local consoleSeg = data:AddSegment("Console")
local playersSeg = data:AddSegment("Player grid")

local console = consoleSeg:AddConsole({ Height = 260, HookLogService = true, MaxLines = 200 })
consoleSeg:AddSearchBar({ Placeholder = "Filter console lines…", Target = console }) -- shows "matches/total"
consoleSeg:AddButtonRow({
    { Name = "Log INFO", Callback = function() Sypse:Log("INFO", "An info line") end },
    { Name = "Log OK", Variant = "Ok", Callback = function() Sypse:Log("OK", "Something worked") end },
    { Name = "Log WARN", Variant = "Warn", Callback = function() Sypse:Log("WARN", "Something looks off") end },
    { Name = "Log ERR", Variant = "Danger", Callback = function() Sypse:Log("ERR", "Something broke") end },
    { Name = "print()", Callback = function() print("printed via print() — mirrored by HookLogService") end },
})
Sypse:Log("OK", "Example loaded")

local SAMPLE = {
    { Name = "alpha_one", Meta = "lvl 12 · 100 hp", Tag = "FRIEND", Kind = "ok", Status = "ok" },
    { Name = "bravo", Meta = "lvl 31 · 64 hp", Tag = "NEUTRAL", Kind = "dim", Status = "ok" },
    { Name = "charlie_x", Meta = "lvl 58 · 12 hp", Tag = "LOW HP", Kind = "danger", Status = "warn" },
    { Name = "delta", Meta = "lvl 7 · 100 hp", Tag = "NEW", Kind = "accent", Status = "ok" },
    { Name = "echo", Meta = "offline", Tag = "AWAY", Kind = "dim", Status = "dim" },
    { Name = "foxtrot", Meta = "lvl 44 · 88 hp", Tag = "VIP", Kind = "warn", Status = "ok",
        UserId = 1 }, -- items with a UserId load a real avatar thumbnail
}
local grid = playersSeg:AddPlayerGrid({
    -- "live" = real players, updating as they join/leave; a list = your own items
    Items = (#Players:GetPlayers() > 1) and "live" or SAMPLE,
    Columns = 4,
    Default = 1,
    OnSelect = function(item) if item then Sypse:Log("INFO", "Selected " .. item.Name) end end,
    Actions = {
        { Name = "Inspect", Variant = "Primary", Callback = function(item)
            toast(item and item.Name or "Nothing selected", item and item.Meta or "pick a card", item and "accent" or "warn")
        end },
    },
})
playersSeg:AddButton({ Name = "Refresh grid with 3 items", Callback = function()
    grid:Refresh({ SAMPLE[2], SAMPLE[4], SAMPLE[6] })
end })

--==============================================================================
-- 7. CONFIG
--==============================================================================
local config = win:AddTab({ Name = "Config", Icon = "circle" })
local cm = config:AddSection("Config manager")
cm:AddParagraph("Every control with a Flag is saved. Type a name and press Save; click a profile to select it, then Load, Export or Delete.")
cm:AddConfigManager()                 -- uses win.ConfigFolder
cm:AddToggle({ Name = "Autosave on close", Flag = "autosave", Description = "Window option AutosaveFlag = \"autosave\"" })

local api = config:AddSection("Flags & config API")
local flagLabel = api:AddLabel({ Text = "Sypse.Flags.ex_slider = …", Mono = true })
Sypse:Every(0.5, function() flagLabel:Set("Sypse.Flags.ex_slider = " .. tostring(Sypse.Flags.ex_slider)) end)
api:AddButtonRow({
    { Name = "Save 'quick.json'", Variant = "Primary", Callback = function()
        local ok, res = win:SaveConfig("quick")          -- ".json" is added automatically
        toast(ok and "Saved" or "Save failed", tostring(res), ok and "ok" or "danger")
    end },
    { Name = "Load 'quick.json'", Callback = function()
        local ok, err = win:LoadConfig("quick.json")
        toast(ok and "Loaded" or "Load failed", ok and "values restored" or tostring(err), ok and "ok" or "danger")
    end },
    { Name = "List configs", Callback = function()
        toast("Configs", table.concat(win:ListConfigs(), ", "), "accent")
    end },
})
local snapshot
api:AddButtonRow({
    { Name = "Snapshot (ExportConfig)", Callback = function()
        snapshot = Sypse:ExportConfig()                  -- JSON string, no disk involved
        toast("Snapshot taken", #snapshot .. " bytes", "accent")
    end },
    { Name = "Randomise values", Variant = "Warn", Callback = function()
        Sypse.Options.ex_slider:Set(math.random(0, 100))
        Sypse.Options.ex_toggle:Set(math.random() > 0.5)
        Sypse.Options.ex_fruit:Set("Cherry")
        toast("Randomised", "now restore the snapshot", "warn")
    end },
    { Name = "Restore (ApplyConfig)", Variant = "Ok", Callback = function()
        if not snapshot then return toast("No snapshot", "take one first", "warn") end
        Sypse:ApplyConfig(snapshot)
        toast("Restored", "snapshot applied", "ok")
    end },
})
api:AddParagraph("Sypse.Options[flag] is the control handle; Sypse.Flags[flag] is its current value. Colour pickers also write Flags[flag .. \"Transparency\"].")

--==============================================================================
-- 8. THEMES & WINDOW
--==============================================================================
-- Register a custom theme before building the picker so it shows up in the list.
-- Partial tables merge over Base (default "Acrylic"); only the listed tokens change.
Sypse:RegisterTheme("Forest", {
    Base = "Daylight",
    Accent = Color3.fromHex("2E7D4F"), AccentFg = Color3.fromHex("FFFFFF"),
    AccentSoft = Color3.fromHex("2E7D4F"), AccentSoftTransparency = 0.9,
    AccentLine = Color3.fromHex("2E7D4F"), AccentLineTransparency = 0.75,
    Accent2 = Color3.fromHex("B7791F"),
    Background = Color3.fromHex("EEF2EC"), Panel3 = Color3.fromHex("F6F8F4"),
    Font = "Nunito", CornerRadius = 16, CornerRadiusSmall = 11,
    Shadow = "hard", ShadowColor = Color3.fromHex("2E7D4F"), ShadowTransparency = 0.8, ShadowOffset = Vector2.new(5, 5),
})

local themes = win:AddTab({ Name = "Themes", Icon = "diamond" })
local tsec = themes:AddSection("Theme")
local picker = tsec:AddDropdown({
    Name = "Theme", Description = "Colours, fonts, radius, strokes, shadows and casing all change",
    Options = Sypse:GetThemeNames(), Default = "Acrylic",
    Callback = function(name) if name then Sypse:SetTheme(name) end end,
})
local quick = {}
for _, name in ipairs(Sypse:GetThemeNames()) do
    table.insert(quick, { Name = name, Callback = function() Sypse:SetTheme(name); picker:Set(name, true) end })
end
tsec:AddButtonRow({ table.unpack(quick, 1, 4) })
tsec:AddButtonRow({ table.unpack(quick, 5) })
tsec:AddButton({ Name = "Apply an unnamed theme table", Callback = function()
    -- SetTheme also accepts a table directly (merged over Acrylic)
    Sypse:SetTheme({ Accent = Color3.fromHex("F5A623"), AccentFg = Color3.fromHex("1A1200"), CornerRadius = 6, CornerRadiusSmall = 5 })
    toast("Ad-hoc theme", "Acrylic + orange accent + tight corners", "accent")
end })
tsec:AddParagraph("Current theme tokens are available via Sypse:GetTheme(); Sypse.Themes lists every registered theme.")

local wsec = themes:AddSection("Window controls")
wsec:AddButtonRow({
    { Name = "Minimize", Callback = function() win:Minimize(); task.delay(1.5, function() win:Minimize() end) end },
    { Name = "Maximize", Callback = function() win:Maximize() end },
    { Name = "Hide 2s", Callback = function() win:SetVisible(false); task.delay(2, function() win:SetVisible(true) end) end },
    { Name = "Retitle", Callback = function() win:SetTitle("Sypse Example " .. math.random(1, 99)) end },
})
local wm = true
wsec:AddButtonRow({
    { Name = "Status: ok", Variant = "Ok", Callback = function() win:SetStatus("all systems nominal", "ok") end },
    { Name = "Status: warn", Variant = "Warn", Callback = function() win:SetStatus("degraded — retrying", "warn") end },
    { Name = "Status: danger", Variant = "Danger", Callback = function() win:SetStatus("disconnected", "danger") end },
    { Name = "Toggle watermark", Callback = function() wm = not wm; win:SetWatermark(wm) end },
})
-- Background blur is a window setting, independent of the theme.
local blurOn = false
wsec:AddButtonRow({
    { Name = "Blur on", Callback = function() blurOn = true; win:SetBlur(true); toast("Blur", "on for every theme", "accent") end },
    { Name = "Blur off", Callback = function() blurOn = false; win:SetBlur(false); toast("Blur", "off", "accent") end },
    { Name = "Blur follows theme", Callback = function()
        win:SetBlur("theme")            -- only themes with Blur = true (Acrylic) blur
        toast("Blur", "follows the theme token", "accent")
    end },
    { Name = "Blur strength 24", Callback = function() win:SetBlur(blurOn and true or "theme", 24); toast("Blur", "size 24", "accent") end },
    { Name = "Blur all windows", Callback = function()
        Sypse:SetBlur(not select(1, Sypse:GetBlur()))  -- library-wide: every window + the default for new ones
        toast("Sypse:SetBlur", tostring(select(1, Sypse:GetBlur())), "accent")
    end },
})
wsec:AddButtonRow({
    { Name = "Toggle key → Insert", Callback = function() win:SetToggleKey(Enum.KeyCode.Insert); toast("Toggle key", "now Insert", "accent") end },
    { Name = "Toggle key → RightShift", Callback = function() win:SetToggleKey(Enum.KeyCode.RightShift); toast("Toggle key", "now RightShift", "accent") end },
    { Name = "Tab counts", Callback = function() basics:SetCount(math.random(1, 99)); pickers:SetCount(nil) end },
    { Name = "Destroy UI", Variant = "Danger", Align = "Right", Callback = function()
        Sypse:Dialog({ Title = "Destroy the whole UI?", Body = "Sypse:Destroy() removes every window, toast, timer and connection.",
            Confirm = { Text = "Destroy", Variant = "Danger", Callback = function() Sypse:Destroy() end }, Cancel = { Text = "Cancel" } })
    end },
})
wsec:AddParagraph("Press / to focus the filter box in the top bar — it filters the current page's controls by name.")

--==============================================================================
-- 9. HANDLES
--==============================================================================
local handles = win:AddTab({ Name = "Handles", Icon = "circle" })
local h = handles:AddSection("Control handle methods")
local target = h:AddToggle({ Name = "Target toggle", Description = "The buttons below drive this control through its handle", Flag = "ex_target" })
local watcher = h:AddLabel({ Text = "OnChanged: (nothing yet)", Mono = true, Color = "Dim" })
target:OnChanged(function(v) watcher:Set("OnChanged: " .. tostring(v)) end) -- extra listener on top of Callback
local visible, locked = true, false
h:AddButtonRow({
    { Name = ":Set(true)", Callback = function() target:Set(true) end },
    { Name = ":Set(false, silent)", Callback = function() target:Set(false, true) end }, -- silent: no callbacks
    { Name = ":Get()", Callback = function() toast(":Get()", tostring(target:Get()), "accent") end },
    { Name = ":Toggle()", Callback = function() target:Toggle() end },
})
h:AddButtonRow({
    { Name = ":SetVisible", Callback = function() visible = not visible; target:SetVisible(visible) end },
    { Name = ":SetLocked", Callback = function() locked = not locked; target:SetLocked(locked) end },
    { Name = ":Destroy()", Variant = "Danger", Callback = function()
        target:Destroy()
        watcher:Set("destroyed — Sypse.Options.ex_target = " .. tostring(Sypse.Options.ex_target))
    end },
})
local btn = h:AddButton({ Name = "Button with handle" })
h:AddButtonRow({
    { Name = "btn:SetText", Callback = function() btn:SetText("Renamed at " .. os.date("%H:%M:%S")) end },
    { Name = "btn:SetLocked", Callback = function() btn:SetLocked(not btn.Locked) end },
    { Name = "btn:Fire()", Callback = function() btn:Fire() end },
})
btn:OnChanged(function() toast("Button fired", "via :Fire() or a click", "accent") end)

win:SelectTab("Basics")
toast("Sypse example", "RightShift toggles the window", "ok")