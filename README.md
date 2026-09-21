# Sypse UI

A themeable Roblox UI library in a single Luau `ModuleScript`. Pure `Instance` UI (no Roact / Fusion), six complete themes that re-skin live, and a full component set: tabs, segments, accordions, toggles, sliders, range sliders, dropdowns, inputs, keybinds, colour pickers, toasts, dialogs, console, player grid, config manager and a floating watermark/keybind HUD.

## Installation

**Studio.** Create a `ModuleScript` named `SypseUI`, paste `SypseUI.lua` into it, and put it next to a `LocalScript` (for example in `StarterPlayerScripts`). Paste `demo.lua` into the LocalScript and press Play.

```lua
local Sypse = require(script.Parent:WaitForChild("SypseUI"))
```

**Loader environments.** Host `SypseUI.lua` somewhere raw and load it with `loadstring`:

```lua
local Sypse = loadstring(game:HttpGet("https://raw.githubusercontent.com/Sypse/Sypse-UI/refs/heads/main/SypseUI.lua"))()
```

The library parents to `gethui()` when available, then `CoreGui` if the script has permission, and otherwise `PlayerGui`. Executor globals (`writefile`, `readfile`, `listfiles`, `delfile`, `setclipboard`, `gethui`, `syn.protect_gui`, `cloneref`) are all feature-detected. Without file I/O, configs are kept in memory for the session; without a clipboard, Export prints the JSON to the output.

## Quick start

```lua
local win = Sypse:CreateWindow({
    Title = "Sypse UI", Version = "v1.1.0", Subtitle = "attached to · Blade Arena",
    Theme = "Acrylic", Size = UDim2.fromOffset(980, 620),
    ToggleKey = Enum.KeyCode.RightShift, LiveStats = true,
})

local combat  = win:AddTab({ Name = "Combat", Icon = "circle", Count = 12 })
local general = combat:AddSegment("General")
local aim     = general:AddSection("Aim assist", { Badge = { Text = "RISKY", Kind = "danger" } })

aim:AddToggle({ Name = "Enabled", Description = "Runs on RenderStepped", Tooltip = "Hover text", Default = true, Flag = "enabled",
    Callback = function(on) print(on) end })
aim:AddSlider({ Name = "Smoothness", Min = 0, Max = 100, Default = 42, Flag = "smooth" })

Sypse:SetTheme("Terminal")          -- everything restyles immediately
print(Sypse.Flags.smooth)            --> 42
win:SaveConfig("legit.json")
```

## API

### Library

| Call | Description |
|---|---|
| `Sypse:CreateWindow(opts)` | Creates a window. See window options below. |
| `Sypse:SetTheme(nameOrTable [, instant])` | Switches theme; every live element restyles (tweened ~0.15 s). Accepts a name, a `Sypse.Themes` entry, or a partial table. |
| `Sypse:RegisterTheme(name, tokens)` | Adds a theme. Partial tables merge over `tokens.Base` (default `"Acrylic"`). |
| `Sypse:GetTheme()` / `Sypse:GetThemeNames()` | Current theme table / ordered names for pickers. |
| `Sypse.Themes` | Public table of themes keyed by name. |
| `Sypse.Flags` / `Sypse.Options` | Flag → value, and flag → control handle. |
| `Sypse:Notify({ Title, Body, Kind, Duration })` | Toast. `Kind`: `info`/`accent`, `ok`, `warn`, `danger`. Max 4 stacked, 4.2 s default. |
| `Sypse:Dialog({ Title, Body, Icon, Confirm, Cancel, DismissOnScrim })` | Blocking modal. `Confirm = { Text, Variant, Callback }`, `Cancel = { Text, Callback }`. Escape cancels. |
| `Sypse:Log(level, message)` | Appends to every console. Levels `INFO`, `OK`, `WARN`, `ERR`. |
| `Sypse:HookLogService([enable])` | Mirrors `print`/`warn`/errors into the console. |
| `Sypse:Every(seconds, fn)` | Managed repeating timer, returns `stop()`. Stopped by `Destroy`. |
| `Sypse:SaveConfig / LoadConfig / ListConfigs / DeleteConfig (name, folder)` | Flag persistence as JSON. |
| `Sypse:ExportConfig()` / `Sypse:ApplyConfig(jsonOrTable)` | Serialise / apply without touching disk. |
| `Sypse:SetBlur(mode [, size])` | Background blur for every open window and the default for new ones. `false` (default), `true` (all themes), `"theme"` (follow each theme's `Blur` token). `size` pins a blur size; `false` or `"theme"` unpins it so each theme's `BlurSize` applies. `Sypse:GetBlur()` reads it back. |
| `Sypse:Toggle()` / `Sypse:Destroy()` | Toggle the active window / tear down everything (instances, connections, timers). |
| `Sypse.Tracking = false` | Disables hair-space letter tracking (see Notes). |

### Window options

`Title`, `Version` (badge), `Subtitle` (dim mono line; a `Subtitle` that looks like `v1.0` becomes the badge), `Icon` (app-square letter), `Theme`, `Size`, `ToggleKey`, `LiveStats` (FPS / ping / memory / position cards on every page), `ConfirmClose`, `OnClose`, `AutosaveFlag` (save on close when that flag is true), `ConfigFolder` (`"SypseUI"`), `Profile` (`"default.json"`), `User = { Name, Sub, Initials }`, `Status`, `Watermark` (default on), `Blur` (`false` default / `true` / `"theme"`), `BlurSize` (10), `Scale`, `Parent`, `DisplayOrder`.

### Window methods

`AddTab(opts)`, `SelectTab(tabOrName)`, `SetVisible(bool)`, `Toggle()`, `Minimize()`, `Maximize()`, `Close()`, `Destroy()`, `SetTitle(text)`, `SetStatus(text, kind)`, `SetToggleKey(key)`, `SetWatermark(bool)`, `SetBlur(mode [, size])`, `GetBlur()`, `BlurEnabled()`, `Notify(opts)`, `Dialog(opts)`, `SaveConfig(name)`, `LoadConfig(name)`, `ListConfigs()`, `DeleteConfig(name)`.

### Tabs and containers

`win:AddTab({ Name, Icon, Count })` returns a tab. `Icon` is `"circle"`, `"square"`, `"diamond"`, an `rbxassetid://` image, or a text glyph. `tab:AddSegment(name)` adds a segmented sub-tab and returns a container. You can also call any `Add*` directly on a tab; it goes to an implicit page. `tab:SetCount(n)`, `tab:SelectSegment(nameOrPage)`.

Every container (page, section, column, accordion) supports:

| Method | Notes |
|---|---|
| `AddSection(name, { Badge, Gap })` | Uppercase tracked header + hairline. Returns a container for the section's rows. |
| `AddColumns(2)` / `AddColumns({ "1fr", 250 })` | Numbers are fixed px, anything else is a flexible share. Returns an array of containers. |
| `AddAccordion({ Name, Badge, Open, Count })` | Collapsible, tweened height, "N settings" count. Children render compact. |
| `AddToggle({ Name, Description, Tooltip, Badge, Default, Flag, Callback, Locked, Checkbox, Risky })` | 44×24 switch. `Checkbox = true` or `AddCheckbox` for the 20 px variant. |
| `AddSlider({ Name, Min, Max, Step, Default, Suffix, Chip, Color, Format, Flag, Callback })` | Drag and click-to-jump. `Color = "Accent2"` for the alternate fill. |
| `AddRangeSlider({ Name, Min, Max, Step, Default = {lo, hi}, MinGap = 5, Suffix, Note, Flag, Callback(lo, hi) })` | Two thumbs, Accent2 fill. |
| `AddDropdown({ Name, Options, Default, Searchable, Placeholder, Flag, Callback })` | Popup closes on outside click. `:Refresh(values, keep)`. |
| `AddDropdown({ …, Multi = true })` | Removable chips with `+` / `×`; `Searchable` adds a filter field. `Get()` returns a list. |
| `AddInput({ Name, Default, Placeholder, Numeric, Min, Max, Password, MultiLine, Width, Finished, Callback, OnFocusLost })` | Numeric rejects non-numbers and right-aligns. Password is masked. |
| `AddKeybind({ Name, Default, Mode = "Press" | "Toggle" | "Hold", Hint, MenuKey, HUD, HudName, Callback, ChangedCallback, Flag })` | Click, press any key or mouse button. Escape cancels, Backspace clears. `MenuKey = true` rebinds the window toggle. |
| `AddColorPicker({ Name, Default, Alpha, Expanded, Flag, Callback(color, transparency) })` | SV square, hue strip, alpha strip, HEX and A fields. `Alpha` is opacity 0–1. |
| `AddButton({ Name, Variant, Callback, DoubleClick, Disabled, Icon, Fill, Tooltip, Align })` | Variants: `Primary`, `Secondary`, `Ghost`, `Danger`, `Ok`, `Warn`, `Icon`. |
| `AddButtonRow({ {…}, {…, Align = "Right"} }, { Height, Gap })` | Several buttons on one row; right-aligned group supported. Rows wrap onto more lines when they run out of width, and no button can grow wider than the row (long labels clip), so buttons never overlap or spill past the window — which matters in uppercase themes where tracking widens labels. |
| `AddLabel(text)` / `AddParagraph({ Title, Body })` / `AddDivider()` / `AddSpacer(px)` | Text blocks. |
| `AddBadges({ { Text, Kind }, … })` | Mono chips: `accent`, `ok`, `warn`, `danger`, `dim`. |
| `AddProgress({ Name, Default, Spinner, Color })` | `:Set(0–100)`. |
| `AddSpinner(style)` / `AddSpinners()` | `ring`, `thin`, `dots`. |
| `AddStatCards({ { Label, Value, Note, Kind }, … })` / `AddLiveStats()` | 4-up cards; live version wired to real FPS, ping, memory, position. |
| `AddConsole({ Height, HookLogService, MaxLines })` | Timestamped levels, filter pills, Clear, blinking caret. |
| `AddSearchBar({ Placeholder, Target, Total, Callback })` | Debounced; `Target` is any handle with `:Filter(q)` (console, player grid, page). |
| `AddPlayerGrid({ Items = "live" or list, Actions, Search, Columns, Default, OnSelect })` | Avatar thumbnails with striped placeholders, status dot, tag. Actions receive the selected item. |
| `AddTree({ Name, Root, Depth, Filter, OnSelect, Height, MaxNodes })` | Collapsible Explorer-style hierarchy. `Root` is a live `Instance` (children walked lazily on expand — pointing it at `game` never recurses the DataModel) or a plain nested Lua table, which makes it a JSON/config viewer. Class-coloured icons, child counts, click to select and expand. `:Refresh()`, `:Expand(path)`, `:Collapse(path)`, `:Select(x)`, `:GetSelected()`, `:SetRoot(x)`, `:Filter(q)`. |
| `AddGraph({ Name, Series, Window = 60, Interval = 1, Height, Sparklines })` | Rolling line chart with a filled area, a dot on the latest sample, peak/low labels and auto-scaled Y. `Series = { { Name, Color, Get = fn } }`; more than one adds a segmented switch plus compact sparklines. Samples on a timer, never RenderStepped, and draws from a reused pool of rotated frames. The curve is Catmull-Rom smoothed (`Smooth = false` for raw straight segments). `:Push(series, value)`, `:Clear()`, `:SetSeries(name)`, `:GetSeries()`, `:Redraw()`. |
| `AddRadar({ Name, Range, Ranges, Shape, Rotate, MaxWidth })` | Circular (or `Shape = "square"`) minimap: range rings, crosshair, sweeping accent line, ringed player dot. Blips beyond range clamp to the edge, shrink and fade. `Rotate = true` turns blips with the camera yaw so "up" is where you face (it only affects blip orientation — the sweep animates either way; `Sweep = false` / `SweepTime` control that). The square variant clamps on the max-norm, so a diagonal outlier lands in the corner. Blips are **offsets from your position**, so something has to recompute them as things move: pass `Track = "players"` (every other player, polled ~10×/s) or `Get = function() … end` for your own source, with `Interval`, `Origin` and `KindFor` to tune it. Feeding a fixed list with `:SetPoints` leaves the blips where you put them. `:SetPoints(list)`, `:SetRange(n)`, `:GetRange()`, `:Poll()`. |
| `AddTable({ Name, Columns, Rows, Sort, Height, OnSelect, Zebra })` | Sortable grid with a pinned header, zebra rows and a selection bar. Columns take `Key, Label, Width ("2fr" or px), Numeric, Align, Format(v, row), Color(v, row)` for conditional colouring. Click a header to sort (toggles asc/desc, arrow on the active column). `:SetRows()`, `:AddRow()`, `:Sort(key, dir)`, `:Select(row)`, `:GetSelected()`, `:Filter(q)`. |
| `AddConfigManager({ Folder })` | Profile list with ACTIVE / SAVED / RISKY tags, filename field, Save / Load / Export / Delete. |

Every control handle has `:Set(value)`, `:Get()`, `:SetVisible(bool)`, `:SetLocked(bool)`, `:OnChanged(fn)` and `:Destroy()`. Controls with a `Flag` write to `Sypse.Flags[flag]` and are saved by the config system. A colour picker also writes `Flags[flag .. "Transparency"]`. Controls marked `Risky = true` make a saved profile show the RISKY tag when they are on.

The title-bar filter box (focus it with `/`) filters the current page's controls by name.

## Themes

Ten built-ins: **Acrylic** (dark glass), **Daylight** (light dashboard), **Terminal** (monospace, uppercase), **Voltage** (neon, glow), **Marshmallow** (soft pastel, round), **Blocky** (chunky 2.5 px borders, hard offset shadow), **Ember** (warm amber dark, soft drop + amber halo), **Paper** (high-contrast print: zero radius, 1.5 px black borders, uppercase, black accent), **Abyss** (deep teal, big radius, inner top highlight, optional 14 px blur), **Cassette** (VHS retro with a chromatic-aberration shadow). A theme change swaps colours, fonts, corner radius, stroke thickness, shadow style and text casing.

### Token reference

Any `Color3` token can be paired with `<Token>Transparency` (0 = opaque, 1 = invisible). Missing transparency tokens mean opaque.

| Token | Purpose |
|---|---|
| `Background` (+ `BackgroundGradient`) | Window base layer under `Panel`; gives Acrylic its tinted glass. The gradient is `{ c1, c2, c3, Rotation = deg, Mid = 0..1 }`, where `Rotation` is CSS degrees − 90 (0 = left→right, 90 = top→bottom). |
| `Stage` | Reserved (the mockup's page backdrop); kept for round-tripping. |
| `Panel` | Window body. |
| `Panel2` | Raised controls: fields, secondary buttons, title bar. |
| `Panel3` | Recessed rows, cards, sidebar, status bar. |
| `Stroke`, `Stroke2` | Primary borders / subtle dividers. |
| `Track`, `Knob` | Slider track and switch off-state / thumbs and knobs. |
| `Text`, `Dim` | Primary / muted text. |
| `Tooltip` | Tooltip, dropdown popup and toast background. |
| `Console`, `ConsoleText` | Log viewer background and text. |
| `Accent`, `AccentFg`, `AccentSoft`, `AccentLine` | Primary action colour, text on it, 10–15 % tint, ~30 % border. |
| `Accent2` | Secondary accent (range sliders, thin spinner). |
| `Ok` / `OkSoft` / `OkLine`, `Warn` / …, `Danger` / … | Semantic colours with the same soft/line convention. |
| `Placeholder`, `Placeholder2` | Stripes on loading thumbnails. |
| `Scrim` | Modal backdrop. |
| `Font`, `FontMono` | Family name (`"Nunito"`), asset path, `rbxassetid://` family, `Font` object, or `Enum.Font`. |
| `CornerRadius`, `CornerRadiusSmall` | Radius in px for window/modals and rows/buttons/fields. |
| `StrokeThickness` | `UIStroke.Thickness` for primary borders. |
| `Shadow` | `"soft"`, `"none"`, `"glow"`, `"hard"`, `"chroma"` (two solid offset blocks over a soft drop — the VHS look). With `ShadowColor`, `ShadowTransparency`, `ShadowOffset` (Vector2, hard only). |
| `ShadowGlow`, `ShadowGlowTransparency` | Optional halo layered on top of a soft shadow (Ember). Independent of `Shadow = "glow"`. |
| `ShadowChromaA` / `ShadowChromaB` (+ `…Transparency`, `…Offset`) | The two blocks of a `"chroma"` shadow. |
| `InnerHighlight`, `InnerHighlightTransparency` | 1 px highlight along the window's top edge (Abyss). Omit for none. |
| `BlurSize` | Blur size used when a window is in `"theme"` blur mode without a pinned size. |
| `ButtonShadow` | `"none"`, `"hard"`, `"glow"`, `"chroma"` under primary buttons. |
| `Blur` | Only consulted in `"theme"` blur mode; windows default to no blur. |
| `TextCase` | `"none"` or `"upper"` for buttons, tab labels, section headers and titles. |
| `LetterSpacing` | Tracking for uppercase themes, in hair-space units. |

### Adding a custom theme

```lua
Sypse:RegisterTheme("Midnight Cyan", {
    Base = "Voltage",                       -- optional, defaults to Acrylic
    Accent = Color3.fromHex("22E7FF"),
    AccentFg = Color3.fromHex("001318"),
    AccentSoft = Color3.fromHex("22E7FF"), AccentSoftTransparency = 0.86,
    CornerRadius = 4, CornerRadiusSmall = 3,
})
Sypse:SetTheme("Midnight Cyan")
```

Only the tokens you list change. If you override a colour without its `…Transparency`, that transparency resets to opaque, so an overridden `Panel` doesn't silently inherit Acrylic's 0.945 glass value. Registered themes appear in `Sypse:GetThemeNames()`, so a theme-picker dropdown picks them up automatically.

To edit a built-in theme, change its table in §4 of `SypseUI.lua`; the section is commented token by token.

## Notes and substitutions

**Fonts.** The mockup's web fonts are not Roblox built-ins, so the themes use the nearest ones: Sora → GothamSSm, IBM Plex Sans → BuilderSans, IBM Plex Mono → RobotoMono, JetBrains Mono → Inconsolata (`Enum.Font.Code`), Chakra Petch → TitilliumWeb, Fredoka → FredokaOne, and Nunito is built in. Upload the real fonts and put their `rbxassetid://` family ids in the theme for a pixel match. Unknown fonts fall back to GothamSSm and never error.

**Roblox limits.** Roblox can't blur UI behind UI, so Acrylic's glass is a translucent panel over a tinted base. The optional background blur is a `BlurEffect` on the camera, which blurs the 3D world behind the window; it is off by default and controlled per window (`Blur` option / `win:SetBlur`) or globally (`Sypse:SetBlur`), independently of the theme. Soft and glow shadows are stacked translucent rounded frames. Hard shadows are a solid offset frame. There is no letter-spacing property, so tracking inserts U+200A hair spaces; set `Sypse.Tracking = false` if a font renders them badly. The window body is a `CanvasGroup` so children clip to rounded corners (it falls back to a clipped `Frame` if unavailable).

**Engineering.** Every themed property goes through one token registry, which is what lets `SetTheme` restyle live UI, including state-dependent styling such as a switch that is on. All `UserInputService` connections are tracked and disconnected on `Destroy`; drag handlers connect on press and disconnect on release. There is one shared `RenderStepped` counter for FPS, ping, memory and position. Spinners and blinking carets use infinite tweens rather than per-frame loops.