--!nocheck
--[[
    ███████╗██╗   ██╗██████╗ ███████╗███████╗    ██╗   ██╗██╗
    ██╔════╝╚██╗ ██╔╝██╔══██╗██╔════╝██╔════╝    ██║   ██║██║
    ███████╗ ╚████╔╝ ██████╔╝███████╗█████╗      ██║   ██║██║
    ╚════██║  ╚██╔╝  ██╔═══╝ ╚════██║██╔══╝      ██║   ██║██║
    ███████║   ██║   ██║     ███████║███████╗    ╚██████╔╝██║
    ╚══════╝   ╚═╝   ╚═╝     ╚══════╝╚══════╝     ╚═════╝ ╚═╝

    Sypse UI v1.0.5 — a themeable, Instance-only Roblox UI library.

    One ModuleScript, no dependencies. Works from `require` in a plain Studio
    LocalScript and from `loadstring` in environments that provide it.

        local Sypse = require(path.to.SypseUI)
        local win   = Sypse:CreateWindow({ Title = "Sypse UI", Theme = "Acrylic" })
        local tab   = win:AddTab({ Name = "Main", Icon = "circle" })
        tab:AddToggle({ Name = "Enabled", Default = true, Flag = "enabled" })
        Sypse:SetTheme("Terminal") -- everything restyles live

    File layout (search for the banners):
        §1  Services & environment guards
        §2  Utilities
        §3  Fonts
        §4  THEMES  ← the part you will most likely edit
        §5  Token registry (live re-skinning)
        §6  Primitive builders
        §7  Shared widgets (badge, chevron, spinner, shadow, tooltip icon)
        §8  Window
        §9  Tabs, segments & containers
        §10 Controls (toggle, slider, dropdown, input, keybind, color…)
        §11 Information & feedback (progress, stats, console, grid, config…)
        §12 Overlay: toasts, dialogs, watermark
        §13 Config persistence
        §14 Public API
]]

local Sypse = {}
Sypse.Version = "1.0.5"

--==============================================================================
-- §1  SERVICES & ENVIRONMENT GUARDS
--==============================================================================

-- `cloneref` exists in some executors; in Studio it is nil and we use identity.
local cloneref = (typeof(cloneref) == "function") and cloneref or function(x) return x end
local function Service(name) return cloneref(game:GetService(name)) end

local Players          = Service("Players")
local TweenService     = Service("TweenService")
local UserInputService = Service("UserInputService")
local RunService       = Service("RunService")
local HttpService      = Service("HttpService")
local StatsService     = Service("Stats")
local LogService       = Service("LogService")
local GuiService       = Service("GuiService")
local CoreGui          = Service("CoreGui")

local LocalPlayer = Players.LocalPlayer

-- Executor-specific globals. Every one of these is optional: when absent the
-- library falls back to something that works in a normal Studio LocalScript.
local function fnOrNil(f) return typeof(f) == "function" and f or nil end
local Env = {
    writefile    = fnOrNil(writefile),
    readfile     = fnOrNil(readfile),
    isfile       = fnOrNil(isfile),
    isfolder     = fnOrNil(isfolder),
    makefolder   = fnOrNil(makefolder),
    listfiles    = fnOrNil(listfiles),
    delfile      = fnOrNil(delfile),
    setclipboard = fnOrNil(setclipboard) or fnOrNil(toclipboard),
    gethui       = fnOrNil(gethui),
    protect_gui  = (typeof(syn) == "table" and fnOrNil(syn.protect_gui)) or nil,
}
Env.HasFileIO = (Env.writefile and Env.readfile) ~= nil

--==============================================================================
-- §2  UTILITIES
--==============================================================================

local function hex(s) return Color3.fromHex(s) end
local function clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end

local function roundStep(x, step)
    if not step or step <= 0 then return x end
    local r = math.floor(x / step + 0.5) * step
    local decimals = tostring(step):match("%.(%d+)")
    if decimals then r = tonumber(string.format("%." .. #decimals .. "f", r)) end
    return r
end

local function fmtNum(n)
    if typeof(n) ~= "number" then return tostring(n) end
    if n == math.floor(n) then return tostring(math.floor(n)) end
    return (string.format("%.2f", n):gsub("0+$", ""):gsub("%.$", ""))
end

local function copy(t)
    local o = {}
    for k, v in pairs(t) do o[k] = v end
    return o
end

local function merge(base, over)
    local o = copy(base)
    if over then for k, v in pairs(over) do o[k] = v end end
    return o
end

local function tween(inst, time, props, style, dir)
    if not time or time <= 0 then
        for k, v in pairs(props) do pcall(function() inst[k] = v end) end
        return nil
    end
    local ok, tw = pcall(function()
        return TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
    end)
    if ok and tw then tw:Play() return tw end
    return nil
end

-- Run a user callback without letting its errors break the UI.
local function safeCall(fn, ...)
    if typeof(fn) ~= "function" then return end
    local args = table.pack(...)
    task.spawn(function()
        local ok, err = pcall(fn, table.unpack(args, 1, args.n))
        if not ok then
            warn("[Sypse] callback error: " .. tostring(err))
            if Sypse.Log then Sypse:Log("ERR", "callback: " .. tostring(err)) end
        end
    end)
end

local function timestamp()
    local d = os.date("*t")
    return string.format("%02d:%02d:%02d", d.hour, d.min, d.sec)
end

-- Maid: owns connections / instances / threads / cleanup functions.
local Maid = {}
Maid.__index = Maid
function Maid.new() return setmetatable({ _items = {} }, Maid) end
function Maid:Give(x) table.insert(self._items, x) return x end
function Maid:Clean()
    local items = self._items
    self._items = {}
    for i = #items, 1, -1 do
        local x = items[i]
        local ty = typeof(x)
        if ty == "RBXScriptConnection" then x:Disconnect()
        elseif ty == "Instance" then pcall(x.Destroy, x)
        elseif ty == "thread" then pcall(task.cancel, x)
        elseif ty == "function" then pcall(x)
        elseif ty == "table" and type(x.Destroy) == "function" then pcall(x.Destroy, x)
        elseif ty == "table" and type(x.Disconnect) == "function" then pcall(x.Disconnect, x) end
    end
end

-- Position of a pointer InputObject in the same space as GuiObject.AbsolutePosition
-- for a ScreenGui with IgnoreGuiInset = true.
-- Pointer position in the same space as GuiObject.AbsolutePosition.
-- Roblox reports AbsolutePosition relative to the area below the top-bar inset,
-- even inside an IgnoreGuiInset ScreenGui (whose own AbsolutePosition is then
-- (0, -inset)). Rather than hard-code that quirk, we take the raw screen point
-- and add the reference ScreenGui's AbsolutePosition, which is correct either way.
local RefGui = nil -- set by makeScreenGui
local function pointerPos(input)
    local t = input.UserInputType
    local raw
    if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.MouseMovement
        or t == Enum.UserInputType.MouseButton2 or t == Enum.UserInputType.MouseButton3 then
        raw = UserInputService:GetMouseLocation()              -- raw screen space
    else
        raw = Vector2.new(input.Position.X, input.Position.Y) + GuiService:GetGuiInset() -- touch: inset-excluded → raw
    end
    if RefGui and RefGui.Parent then return raw + RefGui.AbsolutePosition end
    return raw - GuiService:GetGuiInset()
end

-- Convert a GUI absolute position into ScreenGui offset space (for Position = …).
local function absToOffset(abs)
    if RefGui and RefGui.Parent then return abs - RefGui.AbsolutePosition end
    return abs
end

local function isPointerDown(input)
    return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function inRect(p, guiObj)
    local a, s = guiObj.AbsolutePosition, guiObj.AbsoluteSize
    return p.X >= a.X and p.X <= a.X + s.X and p.Y >= a.Y and p.Y <= a.Y + s.Y
end

local KEY_SHORT = {
    RightShift = "RShift", LeftShift = "LShift", RightControl = "RCtrl", LeftControl = "LCtrl",
    RightAlt = "RAlt", LeftAlt = "LAlt", MouseButton1 = "MB1", MouseButton2 = "MB2", MouseButton3 = "MB3",
    Return = "Enter", Backspace = "Bksp", Insert = "Ins", Delete = "Del", PageUp = "PgUp", PageDown = "PgDn",
    Zero = "0", One = "1", Two = "2", Three = "3", Four = "4", Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9",
    Backquote = "`", Semicolon = ";", Quote = "'", Comma = ",", Period = ".", Slash = "/", BackSlash = "\\",
    LeftBracket = "[", RightBracket = "]", Minus = "-", Equals = "=", Space = "Space", CapsLock = "Caps",
}
local function keyName(k)
    if k == nil then return "None" end
    return KEY_SHORT[k.Name] or k.Name
end

--==============================================================================
-- §3  FONTS
--==============================================================================
-- Theme `Font` / `FontMono` accept any of:
--   * a built-in family name:        "GothamSSm", "Nunito", "RobotoMono", …
--   * a full asset path:             "rbxasset://fonts/families/Ubuntu.json"
--   * an uploaded font family id:    "rbxassetid://12187365364"
--   * a Font object or an Enum.Font  (Enum.Font.Code, Font.fromName("Oswald"))
-- Anything that fails to resolve falls back to GothamSSm — the library never
-- errors because a font is unavailable.

local WEIGHT = {
    Regular  = Enum.FontWeight.Regular,
    Medium   = Enum.FontWeight.Medium,
    SemiBold = Enum.FontWeight.SemiBold,
    Bold     = Enum.FontWeight.Bold,
}
local FALLBACK_FAMILY = "rbxasset://fonts/families/GothamSSm.json"
local FontCache = {}

local function familyOf(spec)
    local ty = typeof(spec)
    if ty == "Font" then return spec.Family end
    if ty == "EnumItem" then
        local ok, f = pcall(Font.fromEnum, spec)
        return ok and f and f.Family or FALLBACK_FAMILY
    end
    if ty == "string" then
        if spec:find("://") then return spec end
        return "rbxasset://fonts/families/" .. spec .. ".json"
    end
    return FALLBACK_FAMILY
end

local function getFont(spec, weight)
    local family = familyOf(spec)
    local w = WEIGHT[weight or "Regular"] or Enum.FontWeight.Regular
    local key = family .. "|" .. w.Name
    local f = FontCache[key]
    if f then return f end
    local ok, res = pcall(Font.new, family, w, Enum.FontStyle.Normal)
    if not ok or not res then
        ok, res = pcall(Font.new, FALLBACK_FAMILY, w, Enum.FontStyle.Normal)
    end
    f = ok and res or Font.fromEnum(Enum.Font.Gotham)
    FontCache[key] = f
    return f
end

--==============================================================================
-- §4  THEMES
--==============================================================================
--[[
    Every theme is a flat table of TOKENS. Components never contain colours —
    they only ever reference token names, so editing a value here restyles the
    whole library (live, if you call Sypse:SetTheme afterwards).

    COLOUR TOKENS
    Any Color3 token may be paired with `<Token>Transparency` (0 = opaque,
    1 = invisible). Missing transparency tokens default to 0.

      Background   window base layer (behind Panel). With a transparent Panel
                   this is what gives Acrylic its tinted-glass look.
      BackgroundGradient  optional { Color3, Color3, Color3, Rotation = deg, Mid = 0..1 }
                   drawn on the window backdrop. Rotation is CSS degrees - 90
                   (0 = left→right, 90 = top→bottom); Mid moves the middle stop.
      Stage        reserved — the mockup's page backdrop. Unused in-game; kept
                   so theme tables round-trip with the HTML mockup.
      Panel        window body.
      Panel2       raised controls: input fields, secondary buttons, title bar.
      Panel3       recessed rows / cards / sidebar / status bar.
      Stroke       primary borders.         Stroke2   subtle internal dividers.
      Track        slider track, switch off-state.
      Knob         slider thumb, switch knob.
      Text         primary text.            Dim       secondary / muted text.
      Tooltip      tooltip, dropdown popup and toast background.
      Console      log viewer background.   ConsoleText  log viewer text colour
                   (added because light themes pair a dark console with dark
                   body text, which would be unreadable).
      Accent       primary action colour.   AccentFg  text drawn on Accent.
      AccentSoft   10-15 % tint (active tab, chips, value pills).
      AccentLine   ~30 % border for AccentSoft surfaces.
      Accent2      secondary accent (range sliders, alt spinners).
      Ok / OkSoft / OkLine, Warn / WarnSoft / WarnLine, Danger / DangerSoft / DangerLine
                   semantic colours, same soft/line convention as Accent.
      Placeholder, Placeholder2  diagonal stripes of loading thumbnails.
      Scrim        modal backdrop colour (+ ScrimTransparency).

    SHAPE / TYPE TOKENS
      Font, FontMono        body and monospace faces (see §3 for accepted forms).
      CornerRadius          UICorner radius (px) for the window, modals.
      CornerRadiusSmall     UICorner radius (px) for rows, buttons, fields.
      StrokeThickness       UIStroke.Thickness for primary borders (Blocky: 2.5).
      Shadow                "soft" | "none" | "glow" | "hard" | "chroma"
                              soft    large blurred drop shadow (layered frames)
                              none    no shadow
                              glow    Accent-coloured halo (ShadowColor)
                              hard    solid offset rectangle, no blur (ShadowOffset)
                              chroma  two solid offset blocks in opposite directions
                                      over a soft drop (the VHS aberration look)
      ShadowColor, ShadowTransparency, ShadowOffset (Vector2, for "hard")
      ShadowGlow, ShadowGlowTransparency   optional halo layered on top of a soft
                            shadow (Ember). Independent of Shadow = "glow".
      ShadowChromaA/B, …Transparency, …Offset   the two "chroma" blocks.
      InnerHighlight, InnerHighlightTransparency   1px highlight along the window's
                            top edge (Abyss). Omit for none.
      BlurSize              BlurEffect size used when a window is in "theme" blur
                            mode and has no explicit size.
      ButtonShadow          "none" | "hard" | "glow" — under primary buttons.
      Blur                  true → BlurEffect on the camera while a window is open.
      TextCase              "none" | "upper" — applied to buttons, tab labels,
                            section headers, window + dialog titles.
      LetterSpacing         tracking for uppercase themes, in hair-space units
                            (0 = none). Roblox has no letter-spacing property, so
                            tracking is emulated with U+200A between glyphs.

    FONT SUBSTITUTIONS (the mockup's web fonts are not Roblox built-ins):
      Sora            → GothamSSm        IBM Plex Sans → BuilderSans
      IBM Plex Mono   → RobotoMono       JetBrains Mono → Inconsolata (Enum.Font.Code)
      Chakra Petch    → TitilliumWeb     Fredoka       → FredokaOne
      Nunito          → Nunito (built-in)
    Upload the real fonts and put their "rbxassetid://" family ids in the theme
    if you want a pixel match.
]]

local Themes = {}

Themes.Acrylic = {
    Name = "Acrylic", Description = "dark glass",
    -- surfaces
    Background = hex"161A25", BackgroundTransparency = 0.1,
    BackgroundGradient = { hex"2B3554", hex"161A25", hex"0F1117" },
    Stage   = hex"FFFFFF", StageTransparency = 0.97,
    Panel   = hex"FFFFFF", PanelTransparency  = 0.945,
    Panel2  = hex"FFFFFF", Panel2Transparency = 0.915,
    Panel3  = hex"080A10", Panel3Transparency = 0.66,
    Stroke  = hex"FFFFFF", StrokeTransparency  = 0.86,
    Stroke2 = hex"FFFFFF", Stroke2Transparency = 0.93,
    Track   = hex"FFFFFF", TrackTransparency   = 0.88,
    Knob    = hex"F4F6FB",
    -- text
    Text = hex"EDF0F7",
    Dim  = hex"EDF0F7", DimTransparency = 0.44,
    -- floating surfaces
    Tooltip = hex"1A1E2A", TooltipTransparency = 0.06,
    Console = hex"05070C", ConsoleTransparency = 0.4,
    ConsoleText = hex"EDF0F7",
    -- accents
    Accent = hex"7AA2FF", AccentFg = hex"0B1020",
    AccentSoft = hex"7AA2FF", AccentSoftTransparency = 0.85,
    AccentLine = hex"7AA2FF", AccentLineTransparency = 0.66,
    Accent2 = hex"A98BFF",
    -- semantic
    Ok = hex"5FE3A1",     OkSoft = hex"5FE3A1",     OkSoftTransparency = 0.86,     OkLine = hex"5FE3A1",     OkLineTransparency = 0.7,
    Warn = hex"FFC46B",   WarnSoft = hex"FFC46B",   WarnSoftTransparency = 0.86,   WarnLine = hex"FFC46B",   WarnLineTransparency = 0.7,
    Danger = hex"FF7A8A", DangerSoft = hex"FF7A8A", DangerSoftTransparency = 0.86, DangerLine = hex"FF7A8A", DangerLineTransparency = 0.68,
    Placeholder = hex"FFFFFF", PlaceholderTransparency = 0.92,
    Placeholder2 = hex"FFFFFF", Placeholder2Transparency = 0.97,
    Scrim = hex"06080C", ScrimTransparency = 0.38,
    -- type & shape
    Font = "GothamSSm",          -- Sora substitute
    FontMono = "RobotoMono",     -- IBM Plex Mono substitute
    CornerRadius = 15, CornerRadiusSmall = 11,
    StrokeThickness = 1,
    Shadow = "soft", ShadowColor = hex"000000", ShadowTransparency = 0.55,
    ButtonShadow = "glow",
    Blur = true,
    TextCase = "none", LetterSpacing = 0,
}

Themes.Daylight = {
    Name = "Daylight", Description = "clean dashboard",
    Background = hex"F2F3F6", Stage = hex"E9EBF0",
    Panel = hex"FFFFFF", Panel2 = hex"F3F4F8", Panel3 = hex"FAFAFC",
    Stroke = hex"DFE2E9", Stroke2 = hex"EAECF1", Track = hex"E4E7EE", Knob = hex"FFFFFF",
    Text = hex"171A21", Dim = hex"6B7280",
    Tooltip = hex"FFFFFF", Console = hex"1B1F2A", ConsoleText = hex"E6E8EE",
    Accent = hex"4A55E0", AccentFg = hex"FFFFFF",
    AccentSoft = hex"4A55E0", AccentSoftTransparency = 0.91,
    AccentLine = hex"4A55E0", AccentLineTransparency = 0.75,
    Accent2 = hex"00897B",
    Ok = hex"0E8A55",     OkSoft = hex"0E8A55",     OkSoftTransparency = 0.9,      OkLine = hex"0E8A55",     OkLineTransparency = 0.76,
    Warn = hex"A86200",   WarnSoft = hex"A86200",   WarnSoftTransparency = 0.9,    WarnLine = hex"A86200",   WarnLineTransparency = 0.76,
    Danger = hex"C62B3E", DangerSoft = hex"C62B3E", DangerSoftTransparency = 0.91, DangerLine = hex"C62B3E", DangerLineTransparency = 0.76,
    Placeholder = hex"171A21", PlaceholderTransparency = 0.93,
    Placeholder2 = hex"171A21", Placeholder2Transparency = 0.98,
    Scrim = hex"171A21", ScrimTransparency = 0.6,
    Font = "BuilderSans",        -- IBM Plex Sans substitute
    FontMono = "RobotoMono",     -- IBM Plex Mono substitute
    CornerRadius = 12, CornerRadiusSmall = 9,
    StrokeThickness = 1,
    Shadow = "soft", ShadowColor = hex"171A21", ShadowTransparency = 0.88,
    ButtonShadow = "glow",
    Blur = false,
    TextCase = "none", LetterSpacing = 0,
}

Themes.Terminal = {
    Name = "Terminal", Description = "monospace",
    Background = hex"070A08", Stage = hex"0A0E0B",
    Panel = hex"0C110D", Panel2 = hex"132016", Panel3 = hex"0A0F0B",
    Stroke = hex"1E3323", Stroke2 = hex"152219", Track = hex"182B1D", Knob = hex"0A0F0B",
    Text = hex"C9F7D4", Dim = hex"5C8C6A",
    Tooltip = hex"0F1A12", Console = hex"050806", ConsoleText = hex"C9F7D4",
    Accent = hex"4BFF95", AccentFg = hex"04150A",
    AccentSoft = hex"4BFF95", AccentSoftTransparency = 0.89,
    AccentLine = hex"4BFF95", AccentLineTransparency = 0.7,
    Accent2 = hex"7DE8FF",
    Ok = hex"4BFF95",     OkSoft = hex"4BFF95",     OkSoftTransparency = 0.89,     OkLine = hex"4BFF95",     OkLineTransparency = 0.7,
    Warn = hex"FFD166",   WarnSoft = hex"FFD166",   WarnSoftTransparency = 0.89,   WarnLine = hex"FFD166",   WarnLineTransparency = 0.7,
    Danger = hex"FF6B6B", DangerSoft = hex"FF6B6B", DangerSoftTransparency = 0.89, DangerLine = hex"FF6B6B", DangerLineTransparency = 0.7,
    Placeholder = hex"4BFF95", PlaceholderTransparency = 0.91,
    Placeholder2 = hex"4BFF95", Placeholder2Transparency = 0.98,
    Scrim = hex"000000", ScrimTransparency = 0.35,
    Font = Enum.Font.Code,       -- JetBrains Mono substitute (Inconsolata)
    FontMono = Enum.Font.Code,
    CornerRadius = 3, CornerRadiusSmall = 2,
    StrokeThickness = 1,
    Shadow = "none", ShadowColor = hex"000000", ShadowTransparency = 0.5,
    ButtonShadow = "none",
    Blur = false,
    TextCase = "upper", LetterSpacing = 1,
}

Themes.Voltage = {
    Name = "Voltage", Description = "neon cyber",
    Background = hex"0B0A1E",
    BackgroundGradient = { hex"0A0614", hex"0B0A1E", hex"07060F" },
    Stage = hex"FFFFFF", StageTransparency = 0.98,
    Panel = hex"0F0D22", Panel2 = hex"191634", Panel3 = hex"0B0919",
    Stroke = hex"2E2A5C", Stroke2 = hex"221F45", Track = hex"221F45", Knob = hex"F2EEFF",
    Text = hex"EDE9FF", Dim = hex"8B85BE",
    Tooltip = hex"161230", Console = hex"07050F", ConsoleText = hex"EDE9FF",
    Accent = hex"FF2D95", AccentFg = hex"12001F",
    AccentSoft = hex"FF2D95", AccentSoftTransparency = 0.86,
    AccentLine = hex"FF2D95", AccentLineTransparency = 0.62,
    Accent2 = hex"22E7FF",
    Ok = hex"3DFFC4",     OkSoft = hex"3DFFC4",     OkSoftTransparency = 0.88,     OkLine = hex"3DFFC4",     OkLineTransparency = 0.68,
    Warn = hex"FFD447",   WarnSoft = hex"FFD447",   WarnSoftTransparency = 0.88,   WarnLine = hex"FFD447",   WarnLineTransparency = 0.68,
    Danger = hex"FF4D6D", DangerSoft = hex"FF4D6D", DangerSoftTransparency = 0.87, DangerLine = hex"FF4D6D", DangerLineTransparency = 0.66,
    Placeholder = hex"FF2D95", PlaceholderTransparency = 0.88,
    Placeholder2 = hex"22E7FF", Placeholder2Transparency = 0.95,
    Scrim = hex"05030C", ScrimTransparency = 0.3,
    Font = "TitilliumWeb",       -- Chakra Petch substitute
    FontMono = "RobotoMono",     -- JetBrains Mono substitute
    CornerRadius = 5, CornerRadiusSmall = 4,
    StrokeThickness = 1,
    Shadow = "glow", ShadowColor = hex"FF2D95", ShadowTransparency = 0.8,
    ButtonShadow = "glow",
    Blur = false,
    TextCase = "upper", LetterSpacing = 1,
}

Themes.Marshmallow = {
    Name = "Marshmallow", Description = "soft pastel",
    Background = hex"FBF6F2", Stage = hex"F4EDE7",
    Panel = hex"FFFFFF", Panel2 = hex"FBF3EE", Panel3 = hex"FDF8F5",
    Stroke = hex"EDE0D7", Stroke2 = hex"F4EAE3", Track = hex"F0E4DC", Knob = hex"FFFFFF",
    Text = hex"4A3E38", Dim = hex"9C8A7E",
    Tooltip = hex"FFFFFF", Console = hex"3C332E", ConsoleText = hex"F4EDE7",
    Accent = hex"E2705C", AccentFg = hex"FFFFFF",
    AccentSoft = hex"E2705C", AccentSoftTransparency = 0.89,
    AccentLine = hex"E2705C", AccentLineTransparency = 0.74,
    Accent2 = hex"7E8CD6",
    Ok = hex"3F9E7C",     OkSoft = hex"3F9E7C",     OkSoftTransparency = 0.89,     OkLine = hex"3F9E7C",     OkLineTransparency = 0.74,
    Warn = hex"C08A2E",   WarnSoft = hex"C08A2E",   WarnSoftTransparency = 0.88,   WarnLine = hex"C08A2E",   WarnLineTransparency = 0.74,
    Danger = hex"C9515E", DangerSoft = hex"C9515E", DangerSoftTransparency = 0.9,  DangerLine = hex"C9515E", DangerLineTransparency = 0.75,
    Placeholder = hex"4A3E38", PlaceholderTransparency = 0.93,
    Placeholder2 = hex"4A3E38", Placeholder2Transparency = 0.98,
    Scrim = hex"4A3E38", ScrimTransparency = 0.62,
    Font = "Nunito",
    FontMono = "RobotoMono",     -- IBM Plex Mono substitute
    CornerRadius = 20, CornerRadiusSmall = 14,
    StrokeThickness = 1,
    Shadow = "soft", ShadowColor = hex"785C4C", ShadowTransparency = 0.84,
    ButtonShadow = "glow",
    Blur = false,
    TextCase = "none", LetterSpacing = 0,
}

Themes.Blocky = {
    Name = "Blocky", Description = "chunky borders",
    Background = hex"D8DEE6", Stage = hex"C9D1DC",
    Panel = hex"FFFFFF", Panel2 = hex"EFF2F6", Panel3 = hex"F7F9FB",
    Stroke = hex"15191F", Stroke2 = hex"15191F", Track = hex"D7DDE5", Knob = hex"FFFFFF",
    Text = hex"15191F", Dim = hex"5C6672",
    Tooltip = hex"FFFFFF", Console = hex"15191F", ConsoleText = hex"F7F9FB",
    Accent = hex"FFB020", AccentFg = hex"15191F",
    AccentSoft = hex"FFB020", AccentSoftTransparency = 0.8,
    AccentLine = hex"15191F",
    Accent2 = hex"2F8CFF",
    Ok = hex"12925E",     OkSoft = hex"12925E",     OkSoftTransparency = 0.84,     OkLine = hex"15191F",
    Warn = hex"B5720A",   WarnSoft = hex"FFB020",   WarnSoftTransparency = 0.78,   WarnLine = hex"15191F",
    Danger = hex"D6323F", DangerSoft = hex"D6323F", DangerSoftTransparency = 0.86, DangerLine = hex"15191F",
    Placeholder = hex"15191F", PlaceholderTransparency = 0.88,
    Placeholder2 = hex"15191F", Placeholder2Transparency = 0.96,
    Scrim = hex"15191F", ScrimTransparency = 0.5,
    Font = "FredokaOne",         -- Fredoka substitute
    FontMono = "RobotoMono",     -- IBM Plex Mono substitute
    CornerRadius = 14, CornerRadiusSmall = 10,
    StrokeThickness = 2.5,
    Shadow = "hard", ShadowColor = hex"15191F", ShadowTransparency = 0, ShadowOffset = Vector2.new(7, 7),
    ButtonShadow = "hard",
    Blur = false,
    TextCase = "none", LetterSpacing = 0,
}


Themes.Ember = {
    Name = "Ember", Description = "warm amber dark",
    Background = hex"1C1512",
    -- radial highlight from the top-right in the mockup; approximated with a
    -- diagonal gradient (Rotation is CSS-degrees - 90).
    BackgroundGradient = { hex"3A2216", hex"1C1512", hex"120D0B", Rotation = 135, Mid = 0.48 },
    Stage = hex"FFFFFF", StageTransparency = 0.975,
    Panel = hex"1B1512", Panel2 = hex"2A211B", Panel3 = hex"150F0D",
    Stroke = hex"3B2C22", Stroke2 = hex"2A1F19", Track = hex"31251E", Knob = hex"FFF3E6",
    Text = hex"F6E9DC", Dim = hex"A98A72",
    Tooltip = hex"241A15", Console = hex"0E0A08", ConsoleText = hex"F6E9DC",
    Accent = hex"FF9034", AccentFg = hex"1A0E05",
    AccentSoft = hex"FF9034", AccentSoftTransparency = 0.86,
    AccentLine = hex"FF9034", AccentLineTransparency = 0.66,
    Accent2 = hex"FFCE5C",
    Ok = hex"8FD66B",     OkSoft = hex"8FD66B",     OkSoftTransparency = 0.87,     OkLine = hex"8FD66B",     OkLineTransparency = 0.7,
    Warn = hex"FFCE5C",   WarnSoft = hex"FFCE5C",   WarnSoftTransparency = 0.87,   WarnLine = hex"FFCE5C",   WarnLineTransparency = 0.7,
    Danger = hex"FF6B57", DangerSoft = hex"FF6B57", DangerSoftTransparency = 0.87, DangerLine = hex"FF6B57", DangerLineTransparency = 0.68,
    Placeholder = hex"FF9034", PlaceholderTransparency = 0.9,
    Placeholder2 = hex"FF9034", Placeholder2Transparency = 0.97,
    Scrim = hex"0E0A08", ScrimTransparency = 0.35,
    Font = "GothamSSm",          -- Sora substitute
    FontMono = "RobotoMono",     -- IBM Plex Mono substitute
    CornerRadius = 10, CornerRadiusSmall = 8,
    StrokeThickness = 1,
    -- soft black drop plus a faint amber halo on top of it
    Shadow = "soft", ShadowColor = hex"000000", ShadowTransparency = 0.62,
    ShadowGlow = hex"FF9034", ShadowGlowTransparency = 0.93,
    ButtonShadow = "glow",
    Blur = false,
    TextCase = "none", LetterSpacing = 0,
}

Themes.Paper = {
    Name = "Paper", Description = "high-contrast mono",
    Background = hex"EFEDE7", Stage = hex"E4E1D8",
    Panel = hex"FBFAF6", Panel2 = hex"EDEAE1", Panel3 = hex"F5F3EC",
    Stroke = hex"111111", Stroke2 = hex"C9C5B8", Track = hex"DDD9CD", Knob = hex"FBFAF6",
    Text = hex"111111", Dim = hex"6E6A5E",
    Tooltip = hex"FBFAF6", Console = hex"111111", ConsoleText = hex"FBFAF6",
    -- the accent IS black: accent buttons are solid #111 with paper-white text
    Accent = hex"111111", AccentFg = hex"FBFAF6",
    AccentSoft = hex"111111", AccentSoftTransparency = 0.93,
    AccentLine = hex"111111",
    Accent2 = hex"8A3FFC",
    Ok = hex"1C6B3C",     OkSoft = hex"1C6B3C",     OkSoftTransparency = 0.9,      OkLine = hex"1C6B3C",
    Warn = hex"8A5A00",   WarnSoft = hex"8A5A00",   WarnSoftTransparency = 0.9,    WarnLine = hex"8A5A00",
    Danger = hex"B0202E", DangerSoft = hex"B0202E", DangerSoftTransparency = 0.91, DangerLine = hex"B0202E",
    Placeholder = hex"111111", PlaceholderTransparency = 0.9,
    Placeholder2 = hex"111111", Placeholder2Transparency = 0.98,
    Scrim = hex"111111", ScrimTransparency = 0.55,
    Font = "RobotoMono",         -- IBM Plex Mono substitute (both roles)
    FontMono = "RobotoMono",
    CornerRadius = 0, CornerRadiusSmall = 0,
    StrokeThickness = 1.5,
    Shadow = "none", ShadowColor = hex"111111", ShadowTransparency = 0.85,
    ButtonShadow = "none",
    Blur = false,
    TextCase = "upper", LetterSpacing = 1,
}

Themes.Abyss = {
    Name = "Abyss", Description = "deep teal",
    Background = hex"03242A",
    BackgroundGradient = { hex"02181C", hex"03242A", hex"010F12", Rotation = 80, Mid = 0.46 },
    Stage = hex"78FFF0", StageTransparency = 0.97,
    Panel = hex"062A31", Panel2 = hex"0B3B44", Panel3 = hex"042227",
    Stroke = hex"0F4B55", Stroke2 = hex"0A3A42", Track = hex"0C3B44", Knob = hex"E4FBFA",
    Text = hex"DCF6F4", Dim = hex"6FA6A9",
    Tooltip = hex"07323A", Console = hex"011317", ConsoleText = hex"DCF6F4",
    Accent = hex"2BE0C4", AccentFg = hex"012622",
    AccentSoft = hex"2BE0C4", AccentSoftTransparency = 0.87,
    AccentLine = hex"2BE0C4", AccentLineTransparency = 0.68,
    Accent2 = hex"5AA9FF",
    Ok = hex"2BE0C4",     OkSoft = hex"2BE0C4",     OkSoftTransparency = 0.87,     OkLine = hex"2BE0C4",     OkLineTransparency = 0.7,
    Warn = hex"FFC98A",   WarnSoft = hex"FFC98A",   WarnSoftTransparency = 0.87,   WarnLine = hex"FFC98A",   WarnLineTransparency = 0.7,
    Danger = hex"FF7C9B", DangerSoft = hex"FF7C9B", DangerSoftTransparency = 0.87, DangerLine = hex"FF7C9B", DangerLineTransparency = 0.68,
    Placeholder = hex"2BE0C4", PlaceholderTransparency = 0.9,
    Placeholder2 = hex"2BE0C4", Placeholder2Transparency = 0.97,
    Scrim = hex"011317", ScrimTransparency = 0.35,
    Font = "GothamSSm",          -- Sora substitute
    FontMono = "RobotoMono",     -- IBM Plex Mono substitute
    CornerRadius = 18, CornerRadiusSmall = 13,
    StrokeThickness = 1,
    Shadow = "soft", ShadowColor = hex"001418", ShadowTransparency = 0.7,
    InnerHighlight = hex"FFFFFF", InnerHighlightTransparency = 0.95, -- 1px top edge
    ButtonShadow = "glow",
    Blur = true, BlurSize = 14,  -- only used in "theme" blur mode
    TextCase = "none", LetterSpacing = 0,
}

Themes.Cassette = {
    Name = "Cassette", Description = "VHS retro",
    Background = hex"1A1424",
    BackgroundGradient = { hex"241A2E", hex"1A1424", hex"120E1A", Rotation = 90, Mid = 0.6 },
    Stage = hex"FFFFFF", StageTransparency = 0.975,
    Panel = hex"241B31", Panel2 = hex"332643", Panel3 = hex"1C1528",
    Stroke = hex"463358", Stroke2 = hex"332543", Track = hex"3A2B4B", Knob = hex"FFF6E8",
    Text = hex"F3E7D6", Dim = hex"A18BB4",
    Tooltip = hex"2C2039", Console = hex"140F1D", ConsoleText = hex"F3E7D6",
    Accent = hex"FF6B9D", AccentFg = hex"1A0A14",
    AccentSoft = hex"FF6B9D", AccentSoftTransparency = 0.86,
    AccentLine = hex"FF6B9D", AccentLineTransparency = 0.66,
    Accent2 = hex"48D6C8",
    Ok = hex"48D6C8",     OkSoft = hex"48D6C8",     OkSoftTransparency = 0.87,     OkLine = hex"48D6C8",     OkLineTransparency = 0.7,
    Warn = hex"FFB84D",   WarnSoft = hex"FFB84D",   WarnSoftTransparency = 0.87,   WarnLine = hex"FFB84D",   WarnLineTransparency = 0.7,
    Danger = hex"FF5252", DangerSoft = hex"FF5252", DangerSoftTransparency = 0.87, DangerLine = hex"FF5252", DangerLineTransparency = 0.68,
    Placeholder = hex"FF6B9D", PlaceholderTransparency = 0.88,
    Placeholder2 = hex"48D6C8", Placeholder2Transparency = 0.95,
    Scrim = hex"120E1A", ScrimTransparency = 0.35,
    Font = "TitilliumWeb",       -- Chakra Petch substitute
    FontMono = "RobotoMono",     -- JetBrains Mono substitute
    CornerRadius = 7, CornerRadiusSmall = 5,
    StrokeThickness = 1,
    -- chromatic aberration: teal block down-right, pink block up-left, soft black drop
    Shadow = "chroma", ShadowColor = hex"000000", ShadowTransparency = 0.6,
    ShadowChromaA = hex"48D6C8", ShadowChromaATransparency = 0.65, ShadowChromaAOffset = Vector2.new(4, 4),
    ShadowChromaB = hex"FF6B9D", ShadowChromaBTransparency = 0.72, ShadowChromaBOffset = Vector2.new(-4, -4),
    ButtonShadow = "chroma",
    Blur = false,
    TextCase = "upper", LetterSpacing = 1,
}

-- Order used by theme pickers.
local THEME_ORDER = { "Acrylic", "Daylight", "Terminal", "Voltage", "Marshmallow", "Blocky", "Ember", "Paper", "Abyss", "Cassette" }

-- Build a complete theme from a (possibly partial) table merged over `base`.
-- Rule for partial themes: if you override a colour token but NOT its
-- `<Token>Transparency`, the transparency resets to 0 (opaque). This stops a
-- custom opaque Panel from silently inheriting Acrylic's 0.945 glass value.
local function completeTheme(tbl, base)
    base = base or Themes.Acrylic
    local t = merge(base, tbl)
    for k, v in pairs(tbl) do
        if typeof(v) == "Color3" and tbl[k .. "Transparency"] == nil then
            t[k .. "Transparency"] = nil
        end
    end
    t.ShadowOffset = t.ShadowOffset or Vector2.new(7, 7)
    t.LetterSpacing = t.LetterSpacing or 0
    t.TextCase = t.TextCase or "none"
    t.Name = tbl.Name or t.Name
    return t
end
-- Built-in themes are complete already; this only fills structural defaults.
for _, name in ipairs(THEME_ORDER) do
    local t = Themes[name]
    t.ShadowOffset = t.ShadowOffset or Vector2.new(7, 7)
end

Sypse.Themes = Themes
Sypse.ThemeOrder = THEME_ORDER

--==============================================================================
-- §5  TOKEN REGISTRY — live re-skinning
--==============================================================================
--[[
    Every themed property goes through `bind(instance, { Property = spec })`.
    A spec is either:
      * a token name string   "Panel"  → theme.Panel (+ theme.PanelTransparency
                                          written to the paired transparency prop)
      * a function(theme, instance) → value [, transparency]
                                          used for state-dependent styling
      * a literal value
    The registry remembers every binding. `Sypse:SetTheme` walks it and re-applies
    each spec against the new theme, tweening colours / numbers over 0.15 s.
    Components call `restyle(inst)` after their own state changes (e.g. a toggle
    flipping) so state styling and theme styling go through the same path.
]]

local CurrentTheme = Themes.Acrylic
local Registry = {}          -- [Instance] = { [prop] = spec }
local RegistryCount = 0
local PruneAt = 4000
local PrunePending = false
local ThemeListeners = {}    -- [key] = function(theme)
local FadeMap = setmetatable({}, { __mode = "k" }) -- [Instance] = 0..1 extra fade (disabled / locked)

local PAIRED = {
    BackgroundColor3 = "BackgroundTransparency",
    TextColor3 = "TextTransparency",
    ImageColor3 = "ImageTransparency",
    ScrollBarImageColor3 = "ScrollBarImageTransparency",
}
local TWEENABLE = { Color3 = true, number = true, UDim = true, UDim2 = true, Vector2 = true }

local function pairedProp(inst, prop)
    if prop == "Color" and inst:IsA("UIStroke") then return "Transparency" end
    return PAIRED[prop]
end

-- token → (value, transparency)
local function tk(t, name)
    return t[name], t[name .. "Transparency"] or 0
end

local function resolveSpec(spec, t, inst)
    local ty = type(spec)
    if ty == "string" then
        local v = t[spec]
        if typeof(v) == "Color3" then return v, t[spec .. "Transparency"] or 0 end
        return v
    elseif ty == "function" then
        return spec(t, inst)
    end
    return spec
end

local function applyProp(inst, prop, spec, animTime)
    local ok, v, tr = pcall(resolveSpec, spec, CurrentTheme, inst)
    if not ok then warn("[Sypse] theme spec error on " .. prop .. ": " .. tostring(v)) return end
    if v == nil then return end
    local goal, direct = nil, nil
    local function put(p, val)
        if animTime and animTime > 0 and TWEENABLE[typeof(val)] then
            goal = goal or {}; goal[p] = val
        else
            direct = direct or {}; direct[p] = val
        end
    end
    local f = FadeMap[inst]
    if f and tr ~= nil then tr = 1 - (1 - tr) * (1 - f) end
    put(prop, v)
    if tr ~= nil then
        local tp = pairedProp(inst, prop)
        if tp then put(tp, tr) end
    end
    if direct then for p, val in pairs(direct) do pcall(function() inst[p] = val end) end end
    if goal then tween(inst, animTime, goal) end
end

local function prune()
    PrunePending = false
    local n = 0
    for inst in pairs(Registry) do
        if inst.Parent == nil then Registry[inst] = nil else n += 1 end
    end
    RegistryCount = n
    PruneAt = math.max(4000, n * 2)
end

local function bind(inst, props)
    local entry = Registry[inst]
    if not entry then
        entry = {}
        Registry[inst] = entry
        RegistryCount += 1
        if RegistryCount > PruneAt and not PrunePending then
            PrunePending = true
            task.defer(prune) -- deferred so half-built (unparented) UI is never pruned
        end
    end
    for prop, spec in pairs(props) do
        entry[prop] = spec
        applyProp(inst, prop, spec, nil)
    end
    return inst
end

-- Re-apply an instance's bindings (after a state change). `only` limits props.
local function restyle(inst, animTime, only)
    local entry = Registry[inst]
    if not entry then return end
    if only then
        for _, prop in ipairs(only) do
            if entry[prop] ~= nil then applyProp(inst, prop, entry[prop], animTime) end
        end
    else
        for prop, spec in pairs(entry) do applyProp(inst, prop, spec, animTime) end
    end
end

-- Fade a whole subtree (disabled / locked look). Survives theme changes.
local function setFaded(root, amount)
    local a = (amount and amount > 0) and amount or nil
    FadeMap[root] = a
    restyle(root, 0.15)
    for _, d in ipairs(root:GetDescendants()) do
        FadeMap[d] = a
        restyle(d, 0.15)
    end
end

local function restyleAll(list, animTime)
    for _, inst in ipairs(list) do restyle(inst, animTime) end
end

local function applyThemeEverywhere(animTime)
    prune()
    for inst, entry in pairs(Registry) do
        for prop, spec in pairs(entry) do applyProp(inst, prop, spec, animTime) end
    end
    for _, fn in pairs(ThemeListeners) do
        local ok, err = pcall(fn, CurrentTheme)
        if not ok then warn("[Sypse] theme listener: " .. tostring(err)) end
    end
end

--==============================================================================
-- §6  PRIMITIVE BUILDERS
--==============================================================================

Sypse.Tracking = true -- set false to disable hair-space letter tracking

local HAIR = utf8.char(0x200A)
local function track(s, amount)
    if not Sypse.Tracking or not amount or amount <= 0 or s == "" then return s end
    local sep = string.rep(HAIR, math.clamp(math.floor(amount + 0.5), 1, 3))
    local out = {}
    for _, cp in utf8.codes(s) do table.insert(out, utf8.char(cp)) end
    return table.concat(out, sep)
end

-- mode: nil (raw) | "theme" (theme TextCase + LetterSpacing) | "upper" (always, tracked)
local function caseText(raw, t, mode)
    raw = raw or ""
    if mode == "upper" then return track(string.upper(raw), 1) end
    if mode == "theme" and t.TextCase == "upper" then return track(string.upper(raw), t.LetterSpacing) end
    return raw
end

local function New(class, props, children)
    local inst = Instance.new(class)
    local themed, parent
    if props then
        for k, v in pairs(props) do
            if k == "Theme" then themed = v
            elseif k == "Parent" then parent = v
            else inst[k] = v end
        end
    end
    if children then for _, c in ipairs(children) do c.Parent = inst end end
    if themed then bind(inst, themed) end
    if parent then inst.Parent = parent end
    return inst
end

local function Frame(p)
    p = p or {}
    if p.BorderSizePixel == nil then p.BorderSizePixel = 0 end
    if p.BackgroundTransparency == nil and not (p.Theme and p.Theme.BackgroundColor3) then
        p.BackgroundTransparency = 1
    end
    return New("Frame", p)
end

local function Button(p)
    p = p or {}
    p.BorderSizePixel = 0
    p.AutoButtonColor = false
    if p.Text == nil then p.Text = "" end
    if p.BackgroundTransparency == nil and not (p.Theme and p.Theme.BackgroundColor3) then
        p.BackgroundTransparency = 1
    end
    return New("TextButton", p)
end

-- Corner(parent, spec) — spec: token name, px number, "full", or function(t)->px
local function Corner(parent, spec)
    local c = Instance.new("UICorner")
    if spec == "full" then
        c.CornerRadius = UDim.new(1, 0)
    elseif type(spec) == "number" then
        c.CornerRadius = UDim.new(0, spec)
    elseif type(spec) == "string" then
        bind(c, { CornerRadius = function(t) return UDim.new(0, math.max(0, t[spec] or 0)) end })
    elseif type(spec) == "function" then
        bind(c, { CornerRadius = function(t) return UDim.new(0, math.max(0, spec(t))) end })
    end
    c.Parent = parent
    return c
end

-- Stroke(parent, colorSpec, thickness) — thickness: nil = theme StrokeThickness
local function Stroke(parent, colorSpec, thickness)
    local s = Instance.new("UIStroke")
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.LineJoinMode = Enum.LineJoinMode.Round
    local props = { Color = colorSpec or "Stroke" }
    if thickness == nil then
        props.Thickness = function(t) return t.StrokeThickness end
    elseif type(thickness) == "function" then
        props.Thickness = thickness
    else
        s.Thickness = thickness
    end
    bind(s, props)
    s.Parent = parent
    return s
end

local function Pad(parent, t, r, b, l)
    r = r or t; b = b or t; l = l or r
    return New("UIPadding", {
        PaddingTop = UDim.new(0, t), PaddingRight = UDim.new(0, r),
        PaddingBottom = UDim.new(0, b), PaddingLeft = UDim.new(0, l),
        Parent = parent,
    })
end

local function List(parent, dir, gap, props)
    local l = Instance.new("UIListLayout")
    l.FillDirection = dir == "x" and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical
    l.SortOrder = Enum.SortOrder.LayoutOrder
    l.Padding = UDim.new(0, gap or 0)
    if props then for k, v in pairs(props) do pcall(function() l[k] = v end) end end
    l.Parent = parent
    return l
end

local function FlexFill(inst)
    pcall(function()
        local f = Instance.new("UIFlexItem")
        f.FlexMode = Enum.UIFlexMode.Fill
        f.Parent = inst
    end)
end

local function TryCanvasGroup(props)
    local ok, cg = pcall(Instance.new, "CanvasGroup")
    if ok and cg then
        cg.BorderSizePixel = 0
        if props then
            local themed, parent = props.Theme, props.Parent
            for k, v in pairs(props) do if k ~= "Theme" and k ~= "Parent" then cg[k] = v end end
            if themed then bind(cg, themed) end
            if parent then cg.Parent = parent end
        end
        return cg, true
    end
    return Frame(props), false
end

--[[ Label(parent, opts)
    Text, TextSize (13), Weight ("Regular"), Mono (false), Color (spec, "Text"),
    Case (nil|"theme"|"upper"), Wrap, Size, Position, AnchorPoint, XAlign, YAlign,
    LayoutOrder, ZIndex, LineHeight, Rich, Name, AutoSize (Enum.AutomaticSize) ]]
local function Label(parent, o)
    o = o or {}
    local l = Instance.new("TextLabel")
    l.Name = o.Name or "Label"
    l.BackgroundTransparency = 1
    l.BorderSizePixel = 0
    l.TextSize = o.TextSize or 13
    l.RichText = o.Rich or false
    l.TextWrapped = o.Wrap or false
    l.TextXAlignment = o.XAlign or Enum.TextXAlignment.Left
    l.TextYAlignment = o.YAlign or Enum.TextYAlignment.Center
    if o.LineHeight then l.LineHeight = o.LineHeight end
    if o.Truncate then l.TextTruncate = Enum.TextTruncate.AtEnd end
    if o.Size then l.Size = o.Size end
    if o.Position then l.Position = o.Position end
    if o.AnchorPoint then l.AnchorPoint = o.AnchorPoint end
    if o.LayoutOrder then l.LayoutOrder = o.LayoutOrder end
    if o.ZIndex then l.ZIndex = o.ZIndex end
    if o.AutoSize then
        l.AutomaticSize = o.AutoSize
    elseif not o.Size then
        l.AutomaticSize = o.Wrap and Enum.AutomaticSize.Y or Enum.AutomaticSize.XY
        if o.Wrap then l.Size = UDim2.new(1, 0, 0, 0) end
    end
    local weight, mono, case = o.Weight or "Regular", o.Mono, o.Case
    local props = {
        TextColor3 = o.Color or "Text",
        FontFace = function(t) return getFont(mono and t.FontMono or t.Font, weight) end,
    }
    if case then
        l:SetAttribute("SypseRaw", o.Text or "")
        props.Text = function(t, inst) return caseText(inst:GetAttribute("SypseRaw"), t, case) end
    else
        l.Text = o.Text or ""
    end
    bind(l, props)
    l.Parent = parent
    return l
end

-- Update text of a label/button that may be case-bound.
local function setText(inst, raw)
    raw = tostring(raw)
    if inst:GetAttribute("SypseRaw") ~= nil then
        inst:SetAttribute("SypseRaw", raw)
        restyle(inst, nil, { "Text" })
    else
        inst.Text = raw
    end
end

-- Horizontal row whose children are vertically centred.
local function HRow(parent, gap, props)
    local f = Frame(merge({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = parent }, props))
    List(f, "x", gap or 8, { VerticalAlignment = Enum.VerticalAlignment.Center })
    return f
end

local function VStack(parent, gap, props)
    local f = Frame(merge({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = parent }, props))
    List(f, "y", gap or 8)
    return f
end

-- Hover helper: calls fn(true/false).
local function onHover(guiObj, fn)
    guiObj.MouseEnter:Connect(function() fn(true) end)
    guiObj.MouseLeave:Connect(function() fn(false) end)
end

-- Keep `outer` sized to `inner`'s absolute size (divided by UI scale).
local function followSize(outer, inner, scaleFn, extra)
    extra = extra or Vector2.zero
    local function upd()
        local s = scaleFn and scaleFn() or 1
        outer.Size = UDim2.fromOffset(inner.AbsoluteSize.X / s + extra.X, inner.AbsoluteSize.Y / s + extra.Y)
    end
    inner:GetPropertyChangedSignal("AbsoluteSize"):Connect(upd)
    task.defer(upd)
    return upd
end

-- Transparency helper for disabled/faded states: blends toward invisible.
local function fade(tr, amount) return 1 - (1 - (tr or 0)) * (1 - amount) end

--==============================================================================
-- §7  SHARED WIDGETS
--==============================================================================

-- Semantic kinds → token triples (fg, soft bg, line)
local KIND = {
    accent = { "Accent", "AccentSoft", "AccentLine" },
    info   = { "Accent", "AccentSoft", "AccentLine" },
    ok     = { "Ok", "OkSoft", "OkLine" },
    warn   = { "Warn", "WarnSoft", "WarnLine" },
    danger = { "Danger", "DangerSoft", "DangerLine" },
    dim    = { "Dim", "Panel2", "Stroke" },
}
local function kindOf(k)
    k = k and string.lower(tostring(k)) or "accent"
    if k == "err" or k == "error" then k = "danger" elseif k == "success" then k = "ok" elseif k == "warning" then k = "warn" end
    return KIND[k] and k or "accent"
end

-- Compact mono uppercase chip. Returns frame, api{Set(text, kind)}
local function Badge(parent, text, kind, opts)
    opts = opts or {}
    local state = { kind = kindOf(kind) }
    local f = Frame({
        Name = "Badge", AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.new(),
        LayoutOrder = opts.LayoutOrder, Parent = parent,
        Theme = { BackgroundColor3 = function(t) return tk(t, KIND[state.kind][2]) end },
    })
    Corner(f, 5)
    Pad(f, opts.PadY or 3, opts.PadX or 7, opts.PadY or 3, opts.PadX or 7)
    if opts.Border ~= false then
        Stroke(f, function(t) return tk(t, KIND[state.kind][3]) end, 1)
    end
    local l = Label(f, {
        Text = string.upper(tostring(text)), TextSize = opts.TextSize or 9, Weight = "SemiBold", Mono = true,
        Color = function(t) return tk(t, KIND[state.kind][1]) end,
    })
    local api = {}
    function api.Set(_, newText, newKind)
        if newText ~= nil then l.Text = string.upper(tostring(newText)) end
        if newKind ~= nil then
            state.kind = kindOf(newKind)
            restyle(f, 0.15); for _, d in ipairs(f:GetDescendants()) do restyle(d, 0.15) end
        end
    end
    api.Frame = f
    return f, api
end

-- Chevron built from two bars (V shape pointing down at Rotation 0).
local function Chevron(parent, colorSpec, props)
    local c = Frame(merge({ Name = "Chevron", Size = UDim2.fromOffset(10, 10) }, props))
    for i, rot in ipairs({ 45, -45 }) do
        local bar = Frame({
            Size = UDim2.fromOffset(6, 1.5), AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromOffset(i == 1 and 3.2 or 6.8, 5), Rotation = rot,
            BackgroundTransparency = 0, Parent = c,
            Theme = { BackgroundColor3 = colorSpec or "Dim" },
        })
        Corner(bar, "full")
    end
    c.Parent = parent
    return c
end

-- Icon: "circle" | "square" | "diamond" | "rbxassetid://…" | a text glyph
local function Icon(parent, icon, size, colorSpec, props)
    size = size or 14
    icon = icon or "square"
    local holder = Frame(merge({ Name = "Icon", Size = UDim2.fromOffset(size, size) }, props))
    if icon == "circle" or icon == "square" or icon == "diamond" then
        local shape = Frame({ Size = UDim2.new(1, -4, 1, -4), Position = UDim2.fromOffset(2, 2), Parent = holder })
        if icon == "diamond" then shape.Rotation = 45; shape.Size = UDim2.new(1, -6, 1, -6); shape.Position = UDim2.fromOffset(3, 3) end
        Corner(shape, icon == "circle" and "full" or 2)
        Stroke(shape, colorSpec or "Dim", 2)
    elseif type(icon) == "string" and (icon:find("rbxasset") or icon:find("http")) then
        New("ImageLabel", {
            BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Image = icon,
            Theme = { ImageColor3 = colorSpec or "Dim" }, Parent = holder,
        })
    else
        Label(holder, { Text = tostring(icon), TextSize = size, Size = UDim2.fromScale(1, 1),
            XAlign = Enum.TextXAlignment.Center, Color = colorSpec or "Dim", Weight = "SemiBold" })
    end
    holder.Parent = parent
    return holder
end

--[[ Spinner(parent, style, size)
     "ring" — track ring + accent arc          "thin" — 2/3 ring in Accent2
     "dots" — three pulsing dots
   Animated with infinite tweens (no per-frame loops); they stop when destroyed. ]]
local function Spinner(parent, style, size, props)
    style = string.lower(style or "ring")
    size = size or 18
    local root = Frame(merge({ Name = "Spinner", Size = UDim2.fromOffset(style == "dots" and size + 8 or size, size) }, props))
    if style == "dots" then
        List(root, "x", 4, { VerticalAlignment = Enum.VerticalAlignment.Center })
        for i = 1, 3 do
            local d = Frame({ Size = UDim2.fromOffset(6, 6), BackgroundTransparency = 0, LayoutOrder = i, Parent = root,
                Theme = { BackgroundColor3 = function(t) return t.Accent end } })
            Corner(d, "full")
            d.BackgroundTransparency = 0.5
            task.delay((i - 1) * 0.2, function()
                if d.Parent then
                    local ok, tw = pcall(TweenService.Create, TweenService, d,
                        TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { BackgroundTransparency = 0 })
                    if ok then tw:Play() end
                end
            end)
        end
    else
        local thin = style == "thin"
        local thick = thin and 1.5 or 2
        if not thin then
            local base = Frame({ Size = UDim2.new(1, -thick * 2, 1, -thick * 2), Position = UDim2.fromOffset(thick, thick), Parent = root })
            Corner(base, "full")
            Stroke(base, "Stroke", thick)
        end
        local arc = Frame({ Size = UDim2.new(1, -thick * 2, 1, -thick * 2), Position = UDim2.fromOffset(thick, thick), Parent = root })
        Corner(arc, "full")
        local st = Stroke(arc, thin and "Accent2" or "Accent", thick)
        local cut = thin and 0.66 or 0.36
        New("UIGradient", {
            Rotation = 90,
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(cut, 0),
                NumberSequenceKeypoint.new(math.min(cut + 0.001, 0.999), 1), NumberSequenceKeypoint.new(1, 1),
            }),
            Parent = st,
        })
        local ok, tw = pcall(TweenService.Create, TweenService, arc,
            TweenInfo.new(thin and 1.1 or 0.8, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Rotation = 360 })
        if ok then tw:Play() end
    end
    root.Parent = parent
    return root
end

--[[ Shadow layers for an elevated surface. Layers are siblings placed BEFORE the
     surface inside `host` (so they render underneath). The theme decides the
     look: soft / glow = stacked translucent rounded frames, hard = one offset
     solid block, none = hidden. `radiusToken` picks the corner radius token.
     `scale` shrinks spreads for small surfaces. ]]
local SOFT_SPREADS = { 2, 5, 9, 14, 20, 28 }
local function ShadowLayers(host, radiusToken, scale, zindex)
    scale = scale or 1
    local layers = {}
    for i, spread in ipairs(SOFT_SPREADS) do
        local sp = spread * scale
        local layer = Frame({
            Name = "Shadow" .. i, BackgroundTransparency = 1, ZIndex = zindex or 0, Parent = host,
            Theme = {
                Visible = function(t) return t.Shadow == "soft" or t.Shadow == "glow" or t.Shadow == "chroma" end,
                BackgroundColor3 = function(t)
                    local glow = t.Shadow == "glow"
                    local color = glow and (t.ShadowColor or t.Accent) or (t.ShadowColor or Color3.new())
                    local base = 1 - (t.ShadowTransparency or 0.6)          -- total opacity budget
                    local per = base / #SOFT_SPREADS * (glow and 1.2 or 1)
                    return color, 1 - per
                end,
                Position = function(t)
                    local yoff = t.Shadow == "glow" and 0 or sp * 0.45
                    return UDim2.new(0, -sp, 0, -sp + yoff)
                end,
                Size = UDim2.new(1, sp * 2, 1, sp * 2),
            },
        })
        Corner(layer, function(t) return (t[radiusToken] or 10) + sp end)
        table.insert(layers, layer)
    end
    -- Optional accent halo layered ON TOP of a soft shadow (theme.ShadowGlow).
    for i, spread in ipairs({ 16, 30 }) do
        local sp = spread * scale
        local layer = Frame({
            Name = "ShadowGlow" .. i, BackgroundTransparency = 1, ZIndex = zindex or 0, Parent = host,
            Size = UDim2.new(1, sp * 2, 1, sp * 2), Position = UDim2.new(0, -sp, 0, -sp),
            Theme = {
                Visible = function(t) return t.ShadowGlow ~= nil and t.Shadow ~= "none" end,
                BackgroundColor3 = function(t)
                    local base = 1 - (t.ShadowGlowTransparency or 0.93)
                    return t.ShadowGlow or t.Accent, 1 - base / 2
                end,
            },
        })
        Corner(layer, function(t) return (t[radiusToken] or 10) + sp end)
        table.insert(layers, layer)
    end

    -- "chroma": two solid offset blocks in opposite directions (VHS aberration).
    for _, side in ipairs({ "A", "B" }) do
        local chroma = Frame({
            Name = "ShadowChroma" .. side, BackgroundTransparency = 0, ZIndex = zindex or 0, Parent = host,
            Size = UDim2.fromScale(1, 1),
            Theme = {
                Visible = function(t) return t.Shadow == "chroma" and t["ShadowChroma" .. side] ~= nil end,
                BackgroundColor3 = function(t)
                    return t["ShadowChroma" .. side] or t.Accent, t["ShadowChroma" .. side .. "Transparency"] or 0.6
                end,
                Position = function(t)
                    local o = t["ShadowChroma" .. side .. "Offset"] or Vector2.new(side == "A" and 4 or -4, side == "A" and 4 or -4)
                    return UDim2.fromOffset(o.X * scale, o.Y * scale)
                end,
            },
        })
        Corner(chroma, radiusToken)
        table.insert(layers, chroma)
    end

    local hard = Frame({
        Name = "ShadowHard", BackgroundTransparency = 0, ZIndex = zindex or 0, Parent = host,
        Size = UDim2.fromScale(1, 1),
        Theme = {
            Visible = function(t) return t.Shadow == "hard" end,
            BackgroundColor3 = function(t) return t.ShadowColor or t.Stroke, 0 end,
            Position = function(t)
                local o = t.ShadowOffset or Vector2.new(7, 7)
                return UDim2.fromOffset(o.X * scale, o.Y * scale)
            end,
        },
    })
    Corner(hard, radiusToken)
    table.insert(layers, hard)
    return layers
end

-- Small hard/glow shadow under primary buttons (theme.ButtonShadow).
local function ButtonShadow(host, zindex)
    local s = Frame({
        Name = "BtnShadow", ZIndex = zindex or 0, Parent = host, BackgroundTransparency = 1,
        Theme = {
            Visible = function(t) return t.ButtonShadow == "hard" or t.ButtonShadow == "glow" or t.ButtonShadow == "chroma" end,
            BackgroundColor3 = function(t)
                if t.ButtonShadow == "hard" then return t.Stroke, 0 end
                if t.ButtonShadow == "chroma" then return t.ShadowChromaA or t.Accent2, (t.ShadowChromaATransparency or 0.5) end
                return t.Accent, 0.78
            end,
            Position = function(t)
                if t.ButtonShadow == "hard" then return UDim2.fromOffset(3, 3) end
                if t.ButtonShadow == "chroma" then return UDim2.fromOffset(2, 2) end
                return UDim2.fromOffset(-2, 2)
            end,
            Size = function(t)
                if t.ButtonShadow == "glow" then return UDim2.new(1, 4, 1, 4) end
                return UDim2.fromScale(1, 1)
            end,
        },
    })
    Corner(s, function(t) return t.CornerRadiusSmall + (t.ButtonShadow == "glow" and 2 or 0) end)
    return s
end

--==============================================================================
-- §8  WINDOW
--==============================================================================

local Window = {}
Window.__index = Window
local Tab = {}
local Container = {}
Container.__index = Container

local TITLE_H, SIDEBAR_W, SEGBAR_H, STATUS_H, FOOTER_H = 52, 182, 56, 32, 78

local Library = {
    Windows = {},
    DefaultBlur = false,      -- blur is off by default for every theme
    DefaultBlurSize = 10,
    ActiveWindow = nil,
    Flags = {},          -- flag → value         (exposed as Sypse.Flags)
    Options = {},        -- flag → control handle (exposed as Sypse.Options)
    Maid = Maid.new(),
    Overlay = nil,       -- ScreenGui for toasts / watermark
    Logs = {},
    LogSubscribers = {},
    Telemetry = { fps = 0, ping = 0, mem = 0, pos = nil, subs = {} },
}
Sypse.Flags = Library.Flags
Sypse.Options = Library.Options

local function guiParent(explicit)
    if explicit then return explicit end
    if Env.gethui then
        local ok, h = pcall(Env.gethui)
        if ok and h then return h end
    end
    local ok = pcall(function() local _ = CoreGui.Name; local probe = Instance.new("Folder"); probe.Parent = CoreGui; probe:Destroy() end)
    if ok then return CoreGui end
    if LocalPlayer then return LocalPlayer:WaitForChild("PlayerGui") end
    return nil
end

local function makeScreenGui(name, order, parent)
    local g = Instance.new("ScreenGui")
    g.Name = name
    g.ResetOnSpawn = false
    g.IgnoreGuiInset = true
    g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    g.DisplayOrder = order
    if Env.protect_gui then pcall(Env.protect_gui, g) end
    g.Parent = guiParent(parent)
    if not (RefGui and RefGui.Parent) then RefGui = g end
    return g
end

-- Telemetry: one RenderStepped counter shared by every consumer.
local function startTelemetry()
    local T = Library.Telemetry
    if T.running then return end
    T.running = true
    local frames, acc = 0, 0
    Library.Maid:Give(RunService.RenderStepped:Connect(function(dt)
        frames += 1
        acc += dt
        if acc >= 0.5 then
            T.fps = math.floor(frames / acc + 0.5)
            frames, acc = 0, 0
            if LocalPlayer then
                local ok, ping = pcall(function() return LocalPlayer:GetNetworkPing() end)
                T.ping = ok and math.floor((ping or 0) * 1000 + 0.5) or 0
                local char = LocalPlayer.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                T.pos = hrp and hrp.Position or nil
            end
            local okm, mem = pcall(function() return StatsService:GetTotalMemoryUsageMb() end)
            T.mem = okm and math.floor(mem + 0.5) or 0
            for _, fn in pairs(T.subs) do pcall(fn, T) end
        end
    end))
end
local function subscribeTelemetry(key, fn)
    Library.Telemetry.subs[key] = fn
    startTelemetry()
end
local function fmtPos(p, short)
    if not p then return short and "—" or "x —  y —  z —" end
    if short then return string.format("%d, %d", p.X, p.Y) end
    return string.format("x %.1f  y %.1f  z %.1f", p.X, p.Y, p.Z)
end

local function getOverlay()
    if Library.Overlay and Library.Overlay.Parent then return Library.Overlay end
    local g = makeScreenGui("SypseOverlay", 10001, Library.GuiParent)
    Library.Overlay = g
    Library.Maid:Give(g)
    local toasts = Frame({ Name = "Toasts", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -26, 1, -26),
        Size = UDim2.fromOffset(300, 600), Parent = g })
    List(toasts, "y", 9, { VerticalAlignment = Enum.VerticalAlignment.Bottom, HorizontalAlignment = Enum.HorizontalAlignment.Right })
    Library.ToastHost = toasts
    return g
end

-- A small bordered square button with a drawn glyph (title bar controls).
local function ChromeButton(parent, kind, order, onClick)
    local st = { hover = false }
    local b = Button({
        Name = kind, Size = UDim2.fromOffset(26, 26), LayoutOrder = order, Parent = parent,
        BackgroundTransparency = 1,
        Theme = { BackgroundColor3 = function(t)
            if not st.hover then return t.Panel2, 1 end
            if kind == "Close" then return t.Danger, 0 end
            return tk(t, "Panel2")
        end },
    })
    Corner(b, 6)
    local stroke = Stroke(b, function(t)
        if st.hover and kind == "Close" then return t.Danger, 0 end
        return tk(t, "Stroke")
    end)
    local glyphColor = function(t)
        if st.hover then return kind == "Close" and t.AccentFg or t.Text, 0 end
        return tk(t, "Dim")
    end
    local parts = {}
    if kind == "Minimize" then
        local bar = Frame({ Size = UDim2.fromOffset(9, 1.6), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
            BackgroundTransparency = 0, Parent = b, Theme = { BackgroundColor3 = glyphColor } })
        table.insert(parts, bar)
    elseif kind == "Maximize" then
        local box = Frame({ Size = UDim2.fromOffset(8, 8), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Parent = b })
        Corner(box, 1.5)
        local s = Stroke(box, glyphColor, 1.5)
        table.insert(parts, s)
    else
        for _, r in ipairs({ 45, -45 }) do
            local bar = Frame({ Size = UDim2.fromOffset(11, 1.6), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
                Rotation = r, BackgroundTransparency = 0, Parent = b, Theme = { BackgroundColor3 = glyphColor } })
            table.insert(parts, bar)
        end
    end
    onHover(b, function(h)
        st.hover = h
        restyle(b, 0.12); restyle(stroke, 0.12)
        for _, p in ipairs(parts) do restyle(p, 0.12) end
    end)
    b.MouseButton1Click:Connect(onClick)
    return b
end

function Sypse:CreateWindow(o)
    o = o or {}
    local self = setmetatable({}, Window)
    self.Options = o
    self.Title = o.Title or "Sypse UI"
    self.Tabs = {}
    self.Controls = {}
    self.Keybinds = {}
    self.Maid = Maid.new()
    self.Alive = true
    self.Visible = true
    self.ToggleKey = o.ToggleKey or Enum.KeyCode.RightShift
    self.ConfigFolder = o.ConfigFolder or "SypseUI"
    self.BaseSize = o.Size or UDim2.fromOffset(980, 620)
    -- Blur: window option wins, else the library default (off unless Sypse:SetBlur set it).
    self.BlurMode = (o.Blur ~= nil) and o.Blur or Library.DefaultBlur
    self.BlurSize = o.BlurSize                     -- nil = follow the theme / library default
    self.Profile = o.Profile or "default.json"

    if o.Theme then Sypse:SetTheme(o.Theme, true) end
    Library.GuiParent = o.Parent

    local version = o.Version
    local subtitle = o.Subtitle
    if not version and subtitle and tostring(subtitle):match("^v%d") then version, subtitle = subtitle, nil end

    -- ScreenGui ---------------------------------------------------------------
    local gui = makeScreenGui(o.Name or "SypseUI", o.DisplayOrder or 10000, o.Parent)
    self.Gui = gui
    self.Maid:Give(gui)

    -- Root (dragged & sized) → shadows + Chrome(border) → Canvas (clips) -------
    local w, h = self.BaseSize.X.Offset, self.BaseSize.Y.Offset
    local root = Frame({ Name = "Root", Size = UDim2.fromOffset(w, h), Parent = gui })
    self.Root = root
    self.Scale = New("UIScale", { Scale = 1, Parent = root })
    self.ShadowLayers = ShadowLayers(root, "CornerRadius", 1, 0)

    local chrome = Frame({ Name = "Chrome", Size = UDim2.fromScale(1, 1), ZIndex = 1, Parent = root })
    Corner(chrome, "CornerRadius")
    Stroke(chrome, "Stroke")

    -- The CanvasGroup itself stays transparent: a UIGradient on a CanvasGroup
    -- multiplies the colour of EVERYTHING inside it (text, panels, strokes), so
    -- the theme's background gradient lives on its own Backdrop frame instead.
    local canvas, isCanvas = TryCanvasGroup({
        Name = "Canvas", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ClipsDescendants = true,
        Parent = chrome,
    })
    self.Canvas, self.IsCanvasGroup = canvas, isCanvas
    Corner(canvas, "CornerRadius")
    local backdrop = Frame({ Name = "Backdrop", Size = UDim2.fromScale(1, 1), Parent = canvas,
        Theme = { BackgroundColor3 = function(t)
            -- with a gradient the frame is white so the gradient colours show unmodified
            if t.BackgroundGradient then return Color3.new(1, 1, 1), t.BackgroundTransparency or 0 end
            return tk(t, "Background")
        end } })
    Corner(backdrop, "CornerRadius")
    New("UIGradient", { Rotation = 35, Parent = backdrop,
        Theme = {
            Enabled = function(t) return t.BackgroundGradient ~= nil end,
            -- BackgroundGradient = { c1, c2, c3, Rotation = deg, Mid = 0..1 }
            Rotation = function(t) return t.BackgroundGradient and (t.BackgroundGradient.Rotation or 35) or 35 end,
            Color = function(t)
                local g = t.BackgroundGradient
                if not g then return ColorSequence.new(Color3.new(1, 1, 1)) end
                local mid = clamp(g.Mid or 0.52, 0.01, 0.99)
                return ColorSequence.new({ ColorSequenceKeypoint.new(0, g[1]), ColorSequenceKeypoint.new(mid, g[2] or g[1]), ColorSequenceKeypoint.new(1, g[3] or g[2] or g[1]) })
            end,
        } })

    -- Optional 1px inner highlight along the top edge (theme.InnerHighlight).
    Frame({ Name = "InnerHighlight", Size = UDim2.new(1, -24, 0, 1), Position = UDim2.fromOffset(12, 0), ZIndex = 3, Parent = canvas,
        Theme = {
            Visible = function(t) return t.InnerHighlight ~= nil end,
            BackgroundColor3 = function(t) return t.InnerHighlight or Color3.new(1, 1, 1), t.InnerHighlightTransparency or 0.95 end,
        } })
    local surface = Frame({ Name = "Surface", Size = UDim2.fromScale(1, 1), Parent = canvas, Theme = { BackgroundColor3 = "Panel" } })
    Corner(surface, "CornerRadius")

    -- Title bar ---------------------------------------------------------------
    local titleBar = Frame({ Name = "TitleBar", Size = UDim2.new(1, 0, 0, TITLE_H), ZIndex = 2, Parent = canvas,
        Theme = { BackgroundColor3 = "Panel2" }, Active = true })
    self.TitleBar = titleBar
    Frame({ Name = "Border", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), BackgroundTransparency = 0,
        Parent = titleBar, Theme = { BackgroundColor3 = "Stroke", Size = function(t) return UDim2.new(1, 0, 0, math.max(1, math.floor(t.StrokeThickness + 0.5))) end } })
    local left = Frame({ Name = "Left", Size = UDim2.new(1, -120, 1, 0), Position = UDim2.fromOffset(15, 0), Parent = titleBar })
    List(left, "x", 12, { VerticalAlignment = Enum.VerticalAlignment.Center })
    local appIcon = Frame({ Name = "AppIcon", Size = UDim2.fromOffset(26, 26), LayoutOrder = 1, Parent = left, Theme = { BackgroundColor3 = "Accent" } })
    Corner(appIcon, function(t) return t.CornerRadiusSmall - 2 end)
    Label(appIcon, { Text = o.Icon or string.upper(string.sub(self.Title, 1, 1)), TextSize = 13, Weight = "Bold",
        Size = UDim2.fromScale(1, 1), XAlign = Enum.TextXAlignment.Center, Color = "AccentFg" })
    self.TitleLabel = Label(left, { Text = self.Title, TextSize = 14, Weight = "SemiBold", Case = "theme", LayoutOrder = 2 })
    if version then
        local vb = Frame({ AutomaticSize = Enum.AutomaticSize.XY, LayoutOrder = 3, Parent = left, Theme = { BackgroundColor3 = "AccentSoft" } })
        Corner(vb, 5); Pad(vb, 4, 7); Stroke(vb, "AccentLine", 1)
        self.VersionLabel = Label(vb, { Text = version, TextSize = 10, Weight = "Medium", Mono = true, Color = "Accent" })
    end
    if subtitle then
        local sub = Label(left, { Text = subtitle, TextSize = 11, Mono = true, Color = "Dim", LayoutOrder = 4 })
        New("UIPadding", { PaddingLeft = UDim.new(0, 4), Parent = sub })
        self.SubtitleLabel = sub
    end
    local controls = Frame({ Name = "Controls", AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 26),
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -15, 0.5, 0), Parent = titleBar })
    List(controls, "x", 6, { VerticalAlignment = Enum.VerticalAlignment.Center })
    ChromeButton(controls, "Minimize", 1, function() self:Minimize() end)
    ChromeButton(controls, "Maximize", 2, function() self:Maximize() end)
    ChromeButton(controls, "Close", 3, function() self:Close() end)

    -- Body: sidebar + content column --------------------------------------------
    local body = Frame({ Name = "Body", Position = UDim2.fromOffset(0, TITLE_H), Size = UDim2.new(1, 0, 1, -TITLE_H), ZIndex = 1, Parent = canvas })
    self.Body = body

    local sidebar = Frame({ Name = "Sidebar", Size = UDim2.new(0, SIDEBAR_W, 1, 0), Parent = body, Theme = { BackgroundColor3 = "Panel3" } })
    Frame({ Name = "Border", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), BackgroundTransparency = 0, Parent = sidebar,
        Theme = { BackgroundColor3 = "Stroke", Size = function(t) return UDim2.new(0, math.max(1, math.floor(t.StrokeThickness + 0.5)), 1, 0) end } })
    -- UIStroke renders OUTSIDE its frame and a ScrollingFrame clips its children,
    -- so full-width tab buttons would lose the outer part of their border. The
    -- list is widened by STROKE_ROOM on every side and padded back in by the same
    -- amount: tabs stay put, strokes up to STROKE_ROOM px thick have room to draw.
    local STROKE_ROOM = 3
    local tabList = New("ScrollingFrame", {
        Name = "Tabs", BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(11 - STROKE_ROOM, 14 - STROKE_ROOM),
        Size = UDim2.new(1, -22 + STROKE_ROOM * 2, 1, -(14 + FOOTER_H + 11) + STROKE_ROOM * 2), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = 0, ScrollingDirection = Enum.ScrollingDirection.Y, Parent = sidebar,
    })
    Pad(tabList, STROKE_ROOM)
    List(tabList, "y", 4)
    self.TabList = tabList

    local footer = Frame({ Name = "Footer", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 11, 1, -14),
        Size = UDim2.new(1, -22, 0, FOOTER_H), Parent = sidebar })
    Frame({ Name = "Divider", Size = UDim2.new(1, 0, 0, 1), BackgroundTransparency = 0, Parent = footer, Theme = { BackgroundColor3 = "Stroke2" } })
    local user = o.User or {}
    local uname = user.Name or (LocalPlayer and LocalPlayer.Name) or "player"
    local card = Frame({ Name = "User", Position = UDim2.fromOffset(0, 14), Size = UDim2.new(1, 0, 0, 28), Parent = footer })
    local av = Frame({ Size = UDim2.fromOffset(28, 28), Parent = card, Theme = { BackgroundColor3 = "Panel2" } })
    Corner(av, 8); Stroke(av, "Stroke")
    Label(av, { Text = user.Initials or string.upper(string.sub(uname, 1, 2)), TextSize = 11, Weight = "SemiBold", Mono = true, Color = "Dim",
        Size = UDim2.fromScale(1, 1), XAlign = Enum.TextXAlignment.Center })
    self.UserName = Label(card, { Text = uname, TextSize = 11, Weight = "SemiBold", Position = UDim2.fromOffset(37, 2), Size = UDim2.new(1, -37, 0, 13), Truncate = true })
    self.UserSub = Label(card, { Text = user.Sub or user.Status or "online", TextSize = 10, Mono = true, Color = "Dim", Position = UDim2.fromOffset(37, 16), Size = UDim2.new(1, -37, 0, 11) })
    self:_footerButton(footer, o.SaveButtonText or "Save config")

    -- content column
    local content = Frame({ Name = "Content", Position = UDim2.fromOffset(SIDEBAR_W, 0), Size = UDim2.new(1, -SIDEBAR_W, 1, 0), Parent = body })
    self.Content = content
    local segBar = Frame({ Name = "SegBar", Size = UDim2.new(1, 0, 0, SEGBAR_H), Parent = content })
    Frame({ Name = "Border", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 1), BackgroundTransparency = 0,
        Parent = segBar, Theme = { BackgroundColor3 = "Stroke2" } })
    self.SegBar = segBar
    self:_buildFilterBox(segBar)

    local pagesHost = Frame({ Name = "Pages", Position = UDim2.fromOffset(0, SEGBAR_H), Size = UDim2.new(1, 0, 1, -(SEGBAR_H + STATUS_H)), Parent = content })
    self.PagesHost = pagesHost
    self:_buildStatusBar(content)

    -- Overlay layer for popups / tooltips / dialogs (inside the clip) ----------
    self.Overlay = Frame({ Name = "Overlay", Size = UDim2.fromScale(1, 1), ZIndex = 50, Parent = canvas })

    -- Behaviour -----------------------------------------------------------------
    self:_setupDrag()
    self:_setupInput()
    self:_fitToViewport(true)
    self.Maid:Give(gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() self:_fitToViewport(false) end))

    ThemeListeners[self] = function(t) self:_applyBlur() end
    self:_applyBlur()

    subscribeTelemetry(self, function(T) self:_onTelemetry(T) end)

    table.insert(Library.Windows, self)
    Library.ActiveWindow = self

    if o.Watermark ~= false then self:SetWatermark(true) end

    -- open animation
    if isCanvas then
        canvas.GroupTransparency = 1
        tween(canvas, 0.2, { GroupTransparency = 0 })
    end
    return self
end

function Window:_s()
    return self.Scale and self.Scale.Scale or 1
end

function Window:_footerButton(footer, text)
    local st = { hover = false }
    local b = Button({ Name = "Save", Position = UDim2.fromOffset(0, 51), Size = UDim2.new(1, 0, 0, 26), Parent = footer,
        Theme = { BackgroundColor3 = "Panel2", TextColor3 = function(t) return st.hover and t.Accent or t.Text, 0 end,
            FontFace = function(t) return getFont(t.Font, "Medium") end,
            Text = function(t) return caseText(text, t, "theme") end }, TextSize = 11 })
    Corner(b, "CornerRadiusSmall")
    local s = Stroke(b, function(t) if st.hover then return t.Accent, 0 end return tk(t, "Stroke") end)
    onHover(b, function(hv) st.hover = hv; restyle(b, 0.12); restyle(s, 0.12) end)
    b.MouseButton1Click:Connect(function()
        local ok, err = self:SaveConfig(self.Profile)
        if ok then
            Sypse:Notify({ Title = "Config saved", Body = self.Profile .. " written" .. (Env.HasFileIO and " to disk" or " (memory)"), Kind = "ok" })
        else
            Sypse:Notify({ Title = "Save failed", Body = tostring(err), Kind = "danger" })
        end
    end)
end

function Window:_buildFilterBox(segBar)
    local box = Frame({ Name = "Filter", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), Size = UDim2.fromOffset(230, 30),
        Parent = segBar, Theme = { BackgroundColor3 = "Panel3" } })
    Corner(box, "CornerRadiusSmall"); Stroke(box, "Stroke")
    local mag = Frame({ Size = UDim2.fromOffset(10, 10), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 11, 0.5, 0), Parent = box })
    Corner(mag, "full"); Stroke(mag, "Dim", 1.5)
    local tb = New("TextBox", {
        Name = "Input", BackgroundTransparency = 1, Position = UDim2.fromOffset(29, 0), Size = UDim2.new(1, -60, 1, 0),
        ClearTextOnFocus = false, Text = "", PlaceholderText = "Filter controls…", TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left, Parent = box,
        Theme = { TextColor3 = "Text", PlaceholderColor3 = function(t) return t.Dim end, FontFace = function(t) return getFont(t.Font) end },
    })
    local key = Frame({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), AutomaticSize = Enum.AutomaticSize.XY,
        Parent = box, Theme = { BackgroundColor3 = "Panel2" } })
    Corner(key, 4); Pad(key, 3, 5)
    Label(key, { Text = "/", TextSize = 9, Weight = "Medium", Mono = true, Color = "Dim" })
    self.FilterBox = tb
    local pending = 0
    tb:GetPropertyChangedSignal("Text"):Connect(function()
        pending += 1
        local my = pending
        task.delay(0.15, function() -- debounce
            if my == pending and self.Alive then self:_applyFilter(tb.Text) end
        end)
    end)
end

function Window:_applyFilter(q)
    local tab = self.ActiveTab
    local page = tab and tab.ActivePage
    if page then return page:Filter(q) end
    return 0
end

function Window:_buildStatusBar(content)
    local bar = Frame({ Name = "StatusBar", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, STATUS_H),
        Parent = content, Theme = { BackgroundColor3 = "Panel3" } })
    Frame({ Size = UDim2.new(1, 0, 0, 1), BackgroundTransparency = 0, Parent = bar, Theme = { BackgroundColor3 = "Stroke2" } })
    local st = { kind = "ok" }
    local dot = Frame({ Size = UDim2.fromOffset(6, 6), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 16, 0.5, 0), Parent = bar,
        Theme = { BackgroundColor3 = function(t) return t[KIND[st.kind][1]], 0 end } })
    Corner(dot, "full")
    self.StatusText = Label(bar, { Text = self.Options.Status or ("attached · " .. self.Profile), TextSize = 11, Mono = true, Color = "Dim",
        AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 34, 0.5, 0), Size = UDim2.new(0.6, -34, 0, 14), Truncate = true })
    local right = Frame({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), Size = UDim2.new(0.4, 0, 0, 14), Parent = bar })
    List(right, "x", 12, { HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Center })
    self.StatusMem = Label(right, { Text = "mem — MB", TextSize = 11, Mono = true, Color = "Dim", LayoutOrder = 1 })
    self.StatusPos = Label(right, { Text = fmtPos(nil), TextSize = 11, Mono = true, Color = "Dim", LayoutOrder = 2 })
    self._statusDot, self._statusState = dot, st
end

function Window:SetStatus(text, kind)
    if text then self.StatusText.Text = tostring(text) end
    if kind then self._statusState.kind = kindOf(kind); restyle(self._statusDot, 0.15) end
end

function Window:_onTelemetry(T)
    if not self.Alive then return end
    self.StatusMem.Text = "mem " .. T.mem .. " MB"
    self.StatusPos.Text = fmtPos(T.pos)
    if self._wmFps then
        self._wmFps.Text = T.fps .. " fps"
        self._wmPing.Text = T.ping .. " ms"
    end
end

--------------------------------------------------------------------------------
-- Dragging, clamping, visibility
--------------------------------------------------------------------------------

function Window:_viewport()
    local s = self.Gui.AbsoluteSize
    if s.X < 2 then
        local cam = workspace.CurrentCamera
        s = cam and cam.ViewportSize or Vector2.new(1280, 720)
    end
    return s
end

function Window:_clamp(x, y)
    local vp = self:_viewport()
    local sz = self.Root.AbsoluteSize
    return clamp(x, 0, math.max(0, vp.X - sz.X)), clamp(y, 0, math.max(0, vp.Y - sz.Y))
end

function Window:_fitToViewport(center)
    local vp = self:_viewport()
    local w, h = self.Root.Size.X.Offset, self.BaseSize.Y.Offset
    local s = math.min(1, (vp.X - 32) / w, (vp.Y - 32) / h)
    if self.Options.Scale then s = self.Options.Scale end
    self.Scale.Scale = math.max(0.45, s)
    if center then
        local sw, sh = w * self.Scale.Scale, self.Root.Size.Y.Offset * self.Scale.Scale
        self.Root.Position = UDim2.fromOffset(math.floor((vp.X - sw) / 2), math.floor((vp.Y - sh) / 2))
    end
    task.defer(function()
        if not self.Alive then return end
        local x, y = self:_clamp(self.Root.Position.X.Offset, self.Root.Position.Y.Offset)
        self.Root.Position = UDim2.fromOffset(x, y)
    end)
end

function Window:_setupDrag()
    local dragging, startPointer, startPos, dragInput
    self.Maid:Give(self.TitleBar.InputBegan:Connect(function(input)
        if not isPointerDown(input) then return end
        dragging = true
        dragInput = input
        startPointer = pointerPos(input)
        startPos = Vector2.new(self.Root.Position.X.Offset, self.Root.Position.Y.Offset)
    end))
    self.Maid:Give(UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        local moving = (input.UserInputType == Enum.UserInputType.MouseMovement and dragInput.UserInputType == Enum.UserInputType.MouseButton1)
            or input == dragInput
        if not moving then return end
        local d = pointerPos(input) - startPointer
        local x, y = self:_clamp(startPos.X + d.X, startPos.Y + d.Y)
        self.Root.Position = UDim2.fromOffset(x, y)
    end))
    self.Maid:Give(UserInputService.InputEnded:Connect(function(input)
        if dragging and (input == dragInput or input.UserInputType == Enum.UserInputType.MouseButton1) then dragging = false end
    end))
end

function Window:_setupInput()
    self.Maid:Give(UserInputService.InputBegan:Connect(function(input, processed)
        if not self.Alive then return end
        -- close popups on outside click
        if self._popup and isPointerDown(input) then
            local p = pointerPos(input)
            local pop = self._popup
            if not inRect(p, pop.Frame) and not (pop.Anchor and inRect(p, pop.Anchor)) then self:_closePopup() end
        end
        if UserInputService:GetFocusedTextBox() then return end
        if self._listening then return end -- a keybind picker owns this input
        if input.KeyCode ~= Enum.KeyCode.Unknown and input.KeyCode == self.ToggleKey then
            self:Toggle()
            return
        end
        if input.KeyCode == Enum.KeyCode.Slash and self.Visible and not processed then
            task.defer(function() self.FilterBox:CaptureFocus() end)
        end
        -- keybind controls
        for _, kb in ipairs(self.Keybinds) do kb:_input(input, true) end
    end))
    self.Maid:Give(UserInputService.InputEnded:Connect(function(input)
        if not self.Alive or self._listening then return end
        for _, kb in ipairs(self.Keybinds) do kb:_input(input, false) end
    end))
end

--[[ Blur is a window setting, not a theme one.
     Modes: false (default) — never blur
            true            — blur under every theme
            "theme"         — follow the theme's Blur token (Acrylic only, by default)
     `Sypse:SetBlur(mode, size)` applies to every open window and becomes the
     default for new ones. The legacy `DisableBlur` window option still forces off. ]]
function Window:BlurEnabled()
    if self.Options.DisableBlur then return false end
    if self.BlurMode == "theme" then return CurrentTheme.Blur == true end
    return self.BlurMode == true
end

--- SetBlur(true | false | "theme" [, size]) — takes effect immediately.
--- `size`: a number pins the blur size; nil leaves it as-is; false or "theme"
--- clears the pin so the theme's BlurSize (or the library default) applies again.
function Window:SetBlur(mode, size)
    if mode == nil then mode = true end
    self.BlurMode = mode
    if size ~= nil then
        self.BlurSize = (size ~= false and size ~= "theme") and size or nil
    end
    self:_applyBlur()
    return self
end

--- Effective blur size: explicit > theme token > library default.
function Window:_blurSize()
    return self.BlurSize or CurrentTheme.BlurSize or Library.DefaultBlurSize
end

--- Returns the current mode and the effective blur size.
function Window:GetBlur() return self.BlurMode, self:_blurSize() end

function Window:_applyBlur()
    local want = self:BlurEnabled() and self.Visible and self.Alive
    if want and not self._blur then
        local cam = workspace.CurrentCamera
        if cam then
            local ok, b = pcall(function()
                local e = Instance.new("BlurEffect")
                e.Name = "SypseBlur"
                e.Size = 0
                e.Parent = cam
                return e
            end)
            if ok then
                self._blur = b
                tween(b, 0.2, { Size = self:_blurSize() })
            end
        end
    elseif want and self._blur then
        tween(self._blur, 0.2, { Size = self:_blurSize() })
    elseif not want and self._blur then
        local b = self._blur
        self._blur = nil
        tween(b, 0.15, { Size = 0 })
        task.delay(0.16, function() pcall(b.Destroy, b) end)
    end
end

function Window:SetVisible(v)
    if not self.Alive or v == self.Visible then return end
    self.Visible = v
    self:_closePopup()
    if v then
        self.Root.Visible = true
        if self.IsCanvasGroup then self.Canvas.GroupTransparency = 1; tween(self.Canvas, 0.15, { GroupTransparency = 0 }) end
    else
        if self.IsCanvasGroup then
            tween(self.Canvas, 0.12, { GroupTransparency = 1 })
            task.delay(0.12, function() if not self.Visible and self.Alive then self.Root.Visible = false end end)
        else
            self.Root.Visible = false
        end
    end
    self:_applyBlur()
end
function Window:Toggle() self:SetVisible(not self.Visible) end
function Window:IsVisible() return self.Visible end

function Window:Minimize()
    self:_closePopup()
    self.Minimized = not self.Minimized
    local target = self.Minimized and TITLE_H or (self.Maximized and self._maxSize.Y or self.BaseSize.Y.Offset)
    tween(self.Root, 0.2, { Size = UDim2.fromOffset(self.Root.Size.X.Offset, target) })
    self.Body.Visible = true
    if self.Minimized then task.delay(0.2, function() if self.Minimized and self.Alive then self.Body.Visible = false end end) end
end

function Window:Maximize()
    self:_closePopup()
    self.Maximized = not self.Maximized
    local vp, s = self:_viewport(), self:_s()
    local w, h
    if self.Maximized then
        self._restorePos = self.Root.Position
        w, h = math.floor((vp.X - 60) / s), math.floor((vp.Y - 60) / s)
        self._maxSize = Vector2.new(w, h)
    else
        w, h = self.BaseSize.X.Offset, self.BaseSize.Y.Offset
    end
    if self.Minimized then self.Minimized = false; self.Body.Visible = true end
    tween(self.Root, 0.2, { Size = UDim2.fromOffset(w, h) })
    local pos = self.Maximized and UDim2.fromOffset(30, 30) or (self._restorePos or self.Root.Position)
    tween(self.Root, 0.2, { Position = pos })
end

function Window:Close()
    if self.Options.ConfirmClose then
        self:Dialog({
            Title = "Close " .. self.Title .. "?",
            Body = "The interface will be destroyed. Running callbacks keep their current state.",
            Icon = "!",
            Confirm = { Text = "Close", Variant = "Danger", Callback = function() self:Destroy() end },
            Cancel = { Text = "Cancel" },
        })
    else
        self:Destroy()
    end
end

function Window:Destroy()
    if not self.Alive then return end
    if self.Options.AutosaveFlag and Library.Flags[self.Options.AutosaveFlag] then pcall(function() self:SaveConfig(self.Profile) end) end
    self.Alive = false
    self.Visible = false
    ThemeListeners[self] = nil
    Library.Telemetry.subs[self] = nil
    self:_applyBlurOff()
    for _, c in ipairs(self.Controls) do pcall(function() c:_cleanup() end) end
    if self._wm then pcall(self._wm.Destroy, self._wm) end
    self.Maid:Clean()
    for i, w in ipairs(Library.Windows) do if w == self then table.remove(Library.Windows, i) break end end
    if Library.ActiveWindow == self then Library.ActiveWindow = Library.Windows[#Library.Windows] end
    safeCall(self.Options.OnClose)
end
function Window:_applyBlurOff()
    if self._blur then local b = self._blur; self._blur = nil; pcall(b.Destroy, b) end
end

function Window:SetToggleKey(key)
    self.ToggleKey = key
    self:_refreshHUD()
end

function Window:SetTitle(t)
    self.Title = t
    setText(self.TitleLabel, t)
    if self._wmTitle then setText(self._wmTitle, t) end
end

--------------------------------------------------------------------------------
-- Popups & tooltips (rendered in the window overlay)
--------------------------------------------------------------------------------

-- Convert an absolute screen position to overlay-local offset units.
function Window:_toOverlay(absPos)
    local o = self.Overlay.AbsolutePosition
    local s = self:_s()
    return (absPos - o) / s
end

function Window:_overlaySize()
    return self.Overlay.AbsoluteSize / self:_s()
end

function Window:_closePopup()
    local p = self._popup
    if not p then return end
    self._popup = nil
    if p.OnClose then pcall(p.OnClose) end
    pcall(p.Frame.Destroy, p.Frame)
end

--[[ Opens a floating panel under `anchor`. `build(list, close)` fills the
     scrolling list. Returns the popup record. ]]
function Window:_openPopup(anchor, build, opts)
    opts = opts or {}
    self:_closePopup()
    local wrap = Frame({ Name = "Popup", ZIndex = 60, Parent = self.Overlay })
    ShadowLayers(wrap, "CornerRadiusSmall", 0.3, 60)
    local panel = Frame({ Name = "Panel", Size = UDim2.fromScale(1, 1), ZIndex = 61, Parent = wrap, Theme = { BackgroundColor3 = "Tooltip" } })
    Corner(panel, function(t) return math.min(9, t.CornerRadiusSmall) end)
    Stroke(panel, "Stroke")
    local header
    if opts.Header then
        header = Frame({ Name = "Header", Size = UDim2.new(1, -8, 0, 32), Position = UDim2.fromOffset(4, 4), ZIndex = 62, Parent = panel })
        opts.Header(header)
    end
    local topOff = header and 38 or 4
    local scroll = New("ScrollingFrame", {
        Name = "List", BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 62,
        Position = UDim2.fromOffset(4, topOff), Size = UDim2.new(1, -8, 1, -(topOff + 4)),
        CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 3,
        ScrollingDirection = Enum.ScrollingDirection.Y, Parent = panel,
        Theme = { ScrollBarImageColor3 = "Stroke" },
    })
    local layout = List(scroll, "y", 1)
    local record = { Frame = wrap, Anchor = anchor, OnClose = opts.OnClose }
    self._popup = record

    local function close() if self._popup == record then self:_closePopup() end end
    build(scroll, close)

    local function place()
        if self._popup ~= record then return end
        local s = self:_s()
        local contentH = layout.AbsoluteContentSize.Y / s
        local h = math.min(opts.MaxHeight or 220, contentH + topOff + 4)
        local a = self:_toOverlay(anchor.AbsolutePosition)
        local aw, ah = anchor.AbsoluteSize.X / s, anchor.AbsoluteSize.Y / s
        local ov = self:_overlaySize()
        local width = opts.Width or aw
        local x = clamp(a.X, 8, math.max(8, ov.X - width - 8))
        local y = a.Y + ah + 4
        if y + h > ov.Y - 8 then y = math.max(8, a.Y - h - 4) end
        wrap.Size = UDim2.fromOffset(width, h)
        wrap.Position = UDim2.fromOffset(x, y)
    end
    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(place)
    place()
    task.defer(place)
    return record
end

function Window:_showTooltip(anchor, text)
    self:_hideTooltip()
    local tip = Frame({ Name = "Tooltip", Size = UDim2.fromOffset(224, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 90,
        Parent = self.Overlay, Theme = { BackgroundColor3 = "Tooltip" } })
    Corner(tip, function(t) return math.min(8, t.CornerRadiusSmall) end)
    Stroke(tip, "Stroke")
    Pad(tip, 9, 11)
    local l = Label(tip, { Text = text, TextSize = 11, Wrap = true, LineHeight = 1.2, ZIndex = 91 })
    self._tooltip = tip
    local function place()
        if self._tooltip ~= tip then return end
        local s = self:_s()
        local a = self:_toOverlay(anchor.AbsolutePosition)
        local h = tip.AbsoluteSize.Y / s
        local ov = self:_overlaySize()
        local x = clamp(a.X - 8, 8, ov.X - 232)
        local y = a.Y - h - 8
        if y < 8 then y = a.Y + anchor.AbsoluteSize.Y / s + 8 end
        tip.Position = UDim2.fromOffset(x, y)
    end
    tip:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
    place()
    return l
end

function Window:_hideTooltip()
    if self._tooltip then pcall(self._tooltip.Destroy, self._tooltip); self._tooltip = nil end
end

-- `?` affordance used by controls with a Tooltip option.
local function TooltipIcon(window, parent, text, order)
    local q = Frame({ Name = "Help", Size = UDim2.fromOffset(14, 14), LayoutOrder = order, Parent = parent, Active = false })
    Corner(q, "full"); Stroke(q, "Stroke", 1)
    Label(q, { Text = "?", TextSize = 9, Weight = "SemiBold", Mono = true, Color = "Dim", Size = UDim2.fromScale(1, 1), XAlign = Enum.TextXAlignment.Center })
    q.MouseEnter:Connect(function() window:_showTooltip(q, text) end)
    q.MouseLeave:Connect(function() window:_hideTooltip() end)
    return q
end

--==============================================================================
-- §9  TABS, SEGMENTS & CONTAINERS
--==============================================================================

Tab.__index = function(self, k)
    local v = rawget(Tab, k)
    if v ~= nil then return v end
    local cv = Container[k]
    if type(cv) == "function" and k:sub(1, 1) ~= "_" then
        return function(me, ...)
            local page = me:_defaultPage()
            return cv(page, ...)
        end
    end
    return nil
end

function Window:AddTab(o)
    if type(o) == "string" then o = { Name = o } end
    o = o or {}
    local tab = setmetatable({ Window = self, Name = o.Name or ("Tab " .. (#self.Tabs + 1)), Pages = {}, Options = o }, Tab)
    table.insert(self.Tabs, tab)
    local st = { active = false, hover = false }
    tab._state = st

    local btn = Button({ Name = "Tab_" .. tab.Name, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = #self.Tabs, Parent = self.TabList,
        Theme = { BackgroundColor3 = function(t)
            if st.active then return tk(t, "AccentSoft") end
            if st.hover then return tk(t, "Panel2") end
            return t.Panel2, 1
        end } })
    Corner(btn, "CornerRadiusSmall")
    local stroke = Stroke(btn, function(t) if st.active then return tk(t, "AccentLine") end return t.Stroke, 1 end)
    local fg = function(t)
        if st.active then return t.Accent, 0 end
        if st.hover then return tk(t, "Text") end
        return tk(t, "Dim")
    end
    local inner = Frame({ Position = UDim2.fromOffset(11, 0), Size = UDim2.new(1, -40, 1, 0), Parent = btn })
    List(inner, "x", 10, { VerticalAlignment = Enum.VerticalAlignment.Center })
    local icon = Icon(inner, o.Icon or (#self.Tabs % 2 == 1 and "circle" or "square"), 14, fg, { LayoutOrder = 1 })
    local lbl = Label(inner, { Text = tab.Name, TextSize = 13, Weight = "Medium", Case = "theme", Color = fg, LayoutOrder = 2 })
    local count = Label(btn, { Text = o.Count and tostring(o.Count) or "", TextSize = 10, Weight = "Medium", Mono = true,
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -11, 0.5, 0),
        Color = function(t) local c = fg(t); return c, 0.4 end })
    tab.Button, tab.CountLabel = btn, count
    local themed = { btn, stroke, lbl, count }
    for _, d in ipairs(icon:GetDescendants()) do table.insert(themed, d) end
    tab._restyle = function() restyleAll(themed, 0.14) end
    onHover(btn, function(h) st.hover = h; tab._restyle() end)
    btn.MouseButton1Click:Connect(function() self:SelectTab(tab) end)

    -- segmented strip (only shown when the tab has 2+ segments or explicit ones)
    local strip = Frame({ Name = "Segments_" .. tab.Name, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 16, 0.5, 0),
        AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 32), Visible = false, Parent = self.SegBar,
        Theme = { BackgroundColor3 = "Panel3" } })
    Corner(strip, "CornerRadiusSmall"); Stroke(strip, "Stroke2"); Pad(strip, 3)
    List(strip, "x", 3, { VerticalAlignment = Enum.VerticalAlignment.Center })
    tab.Strip = strip

    if not self.ActiveTab then self:SelectTab(tab) end
    return tab
end

function Window:SelectTab(tab)
    if type(tab) == "string" or type(tab) == "number" then
        for i, t in ipairs(self.Tabs) do if t.Name == tab or i == tab then tab = t break end end
    end
    if type(tab) ~= "table" then return end
    self:_closePopup(); self:_hideTooltip()
    for _, t in ipairs(self.Tabs) do
        local on = t == tab
        t._state.active = on
        t._restyle()
        t.Strip.Visible = on and t._explicit == true
        for _, p in ipairs(t.Pages) do p.Scroll.Visible = on and t.ActivePage == p end
    end
    self.ActiveTab = tab
    if self.FilterBox and self.FilterBox.Text ~= "" then self.FilterBox.Text = "" end
    if #tab.Pages == 0 then tab:_defaultPage() end
end

function Tab:SetCount(n)
    self.CountLabel.Text = n and tostring(n) or ""
end

function Tab:_defaultPage()
    if self.ActivePage then return self.ActivePage end
    if #self.Pages > 0 then return self.Pages[1] end
    return self:_newPage(self.Options.DefaultSegment or "General", false)
end

function Tab:AddSegment(name)
    self._explicit = true
    -- adopt an implicit page created by earlier direct calls
    if #self.Pages == 1 and self.Pages[1]._implicit then
        local p = self.Pages[1]
        p._implicit = false
        p.Name = name
        setText(p.SegLabel, name)
        self.Strip.Visible = self.Window.ActiveTab == self
        return p
    end
    local p = self:_newPage(name, true)
    self.Strip.Visible = self.Window.ActiveTab == self
    return p
end
Tab.AddSubTab = Tab.AddSegment

function Tab:SelectSegment(page)
    if type(page) == "string" then for _, p in ipairs(self.Pages) do if p.Name == page then page = p break end end end
    if type(page) ~= "table" then return end
    self.Window:_closePopup()
    self.ActivePage = page
    for _, p in ipairs(self.Pages) do
        p._segState.active = p == page
        restyle(p.SegButton, 0.14); restyle(p.SegLabel, 0.14)
        p.Scroll.Visible = (p == page) and self.Window.ActiveTab == self
    end
    if self.Window.FilterBox.Text ~= "" then page:Filter(self.Window.FilterBox.Text) end
end

function Tab:_newPage(name, explicit)
    local win = self.Window
    local scroll = New("ScrollingFrame", {
        Name = "Page_" .. self.Name .. "_" .. name, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
        CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 4,
        ScrollingDirection = Enum.ScrollingDirection.Y, VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
        Visible = false, Parent = win.PagesHost, Theme = { ScrollBarImageColor3 = "Stroke" },
    })
    Pad(scroll, 18, 20, 22, 20)
    List(scroll, "y", 16)
    local page = setmetatable({ Window = win, Tab = self, Name = name, Scroll = scroll, Frame = scroll, Controls = {}, Compact = false, _order = 0 }, Container)
    page.Page = page
    page._implicit = not explicit
    table.insert(self.Pages, page)
    win.Maid:Give(scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
        if win._popup then win:_closePopup() end
        win:_hideTooltip()
    end))

    local sst = { active = false }
    page._segState = sst
    local sb = Button({ Name = name, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), LayoutOrder = #self.Pages, Parent = self.Strip,
        Theme = { BackgroundColor3 = function(t) if sst.active then return tk(t, "Panel2") end return t.Panel2, 1 end } })
    Corner(sb, function(t) return t.CornerRadiusSmall - 3 end)
    Pad(sb, 0, 13)
    page.SegButton = sb
    page.SegLabel = Label(sb, { Text = name, TextSize = 12, Weight = "Medium", Case = "theme", Size = UDim2.new(0, 0, 1, 0), AutoSize = Enum.AutomaticSize.X,
        Color = function(t) if sst.active then return tk(t, "Text") end return tk(t, "Dim") end })
    sb.MouseButton1Click:Connect(function() self:SelectSegment(page) end)

    if win.Options.LiveStats then page:AddLiveStats() end
    if not self.ActivePage then self:SelectSegment(page) end
    return page
end

-- Filter the controls of this page by name (used by the title-bar filter box).
function Container:Filter(q)
    q = string.lower(q or "")
    local n = 0
    for _, c in ipairs(self.Page.Controls) do
        local match = q == "" or string.find(string.lower(c.Name or ""), q, 1, true) ~= nil
        if c.Root and c.Root.Parent then
            c.Root.Visible = match and not c._hidden
            if match then n += 1 end
        end
    end
    return n
end

--==============================================================================
-- §10  CONTROLS
--==============================================================================
--[[ Every Add* returns a handle with at least:
       :Set(value [, silent])   :Get()   :SetVisible(bool)   :Destroy()
       :OnChanged(fn)  (adds a listener; `Callback`/`OnChanged` options work too)
     Controls created with a `Flag` mirror their value into Sypse.Flags[flag]
     and are persisted by SaveConfig / LoadConfig. ]]

local Control = {}
Control.__index = Control

local function newControl(kind, o)
    return setmetatable({
        Type = kind, Name = o.Name or kind, Flag = o.Flag, Risky = o.Risky,
        Callback = o.Callback or o.OnChanged, Maid = Maid.new(), _listeners = {}, _opts = o,
    }, Control)
end

function Control:Get() return self.Value end
function Control:_flagValue() return self.Value end
function Control:OnChanged(fn) table.insert(self._listeners, fn) return self end
function Control:SetVisible(v)
    self._hidden = not v
    if self.Root then self.Root.Visible = v end
end
function Control:SetLocked(v)
    self.Locked = v and true or false
    if self.Root then setFaded(self.Root, self.Locked and 0.55 or 0) end
end
Control.SetDisabled = Control.SetLocked
function Control:_emit(...)
    if self.Flag then Library.Flags[self.Flag] = self:_flagValue() end
    safeCall(self.Callback, ...)
    for _, fn in ipairs(self._listeners) do safeCall(fn, ...) end
end
function Control:_cleanup() self.Maid:Clean() end
function Control:Destroy()
    self:_cleanup()
    if self.Root then self.Root:Destroy() end
    if self.Flag and Library.Options[self.Flag] == self then
        Library.Options[self.Flag] = nil
        Library.Flags[self.Flag] = nil
    end
    local function drop(list) for i, c in ipairs(list) do if c == self then table.remove(list, i) return end end end
    if self.Container then drop(self.Container.Page.Controls) end
    if self.Window then drop(self.Window.Controls); drop(self.Window.Keybinds); self.Window:_refreshHUD() end
end

-- Container helpers -----------------------------------------------------------

function Container:_lo()
    self._order += 1
    return self._order
end

function Container:_child(frame, compact)
    return setmetatable({ Window = self.Window, Tab = self.Tab, Page = self.Page, Frame = frame,
        Compact = compact or false, _order = 0, _onAdd = self._onAdd }, Container)
end

function Container:_register(ctl)
    ctl.Window = self.Window
    ctl.Container = self
    table.insert(self.Page.Controls, ctl)
    table.insert(self.Window.Controls, ctl)
    if ctl.Flag then
        Library.Options[ctl.Flag] = ctl
        Library.Flags[ctl.Flag] = ctl:_flagValue()
    end
    if self._onAdd then self._onAdd(ctl) end
    if ctl.Locked then ctl:SetLocked(true) end
    return ctl
end

-- A row "card": Panel3 fill + Stroke2 border. Compact containers (accordions)
-- use bare rows instead.
function Container:_card(name, padY)
    local compact = self.Compact
    local card = Frame({
        Name = name, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = self:_lo(), Parent = self.Frame,
        Theme = (not compact) and { BackgroundColor3 = "Panel3" } or nil,
    })
    if not compact then
        Corner(card, "CornerRadiusSmall")
        Stroke(card, "Stroke2")
        Pad(card, padY or 12, 14)
    end
    return card
end

-- name + optional `?` tooltip + optional badge on one line
function Container:_nameLine(parent, o, order)
    local line = Frame({ Name = "NameLine", AutomaticSize = Enum.AutomaticSize.XY, LayoutOrder = order or 1, Parent = parent })
    List(line, "x", 7, { VerticalAlignment = Enum.VerticalAlignment.Center })
    local lbl = Label(line, {
        Text = o.Name or "", TextSize = self.Compact and 12 or 13, Weight = self.Compact and "Regular" or "Medium",
        Color = self.Compact and "Dim" or "Text", LayoutOrder = 1,
    })
    if o.Tooltip then TooltipIcon(self.Window, line, o.Tooltip, 2) end
    if o.Badge then
        local b = type(o.Badge) == "table" and o.Badge or { Text = o.Badge }
        Badge(line, b.Text, b.Kind or "accent", { LayoutOrder = 3 })
    end
    return line, lbl
end

-- left column: name line + description; width leaves `reserve` px on the right
function Container:_info(parent, o, reserve)
    local info = Frame({ Name = "Info", Size = UDim2.new(1, -reserve, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = parent })
    List(info, "y", 3)
    local _, lbl = self:_nameLine(info, o, 1)
    if o.Description and not self.Compact then
        Label(info, { Text = o.Description, TextSize = 11, Mono = true, Color = "Dim", Wrap = true, LayoutOrder = 2 })
    end
    return info, lbl
end

-- Pointer drag on `hit`; onPos(absPos) for press + every move.
local function bindDrag(ctl, hit, onPos)
    ctl.Maid:Give(hit.InputBegan:Connect(function(input)
        if not isPointerDown(input) or ctl.Locked then return end
        local scroll = ctl.Container and ctl.Container.Page.Scroll
        if scroll then scroll.ScrollingEnabled = false end
        onPos(pointerPos(input), true)
        local moveC, endC
        moveC = UserInputService.InputChanged:Connect(function(i)
            if (i.UserInputType == Enum.UserInputType.MouseMovement and input.UserInputType == Enum.UserInputType.MouseButton1) or i == input then
                onPos(pointerPos(i), false)
            end
        end)
        endC = UserInputService.InputEnded:Connect(function(i)
            if i == input or (input.UserInputType == Enum.UserInputType.MouseButton1 and i.UserInputType == Enum.UserInputType.MouseButton1) then
                moveC:Disconnect(); endC:Disconnect()
                if scroll then scroll.ScrollingEnabled = true end
            end
        end)
        ctl._drag = { moveC, endC }
    end))
    ctl.Maid:Give(function()
        if ctl._drag then for _, c in ipairs(ctl._drag) do pcall(c.Disconnect, c) end end
    end)
end

local FIELD_RADIUS = function(t) return math.min(8, t.CornerRadiusSmall) end

-- Toggle ----------------------------------------------------------------------

function Container:AddToggle(o)
    o = o or {}
    local ctl = newControl("Toggle", o)
    local checkbox = o.Checkbox or o.Style == "Checkbox"
    local compact = self.Compact
    local card = self:_card("Toggle_" .. ctl.Name, 12)
    ctl.Root = card
    local row = HRow(card, 12)
    local sw, sh = 44, 24
    if compact then sw, sh = 40, 22 end
    local cw = checkbox and 20 or sw
    self:_info(row, o, cw + 12)

    local st = { on = o.Default == true }
    ctl.Value = st.on
    ctl.Locked = o.Locked or o.Disabled
    local parts, control, knob, kpos
    if checkbox then
        control = Button({ Name = "Checkbox", Size = UDim2.fromOffset(20, 20), LayoutOrder = 2, Parent = row,
            Theme = { BackgroundColor3 = function(t) return t.Accent, st.on and 0 or 1 end } })
        Corner(control, 5)
        local s = Stroke(control, function(t) if st.on then return t.Accent, 0 end return tk(t, "Stroke") end)
        local mark = Label(control, { Text = "✓", TextSize = 12, Weight = "Bold", Size = UDim2.fromScale(1, 1),
            XAlign = Enum.TextXAlignment.Center, Color = function(t) return t.AccentFg, st.on and 0 or 1 end })
        parts = { control, s, mark }
    else
        control = Button({ Name = "Switch", Size = UDim2.fromOffset(sw, sh), LayoutOrder = 2, Parent = row,
            Theme = { BackgroundColor3 = function(t) return tk(t, st.on and "Accent" or "Track") end } })
        Corner(control, "full")
        local s = Stroke(control, function(t) return tk(t, st.on and "Accent" or "Stroke") end)
        local ks = sh - 6
        kpos = function() return UDim2.new(0, st.on and (sw - ks - 3) or 3, 0.5, 0) end
        knob = Frame({ Name = "Knob", Size = UDim2.fromOffset(ks, ks), AnchorPoint = Vector2.new(0, 0.5), Position = kpos(), Parent = control,
            Theme = { BackgroundColor3 = function(t) return tk(t, st.on and "Knob" or "Dim") end } })
        Corner(knob, "full")
        parts = { control, s, knob }
    end

    function ctl:Set(v, silent)
        v = v == true
        local changed = v ~= st.on
        st.on = v
        self.Value = v
        restyleAll(parts, 0.16)
        if knob then tween(knob, 0.16, { Position = kpos() }) end
        if self.Flag then Library.Flags[self.Flag] = v end
        if changed and not silent then self:_emit(v) end
    end
    function ctl:Toggle() self:Set(not st.on) end
    control.MouseButton1Click:Connect(function() if not ctl.Locked then ctl:Set(not st.on) end end)
    return self:_register(ctl)
end

function Container:AddCheckbox(o)
    o = o or {}
    o.Checkbox = true
    return self:AddToggle(o)
end

-- Slider ----------------------------------------------------------------------

local function sliderTrack(parent, h, colorTok, order)
    local hit = Button({ Name = "Track", Size = UDim2.new(1, 0, 0, h), LayoutOrder = order or 2, Parent = parent })
    local rail = Frame({ Name = "Rail", Size = UDim2.new(1, 0, 0, 6), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5),
        Parent = hit, Theme = { BackgroundColor3 = "Track" } })
    Corner(rail, "full")
    local fill = Frame({ Name = "Fill", Size = UDim2.new(0, 0, 0, 6), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5),
        Parent = hit, Theme = { BackgroundColor3 = colorTok } })
    Corner(fill, "full")
    local function thumb()
        local th = Frame({ Name = "Thumb", Size = UDim2.fromOffset(10, 10), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5),
            ZIndex = 2, Parent = hit, Theme = { BackgroundColor3 = "Knob" } })
        Corner(th, "full")
        Stroke(th, colorTok, 2)
        return th
    end
    return hit, rail, fill, thumb
end

function Container:_sliderHeader(stack, o, h)
    local header = Frame({ Name = "Header", Size = UDim2.new(1, 0, 0, h), LayoutOrder = 1, Parent = stack })
    local line = self:_nameLine(header, o)
    line.AnchorPoint = Vector2.new(0, 0.5)
    line.Position = UDim2.fromScale(0, 0.5)
    return header, line
end

function Container:AddSlider(o)
    o = o or {}
    local ctl = newControl("Slider", o)
    local min, max, step = o.Min or 0, o.Max or 100, o.Step or o.Increment or 1
    local suffix = o.Suffix or ""
    local colorTok = o.Color or (o.Accent2 and "Accent2") or "Accent"
    local compact = self.Compact
    local card = self:_card("Slider_" .. ctl.Name, 13)
    ctl.Root = card
    ctl.Locked = o.Locked or o.Disabled
    local stack = VStack(card, compact and 7 or 10)
    local header = self:_sliderHeader(stack, o, compact and 14 or 22)
    local valueLabel
    if o.Chip ~= false and not compact then
        local chip = Frame({ Name = "Value", AutomaticSize = Enum.AutomaticSize.XY, AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, 0, 0.5, 0), Parent = header, Theme = { BackgroundColor3 = colorTok == "Accent" and "AccentSoft" or "Panel2" } })
        Corner(chip, 6); Pad(chip, 4, 8)
        valueLabel = Label(chip, { TextSize = 12, Weight = "Medium", Mono = true, Color = colorTok })
    else
        valueLabel = Label(header, { TextSize = 11, Weight = "Medium", Mono = true, Color = compact and "Text" or "Dim",
            AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0) })
    end
    local hit, rail, fill, mkThumb = sliderTrack(stack, compact and 18 or 22, colorTok, 2)
    local thumb = mkThumb()

    local function render(anim)
        local p = max == min and 0 or (ctl.Value - min) / (max - min)
        local t = anim and 0.06 or 0
        tween(fill, t, { Size = UDim2.new(p, 0, 0, 6) })
        tween(thumb, t, { Position = UDim2.new(p, 0, 0.5, 0) })
        valueLabel.Text = o.Format and o.Format(ctl.Value) or (fmtNum(ctl.Value) .. suffix)
    end
    function ctl:Set(v, silent)
        v = tonumber(v) or min
        v = clamp(min + roundStep(v - min, step), min, max)
        local changed = v ~= self.Value
        self.Value = v
        render(true)
        if self.Flag then Library.Flags[self.Flag] = v end
        if changed and not silent then self:_emit(v) end
    end
    ctl.Value = clamp(o.Default or min, min, max)
    render(false)
    bindDrag(ctl, hit, function(p)
        local w = rail.AbsoluteSize.X
        if w <= 0 then return end
        ctl:Set(min + clamp((p.X - rail.AbsolutePosition.X) / w, 0, 1) * (max - min))
    end)
    return self:_register(ctl)
end

-- Range slider ----------------------------------------------------------------

function Container:AddRangeSlider(o)
    o = o or {}
    local ctl = newControl("Range", o)
    local min, max, step = o.Min or 0, o.Max or 100, o.Step or 1
    local gap = o.MinGap or 5
    local suffix = o.Suffix or ""
    local colorTok = o.Color or "Accent2"
    local compact = self.Compact
    local card = self:_card("Range_" .. ctl.Name, 13)
    ctl.Root = card
    ctl.Locked = o.Locked or o.Disabled
    local stack = VStack(card, compact and 7 or 10)
    local header, line = self:_sliderHeader(stack, o, compact and 14 or 22)
    if o.Note ~= false then
        Label(line, { Text = o.Note or "dual thumb", TextSize = 11, Mono = true, Color = "Dim", LayoutOrder = 4 })
    end
    local valueLabel = Label(header, { TextSize = 12, Weight = "Medium", Mono = true, Color = "Dim",
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0) })
    local hit, rail, fill, mkThumb = sliderTrack(stack, compact and 18 or 22, colorTok, 2)
    local tLo, tHi = mkThumb(), mkThumb()
    local d = o.Default or { min, max }
    ctl.Lo, ctl.Hi = clamp(d[1] or min, min, max), clamp(d[2] or max, min, max)

    local function pct(v) return max == min and 0 or (v - min) / (max - min) end
    local function render(anim)
        local t = anim and 0.06 or 0
        local a, b = pct(ctl.Lo), pct(ctl.Hi)
        tween(fill, t, { Position = UDim2.new(a, 0, 0.5, 0), Size = UDim2.new(b - a, 0, 0, 6) })
        tween(tLo, t, { Position = UDim2.new(a, 0, 0.5, 0) })
        tween(tHi, t, { Position = UDim2.new(b, 0, 0.5, 0) })
        valueLabel.Text = fmtNum(ctl.Lo) .. suffix .. " – " .. fmtNum(ctl.Hi) .. suffix
        ctl.Value = { ctl.Lo, ctl.Hi }
    end
    function ctl:Get() return self.Lo, self.Hi end
    function ctl:_flagValue() return { self.Lo, self.Hi } end
    function ctl:Set(lo, hi, silent)
        if type(lo) == "table" then silent = hi; lo, hi = lo[1], lo[2] end
        lo = clamp(min + roundStep((tonumber(lo) or self.Lo) - min, step), min, max)
        hi = clamp(min + roundStep((tonumber(hi) or self.Hi) - min, step), min, max)
        if hi - lo < gap then
            if lo ~= self.Lo then lo = hi - gap else hi = lo + gap end
            lo, hi = clamp(lo, min, max), clamp(hi, min, max)
        end
        local changed = lo ~= self.Lo or hi ~= self.Hi
        self.Lo, self.Hi = lo, hi
        render(true)
        if self.Flag then Library.Flags[self.Flag] = { lo, hi } end
        if changed and not silent then self:_emit(lo, hi) end
    end
    render(false)
    local which
    bindDrag(ctl, hit, function(p, first)
        local w = rail.AbsoluteSize.X
        if w <= 0 then return end
        local v = min + clamp((p.X - rail.AbsolutePosition.X) / w, 0, 1) * (max - min)
        if first then which = math.abs(v - ctl.Lo) <= math.abs(v - ctl.Hi) and "lo" or "hi" end
        v = min + roundStep(v - min, step)
        if which == "lo" then ctl:Set(math.min(v, ctl.Hi - gap), ctl.Hi)
        else ctl:Set(ctl.Lo, math.max(v, ctl.Lo + gap)) end
    end)
    return self:_register(ctl)
end

-- Dropdown --------------------------------------------------------------------

local function popupRow(parent, text, selected, onClick, order)
    local st = { hover = false }
    local b = Button({ Name = "Opt", Size = UDim2.new(1, 0, 0, 27), LayoutOrder = order, ZIndex = 63, Parent = parent,
        Theme = { BackgroundColor3 = function(t)
            if selected() then return tk(t, "AccentSoft") end
            if st.hover then return tk(t, "Panel2") end
            return t.Panel2, 1
        end } })
    Corner(b, 6)
    local fg = function(t) if selected() then return t.Accent, 0 end if st.hover then return tk(t, "Text") end return tk(t, "Dim") end
    local l = Label(b, { Text = text, TextSize = 12, Color = fg, ZIndex = 64, Position = UDim2.fromOffset(9, 0), Size = UDim2.new(1, -30, 1, 0), Truncate = true })
    local dot = Label(b, { Text = "●", TextSize = 9, Mono = true, Weight = "SemiBold", ZIndex = 64, AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -9, 0.5, 0), Color = function(t) return t.Accent, selected() and 0 or 1 end })
    onHover(b, function(h) st.hover = h; restyleAll({ b, l }, 0.1) end)
    b.MouseButton1Click:Connect(onClick)
    return b
end

local function searchField(parent, placeholder, props)
    local box = Frame(merge({ Name = "Search", Size = UDim2.new(1, 0, 0, 30), Parent = parent, Theme = { BackgroundColor3 = "Panel3" } }, props))
    Corner(box, FIELD_RADIUS); Stroke(box, "Stroke")
    local mag = Frame({ Size = UDim2.fromOffset(11, 11), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 11, 0.5, 0), ZIndex = box.ZIndex + 1, Parent = box })
    Corner(mag, "full"); Stroke(mag, "Dim", 1.5)
    local tb = New("TextBox", {
        BackgroundTransparency = 1, Position = UDim2.fromOffset(30, 0), Size = UDim2.new(1, -40, 1, 0), ZIndex = box.ZIndex + 1,
        ClearTextOnFocus = false, Text = "", PlaceholderText = placeholder or "Search…", TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left, Parent = box,
        Theme = { TextColor3 = "Text", PlaceholderColor3 = function(t) return t.Dim end, FontFace = function(t) return getFont(t.Font) end },
    })
    return box, tb
end

function Container:AddDropdown(o)
    o = o or {}
    if o.Multi then return self:_multiDropdown(o) end
    local ctl = newControl("Dropdown", o)
    ctl.Values = o.Options or o.Values or {}
    local compact = self.Compact
    local card = self:_card("Dropdown_" .. ctl.Name, 13)
    ctl.Root = card
    ctl.Locked = o.Locked or o.Disabled
    local stack = VStack(card, 8)
    self:_nameLine(stack, o, 1)
    local stField = { open = false }
    local field = Button({ Name = "Field", Size = UDim2.new(1, 0, 0, 32), LayoutOrder = 2, Parent = stack, Theme = { BackgroundColor3 = "Panel2" } })
    Corner(field, FIELD_RADIUS)
    local fstroke = Stroke(field, function(t) return tk(t, stField.open and "AccentLine" or "Stroke") end)
    local valueLabel = Label(field, { Text = "", TextSize = 12, Position = UDim2.fromOffset(11, 0), Size = UDim2.new(1, -40, 1, 0), Truncate = true })
    local chev = Chevron(field, "Dim", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -11, 0.5, 0) })

    local function render()
        valueLabel.Text = ctl.Value ~= nil and tostring(ctl.Value) or (o.Placeholder or "Select…")
        restyle(valueLabel, 0, { "TextColor3" })
    end
    bind(valueLabel, { TextColor3 = function(t) return tk(t, ctl.Value ~= nil and "Text" or "Dim") end })

    function ctl:Set(v, silent)
        local changed = v ~= self.Value
        self.Value = v
        render()
        if self.Flag then Library.Flags[self.Flag] = v end
        if changed and not silent then self:_emit(v) end
    end
    function ctl:Refresh(values, keep)
        self.Values = values or {}
        if not keep or not table.find(self.Values, self.Value) then self:Set(nil, true) end
    end
    ctl.Value = o.Default
    render()

    field.MouseButton1Click:Connect(function()
        if ctl.Locked then return end
        local win = self.Window
        if win._popup and win._popup.Anchor == field then win:_closePopup() return end
        local rows = {}
        local searchBox
        stField.open = true
        restyle(fstroke, 0.12)
        tween(chev, 0.15, { Rotation = 180 })
        win:_openPopup(field, function(list, close)
            for i, v in ipairs(ctl.Values) do
                local r = popupRow(list, tostring(v), function() return ctl.Value == v end, function() ctl:Set(v); close() end, i)
                rows[i] = { r, string.lower(tostring(v)) }
            end
        end, {
            Header = (o.Searchable or o.Search) and function(h)
                local _, tb = searchField(h, o.SearchPlaceholder or "Filter…", { Size = UDim2.fromScale(1, 1), ZIndex = 62 })
                searchBox = tb
                tb:GetPropertyChangedSignal("Text"):Connect(function()
                    local q = string.lower(tb.Text)
                    for _, r in ipairs(rows) do r[1].Visible = q == "" or string.find(r[2], q, 1, true) ~= nil end
                end)
                task.defer(function() pcall(tb.CaptureFocus, tb) end)
            end or nil,
            OnClose = function()
                stField.open = false
                if fstroke.Parent then restyle(fstroke, 0.12); tween(chev, 0.15, { Rotation = 0 }) end
            end,
        })
    end)
    return self:_register(ctl)
end

-- Multi-select: removable chips (+ / ×), optional search filter.
function Container:_multiDropdown(o)
    local ctl = newControl("MultiDropdown", o)
    ctl.Values = o.Options or o.Values or {}
    local card = self:_card("Multi_" .. ctl.Name, 13)
    ctl.Root = card
    ctl.Locked = o.Locked or o.Disabled
    local stack = VStack(card, self.Compact and 7 or 8)
    self:_nameLine(stack, o, 1)
    local query = ""
    if o.Searchable or o.Search then
        local _, tb = searchField(stack, o.SearchPlaceholder or "Filter options…", { LayoutOrder = 2 })
        tb:GetPropertyChangedSignal("Text"):Connect(function() query = string.lower(tb.Text); ctl:_layout() end)
    end
    local chips = Frame({ Name = "Chips", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3, Parent = stack })
    List(chips, "x", 6, { Wraps = true, VerticalAlignment = Enum.VerticalAlignment.Center })
    ctl.Selected = {}
    for _, v in ipairs(o.Default or {}) do ctl.Selected[v] = true end
    local chipObjs = {}

    function ctl:_layout()
        for _, c in ipairs(chipObjs) do c.frame:Destroy() end
        chipObjs = {}
        for i, v in ipairs(self.Values) do
            local on = function() return self.Selected[v] == true end
            local chip = Button({ Name = "Chip", AutomaticSize = Enum.AutomaticSize.XY, LayoutOrder = i, Parent = chips,
                Visible = query == "" or string.find(string.lower(tostring(v)), query, 1, true) ~= nil,
                Theme = { BackgroundColor3 = function(t) if on() then return tk(t, "AccentSoft") end return t.Panel2, 1 end } })
            Corner(chip, "full"); Pad(chip, 5, 9)
            local s = Stroke(chip, function(t) return tk(t, on() and "AccentLine" or "Stroke") end)
            List(chip, "x", 6, { VerticalAlignment = Enum.VerticalAlignment.Center })
            local fg = function(t) return tk(t, on() and "Accent" or "Dim") end
            local l = Label(chip, { Text = tostring(v), TextSize = 11, Weight = "Medium", Color = fg, LayoutOrder = 1 })
            local m = Label(chip, { Text = on() and "×" or "+", TextSize = 10, Weight = "SemiBold", Mono = true, LayoutOrder = 2,
                Color = function(t) local c = fg(t); return c, 0.3 end })
            chip.MouseButton1Click:Connect(function()
                if self.Locked then return end
                self.Selected[v] = not self.Selected[v] or nil
                m.Text = on() and "×" or "+"
                restyleAll({ chip, s, l, m }, 0.12)
                if self.Flag then Library.Flags[self.Flag] = self:Get() end
                self:_emit(self:Get())
            end)
            table.insert(chipObjs, { frame = chip })
        end
    end
    function ctl:Get()
        local out = {}
        for _, v in ipairs(self.Values) do if self.Selected[v] then table.insert(out, v) end end
        return out
    end
    function ctl:_flagValue() return self:Get() end
    function ctl:Set(list, silent)
        self.Selected = {}
        for _, v in ipairs(list or {}) do self.Selected[v] = true end
        self:_layout()
        if self.Flag then Library.Flags[self.Flag] = self:Get() end
        if not silent then self:_emit(self:Get()) end
    end
    function ctl:Refresh(values)
        self.Values = values or {}
        self:_layout()
    end
    ctl:_layout()
    ctl.Value = ctl:Get()
    return self:_register(ctl)
end

-- Text input ------------------------------------------------------------------
--[[ Options: Name, Default, Placeholder, Numeric, Min, Max, Password, MultiLine,
     Width, Finished (only fire on focus lost), Callback/OnChanged(value),
     OnFocusLost(value, enterPressed), Flag ]]
function Container:AddInput(o)
    o = o or {}
    local ctl = newControl("Input", o)
    local numeric, password = o.Numeric, o.Password
    local multi = o.MultiLine or o.Multiline
    local card = self:_card("Input_" .. ctl.Name, 12)
    ctl.Root = card
    ctl.Locked = o.Locked or o.Disabled
    local inline = (numeric or self.Compact) and not multi
    local fieldParent, fieldSize
    if inline then
        local fw = o.Width or (numeric and 90 or 170)
        local row = HRow(card, 12)
        self:_info(row, o, fw + 12)
        fieldParent, fieldSize = row, UDim2.fromOffset(fw, 30)
    else
        local stack = VStack(card, 8)
        if o.Name then self:_nameLine(stack, o, 1) end
        fieldParent, fieldSize = stack, UDim2.new(1, 0, 0, multi and (o.Height or 88) or 32)
    end
    local st = { focus = false }
    local field = Frame({ Name = "Field", Size = fieldSize, LayoutOrder = 2, Parent = fieldParent, Theme = { BackgroundColor3 = "Panel2" } })
    Corner(field, FIELD_RADIUS)
    local fstroke = Stroke(field, function(t) return tk(t, st.focus and "AccentLine" or "Stroke") end)
    local mono = numeric or password or multi or o.Mono
    local tb = New("TextBox", {
        Name = "Box", BackgroundTransparency = 1, ClearTextOnFocus = false, MultiLine = multi and true or false,
        TextWrapped = multi and true or false, TextSize = 12, PlaceholderText = o.Placeholder or "",
        Text = o.Default ~= nil and tostring(o.Default) or "",
        TextXAlignment = numeric and Enum.TextXAlignment.Right or Enum.TextXAlignment.Left,
        TextYAlignment = multi and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center,
        Position = UDim2.fromOffset(11, multi and 9 or 0), Size = UDim2.new(1, -22, 1, multi and -18 or 0),
        ClipsDescendants = true, TextEditable = not ctl.Locked, Parent = field,
        Theme = {
            TextColor3 = password and function(t) return t.Text, 1 end or "Text",
            PlaceholderColor3 = function(t) return t.Dim end,
            FontFace = function(t) return getFont(mono and t.FontMono or t.Font) end,
        },
    })
    if multi then tb.LineHeight = 1.25 end
    local mask
    if password then
        mask = Label(field, { Text = "", TextSize = 12, Mono = true, Position = tb.Position, Size = tb.Size })
    end
    local function updMask()
        if mask then mask.Text = track(string.rep("•", utf8.len(tb.Text) or #tb.Text), 2) end
    end
    local function parse(txt)
        if numeric then return tonumber(txt) end
        return txt
    end
    ctl.Value = parse(tb.Text)
    updMask()
    local lastValid = tb.Text
    tb:GetPropertyChangedSignal("Text"):Connect(function()
        local txt = tb.Text
        if numeric and txt ~= "" and txt ~= "-" and txt ~= "." and txt ~= "-." and not txt:match("^%-?%d*%.?%d*$") then
            tb.Text = lastValid
            return
        end
        lastValid = txt
        updMask()
        ctl.Value = parse(txt)
        if ctl.Flag then Library.Flags[ctl.Flag] = ctl.Value end
        if not o.Finished and not ctl._silent then ctl:_emit(ctl.Value) end
    end)
    tb.Focused:Connect(function() st.focus = true; restyle(fstroke, 0.12) end)
    tb.FocusLost:Connect(function(enter)
        st.focus = false
        restyle(fstroke, 0.12)
        if numeric then
            local n = tonumber(tb.Text)
            if n == nil then n = tonumber(o.Default) or o.Min or 0 end
            if o.Min then n = math.max(o.Min, n) end
            if o.Max then n = math.min(o.Max, n) end
            ctl._silent = true
            tb.Text = fmtNum(n)
            ctl._silent = false
            ctl.Value = n
            if ctl.Flag then Library.Flags[ctl.Flag] = n end
        end
        if o.Finished then ctl:_emit(ctl.Value) end
        safeCall(o.OnFocusLost, ctl.Value, enter)
    end)
    function ctl:Set(v, silent)
        self._silent = silent
        tb.Text = v == nil and "" or (numeric and fmtNum(tonumber(v) or 0) or tostring(v))
        self._silent = false
        self.Value = parse(tb.Text)
        if self.Flag then Library.Flags[self.Flag] = self.Value end
    end
    function ctl:SetLocked(v)
        Control.SetLocked(self, v)
        tb.TextEditable = not v
    end
    ctl.Box = tb
    return self:_register(ctl)
end
Container.AddTextbox = Container.AddInput

-- Keybind ---------------------------------------------------------------------
--[[ Options: Name, Default (Enum.KeyCode / Enum.UserInputType / name string),
     Mode "Press" (default) | "Toggle" | "Hold", Hint, MenuKey (rebinds the
     window toggle key), HUD (false hides it from the keybind HUD), HudName,
     Callback(state?) on activation, ChangedCallback(key) on rebind, Flag ]]
local function toKey(v)
    if typeof(v) == "EnumItem" then return v end
    if type(v) == "string" and v ~= "" and v ~= "None" then
        local ok, k = pcall(function() return Enum.KeyCode[v] end)
        if ok and k then return k end
        ok, k = pcall(function() return Enum.UserInputType[v] end)
        if ok and k then return k end
    end
    return nil
end

function Container:AddKeybind(o)
    o = o or {}
    local ctl = newControl("Keybind", o)
    local win = self.Window
    ctl.Mode = o.Mode or "Press"
    ctl.MenuKey = o.MenuKey
    ctl.Value = ctl.MenuKey and win.ToggleKey or toKey(o.Default)
    ctl.Active = false
    local card = self:_card("Keybind_" .. ctl.Name, 12)
    ctl.Root = card
    ctl.Locked = o.Locked or o.Disabled
    local st = { listening = false }
    local stack = VStack(card, 8)
    self:_nameLine(stack, o, 1)
    local field = Button({ Name = "Field", Size = UDim2.new(1, 0, 0, 32), LayoutOrder = 2, Parent = stack, Theme = { BackgroundColor3 = "Panel2" } })
    Corner(field, FIELD_RADIUS)
    local fstroke = Stroke(field, function(t) if st.listening then return t.Accent, 0 end return tk(t, "Stroke") end)
    local defaultHint = o.Hint or (ctl.MenuKey and "Toggle menu") or (ctl.Mode == "Hold" and "Hold to activate") or (ctl.Mode == "Toggle" and "Press to toggle") or "Press to trigger"
    local hint = Label(field, { Text = defaultHint, TextSize = 12, Color = "Dim", Position = UDim2.fromOffset(11, 0), Size = UDim2.new(1, -90, 1, 0), Truncate = true })
    local chip = Frame({ Name = "Key", AutomaticSize = Enum.AutomaticSize.XY, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0),
        Parent = field, Theme = { BackgroundColor3 = "Panel" } })
    Corner(chip, 5); Pad(chip, 4, 8); Stroke(chip, "Stroke", 1)
    local keyLabel = Label(chip, { Text = keyName(ctl.Value), TextSize = 11, Weight = "SemiBold", Mono = true })

    function ctl:_flagValue() return self.Value and self.Value.Name or "None" end
    function ctl:Set(key, silent)
        key = toKey(key)
        self.Value = key
        keyLabel.Text = keyName(key)
        if self.MenuKey and key then win:SetToggleKey(key) end
        if self.Flag then Library.Flags[self.Flag] = self:_flagValue() end
        win:_refreshHUD()
        if not silent then
            safeCall(o.ChangedCallback, key)
            for _, fn in ipairs(self._listeners) do safeCall(fn, key) end
        end
    end
    function ctl:_input(input, began)
        if self.MenuKey or not self.Value or self.Locked then return end
        local k = self.Value
        local hit = (k.EnumType == Enum.KeyCode and input.KeyCode == k) or (k.EnumType == Enum.UserInputType and input.UserInputType == k)
        if not hit then return end
        if self.Mode == "Hold" then
            self.Active = began
            safeCall(self.Callback, began)
        elseif began then
            if self.Mode == "Toggle" then
                self.Active = not self.Active
                safeCall(self.Callback, self.Active)
            else
                safeCall(self.Callback)
            end
        end
    end
    local function stopListening()
        st.listening = false
        setText(hint, defaultHint)
        restyle(fstroke, 0.12)
        task.defer(function() if win._listening == ctl then win._listening = nil end end)
    end
    field.MouseButton1Click:Connect(function()
        if ctl.Locked or st.listening then return end
        st.listening = true
        win._listening = ctl
        hint.Text = "press any key…"
        restyle(fstroke, 0.12)
        local conn
        conn = UserInputService.InputBegan:Connect(function(input)
            local key
            if input.UserInputType == Enum.UserInputType.Keyboard then
                if input.KeyCode == Enum.KeyCode.Escape then key = "cancel"
                elseif input.KeyCode == Enum.KeyCode.Backspace or input.KeyCode == Enum.KeyCode.Delete then key = "none"
                else key = input.KeyCode end
            elseif input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.MouseButton2
                or input.UserInputType == Enum.UserInputType.MouseButton3 then
                key = input.UserInputType
            else
                return
            end
            conn:Disconnect()
            stopListening()
            if key == "none" then
                if not ctl.MenuKey then ctl:Set(nil) end
            elseif key ~= "cancel" then
                ctl:Set(key)
            end
        end)
        ctl.Maid:Give(conn)
    end)
    table.insert(win.Keybinds, ctl)
    self:_register(ctl)
    win:_refreshHUD()
    return ctl
end

-- Color picker ----------------------------------------------------------------
--[[ Options: Name, Default (Color3), Alpha (opacity 0-1; omit to hide the
     alpha strip), Expanded (true), Callback(color, transparency), Flag.
     Flags[flag] = Color3, Flags[flag .. "Transparency"] = transparency.
     (The SV square / hue strip use fixed white/black/rainbow gradients: that is
     colour-picker data, not theme styling.) ]]
function Container:AddColorPicker(o)
    o = o or {}
    local ctl = newControl("ColorPicker", o)
    local hasAlpha = o.Alpha ~= nil
    local h, s, v = (o.Default or Color3.fromHex("7AA2FF")):ToHSV()
    local a = hasAlpha and clamp(o.Alpha, 0, 1) or 1
    local card = self:_card("Color_" .. ctl.Name, 13)
    ctl.Root = card
    ctl.Locked = o.Locked or o.Disabled
    local stack = VStack(card, 10)
    local header = Frame({ Name = "Header", Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 1, Parent = stack })
    local line = self:_nameLine(header, o)
    line.AnchorPoint = Vector2.new(0, 0.5); line.Position = UDim2.fromScale(0, 0.5)
    local swatch = Button({ Name = "Swatch", Size = UDim2.fromOffset(18, 18), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
        BackgroundTransparency = 0, Parent = header })
    Corner(swatch, 5); Stroke(swatch, "Stroke")

    local body = VStack(stack, 10, { LayoutOrder = 2, Visible = o.Expanded ~= false })
    -- SV square
    local sv = Button({ Name = "SV", Size = UDim2.new(1, 0, 0, 104), BackgroundTransparency = 0, LayoutOrder = 1, Parent = body, ClipsDescendants = true })
    Corner(sv, 8)
    local white = Frame({ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1), Parent = sv })
    Corner(white, 8)
    New("UIGradient", { Transparency = NumberSequence.new(0, 1), Parent = white })
    local black = Frame({ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(0, 0, 0), Parent = sv })
    Corner(black, 8)
    New("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0), Parent = black })
    local ring = Frame({ Size = UDim2.fromOffset(9, 9), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 3, Parent = sv })
    Corner(ring, "full")
    New("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2, Parent = ring })
    -- hue strip
    local hue = Button({ Name = "Hue", Size = UDim2.new(1, 0, 0, 12), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1), LayoutOrder = 2, Parent = body })
    Corner(hue, "full")
    local keys = {}
    for i = 0, 6 do table.insert(keys, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV((i / 6) % 1, 1, 1))) end
    New("UIGradient", { Color = ColorSequence.new(keys), Parent = hue })
    local hueThumb = Frame({ Size = UDim2.fromOffset(12, 12), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 0, ZIndex = 3, Parent = hue })
    Corner(hueThumb, "full")
    New("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2, Parent = hueThumb })
    -- alpha strip (checkerboard + colour ramp)
    local alphaBar, alphaFill, alphaThumb
    if hasAlpha then
        alphaBar = Button({ Name = "Alpha", Size = UDim2.new(1, 0, 0, 12), BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1),
            LayoutOrder = 3, ClipsDescendants = true, Parent = body })
        Corner(alphaBar, "full")
        for col = 0, 59 do
            for row = 0, 1 do
                if (col + row) % 2 == 0 then
                    Frame({ Size = UDim2.fromOffset(6, 6), Position = UDim2.fromOffset(col * 6, row * 6), BackgroundTransparency = 0.73,
                        BackgroundColor3 = Color3.fromRGB(136, 136, 136), Parent = alphaBar })
                end
            end
        end
        alphaFill = Frame({ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0, ZIndex = 2, Parent = alphaBar })
        Corner(alphaFill, "full")
        New("UIGradient", { Transparency = NumberSequence.new(1, 0), Parent = alphaFill })
        alphaThumb = Frame({ Size = UDim2.fromOffset(12, 12), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 3, Parent = alphaBar })
        Corner(alphaThumb, "full")
        New("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2, Parent = alphaThumb })
    end
    -- readouts
    local readRow = Frame({ Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 4, Parent = body })
    local function readBox(label, size, pos)
        local f = Frame({ Size = size, Position = pos or UDim2.new(), Parent = readRow, Theme = { BackgroundColor3 = "Panel2" } })
        Corner(f, function(t) return math.min(7, t.CornerRadiusSmall) end); Stroke(f, "Stroke")
        Label(f, { Text = label, TextSize = 10, Weight = "Medium", Mono = true, Color = "Dim", Position = UDim2.fromOffset(9, 0), Size = UDim2.new(0, 26, 1, 0) })
        local tb = New("TextBox", { BackgroundTransparency = 1, ClearTextOnFocus = false, TextSize = 11, Text = "",
            Position = UDim2.fromOffset(label == "HEX" and 36 or 20, 0), Size = UDim2.new(1, label == "HEX" and -44 or -26, 1, 0),
            TextXAlignment = Enum.TextXAlignment.Left, Parent = f,
            Theme = { TextColor3 = "Text", FontFace = function(t) return getFont(t.FontMono, "Medium") end } })
        return tb
    end
    local hexBox = readBox("HEX", UDim2.new(1, hasAlpha and -70 or 0, 1, 0))
    local aBox = hasAlpha and readBox("A", UDim2.new(0, 64, 1, 0), UDim2.new(1, -64, 0, 0)) or nil

    local function render()
        local c = Color3.fromHSV(h, s, v)
        sv.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
        ring.Position = UDim2.fromScale(s, 1 - v)
        hueThumb.Position = UDim2.fromScale(h, 0.5)
        hueThumb.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
        swatch.BackgroundColor3 = c
        swatch.BackgroundTransparency = 1 - a
        if hasAlpha then
            alphaFill.BackgroundColor3 = c
            alphaThumb.Position = UDim2.fromScale(a, 0.5)
            if not aBox:IsFocused() then aBox.Text = tostring(math.floor(a * 100 + 0.5)) end
        end
        if not hexBox:IsFocused() then hexBox.Text = "#" .. string.upper(c:ToHex()) end
        ctl.Value = c
        ctl.Transparency = 1 - a
    end
    local function commit(silent)
        render()
        if ctl.Flag then
            Library.Flags[ctl.Flag] = ctl.Value
            if hasAlpha then Library.Flags[ctl.Flag .. "Transparency"] = ctl.Transparency end
        end
        if not silent then ctl:_emit(ctl.Value, ctl.Transparency) end
    end
    function ctl:Get() return self.Value, self.Transparency end
    function ctl:_flagValue() return self.Value end
    function ctl:Set(color, alpha, silent)
        if typeof(color) == "Color3" then h, s, v = color:ToHSV() end
        if alpha ~= nil and hasAlpha then a = clamp(alpha, 0, 1) end
        commit(silent)
    end
    bindDrag(ctl, sv, function(p)
        s = clamp((p.X - sv.AbsolutePosition.X) / math.max(1, sv.AbsoluteSize.X), 0, 1)
        v = 1 - clamp((p.Y - sv.AbsolutePosition.Y) / math.max(1, sv.AbsoluteSize.Y), 0, 1)
        commit()
    end)
    bindDrag(ctl, hue, function(p)
        h = clamp((p.X - hue.AbsolutePosition.X) / math.max(1, hue.AbsoluteSize.X), 0, 0.999)
        commit()
    end)
    if hasAlpha then
        bindDrag(ctl, alphaBar, function(p)
            a = clamp((p.X - alphaBar.AbsolutePosition.X) / math.max(1, alphaBar.AbsoluteSize.X), 0, 1)
            commit()
        end)
        aBox.FocusLost:Connect(function()
            local n = tonumber(aBox.Text)
            if n then a = clamp(n / 100, 0, 1) end
            commit()
        end)
    end
    hexBox.FocusLost:Connect(function()
        local ok, c = pcall(Color3.fromHex, (hexBox.Text:gsub("#", "")))
        if ok and c then h, s, v = c:ToHSV() end
        commit()
    end)
    swatch.MouseButton1Click:Connect(function() body.Visible = not body.Visible end)
    render()
    return self:_register(ctl)
end
Container.AddColor = Container.AddColorPicker

-- Buttons ---------------------------------------------------------------------
--[[ Variant: "Primary" | "Secondary" (default) | "Ghost" | "Danger" | "Ok" | "Warn" | "Icon"
     Options: Name/Text, Callback, DoubleClick, Disabled, Icon, Fill (full width),
     Height (34), ConfirmText ("Click again to confirm"), Tooltip ]]
local VARIANT = {
    Primary   = { bg = "Accent", fg = "AccentFg", line = "Accent" },
    Secondary = { bg = "Panel2", fg = "Text", line = "Stroke" },
    Ghost     = { bg = nil, fg = "Dim", line = nil },
    Danger    = { bg = "DangerSoft", fg = "Danger", line = "DangerLine" },
    Ok        = { bg = "OkSoft", fg = "Ok", line = "OkLine" },
    Warn      = { bg = "WarnSoft", fg = "Warn", line = "WarnLine" },
    Icon      = { bg = "Panel2", fg = "Text", line = "Stroke" },
}

local function makeButton(container, parent, o, order)
    o = o or {}
    local ctl = newControl("Button", o)
    local variant = o.Variant or "Secondary"
    if o.Icon and not (o.Name or o.Text) then variant = "Icon" end
    local V = VARIANT[variant] or VARIANT.Secondary
    local st = { hover = false, armed = false }
    local height = o.Height or 34
    local isIcon = variant == "Icon"
    local wrap = Frame({ Name = "Btn_" .. (o.Name or o.Text or variant), LayoutOrder = order, Parent = parent,
        Size = o.Fill and UDim2.new(1, 0, 0, height) or UDim2.fromOffset(isIcon and height or 0, height) })
    if variant == "Primary" then ButtonShadow(wrap, 0) end
    local btn = Button({ Name = "Button", ZIndex = 1, Parent = wrap,
        Size = (o.Fill or isIcon) and UDim2.fromScale(1, 1) or UDim2.new(0, 0, 1, 0),
        AutomaticSize = (o.Fill or isIcon) and Enum.AutomaticSize.None or Enum.AutomaticSize.X,
        Theme = { BackgroundColor3 = function(t)
            if st.armed then return tk(t, "WarnSoft") end
            if V.bg then
                local c, tr = tk(t, V.bg)
                if st.hover and variant ~= "Primary" then tr = math.max(0, tr - 0.06) end
                return c, tr
            end
            if st.hover then return tk(t, "Panel2") end
            return t.Panel2, 1
        end } })
    Corner(btn, "CornerRadiusSmall")
    local stroke = Stroke(btn, function(t)
        if st.armed then return tk(t, "WarnLine") end
        if st.hover and variant == "Secondary" then return tk(t, "AccentLine") end
        if V.line then return tk(t, V.line) end
        return t.Stroke, 1
    end)
    local fg = function(t)
        if st.armed then return tk(t, "Warn") end
        if variant == "Ghost" and st.hover then return tk(t, "Text") end
        return tk(t, V.fg)
    end
    local parts = { btn, stroke }
    local lbl
    if isIcon then
        local ic = Icon(btn, o.Icon or "square", 12, fg, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
        for _, d in ipairs(ic:GetDescendants()) do table.insert(parts, d) end
    else
        Pad(btn, 0, 17)
        lbl = Label(btn, { Text = o.Name or o.Text or "Button", TextSize = o.TextSize or 12, Weight = "SemiBold", Case = "theme", Color = fg,
            Size = o.Fill and UDim2.fromScale(1, 1) or UDim2.new(0, 0, 1, 0), AutoSize = (not o.Fill) and Enum.AutomaticSize.X or nil,
            XAlign = Enum.TextXAlignment.Center })
        table.insert(parts, lbl)
        if not o.Fill then followSize(wrap, btn, function() return container.Window:_s() end) end
    end
    ctl.Root, ctl.Button, ctl.Label = wrap, btn, lbl
    ctl.Locked = o.Disabled or o.Locked
    local baseText = o.Name or o.Text or "Button"
    local armId = 0
    local function disarm()
        st.armed = false
        if lbl then setText(lbl, baseText) end
        restyleAll(parts, 0.12)
    end
    onHover(btn, function(h) st.hover = h and not ctl.Locked; restyleAll(parts, 0.12) end)
    btn.MouseButton1Click:Connect(function()
        if ctl.Locked then return end
        if o.DoubleClick then
            if st.armed then
                disarm()
                ctl:_emit()
            else
                st.armed = true
                armId += 1
                local my = armId
                if lbl then setText(lbl, o.ConfirmText or "Click again to confirm") end
                restyleAll(parts, 0.12)
                task.delay(2.2, function() if st.armed and armId == my and wrap.Parent then disarm() end end)
            end
        else
            ctl:_emit()
        end
    end)
    if o.Tooltip then
        btn.MouseEnter:Connect(function() container.Window:_showTooltip(btn, o.Tooltip) end)
        btn.MouseLeave:Connect(function() container.Window:_hideTooltip() end)
    end
    function ctl:SetText(t) baseText = tostring(t); if lbl then setText(lbl, baseText) end end
    ctl.Set = function(self, t) self:SetText(t) end
    function ctl:Fire() self:_emit() end
    return ctl
end

function Container:AddButton(o)
    if type(o) == "string" then o = { Name = o } end
    o = o or {}
    local row = Frame({ Name = "ButtonRow", Size = UDim2.new(1, 0, 0, o.Height or 34), LayoutOrder = self:_lo(), Parent = self.Frame })
    List(row, "x", 9, { VerticalAlignment = Enum.VerticalAlignment.Center,
        HorizontalAlignment = o.Align == "Right" and Enum.HorizontalAlignment.Right or Enum.HorizontalAlignment.Left })
    local ctl = makeButton(self, row, o, 1)
    ctl.Root = row
    return self:_register(ctl)
end

--[[ AddButtonRow({ {Name=...}, {Name=..., Align="Right"} }) — buttons with
     Align = "Right" are pushed to the right edge. Returns the handles. ]]
function Container:AddButtonRow(list, opts)
    opts = opts or {}
    local h = opts.Height or 34
    local row = Frame({ Name = "ButtonRow", Size = UDim2.new(1, 0, 0, h), LayoutOrder = self:_lo(), Parent = self.Frame })
    local leftF = Frame({ Size = UDim2.fromScale(1, 1), Parent = row })
    List(leftF, "x", 9, { VerticalAlignment = Enum.VerticalAlignment.Center })
    local rightF = Frame({ Size = UDim2.fromScale(1, 1), Parent = row })
    List(rightF, "x", 9, { VerticalAlignment = Enum.VerticalAlignment.Center, HorizontalAlignment = Enum.HorizontalAlignment.Right })
    local handles = {}
    for i, o in ipairs(list) do
        o.Height = o.Height or h
        local ctl = makeButton(self, o.Align == "Right" and rightF or leftF, o, i)
        self:_register(ctl)
        table.insert(handles, ctl)
    end
    return handles
end

-- Text blocks -----------------------------------------------------------------

local function simpleHandle(kind, root, name)
    local ctl = setmetatable({ Type = kind, Name = name or kind, Root = root, Maid = Maid.new(), _listeners = {} }, Control)
    return ctl
end

function Container:AddLabel(o)
    if type(o) ~= "table" then o = { Text = tostring(o) } end
    local l = Label(self.Frame, { Text = o.Text or o.Name or "", TextSize = o.TextSize or 13, Weight = o.Weight or "Regular", Mono = o.Mono,
        Color = o.Color or "Text", Wrap = true, LayoutOrder = self:_lo(), Rich = o.Rich })
    local ctl = simpleHandle("Label", l, o.Text)
    ctl.Set = function(_, t) l.Text = tostring(t) end
    ctl.Get = function() return l.Text end
    table.insert(self.Page.Controls, ctl)
    return ctl
end

function Container:AddParagraph(o)
    if type(o) ~= "table" then o = { Body = tostring(o) } end
    local f = VStack(self.Frame, 5, { Name = "Paragraph", LayoutOrder = self:_lo() })
    local title
    if o.Title then title = Label(f, { Text = o.Title, TextSize = 13, Weight = "SemiBold", Wrap = true, LayoutOrder = 1 }) end
    local body = Label(f, { Text = o.Body or o.Text or "", TextSize = 12, Color = "Dim", Wrap = true, LineHeight = 1.3, LayoutOrder = 2, Rich = o.Rich })
    local ctl = simpleHandle("Paragraph", f, o.Title or "paragraph")
    ctl.Set = function(_, b, t) body.Text = tostring(b); if t and title then title.Text = t end end
    table.insert(self.Page.Controls, ctl)
    return ctl
end

-- Section header + hairline; returns a sub-container for the section's rows.
function Container:AddSection(name, opts)
    if type(name) == "table" then opts = name; name = opts.Name end
    opts = opts or {}
    local header = Frame({ Name = "Section_" .. tostring(name), Size = UDim2.new(1, 0, 0, 16), LayoutOrder = self:_lo(), Parent = self.Frame })
    List(header, "x", 11, { VerticalAlignment = Enum.VerticalAlignment.Center })
    local title = Label(header, { Text = name or "", TextSize = 11, Weight = "SemiBold", Case = "upper", Color = "Dim", LayoutOrder = 1 })
    local line = Frame({ Name = "Rule", Size = UDim2.new(0, 40, 0, 1), BackgroundTransparency = 0, LayoutOrder = 2, Parent = header, Theme = { BackgroundColor3 = "Stroke" } })
    FlexFill(line)
    local badgeApi
    if opts.Badge then
        local b = type(opts.Badge) == "table" and opts.Badge or { Text = opts.Badge }
        _, badgeApi = Badge(header, b.Text, b.Kind or "accent", { LayoutOrder = 3 })
    end
    local body = VStack(self.Frame, opts.Gap or 9, { Name = "SectionBody", LayoutOrder = self:_lo() })
    local sec = self:_child(body, self.Compact)
    sec.Header = header
    function sec:SetTitle(t) setText(title, t) end
    function sec:SetBadge(t, k) if badgeApi then badgeApi:Set(t, k) end end
    return sec
end

function Container:AddDivider()
    Frame({ Name = "Divider", Size = UDim2.new(1, 0, 0, 1), BackgroundTransparency = 0, LayoutOrder = self:_lo(), Parent = self.Frame,
        Theme = { BackgroundColor3 = "Stroke2" } })
end

function Container:AddSpacer(px)
    Frame({ Name = "Spacer", Size = UDim2.new(1, 0, 0, px or 8), LayoutOrder = self:_lo(), Parent = self.Frame })
end

--[[ AddColumns(2) or AddColumns({ "1fr", 250 }) — numbers are fixed px widths,
     anything else is a flexible share. Returns an array of containers. ]]
function Container:AddColumns(spec, gap)
    gap = gap or 9
    if type(spec) == "number" then local n = spec; spec = {}; for i = 1, n do spec[i] = "1fr" end end
    local row = Frame({ Name = "Columns", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = self:_lo(), Parent = self.Frame })
    List(row, "x", gap)
    local fixed, flex = 0, 0
    for _, s in ipairs(spec) do if type(s) == "number" then fixed += s else flex += 1 end end
    local gaps = gap * (#spec - 1)
    local cols = {}
    for i, s in ipairs(spec) do
        local size
        if type(s) == "number" then size = UDim2.new(0, s, 0, 0)
        else size = UDim2.new(1 / flex, -(fixed + gaps) / flex, 0, 0) end
        local col = VStack(row, 9, { Name = "Col" .. i, Size = size, LayoutOrder = i })
        table.insert(cols, self:_child(col, self.Compact))
    end
    return cols
end

-- Accordion -------------------------------------------------------------------
--[[ Options: Name, Badge (string or {Text, Kind}), Open (false), Count (fixed
     "N settings" text; defaults to the live number of controls inside). ]]
function Container:AddAccordion(o)
    if type(o) == "string" then o = { Name = o } end
    o = o or {}
    local win = self.Window
    local card = Frame({ Name = "Accordion_" .. (o.Name or ""), Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = self:_lo(), Parent = self.Frame, Theme = { BackgroundColor3 = "Panel3" } })
    Corner(card, "CornerRadiusSmall"); Stroke(card, "Stroke2")
    List(card, "y", 0)
    local head = Button({ Name = "Header", Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 1, Parent = card })
    local left = Frame({ Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -110, 1, 0), Parent = head })
    List(left, "x", 10, { VerticalAlignment = Enum.VerticalAlignment.Center })
    local chev = Chevron(left, "Accent", { LayoutOrder = 1 })
    Label(left, { Text = o.Name or "", TextSize = 13, Weight = "Medium", LayoutOrder = 2 })
    if o.Badge then
        local b = type(o.Badge) == "table" and o.Badge or { Text = o.Badge }
        Badge(left, b.Text, b.Kind or "accent", { LayoutOrder = 3, Border = false })
    end
    local countLbl = Label(head, { Text = "", TextSize = 11, Mono = true, Color = "Dim",
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0) })

    local body = Frame({ Name = "Body", Size = UDim2.new(1, 0, 0, 0), ClipsDescendants = true, LayoutOrder = 2, Parent = card })
    local inner = Frame({ Name = "Inner", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = body })
    Pad(inner, 4, 14, 14, 14)
    List(inner, "y", 12)

    local acc = self:_child(inner, true)
    local n = 0
    acc._onAdd = function()
        n += 1
        if not o.Count then countLbl.Text = n .. (n == 1 and " setting" or " settings") end
    end
    if o.Count then countLbl.Text = tostring(o.Count) end
    acc.Open = false

    local function contentH() return inner.AbsoluteSize.Y / win:_s() end
    function acc:SetOpen(open, instant)
        self.Open = open
        tween(chev, instant and 0 or 0.18, { Rotation = open and 0 or -90 })
        body.AutomaticSize = Enum.AutomaticSize.None
        if open then
            body.Visible = true
            local tw = tween(body, instant and 0 or 0.2, { Size = UDim2.new(1, 0, 0, contentH()) })
            local function finish() if self.Open then body.AutomaticSize = Enum.AutomaticSize.Y; body.Size = UDim2.new(1, 0, 0, 0) end end
            if tw then tw.Completed:Once(finish) else finish() end
        else
            body.Size = UDim2.new(1, 0, 0, contentH())
            local tw = tween(body, instant and 0 or 0.2, { Size = UDim2.new(1, 0, 0, 0) })
            local function finish() if not self.Open then body.Visible = false end end
            if tw then tw.Completed:Once(finish) else finish() end
        end
    end
    function acc:Toggle() self:SetOpen(not self.Open) end
    head.MouseButton1Click:Connect(function() acc:Toggle() end)
    chev.Rotation = -90
    body.Visible = false
    if o.Open then task.defer(function() if card.Parent then acc:SetOpen(true, true) end end) end
    acc.Root = card
    return acc
end

--==============================================================================
-- §11  INFORMATION & FEEDBACK
--==============================================================================

-- Progress bar (optionally with a spinner) --------------------------------------
function Container:AddProgress(o)
    if type(o) == "string" then o = { Name = o } end
    o = o or {}
    local ctl = newControl("Progress", o)
    local card = self:_card("Progress_" .. ctl.Name, 13)
    ctl.Root = card
    local row = HRow(card, 14)
    local reserve = 0
    if o.Spinner then
        Spinner(row, o.Spinner == true and "ring" or o.Spinner, 18, { LayoutOrder = 1 })
        reserve = 32
    end
    local stack = VStack(row, 7, { Size = UDim2.new(1, -reserve, 0, 0), LayoutOrder = 2 })
    local head = Frame({ Size = UDim2.new(1, 0, 0, 13), LayoutOrder = 1, Parent = stack })
    Label(head, { Text = o.Name or "", TextSize = 12, Color = "Dim", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5) })
    local pct = Label(head, { Text = "0%", TextSize = 11, Weight = "Medium", Mono = true, Color = "Dim", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5) })
    local bar = Frame({ Size = UDim2.new(1, 0, 0, 6), LayoutOrder = 2, ClipsDescendants = true, Parent = stack, Theme = { BackgroundColor3 = "Track" } })
    Corner(bar, "full")
    local fill = Frame({ Size = UDim2.new(0, 0, 1, 0), Parent = bar, Theme = { BackgroundColor3 = o.Color or "Accent" } })
    Corner(fill, "full")
    function ctl:Set(v)
        v = clamp(tonumber(v) or 0, 0, 100)
        self.Value = v
        pct.Text = fmtNum(math.floor(v + 0.5)) .. "%"
        tween(fill, 0.2, { Size = UDim2.new(v / 100, 0, 1, 0) })
    end
    function ctl:SetText(t) head:FindFirstChildWhichIsA("TextLabel").Text = t end
    ctl:Set(o.Default or o.Value or 0)
    table.insert(self.Page.Controls, ctl)
    ctl.Window, ctl.Container = self.Window, self
    return ctl
end

function Container:AddSpinner(style)
    local row = Frame({ Name = "Spinner", Size = UDim2.new(1, 0, 0, 20), LayoutOrder = self:_lo(), Parent = self.Frame })
    Spinner(row, style or "ring", 18)
    return row
end

-- All three spinner variants on one row (component-sheet style).
function Container:AddSpinners(note)
    local card = self:_card("Spinners", 13)
    local row = HRow(card, 18)
    Spinner(row, "ring", 20, { LayoutOrder = 1 })
    Spinner(row, "thin", 20, { LayoutOrder = 2 })
    Spinner(row, "dots", 12, { LayoutOrder = 3 })
    Label(row, { Text = note or "3 variants", TextSize = 11, Mono = true, Color = "Dim", LayoutOrder = 4 })
    return card
end

-- Badges ------------------------------------------------------------------------
function Container:AddBadges(list)
    local f = Frame({ Name = "Badges", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = self:_lo(), Parent = self.Frame })
    List(f, "x", 6, { Wraps = true })
    local apis = {}
    for i, b in ipairs(list or {}) do
        if type(b) == "string" then b = { Text = b } end
        local _, api = Badge(f, b.Text, b.Kind or "accent", { LayoutOrder = i, TextSize = 10, PadY = 4, PadX = 8 })
        table.insert(apis, api)
    end
    return apis
end

-- Stat cards --------------------------------------------------------------------
--[[ AddStatCards({ {Label="FPS", Value="60", Note="target 60", Kind="ok"}, … })
     Kind: "ok" | "warn" | "danger" | "accent" | "text" (default). Returns an
     api with :Update(index, {Value=, Note=, Kind=}). ]]
function Container:AddStatCards(cards)
    local n = math.max(1, #cards)
    local gap = 10
    local grid = Frame({ Name = "Stats", Size = UDim2.new(1, 0, 0, 66), LayoutOrder = self:_lo(), Parent = self.Frame })
    -- a non-wrapping horizontal list: sub-pixel rounding can never push the last card to a new row
    List(grid, "x", gap)
    local cellSize = UDim2.new(1 / n, -math.ceil(gap * (n - 1) / n), 1, 0)
    local api = { Cards = {}, Frame = grid }
    for i, c in ipairs(cards) do
        local st = { kind = c.Kind or "text" }
        local card = Frame({ Size = cellSize, LayoutOrder = i, Parent = grid, Theme = { BackgroundColor3 = "Panel3" } })
        Corner(card, "CornerRadiusSmall"); Stroke(card, "Stroke2"); Pad(card, 11, 13)
        List(card, "y", 6)
        Label(card, { Text = c.Label or "", TextSize = 9, Weight = "SemiBold", Mono = true, Case = "upper", Color = "Dim", LayoutOrder = 1 })
        local value = Label(card, { Text = tostring(c.Value or "—"), TextSize = 19, Weight = "SemiBold", LayoutOrder = 2,
            Color = function(t) if st.kind == "text" then return tk(t, "Text") end return tk(t, KIND[kindOf(st.kind)][1]) end })
        local note = Label(card, { Text = c.Note or "", TextSize = 10, Mono = true, Color = "Dim", LayoutOrder = 3 })
        api.Cards[i] = { value = value, note = note, st = st }
    end
    function api:Update(i, d)
        local c = self.Cards[i]
        if not c then return end
        if d.Value ~= nil then c.value.Text = tostring(d.Value) end
        if d.Note ~= nil then c.note.Text = tostring(d.Note) end
        if d.Kind ~= nil and d.Kind ~= c.st.kind then c.st.kind = d.Kind; restyle(c.value, 0.15) end
    end
    return api
end

-- FPS / ping / memory / position wired to real telemetry.
function Container:AddLiveStats(o)
    o = o or {}
    local api = self:AddStatCards({
        { Label = "FPS", Value = "—", Note = "target " .. (o.TargetFPS or 60) },
        { Label = "Ping", Value = "—", Note = o.Region or "network" },
        { Label = "Memory", Value = "—", Note = "client total" },
        { Label = "Position", Value = "—", Note = "z —" },
    })
    local key = {}
    subscribeTelemetry(key, function(T)
        if not api.Frame.Parent then Library.Telemetry.subs[key] = nil return end
        local scroll = api.Frame:FindFirstAncestorWhichIsA("ScrollingFrame")
        if scroll and not scroll.Visible then return end -- skip hidden pages
        api:Update(1, { Value = T.fps, Kind = T.fps >= (o.WarnFPS or 55) and "ok" or "warn" })
        api:Update(2, { Value = T.ping .. " ms", Kind = T.ping < (o.WarnPing or 100) and "ok" or "warn" })
        api:Update(3, { Value = T.mem .. " MB" })
        api:Update(4, { Value = fmtPos(T.pos, true), Note = T.pos and string.format("z %d", T.pos.Z) or "no character" })
    end)
    return api
end

-- Console / log viewer --------------------------------------------------------------
local LEVEL_KIND = { INFO = "Accent", OK = "Ok", WARN = "Warn", ERR = "Danger" }
local function normLevel(l)
    l = string.upper(tostring(l or "INFO"))
    if l == "ERROR" or l == "DANGER" then return "ERR" end
    if l == "WARNING" then return "WARN" end
    if l == "SUCCESS" then return "OK" end
    if not LEVEL_KIND[l] then return "INFO" end
    return l
end

function Container:AddConsole(o)
    o = o or {}
    local ctl = newControl("Console", o)
    local root = VStack(self.Frame, 11, { Name = "Console", LayoutOrder = self:_lo() })
    ctl.Root = root
    local filterRow = Frame({ Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 1, Parent = root })
    local pills = Frame({ Size = UDim2.fromScale(0.8, 1), Parent = filterRow })
    List(pills, "x", 7, { VerticalAlignment = Enum.VerticalAlignment.Center })
    local filter = "ALL"
    local pillParts = {}
    local lines = {}
    local function pill(parent, text, order, isActive, onClick)
        local b = Button({ AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), LayoutOrder = order, Parent = parent,
            Theme = { BackgroundColor3 = function(t) if isActive() then return tk(t, "AccentSoft") end return t.Panel2, 1 end } })
        Corner(b, "full"); Pad(b, 0, 11)
        local s = Stroke(b, function(t) return tk(t, isActive() and "AccentLine" or "Stroke") end)
        local l = Label(b, { Text = text, TextSize = 11, Weight = "Medium", Mono = true, Size = UDim2.new(0, 0, 1, 0), AutoSize = Enum.AutomaticSize.X,
            Color = function(t) return tk(t, isActive() and "Accent" or "Dim") end })
        b.MouseButton1Click:Connect(onClick)
        return { b, s, l }
    end
    local view
    local function applyFilter()
        for _, ln in ipairs(lines) do ln.frame.Visible = filter == "ALL" or ln.level == filter end
    end
    for i, f in ipairs({ "ALL", "INFO", "OK", "WARN", "ERR" }) do
        local parts = pill(pills, f == "ALL" and "All" or f, i, function() return filter == f end, function()
            filter = f
            for _, p in ipairs(pillParts) do restyleAll(p, 0.12) end
            applyFilter()
        end)
        table.insert(pillParts, parts)
    end
    local clearRow = Frame({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromScale(0.2, 1), Parent = filterRow })
    List(clearRow, "x", 0, { HorizontalAlignment = Enum.HorizontalAlignment.Right })
    pill(clearRow, "Clear", 1, function() return false end, function() ctl:Clear() end)

    view = New("ScrollingFrame", {
        Name = "View", Size = UDim2.new(1, 0, 0, o.Height or 330), LayoutOrder = 2, BorderSizePixel = 0,
        CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 4,
        ScrollingDirection = Enum.ScrollingDirection.Y, Parent = root,
        Theme = { BackgroundColor3 = "Console", ScrollBarImageColor3 = "Stroke" },
    })
    Corner(view, "CornerRadiusSmall"); Stroke(view, "Stroke"); Pad(view, 12, 13)
    List(view, "y", 4)
    local caret = Frame({ Name = "Caret", Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 2 ^ 30, Parent = view })
    Label(caret, { Text = ">", TextSize = 12, Mono = true, Color = "Accent", Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(10, 18) })
    local block = Frame({ Size = UDim2.fromOffset(7, 14), Position = UDim2.fromOffset(16, 2), Parent = caret, Theme = { BackgroundColor3 = function(t) return t.Accent end } })
    block.BackgroundTransparency = 0
    pcall(function()
        TweenService:Create(block, TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, true), { BackgroundTransparency = 0.85 }):Play()
    end)

    local counter = 0
    local maxLines = o.MaxLines or 200
    function ctl:Add(entry)
        counter += 1
        local atBottom = view.CanvasPosition.Y >= view.AbsoluteCanvasSize.Y - view.AbsoluteSize.Y - 24
        local ln = Frame({ Name = "Line", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = counter, Parent = view,
            Visible = filter == "ALL" or filter == entry.level })
        Label(ln, { Text = entry.time, TextSize = 11, Mono = true, Size = UDim2.fromOffset(60, 18), Color = function(t) return t.ConsoleText, 0.55 end })
        Label(ln, { Text = entry.level, TextSize = 11, Weight = "SemiBold", Mono = true, Position = UDim2.fromOffset(66, 0), Size = UDim2.fromOffset(46, 18),
            Color = function(t) return t[LEVEL_KIND[entry.level]], 0 end })
        Label(ln, { Text = entry.msg, TextSize = 11, Mono = true, Position = UDim2.fromOffset(116, 0), Size = UDim2.new(1, -116, 0, 0),
            AutoSize = Enum.AutomaticSize.Y, Wrap = true, LineHeight = 1.15, Color = function(t) return t.ConsoleText, 0.12 end })
        table.insert(lines, { frame = ln, level = entry.level })
        while #lines > maxLines do table.remove(lines, 1).frame:Destroy() end
        if atBottom then task.defer(function() if view.Parent then view.CanvasPosition = Vector2.new(0, 1e7) end end) end
    end
    function ctl:Clear()
        for _, ln in ipairs(lines) do ln.frame:Destroy() end
        lines = {}
        if o.ClearGlobal ~= false then table.clear(Library.Logs) end
    end
    function ctl:Filter(q)
        q = string.lower(q or "")
        local n = 0
        for _, ln in ipairs(lines) do
            local txt = string.lower(ln.frame:GetChildren()[3] and ln.frame:GetChildren()[3].Text or "")
            local ok = (filter == "ALL" or ln.level == filter) and (q == "" or string.find(txt, q, 1, true) ~= nil)
            ln.frame.Visible = ok
            if ok then n += 1 end
        end
        return n
    end
    function ctl:_total() return #lines end
    for _, e in ipairs(Library.Logs) do ctl:Add(e) end
    Library.LogSubscribers[ctl] = function(e) if root.Parent then ctl:Add(e) else Library.LogSubscribers[ctl] = nil end end
    ctl.Maid:Give(function() Library.LogSubscribers[ctl] = nil end)
    if o.HookLogService then Sypse:HookLogService(true) end
    ctl.Window, ctl.Container = self.Window, self
    table.insert(self.Page.Controls, ctl)
    table.insert(self.Window.Controls, ctl)
    return ctl
end

-- Search / filter bar --------------------------------------------------------------
--[[ AddSearchBar({ Placeholder, Target = <handle with :Filter(q)>, Total, Callback(q) })
     Debounced 0.15 s; shows "matches/total". ]]
local function buildSearchBar(container, parent, o, order)
    local box, tb = searchField(parent, o.Placeholder or "Search…", { Size = o.Size or UDim2.new(1, 0, 0, 36), LayoutOrder = order })
    local count = Label(box, { Text = "", TextSize = 11, Mono = true, Color = "Dim", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0) })
    tb.Size = UDim2.new(1, -90, 1, 0)
    local api = { Box = tb, Frame = box, Target = o.Target }
    local pending = 0
    function api:Refresh()
        local q = tb.Text
        local n
        if self.Target and self.Target.Filter then n = self.Target:Filter(q) end
        if n then
            local total = o.Total or (self.Target._total and self.Target:_total()) or n
            count.Text = n .. "/" .. total
        end
        safeCall(o.Callback, q)
    end
    tb:GetPropertyChangedSignal("Text"):Connect(function()
        pending += 1
        local my = pending
        task.delay(o.Debounce or 0.15, function() if my == pending and box.Parent then api:Refresh() end end)
    end)
    task.defer(function() if box.Parent then api:Refresh() end end)
    return api
end

function Container:AddSearchBar(o)
    o = o or {}
    local api = buildSearchBar(self, self.Frame, o, self:_lo())
    return api
end

-- Player / asset grid ----------------------------------------------------------------
--[[ AddPlayerGrid({
        Items   = "live" (default: real players, live-updating) or a list of
                  { Name, Meta, Tag, Kind, UserId, Initials, Status = "ok"|… },
        Actions = { { Name = "Spectate", Variant = "Primary", Callback = function(item) end }, … },
        Search  = true, Columns = 4, Placeholder = "Search players in server…" })
     Handle: :GetSelected(), :Select(i), :Refresh(items), :Filter(q) ]]
function Container:AddPlayerGrid(o)
    o = o or {}
    local ctl = newControl("PlayerGrid", o)
    local win = self.Window
    local cols = o.Columns or 4
    local root = VStack(self.Frame, 14, { Name = "PlayerGrid", LayoutOrder = self:_lo() })
    ctl.Root = root
    local top = Frame({ Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 1, Parent = root })
    List(top, "x", 10, { VerticalAlignment = Enum.VerticalAlignment.Center })
    local search
    if o.Search ~= false then
        search = buildSearchBar(self, top, { Placeholder = o.Placeholder or "Search players in server…", Target = ctl, Size = UDim2.new(0, 200, 0, 36) }, 1)
        FlexFill(search.Frame)
    end
    for i, a in ipairs(o.Actions or {}) do
        local cb = a.Callback
        local btnOpts = merge(a, { Callback = function() safeCall(cb, ctl.Selected and ctl.Selected.item) end, Height = 36 })
        local b = makeButton(self, top, btnOpts, 10 + i)
        b.Window, b.Container = win, self
    end

    local grid = Frame({ Name = "Grid", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Parent = root })
    local gridLayout = New("UIGridLayout", { CellSize = UDim2.new(1 / cols, -math.ceil(10 * (cols - 1) / cols) - 1, 0, 200), CellPadding = UDim2.fromOffset(10, 10),
        SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
    -- a UIAspectRatioConstraint parented to the UIGridLayout applies to every cell
    New("UIAspectRatioConstraint", { AspectRatio = o.AspectRatio or 0.74, Parent = gridLayout })

    local cards = {}
    ctl.Selected = nil
    local query = ""

    local function makeCard(item, i)
        local st = { sel = false }
        local c = Button({ Name = "Card", LayoutOrder = i, Parent = grid, Theme = { BackgroundColor3 = function(t) return tk(t, st.sel and "AccentSoft" or "Panel3") end } })
        Corner(c, "CornerRadiusSmall")
        local s = Stroke(c, function(t) return tk(t, st.sel and "AccentLine" or "Stroke2") end)
        Pad(c, 12)
        List(c, "y", 9)
        local av = Frame({ Name = "Avatar", Size = UDim2.new(1, 0, 1, 0), LayoutOrder = 1, Parent = c, BackgroundTransparency = 0,
            Theme = { BackgroundColor3 = function(t) return t.Placeholder, 0 end } })
        New("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Width, Parent = av })
        Corner(av, 8)
        New("UIGradient", { Rotation = 135, Parent = av, Theme = { Transparency = function(t)
            local a, b = t.PlaceholderTransparency or 0.92, t.Placeholder2Transparency or 0.97
            local kps, n = {}, 9
            for k = 0, n do
                local val = (k % 2 == 0) and a or b
                local x0 = k / (n + 1)
                local x1 = (k + 1) / (n + 1)
                table.insert(kps, NumberSequenceKeypoint.new(k == 0 and 0 or x0 + 0.0005, val))
                table.insert(kps, NumberSequenceKeypoint.new(k == n and 1 or x1, val))
            end
            return NumberSequence.new(kps)
        end } })
        local initials = Label(av, { Text = item.Initials or string.upper(string.sub(item.Name or "?", 1, 2)), TextSize = 15, Weight = "SemiBold", Mono = true,
            Color = "Dim", Size = UDim2.fromScale(1, 1), XAlign = Enum.TextXAlignment.Center })
        local img = New("ImageLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = av })
        Corner(img, 8)
        local dotKind = item.Status or item.Kind or "dim"
        local dot = Frame({ Size = UDim2.fromOffset(8, 8), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 6), ZIndex = 3, Parent = av,
            Theme = { BackgroundColor3 = function(t) return t[KIND[kindOf(dotKind)][1]], 0 end } })
        Corner(dot, "full")
        local texts = Frame({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Parent = c })
        List(texts, "y", 3)
        Label(texts, { Text = item.Name or "", TextSize = 12, Weight = "SemiBold", Truncate = true, Size = UDim2.new(1, 0, 0, 15), LayoutOrder = 1 })
        local meta = Label(texts, { Text = item.Meta or "", TextSize = 10, Mono = true, Color = "Dim", Truncate = true, Size = UDim2.new(1, 0, 0, 12), LayoutOrder = 2 })
        local _, tagApi = Badge(c, item.Tag or "", item.Kind or "dim", { LayoutOrder = 3, Border = false, PadY = 3, PadX = 6 })
        if (item.Tag or "") == "" then tagApi.Frame.Visible = false end
        if item.UserId and item.UserId > 0 then
            task.spawn(function()
                local ok, content, ready = pcall(function()
                    return Players:GetUserThumbnailAsync(item.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
                end)
                if ok and content and img.Parent then img.Image = content; img.Visible = true; initials.Visible = false end
            end)
        end
        local rec = { item = item, frame = c, st = st, parts = { c, s }, meta = meta, tag = tagApi }
        c.MouseButton1Click:Connect(function() ctl:Select(rec) end)
        return rec
    end

    function ctl:Select(rec)
        if type(rec) == "number" then rec = cards[rec] end
        for _, r in ipairs(cards) do
            r.st.sel = (r == rec)
            restyleAll(r.parts, 0.12)
        end
        self.Selected = rec
        self.Value = rec and rec.item
        safeCall(o.OnSelect, rec and rec.item)
    end
    function ctl:GetSelected() return self.Selected and self.Selected.item end
    function ctl:Filter(q)
        query = string.lower(q or "")
        local n = 0
        for _, r in ipairs(cards) do
            local ok = query == "" or string.find(string.lower(r.item.Name or ""), query, 1, true) ~= nil
            r.frame.Visible = ok
            if ok then n += 1 end
        end
        return n
    end
    function ctl:_total() return #cards end
    function ctl:Refresh(items)
        local selName = self.Selected and self.Selected.item.Name
        for _, r in ipairs(cards) do r.frame:Destroy() end
        cards = {}
        self.Selected = nil
        for i, it in ipairs(items or {}) do
            local rec = makeCard(it, i)
            table.insert(cards, rec)
            if it.Name == selName then self.Selected = rec; rec.st.sel = true; restyleAll(rec.parts) end
        end
        self:Filter(query)
        if search then search:Refresh() end
    end

    local live = o.Items == nil or o.Items == "live"
    local function playerItem(p)
        local tag, kind = "NEUTRAL", "dim"
        if p == LocalPlayer then tag, kind = "YOU", "accent" end
        local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
        return {
            Name = p.Name, UserId = p.UserId, Player = p, Tag = tag, Kind = kind, Status = hum and hum.Health > 0 and "ok" or "dim",
            Meta = "@" .. p.DisplayName .. (hum and (" · " .. math.floor(hum.Health) .. " hp") or ""),
        }
    end
    local function rebuildLive()
        local items = {}
        for _, p in ipairs(Players:GetPlayers()) do table.insert(items, playerItem(p)) end
        ctl:Refresh(items)
        -- friend tags resolve asynchronously
        for _, r in ipairs(cards) do
            local p = r.item.Player
            if p and p ~= LocalPlayer and LocalPlayer then
                task.spawn(function()
                    local ok, isFriend = pcall(function() return LocalPlayer:IsFriendsWith(p.UserId) end)
                    if ok and isFriend and r.frame.Parent then r.item.Tag, r.item.Kind = "FRIEND", "ok"; r.tag:Set("FRIEND", "ok") end
                end)
            end
        end
    end
    if live then
        rebuildLive()
        ctl.Maid:Give(Players.PlayerAdded:Connect(function() task.defer(rebuildLive) end))
        ctl.Maid:Give(Players.PlayerRemoving:Connect(function() task.defer(rebuildLive) end))
        local tick = 0
        subscribeTelemetry(ctl, function()
            if not root.Parent then Library.Telemetry.subs[ctl] = nil return end
            tick += 1
            if tick % 4 ~= 0 then return end
            for _, r in ipairs(cards) do
                local p = r.item.Player
                local hum = p and p.Character and p.Character:FindFirstChildOfClass("Humanoid")
                if p then r.meta.Text = "@" .. p.DisplayName .. (hum and (" · " .. math.floor(hum.Health) .. " hp") or "") end
            end
        end)
        ctl.Maid:Give(function() Library.Telemetry.subs[ctl] = nil end)
    else
        ctl:Refresh(o.Items)
    end
    if o.Default then ctl:Select(o.Default) end
    ctl.Window, ctl.Container = win, self
    table.insert(self.Page.Controls, ctl)
    table.insert(win.Controls, ctl)
    return ctl
end

-- Config / preset manager ----------------------------------------------------------
--[[ AddConfigManager({ Folder = window.ConfigFolder })
     Lists saved profiles (name, key count, size, ACTIVE / SAVED / RISKY tag), a
     filename field and Save / Load / Export / Delete. Persists every control
     that has a Flag. File I/O is feature-detected; without it profiles live in
     memory for the session. ]]
function Container:AddConfigManager(o)
    o = o or {}
    local win = self.Window
    local folder = o.Folder or win.ConfigFolder
    local ctl = newControl("ConfigManager", o)
    local root = VStack(self.Frame, 7, { Name = "ConfigManager", LayoutOrder = self:_lo() })
    ctl.Root = root
    local listF = VStack(root, 7, { LayoutOrder = 1 })
    local fieldRow = Frame({ Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 2, Parent = root })
    List(fieldRow, "x", 7, { VerticalAlignment = Enum.VerticalAlignment.Center })
    local fbox = Frame({ Size = UDim2.new(0, 120, 1, 0), LayoutOrder = 1, Parent = fieldRow, Theme = { BackgroundColor3 = "Panel2" } })
    Corner(fbox, "CornerRadiusSmall"); Stroke(fbox, "Stroke")
    FlexFill(fbox)
    local nameBox = New("TextBox", { BackgroundTransparency = 1, ClearTextOnFocus = false, Text = win.Profile, TextSize = 12,
        Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -24, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, Parent = fbox,
        Theme = { TextColor3 = "Text", FontFace = function(t) return getFont(t.FontMono) end } })
    local rows = {}
    local selected = win.Profile

    local function refresh()
        for _, r in ipairs(rows) do r:Destroy() end
        rows = {}
        local names = Sypse:ListConfigs(folder)
        if #names == 0 then
            table.insert(rows, Label(listF, { Text = "No saved profiles yet — type a name and press Save.", TextSize = 11, Mono = true, Color = "Dim", Wrap = true }))
        end
        for i, name in ipairs(names) do
            local info = Sypse:ConfigInfo(name, folder)
            local tag, kind = "SAVED", "dim"
            if info.risky then tag, kind = "RISKY", "danger" end
            if name == win.Profile then tag, kind = "ACTIVE", "ok" end
            local st = { sel = name == selected }
            local b = Button({ Name = name, Size = UDim2.new(1, 0, 0, 46), LayoutOrder = i, Parent = listF,
                Theme = { BackgroundColor3 = function(t) return tk(t, st.sel and "AccentSoft" or "Panel3") end } })
            Corner(b, "CornerRadiusSmall")
            Stroke(b, function(t) return tk(t, st.sel and "AccentLine" or "Stroke2") end)
            local dot = Frame({ Size = UDim2.fromOffset(9, 9), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 13, 0.5, 0), Parent = b,
                Theme = { BackgroundColor3 = function(t) return t[KIND[kind][1]], 0 end } })
            Corner(dot, 2)
            Label(b, { Text = name, TextSize = 12, Weight = "Medium", Mono = true, Position = UDim2.fromOffset(33, 9), Size = UDim2.new(1, -120, 0, 14), Truncate = true })
            Label(b, { Text = string.format("%d keys · %s", info.keys, info.size), TextSize = 10, Mono = true, Color = "Dim", Position = UDim2.fromOffset(33, 26), Size = UDim2.new(1, -120, 0, 12) })
            local bf = Badge(b, tag, kind, { Border = false })
            bf.AnchorPoint = Vector2.new(1, 0.5); bf.Position = UDim2.new(1, -13, 0.5, 0)
            b.MouseButton1Click:Connect(function()
                selected = name
                nameBox.Text = name
                refresh()
            end)
            table.insert(rows, b)
        end
    end
    ctl.Refresh = function() refresh() end

    local function btn(opts, i)
        local h = makeButton(self, fieldRow, merge(opts, { Height = 36 }), 10 + i)
        h.Window, h.Container = win, self
        return h
    end
    btn({ Name = "Save", Variant = "Primary", Callback = function()
        local name = nameBox.Text ~= "" and nameBox.Text or "default.json"
        local ok, err = win:SaveConfig(name)
        if ok then selected = win.Profile; nameBox.Text = win.Profile
            Sypse:Notify({ Title = "Config saved", Body = win.Profile .. (Env.HasFileIO and " written to disk" or " kept in memory"), Kind = "ok" })
        else Sypse:Notify({ Title = "Save failed", Body = tostring(err), Kind = "danger" }) end
        refresh()
    end }, 1)
    btn({ Name = "Load", Callback = function()
        local ok, err = win:LoadConfig(nameBox.Text)
        if ok then Sypse:Notify({ Title = "Config loaded", Body = win.Profile .. " applied", Kind = "ok" })
        else Sypse:Notify({ Title = "Load failed", Body = tostring(err), Kind = "danger" }) end
        refresh()
    end }, 2)
    btn({ Name = "Export", Callback = function()
        local json = Sypse:ExportConfig()
        if Env.setclipboard then
            pcall(Env.setclipboard, json)
            Sypse:Notify({ Title = "Exported", Body = "config JSON copied to clipboard", Kind = "accent" })
        else
            print("[Sypse] exported config:\n" .. json)
            Sypse:Log("INFO", "config export printed to output (" .. #json .. " bytes)")
            Sypse:Notify({ Title = "Exported", Body = "no clipboard here — JSON printed to output", Kind = "warn" })
        end
    end }, 3)
    btn({ Name = "Delete", Variant = "Danger", Callback = function()
        local name = nameBox.Text
        win:Dialog({
            Title = "Delete " .. name .. "?",
            Body = "This removes the saved profile from " .. (Env.HasFileIO and "disk" or "memory") .. ". This cannot be undone.",
            Confirm = { Text = "Delete", Variant = "Danger", Callback = function()
                local ok = win:DeleteConfig(name)
                Sypse:Notify({ Title = ok and "Profile deleted" or "Delete failed", Body = name, Kind = ok and "danger" or "warn" })
                refresh()
            end },
            Cancel = { Text = "Cancel" },
        })
    end }, 4)
    refresh()
    ctl.Window, ctl.Container = win, self
    table.insert(self.Page.Controls, ctl)
    return ctl
end

--==============================================================================
-- §12  OVERLAY: TOASTS, DIALOGS, WATERMARK
--==============================================================================

local ToastList = {}
local toastOrder = 0

--[[ Sypse:Notify({ Title, Body, Kind = "info"|"accent"|"ok"|"warn"|"danger", Duration = 4.2 })
     Bottom-right stack, max 4, slide-in from the right, manual close. ]]
function Sypse:Notify(o)
    if type(o) == "string" then o = { Title = o } end
    o = o or {}
    getOverlay()
    local kind = kindOf(o.Kind)
    toastOrder += 1
    local slot = Frame({ Name = "Toast", Size = UDim2.fromOffset(290, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = toastOrder, Parent = Library.ToastHost })
    local card = Frame({ Name = "Card", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Position = UDim2.fromOffset(28, 0), Parent = slot,
        Theme = { BackgroundColor3 = "Tooltip" } })
    Corner(card, "CornerRadiusSmall"); Stroke(card, "Stroke")
    local bar = Frame({ Name = "Accent", Size = UDim2.new(0, 3, 1, 0), BackgroundTransparency = 0, Parent = card,
        Theme = { BackgroundColor3 = function(t) return t[KIND[kind][1]], 0 end } })
    Corner(bar, 2)
    local content = Frame({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = card })
    Pad(content, 12, 13, 12, 16)
    local dot = Frame({ Size = UDim2.fromOffset(8, 8), Position = UDim2.fromOffset(0, 4), Parent = content,
        Theme = { BackgroundColor3 = function(t) return t[KIND[kind][1]], 0 end } })
    Corner(dot, "full")
    local texts = Frame({ Position = UDim2.fromOffset(19, 0), Size = UDim2.new(1, -45, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = content })
    List(texts, "y", 3)
    Label(texts, { Text = o.Title or "Notice", TextSize = 12, Weight = "SemiBold", Wrap = true, LayoutOrder = 1 })
    if o.Body or o.Content then
        Label(texts, { Text = o.Body or o.Content, TextSize = 11, Mono = true, Color = "Dim", Wrap = true, LineHeight = 1.2, LayoutOrder = 2 })
    end
    local close = Button({ Name = "Close", Size = UDim2.fromOffset(18, 18), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, -1),
        Parent = content, Text = "×", TextSize = 14, Theme = { TextColor3 = "Dim", FontFace = function(t) return getFont(t.FontMono) end } })

    local rec = { slot = slot, alive = true }
    local function dismiss()
        if not rec.alive then return end
        rec.alive = false
        for i, r in ipairs(ToastList) do if r == rec then table.remove(ToastList, i) break end end
        setFaded(card, 1)
        tween(card, 0.18, { Position = UDim2.fromOffset(28, 0) })
        task.delay(0.2, function() pcall(slot.Destroy, slot) end)
    end
    rec.dismiss = dismiss
    close.MouseButton1Click:Connect(dismiss)
    table.insert(ToastList, rec)
    while #ToastList > (o.Max or 4) do ToastList[1].dismiss() end
    -- enter
    FadeMap[card] = 1
    for _, d in ipairs(card:GetDescendants()) do FadeMap[d] = 1; restyle(d) end
    restyle(card)
    task.defer(function()
        if not rec.alive then return end
        setFaded(card, 0)
        tween(card, 0.22, { Position = UDim2.fromOffset(0, 0) })
    end)
    task.delay(o.Duration or 4.2, dismiss)
    return { Dismiss = dismiss }
end

--[[ Dialog({ Title, Body, Icon = "!", Confirm = { Text, Variant, Callback },
             Cancel = { Text, Callback }, DismissOnScrim = false })
     Blocking modal over the window (or the whole screen when no window exists). ]]
local function buildDialog(host, win, o)
    o = o or {}
    local confirm = o.Confirm or { Text = "OK" }
    local cancel = o.Cancel
    local kind = (confirm.Variant == "Danger" and "danger") or (confirm.Variant == "Warn" and "warn") or "accent"
    local scrim = Button({ Name = "Scrim", Size = UDim2.fromScale(1, 1), ZIndex = 100, Active = true, Parent = host,
        Theme = { BackgroundColor3 = "Scrim" } })
    pcall(function() scrim.Modal = true end)
    local wrap = Frame({ Name = "Dialog", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(400, 180), ZIndex = 101, Parent = scrim })
    local scale = New("UIScale", { Scale = 0.96, Parent = wrap })
    ShadowLayers(wrap, "CornerRadius", 0.6, 101)
    local card = Frame({ Name = "Card", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 102, Parent = wrap,
        Theme = { BackgroundColor3 = "Background" } })
    Corner(card, "CornerRadius"); Stroke(card, "Stroke")
    local surface = Frame({ Size = UDim2.fromScale(1, 1), ZIndex = 102, Parent = card, Theme = { BackgroundColor3 = "Panel" } })
    Corner(surface, "CornerRadius")
    local inner = Frame({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 103, Parent = card })
    Pad(inner, 22)
    List(inner, "y", 13)
    local head = Frame({ Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 1, Parent = inner })
    List(head, "x", 10, { VerticalAlignment = Enum.VerticalAlignment.Center })
    local ic = Frame({ Size = UDim2.fromOffset(28, 28), LayoutOrder = 1, Parent = head, Theme = { BackgroundColor3 = KIND[kind][2] } })
    Corner(ic, 8); Stroke(ic, KIND[kind][3], 1)
    Label(ic, { Text = o.Icon or "!", TextSize = 14, Weight = "Bold", Size = UDim2.fromScale(1, 1), XAlign = Enum.TextXAlignment.Center, Color = KIND[kind][1] })
    Label(head, { Text = o.Title or "Are you sure?", TextSize = 15, Weight = "SemiBold", Case = "theme", LayoutOrder = 2 })
    if o.Body then
        Label(inner, { Text = o.Body, TextSize = 12.5, Color = "Dim", Wrap = true, LineHeight = 1.3, LayoutOrder = 2 })
    end
    local btnRow = Frame({ Size = UDim2.new(1, 0, 0, 38), LayoutOrder = 3, Parent = inner })
    local fakeContainer = { Window = win or { _s = function() return 1 end, _showTooltip = function() end, _hideTooltip = function() end } }
    local closed = false
    local escConn
    local function closeDialog()
        if closed then return end
        closed = true
        if escConn then escConn:Disconnect() end
        setFaded(scrim, 1)
        tween(scale, 0.12, { Scale = 0.96 })
        task.delay(0.16, function() pcall(scrim.Destroy, scrim) end)
    end
    local cols = cancel and 2 or 1
    local function col(i)
        return Frame({ Size = UDim2.new(1 / cols, cols == 2 and -4 or 0, 1, 0), Position = UDim2.new((i - 1) / cols, i == 2 and 4 or 0, 0, 0), Parent = btnRow })
    end
    if cancel then
        makeButton(fakeContainer, col(1), { Name = cancel.Text or "Cancel", Variant = cancel.Variant or "Secondary", Fill = true, Height = 38,
            Callback = function() closeDialog(); safeCall(cancel.Callback) end }, 1)
    end
    local cVariant = confirm.Variant or "Primary"
    local cb = makeButton(fakeContainer, col(cols), { Name = confirm.Text or "Confirm", Variant = cVariant == "Danger" and "Primary" or cVariant, Fill = true, Height = 38,
        Callback = function() closeDialog(); safeCall(confirm.Callback) end }, 2)
    if cVariant == "Danger" then
        -- filled danger button: Danger background, AccentFg text (matches the mockup)
        bind(cb.Button, { BackgroundColor3 = function(t) return t.Danger, 0 end })
        for _, d in ipairs(cb.Button:GetDescendants()) do
            if d:IsA("UIStroke") then bind(d, { Color = function(t) return t.Danger, 0 end }) end
        end
        for _, d in ipairs(cb.Root:GetChildren()) do if d.Name == "BtnShadow" then d:Destroy() end end
    end
    followSize(wrap, card, function() return win and win:_s() or 1 end)
    wrap.Size = UDim2.fromOffset(400, 180)
    card.Size = UDim2.new(0, 400, 0, 0)
    if o.DismissOnScrim then
        scrim.InputBegan:Connect(function(input)
            if not isPointerDown(input) then return end
            if not inRect(pointerPos(input), card) then closeDialog(); if cancel then safeCall(cancel.Callback) end end
        end)
    end
    escConn = UserInputService.InputBegan:Connect(function(input)
        if input.KeyCode == Enum.KeyCode.Escape then closeDialog(); if cancel then safeCall(cancel.Callback) end end
    end)
    -- enter animation
    FadeMap[scrim] = 1
    for _, d in ipairs(scrim:GetDescendants()) do FadeMap[d] = 1; restyle(d) end
    restyle(scrim)
    task.defer(function() if not closed then setFaded(scrim, 0); tween(scale, 0.18, { Scale = 1 }) end end)
    return { Close = closeDialog }
end

function Window:Dialog(o)
    self:_closePopup()
    return buildDialog(self.Overlay, self, o)
end

function Sypse:Dialog(o)
    local w = Library.ActiveWindow
    if w and w.Alive and w.Visible then return w:Dialog(o) end
    local host = getOverlay()
    return buildDialog(host, nil, o)
end

function Window:Notify(o) return Sypse:Notify(o) end

-- Floating watermark + keybind HUD -----------------------------------------------
function Window:SetWatermark(on)
    if not on then
        if self._wm then self._wm:Destroy(); self._wm = nil; self._wmFps = nil; self._wmPing = nil end
        return
    end
    if self._wm then return end
    local g = getOverlay()
    local holder = Frame({ Name = "Watermark", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -26, 0, 22),
        AutomaticSize = Enum.AutomaticSize.XY, Parent = g })
    List(holder, "y", 8, { HorizontalAlignment = Enum.HorizontalAlignment.Right })
    self._wm = holder
    local pill = Button({ Name = "Pill", AutomaticSize = Enum.AutomaticSize.XY, LayoutOrder = 1, Parent = holder, Theme = { BackgroundColor3 = "Panel3" } })
    Corner(pill, "CornerRadiusSmall"); Stroke(pill, "Stroke"); Pad(pill, 8, 13)
    List(pill, "x", 10, { VerticalAlignment = Enum.VerticalAlignment.Center })
    local dot = Frame({ Size = UDim2.fromOffset(7, 7), LayoutOrder = 1, Parent = pill, Theme = { BackgroundColor3 = function(t) return t.Ok end } })
    dot.BackgroundTransparency = 0.5
    Corner(dot, "full")
    pcall(function() TweenService:Create(dot, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { BackgroundTransparency = 0 }):Play() end)
    self._wmTitle = Label(pill, { Text = self.Title, TextSize = 12, Weight = "SemiBold", Case = "theme", LayoutOrder = 2 })
    local ver = self.Options.Version or (self.Options.Subtitle and tostring(self.Options.Subtitle):match("^v%d") and self.Options.Subtitle) or ("v" .. Sypse.Version)
    Label(pill, { Text = ver, TextSize = 11, Mono = true, Color = "Dim", LayoutOrder = 3 })
    Frame({ Size = UDim2.fromOffset(1, 12), BackgroundTransparency = 0, LayoutOrder = 4, Parent = pill, Theme = { BackgroundColor3 = "Stroke" } })
    self._wmFps = Label(pill, { Text = "— fps", TextSize = 11, Mono = true, Color = "Dim", LayoutOrder = 5 })
    self._wmPing = Label(pill, { Text = "— ms", TextSize = 11, Mono = true, Color = "Dim", LayoutOrder = 6 })

    local hud = Frame({ Name = "Keybinds", AutomaticSize = Enum.AutomaticSize.XY, LayoutOrder = 2, Parent = holder, Theme = { BackgroundColor3 = "Panel3" } })
    Corner(hud, "CornerRadiusSmall"); Stroke(hud, "Stroke"); Pad(hud, 9, 12)
    List(hud, "y", 5)
    Label(hud, { Text = "Keybinds", TextSize = 9, Weight = "SemiBold", Mono = true, Case = "upper", Color = "Dim", LayoutOrder = 0 })
    self._hud = hud
    self:_refreshHUD()

    -- drag the stack; a click without movement toggles the window (touch-friendly)
    local dragInput, startP, startPos, moved
    pill.InputBegan:Connect(function(input)
        if not isPointerDown(input) then return end
        dragInput, moved = input, false
        startP = pointerPos(input)
        local off = absToOffset(holder.AbsolutePosition)
        holder.AnchorPoint = Vector2.zero
        holder.Position = UDim2.fromOffset(off.X, off.Y)
        startPos = off
    end)
    self.Maid:Give(UserInputService.InputChanged:Connect(function(input)
        if not dragInput then return end
        if (input.UserInputType == Enum.UserInputType.MouseMovement and dragInput.UserInputType == Enum.UserInputType.MouseButton1) or input == dragInput then
            local d = pointerPos(input) - startP
            if d.Magnitude > 4 then moved = true end
            local vp = g.AbsoluteSize
            holder.Position = UDim2.fromOffset(clamp(startPos.X + d.X, 0, math.max(0, vp.X - holder.AbsoluteSize.X)),
                clamp(startPos.Y + d.Y, 0, math.max(0, vp.Y - holder.AbsoluteSize.Y)))
        end
    end))
    self.Maid:Give(UserInputService.InputEnded:Connect(function(input)
        if dragInput and (input == dragInput or input.UserInputType == Enum.UserInputType.MouseButton1) then
            dragInput = nil
            if not moved then self:Toggle() end
        end
    end))
end

function Window:_refreshHUD()
    local hud = self._hud
    if not hud or not hud.Parent then return end
    for _, c in ipairs(hud:GetChildren()) do if c.Name == "Bind" then c:Destroy() end end
    local function row(name, key, order)
        local r = Frame({ Name = "Bind", Size = UDim2.fromOffset(150, 18), LayoutOrder = order, Parent = hud })
        Label(r, { Text = name, TextSize = 11, Color = "Dim", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, -60, 1, 0), Truncate = true })
        local chip = Frame({ AutomaticSize = Enum.AutomaticSize.XY, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), Parent = r,
            Theme = { BackgroundColor3 = "Panel2" } })
        Corner(chip, 5); Pad(chip, 3, 6); Stroke(chip, "Stroke", 1)
        Label(chip, { Text = key, TextSize = 10, Weight = "Medium", Mono = true })
    end
    row("Menu", keyName(self.ToggleKey), 1)
    local i = 1
    for _, kb in ipairs(self.Keybinds) do
        if not kb.MenuKey and kb.Value and kb._opts.HUD ~= false then
            i += 1
            row(kb._opts.HudName or kb.Name, keyName(kb.Value), i)
        end
    end
end

--==============================================================================
-- §13  CONFIG PERSISTENCE
--==============================================================================

local MemoryFS = {} -- folder → { name → json } (fallback without file I/O)

local function normName(name)
    name = tostring(name or "default.json"):gsub("[/\\]", "_")
    if name == "" then name = "default.json" end
    if not name:lower():match("%.json$") then name = name .. ".json" end
    return name
end

local function encodeValue(v)
    local ty = typeof(v)
    if ty == "Color3" then return { __t = "Color3", v = v:ToHex() } end
    if ty == "EnumItem" then return { __t = "Enum", e = tostring(v.EnumType), n = v.Name } end
    if ty == "table" then
        local o = {}
        for k, x in pairs(v) do o[k] = encodeValue(x) end
        return o
    end
    if ty == "number" or ty == "string" or ty == "boolean" then return v end
    return nil
end

local function decodeValue(v)
    if type(v) ~= "table" then return v end
    if v.__t == "Color3" then local ok, c = pcall(Color3.fromHex, v.v); return ok and c or nil end
    if v.__t == "Enum" then
        local ok, e = pcall(function() return Enum[v.e][v.n] end)
        return ok and e or nil
    end
    local o = {}
    for k, x in pairs(v) do o[k] = decodeValue(x) end
    return o
end

function Sypse:SerializeFlags()
    local flags, risky = {}, false
    for flag, ctl in pairs(Library.Options) do
        local val
        if ctl.Type == "ColorPicker" then
            val = { __t = "Color3", v = ctl.Value:ToHex(), tr = ctl.Transparency }
        else
            val = encodeValue(ctl:_flagValue())
        end
        flags[flag] = val
        if ctl.Risky then
            local v = ctl:_flagValue()
            if v == true or (type(v) == "number" and v ~= 0) then risky = true end
        end
    end
    return { __sypse = Sypse.Version, __theme = CurrentTheme.Name, __risky = risky, flags = flags }
end

function Sypse:ExportConfig()
    return HttpService:JSONEncode(self:SerializeFlags())
end

function Sypse:ApplyConfig(data, applyTheme)
    if type(data) == "string" then
        local ok, d = pcall(HttpService.JSONDecode, HttpService, data)
        if not ok then return false, "invalid JSON" end
        data = d
    end
    if type(data) ~= "table" or type(data.flags) ~= "table" then return false, "not a Sypse config" end
    for flag, raw in pairs(data.flags) do
        local ctl = Library.Options[flag]
        if ctl then
            local ok, err = pcall(function()
                if ctl.Type == "ColorPicker" and type(raw) == "table" then
                    local c = decodeValue({ __t = "Color3", v = raw.v })
                    ctl:Set(c, raw.tr ~= nil and (1 - raw.tr) or nil)
                elseif ctl.Type == "Range" and type(raw) == "table" then
                    ctl:Set(raw[1], raw[2])
                else
                    ctl:Set(decodeValue(raw))
                end
            end)
            if not ok then warn("[Sypse] could not apply flag " .. flag .. ": " .. tostring(err)) end
        end
    end
    if applyTheme and data.__theme and Themes[data.__theme] then self:SetTheme(data.__theme) end
    return true
end

local function ensureFolder(folder)
    if Env.isfolder and Env.makefolder then
        local ok, exists = pcall(Env.isfolder, folder)
        if ok and not exists then pcall(Env.makefolder, folder) end
    end
end

function Sypse:SaveConfig(name, folder)
    folder = folder or "SypseUI"
    name = normName(name)
    local ok, json = pcall(function() return self:ExportConfig() end)
    if not ok then return false, json end
    if Env.HasFileIO then
        ensureFolder(folder)
        local wok, err = pcall(Env.writefile, folder .. "/" .. name, json)
        if not wok then return false, err end
    else
        MemoryFS[folder] = MemoryFS[folder] or {}
        MemoryFS[folder][name] = json
    end
    self:Log("OK", folder .. "/" .. name .. " saved")
    return true, name
end

function Sypse:ReadConfig(name, folder)
    folder = folder or "SypseUI"
    name = normName(name)
    if Env.HasFileIO then
        local path = folder .. "/" .. name
        if Env.isfile then
            local ok, exists = pcall(Env.isfile, path)
            if ok and not exists then return nil, "file not found" end
        end
        local ok, content = pcall(Env.readfile, path)
        if not ok then return nil, content end
        return content
    end
    local m = MemoryFS[folder]
    if m and m[name] then return m[name] end
    return nil, "profile not found"
end

function Sypse:LoadConfig(name, folder)
    local json, err = self:ReadConfig(name, folder)
    if not json then return false, err end
    local ok, e = self:ApplyConfig(json)
    if ok then self:Log("OK", normName(name) .. " restored") end
    return ok, e
end

function Sypse:ListConfigs(folder)
    folder = folder or "SypseUI"
    local out = {}
    if Env.HasFileIO and Env.listfiles then
        ensureFolder(folder)
        local ok, files = pcall(Env.listfiles, folder)
        if ok and type(files) == "table" then
            for _, f in ipairs(files) do
                local base = tostring(f):match("([^/\\]+)$")
                if base and base:lower():match("%.json$") then table.insert(out, base) end
            end
        end
    else
        for n in pairs(MemoryFS[folder] or {}) do table.insert(out, n) end
    end
    table.sort(out)
    return out
end

function Sypse:ConfigInfo(name, folder)
    local json = self:ReadConfig(name, folder)
    local info = { keys = 0, size = "0 B", risky = false }
    if not json then return info end
    local bytes = #json
    info.size = bytes >= 1024 and (math.ceil(bytes / 1024) .. " KB") or (bytes .. " B")
    local ok, d = pcall(HttpService.JSONDecode, HttpService, json)
    if ok and type(d) == "table" and type(d.flags) == "table" then
        for _ in pairs(d.flags) do info.keys += 1 end
        info.risky = d.__risky == true
    end
    return info
end

function Sypse:DeleteConfig(name, folder)
    folder = folder or "SypseUI"
    name = normName(name)
    if Env.HasFileIO then
        if not Env.delfile then return false, "delfile unavailable" end
        local ok, err = pcall(Env.delfile, folder .. "/" .. name)
        return ok, err
    end
    local m = MemoryFS[folder]
    if m and m[name] then m[name] = nil return true end
    return false, "not found"
end

function Window:SaveConfig(name)
    local ok, res = Sypse:SaveConfig(name or self.Profile, self.ConfigFolder)
    if ok then self.Profile = res; self:SetStatus("attached · " .. res) end
    return ok, res
end
function Window:LoadConfig(name)
    local ok, err = Sypse:LoadConfig(name or self.Profile, self.ConfigFolder)
    if ok then self.Profile = normName(name or self.Profile); self:SetStatus("attached · " .. self.Profile) end
    return ok, err
end
function Window:ListConfigs() return Sypse:ListConfigs(self.ConfigFolder) end
function Window:DeleteConfig(name) return Sypse:DeleteConfig(name, self.ConfigFolder) end

--==============================================================================
-- §14  PUBLIC API
--==============================================================================

local function findTheme(theme)
    if type(theme) == "string" then
        if Themes[theme] then return Themes[theme] end
        for k, v in pairs(Themes) do if string.lower(k) == string.lower(theme) then return v end end
        return nil
    end
    if type(theme) == "table" then
        for _, v in pairs(Themes) do if v == theme then return v end end
        return completeTheme(theme)
    end
    return nil
end

--- Switch theme at runtime. Every live element restyles (tweened ~0.15 s).
function Sypse:SetTheme(theme, instant)
    local t = findTheme(theme)
    if not t then
        warn("[Sypse] unknown theme: " .. tostring(theme))
        return false
    end
    CurrentTheme = t
    Sypse.Theme = t
    Sypse.ThemeName = t.Name
    applyThemeEverywhere(instant and 0 or 0.15)
    return true
end

function Sypse:GetTheme() return CurrentTheme end

--- Register a custom theme. Partial tables are merged over `Base` (default Acrylic).
function Sypse:RegisterTheme(name, tbl)
    tbl = tbl or {}
    local base = tbl.Base and findTheme(tbl.Base) or Themes.Acrylic
    local t = completeTheme(merge(tbl, { Name = name }), base)
    t.Base = nil
    Themes[name] = t
    if not table.find(THEME_ORDER, name) then table.insert(THEME_ORDER, name) end
    return t
end

--- Theme names in picker order (built-ins first, then registered themes).
function Sypse:GetThemeNames()
    local out = {}
    for _, n in ipairs(THEME_ORDER) do if Themes[n] then table.insert(out, n) end end
    for n in pairs(Themes) do if not table.find(out, n) then table.insert(out, n) end end
    return out
end

--- Append a line to every console viewer. Levels: INFO, OK, WARN, ERR.
function Sypse:Log(level, message)
    local e = { time = timestamp(), level = normLevel(level), msg = tostring(message) }
    table.insert(Library.Logs, e)
    while #Library.Logs > 500 do table.remove(Library.Logs, 1) end
    for _, fn in pairs(Library.LogSubscribers) do pcall(fn, e) end
    return e
end

--- Mirror LogService output (print / warn / errors) into the console viewers.
function Sypse:HookLogService(enable)
    if enable == false then
        if Library.LogHook then Library.LogHook:Disconnect(); Library.LogHook = nil end
        return
    end
    if Library.LogHook then return end
    Library.LogHook = LogService.MessageOut:Connect(function(msg, mtype)
        if string.find(msg, "[Sypse]", 1, true) then return end
        local lvl = "INFO"
        if mtype == Enum.MessageType.MessageWarning then lvl = "WARN"
        elseif mtype == Enum.MessageType.MessageError then lvl = "ERR" end
        Sypse:Log(lvl, msg)
    end)
    Library.Maid:Give(Library.LogHook)
end

--- Managed repeating timer; stopped automatically by Sypse:Destroy().
function Sypse:Every(seconds, fn)
    local alive = true
    local th = task.spawn(function()
        while alive do
            task.wait(seconds)
            if not alive then break end
            local ok, err = pcall(fn)
            if not ok then warn("[Sypse] Every: " .. tostring(err)) end
        end
    end)
    local function stop() alive = false; pcall(task.cancel, th) end
    Library.Maid:Give(stop)
    return stop
end

--[[ Sypse:SetBlur(mode [, size])
     Sets the background blur for every open window and the default for new ones.
       false    (default) never blur
       true     blur under every theme
       "theme"  follow each theme's Blur token (Acrylic only, out of the box)
     `size` is the BlurEffect size (default 10); false or "theme" clears a pinned
     size so each theme's own BlurSize token applies. ]]
function Sypse:SetBlur(mode, size)
    if mode == nil then mode = true end
    Library.DefaultBlur = mode
    if type(size) == "number" then Library.DefaultBlurSize = size end
    for _, w in ipairs(Library.Windows) do
        if w.Alive then w:SetBlur(mode, size) end
    end
    return mode
end

function Sypse:GetBlur() return Library.DefaultBlur, Library.DefaultBlurSize end

function Sypse:Toggle()
    local w = Library.ActiveWindow
    if w then w:Toggle() end
end

function Sypse:GetWindows() return Library.Windows end

--- Destroy every window, overlay, connection and timer the library created.
function Sypse:Destroy()
    for i = #Library.Windows, 1, -1 do pcall(function() Library.Windows[i]:Destroy() end) end
    Library.Maid:Clean()
    Library.Telemetry.running = false
    Library.Telemetry.subs = {}
    Library.LogHook = nil
    Library.Overlay = nil
    table.clear(Library.LogSubscribers)
    table.clear(Registry)
    RegistryCount = 0
end

Sypse.Env = Env

return Sypse