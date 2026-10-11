--[[
    Airflow UI library (Roblox / Luau)
    Version lisible : le code d'origine était minifié (variables d'une lettre).
    Seuls les noms, l'indentation et les commentaires ont changé ; la logique est la même.
]]

--// Services
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService       = game:GetService("GuiService")
local RunService       = game:GetService("RunService")
local HttpService      = game:GetService("HttpService")
local Players          = game:GetService("Players")
local LocalPlayer      = Players.LocalPlayer

--// Bibliothèque principale
local Airflow = {}
Airflow.Flags   = {} -- éléments enregistrés avec l'option `Flag` (utilisés pour les configs)
Airflow.Windows = {}

----------------------------------------------------------------------
-- Gestion des options / enregistrement des éléments
----------------------------------------------------------------------

-- Copie `input` (string => {Name = input}) et applique des alias : { Alias = "NomCanonique" }.
local function normalizeOptions(input, aliases)
    local result = {}
    if type(input) == "string" then
        result.Name = input
    elseif type(input) == "table" then
        for key, value in pairs(input) do
            result[key] = value
        end
    end
    for alias, canonical in pairs(aliases or {}) do
        if result[canonical] == nil and result[alias] ~= nil then
            result[canonical] = result[alias]
        end
    end
    if result.Range then
        result.Min = result.Min or result.Range[1]
        result.Max = result.Max or result.Range[2]
    end
    return result
end

-- Ajoute les champs communs à un élément, le branche sur les Flags et ajoute :Destroy().
local function registerElement(tab, options, element, frame, typeName)
    element._type = typeName
    element._frame = frame
    element._listeners = element._listeners or {}

    local window = tab and tab.Window

    if options.Flag then
        Airflow.Flags[options.Flag] = element
        if window then
            -- Chaque changement déclenche une sauvegarde automatique de la config
            local originalCallback = options.Callback
            options.Callback = function(...)
                if type(originalCallback) == "function" then
                    originalCallback(...)
                end
                window:_autoSave()
            end
        end
    end

    function element:Destroy()
        if element._destroyed then return end
        element._destroyed = true
        for _, disconnect in ipairs(element._listeners) do
            disconnect()
        end
        element._listeners = {}
        if options.Flag and Airflow.Flags[options.Flag] == element then
            Airflow.Flags[options.Flag] = nil
        end
        if window then
            window._controlsDirty = true
        end
        if frame then
            frame:Destroy()
        end
    end

    return element
end

----------------------------------------------------------------------
-- Thème et assets
----------------------------------------------------------------------

Airflow.Theme = {
    Background  = Color3.fromRGB(20, 16, 20),
    Surface     = Color3.fromRGB(24, 19, 24),
    Surface2    = Color3.fromRGB(28, 22, 28),
    Surface3    = Color3.fromRGB(42, 36, 43),
    Stroke      = Color3.fromRGB(40, 32, 41),
    StrokeHover = Color3.fromRGB(88, 70, 90),
    Accent      = Color3.fromRGB(235, 199, 246),
    AccentDark  = Color3.fromRGB(24, 18, 26),
    Text        = Color3.fromRGB(233, 229, 234),
    Muted       = Color3.fromRGB(125, 115, 126),
    Warning     = Color3.fromRGB(240, 176, 108),
    Success     = Color3.fromRGB(150, 220, 170),
    Error       = Color3.fromRGB(240, 120, 120),
}

Airflow.Assets = {
    Shadow = "rbxassetid://6014261993",
    Glow   = "rbxassetid://8992230677",
    Logo   = "rbxassetid://103859712365480",
}

----------------------------------------------------------------------
-- Icônes (Lucide, chargées à distance une seule fois)
----------------------------------------------------------------------

local iconLibrary -- nil = pas encore essayé, false = indisponible

local function loadIcons()
    if iconLibrary ~= nil then
        return iconLibrary
    end
    local ok, result = pcall(function()
        local source = game:HttpGet("https://raw.githubusercontent.com/Footagesus/Icons/refs/heads/main/lucide/dist/Icons.lua")
        return loadstring(source)()
    end)
    if ok and type(result) == "table" then
        iconLibrary = result
    else
        iconLibrary = false
        warn("[AirFlow] lucide icons unavailable: " .. tostring(result))
    end
    return iconLibrary
end

----------------------------------------------------------------------
-- Polices personnalisées
----------------------------------------------------------------------

local FontSources = {
    ValleySans = {
        Regular  = "https://raw.githubusercontent.com/HelsinkiTypeStudio/valley-sans/main/fonts/ttf/ValleySans-Regular.ttf",
        Medium   = "https://raw.githubusercontent.com/HelsinkiTypeStudio/valley-sans/main/fonts/ttf/ValleySans-Medium.ttf",
        SemiBold = "https://raw.githubusercontent.com/HelsinkiTypeStudio/valley-sans/main/fonts/ttf/ValleySans-SemiBold.ttf",
    },
}

local FontWeights = {
    Regular  = { 400, Enum.FontWeight.Regular },
    Medium   = { 500, Enum.FontWeight.Medium },
    SemiBold = { 600, Enum.FontWeight.SemiBold },
    Bold     = { 700, Enum.FontWeight.Bold },
}

function Airflow:LoadFont(options)
    local functionType = "function"
    options = normalizeOptions(options, {})

    if type(writefile) ~= functionType or type(isfile) ~= functionType or typeof(getcustomasset) ~= functionType then
        warn("[AirFlow] custom fonts need writefile, isfile and getcustomasset")
        return false
    end

    local name = options.Name or "CustomFont"
    local weights = options.Weights or FontSources[name]
    if type(weights) ~= "table" then
        warn("[AirFlow] no font weights for " .. name)
        return false
    end

    local folder = options.Folder or "AirFlowFonts"
    pcall(function()
        if type(isfolder) == "function" and type(makefolder) == "function" and not isfolder(folder) then
            makefolder(folder)
        end
    end)

    local faces = {}
    for weightName, url in pairs(weights) do
        local weightInfo = FontWeights[weightName]
        if weightInfo then
            local path = folder .. "/" .. name .. "-" .. weightName .. ".ttf"
            local available = true
            if not isfile(path) then
                available = pcall(function()
                    writefile(path, game:HttpGet(url))
                end)
            end
            if available then
                table.insert(faces, {
                    name = weightName,
                    weight = weightInfo[1],
                    style = "normal",
                    assetId = getcustomasset(path),
                })
            else
                warn("[AirFlow] could not download " .. weightName .. " weight of " .. name)
            end
        end
    end
    if #faces == 0 then
        return false
    end

    local familyPath = folder .. "/" .. name .. ".json"
    local wroteFamily = pcall(function()
        writefile(familyPath, HttpService:JSONEncode({ name = name, faces = faces }))
    end)
    if not wroteFamily then
        return false
    end

    local familyAsset = getcustomasset(familyPath)

    local function pickFont(weightName, fallback)
        local weightInfo = FontWeights[weightName]
        if weightInfo and weights[weightName] then
            return Font.new(familyAsset, weightInfo[2])
        end
        return fallback
    end

    Airflow.Fonts.Regular = pickFont("Regular", Airflow.Fonts.Regular)
    Airflow.Fonts.Medium  = pickFont("Medium", pickFont("Regular", Airflow.Fonts.Medium))
    Airflow.Fonts.Bold    = pickFont("SemiBold", pickFont("Bold", Airflow.Fonts.Bold))
    return true
end

function Airflow:PreloadIcons()
    return loadIcons() ~= false
end

-- Retourne (image, rectOffset, rectSize) pour un nom d'icône, un asset ou une table.
local function resolveIcon(icon)
    if typeof(icon) == "table" then
        return icon.Image, icon.RectOffset, icon.RectSize
    end
    if type(icon) ~= "string" then
        return nil
    end
    if icon:find("^rbxassetid://") or icon:find("^rbxasset://") or icon:find("^http") then
        return icon
    end

    local iconName = icon:gsub("^lucide:", "")
    local library = loadIcons()
    if not library then
        return nil
    end

    local entry = library.Icons and library.Icons[iconName] or library[iconName]
    if type(entry) == "table" then
        local image = entry.Image
        if type(image) == "number" then
            image = "rbxassetid://" .. tostring(image)
        end
        local sheet = library.Spritesheets and library.Spritesheets[tostring(image)] or image
        return sheet, entry.ImageRectPosition, entry.ImageRectSize
    elseif type(entry) == "string" then
        return entry
    end

    warn("[AirFlow] unknown lucide icon: " .. iconName)
    return nil
end

local DEFAULT_FONT_FAMILY = "rbxasset://fonts/families/BuilderSans.json"
Airflow.Fonts = {
    Regular = Font.new(DEFAULT_FONT_FAMILY, Enum.FontWeight.Regular),
    Medium  = Font.new(DEFAULT_FONT_FAMILY, Enum.FontWeight.Medium),
    Bold    = Font.new(DEFAULT_FONT_FAMILY, Enum.FontWeight.SemiBold),
}

local Theme  = Airflow.Theme
local Assets = Airflow.Assets
local Fonts  = Airflow.Fonts

--// Dimensions (plus grandes sur mobile)
local isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
Airflow.Touch = isTouch

local ROW_HEIGHT        = isTouch and 54 or 48
local ROW_HEIGHT_DESC   = isTouch and 70 or 64
local OPTION_HEIGHT     = isTouch and 40 or 34
local CONTROL_HEIGHT    = isTouch and 34 or 28

----------------------------------------------------------------------
-- Helpers d'instances / animations
----------------------------------------------------------------------

local tweenInfoCache = {}

-- Anime `props` sur `instance`. Si la durée est <= 0, applique directement.
local function tween(instance, props, duration, style, direction)
    duration = duration or 0.2
    if duration <= 0 then
        for property, value in pairs(props) do
            instance[property] = value
        end
        return nil
    end

    style = style or Enum.EasingStyle.Quart
    direction = direction or Enum.EasingDirection.Out

    local cacheKey = duration .. style.Name .. direction.Name
    local info = tweenInfoCache[cacheKey]
    if not info then
        info = TweenInfo.new(duration, style, direction)
        tweenInfoCache[cacheKey] = info
    end

    local playing = TweenService:Create(instance, info, props)
    playing:Play()
    return playing
end

-- Crée une instance, applique les propriétés, ajoute les enfants, puis le Parent en dernier.
local function create(className, props, children)
    local instance = Instance.new(className)
    for property, value in pairs(props) do
        if property ~= "Parent" then
            instance[property] = value
        end
    end
    if children then
        for _, child in ipairs(children) do
            child.Parent = instance
        end
    end
    if props.Parent then
        instance.Parent = props.Parent
    end
    return instance
end

local function addCorner(parent, radius)
    return create("UICorner", { CornerRadius = radius or UDim.new(0, 8), Parent = parent })
end

local function addStroke(parent, color, transparency, thickness)
    return create("UIStroke", {
        Color = color or Theme.Stroke,
        Transparency = transparency or 0,
        Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = parent,
    })
end

local function addPadding(parent, left, right, top, bottom)
    return create("UIPadding", {
        PaddingLeft = UDim.new(0, left or 0),
        PaddingRight = UDim.new(0, right or 0),
        PaddingTop = UDim.new(0, top or 0),
        PaddingBottom = UDim.new(0, bottom or 0),
        Parent = parent,
    })
end

local function createLabel(props)
    local defaults = {
        BackgroundTransparency = 1,
        TextColor3 = Theme.Text,
        TextSize = 14,
        FontFace = Fonts.Medium,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }
    for property, value in pairs(props) do
        defaults[property] = value
    end
    return create("TextLabel", defaults)
end

-- Halo lumineux décoratif
local function addGlow(parent, size, position, transparency, rotation)
    local glow = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = position,
        Size = size,
        BackgroundTransparency = 1,
        Image = Assets.Glow,
        ImageColor3 = Color3.fromRGB(226, 218, 230),
        ImageTransparency = transparency,
        ZIndex = 0,
        Parent = parent,
    })
    create("UIGradient", {
        Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Theme.Accent),
        Rotation = rotation or 90,
        Parent = glow,
    })
    return glow
end

-- Fine ligne claire en haut d'un panneau
local function addTopHighlight(parent)
    return create("Frame", {
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BackgroundTransparency = 0.93,
        BorderSizePixel = 0,
        ZIndex = 0,
        Parent = parent,
    })
end

-- Applique une icône (nom Lucide, asset, ou table) sur une ImageLabel
local function setIcon(imageLabel, icon)
    local image, rectOffset, rectSize = resolveIcon(icon)
    if not image then return end
    imageLabel.Image = image
    imageLabel.ImageRectOffset = rectOffset or Vector2.zero
    imageLabel.ImageRectSize = rectSize or Vector2.zero
end

-- Où mettre le ScreenGui : gethui > CoreGui > PlayerGui
local function getGuiParent()
    local hiddenUi
    pcall(function()
        if typeof(gethui) == "function" then
            hiddenUi = gethui()
        end
    end)
    if typeof(hiddenUi) == "Instance" then
        return hiddenUi
    end

    local coreGui
    pcall(function()
        coreGui = game:GetService("CoreGui")
        local probe = Instance.new("Folder")
        probe.Parent = coreGui
        probe:Destroy()
    end)
    if coreGui then
        return coreGui
    end

    return LocalPlayer:WaitForChild("PlayerGui")
end

--// Position de la souris (corrigée de l'inset GUI, mise en cache par frame)
local lastInsetTime, guiInset = nil, Vector2.zero
local function getMousePosition()
    local now = time()
    if lastInsetTime ~= now then
        lastInsetTime = now
        guiInset = GuiService:GetGuiInset()
    end
    return UserInputService:GetMouseLocation() - guiInset
end

local function isPress(input)
    return input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
end

local function isMove(input)
    return input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch
end

-- Petite icône 16x16 alignée verticalement. Retourne (conteneur, image).
local function createIconFrame(parent, icon, color, position)
    local holder = create("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = position,
        Size = UDim2.fromOffset(16, 16),
        BackgroundTransparency = 1,
        Parent = parent,
    })
    local image = create("ImageLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        ImageColor3 = color,
        ScaleType = Enum.ScaleType.Fit,
        Parent = holder,
    })
    setIcon(image, icon)
    return holder, image
end

-- Chevron animé (icône Lucide si dispo, sinon caractère "›" tourné)
local function createChevron(parent, anchorX, xOffset)
    local holder = create("Frame", {
        AnchorPoint = Vector2.new(anchorX, 0.5),
        Position = UDim2.new(anchorX, xOffset, 0.5, 0),
        Size = UDim2.fromOffset(18, 18),
        BackgroundTransparency = 1,
        Parent = parent,
    })

    local chevron = {}

    local icon = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(16, 16),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Muted,
        ScaleType = Enum.ScaleType.Fit,
        Parent = holder,
    })
    setIcon(icon, "chevron-down")

    if icon.Image ~= "" then
        function chevron:Set(open)
            tween(icon, {
                Rotation = open and 180 or 0,
                ImageColor3 = open and Theme.Accent or Theme.Muted,
            }, 0.3, Enum.EasingStyle.Quint)
        end
        return chevron
    end

    -- Repli texte si les icônes ne sont pas disponibles
    icon:Destroy()

    local function glyph(rotation, transparency)
        return createLabel({
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(18, 18),
            Text = "›",
            TextSize = 22,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextColor3 = Theme.Muted,
            TextTransparency = transparency,
            Rotation = rotation,
            Parent = holder,
        })
    end

    local closedGlyph = glyph(90, 0)
    local openGlyph = glyph(270, 1)

    function chevron:Set(open)
        tween(closedGlyph, { TextTransparency = open and 1 or 0 }, 0.2)
        tween(openGlyph, {
            TextTransparency = open and 0 or 1,
            TextColor3 = open and Theme.Accent or Theme.Muted,
        }, 0.2)
    end
    return chevron
end

--// Effet "ripple" au clic (avec petit pool d'objets réutilisables)
local ripplePool = {}

local function ripple(button)
    local mouse = getMousePosition()
    local diameter = math.max(button.AbsoluteSize.X, button.AbsoluteSize.Y) * 2.2

    local dot = table.remove(ripplePool)
    if not dot then
        dot = create("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundColor3 = Theme.Accent,
            BorderSizePixel = 0,
        })
        addCorner(dot, UDim.new(1, 0))
    end

    dot.Position = UDim2.fromOffset(mouse.X - button.AbsolutePosition.X, mouse.Y - button.AbsolutePosition.Y)
    dot.Size = UDim2.fromOffset(0, 0)
    dot.BackgroundTransparency = 0.82
    dot.ZIndex = button.ZIndex + 1
    dot.Parent = button

    tween(dot, { Size = UDim2.fromOffset(diameter, diameter), BackgroundTransparency = 1 }, 0.55)

    task.delay(0.55, function()
        dot.Parent = nil
        if #ripplePool < 4 then
            table.insert(ripplePool, dot)
        else
            dot:Destroy()
        end
    end)
end

-- Fait clignoter brièvement un contour en couleur d'accent
local function flashStroke(stroke)
    if not stroke then return end
    tween(stroke, { Color = Theme.Accent, Transparency = 0.2 }, 0.08)
    task.delay(0.12, function()
        tween(stroke, { Color = Theme.Stroke, Transparency = 0 }, 0.35)
    end)
end

-- Contour qui s'éclaircit au survol
local function hoverStroke(gui, stroke)
    gui.MouseEnter:Connect(function()
        tween(stroke, { Color = Theme.StrokeHover }, 0.12)
    end)
    gui.MouseLeave:Connect(function()
        tween(stroke, { Color = Theme.Stroke }, 0.25)
    end)
end

--// Noms lisibles des touches
local KeyDisplayNames = {
    [Enum.KeyCode.LeftControl]  = "LCtrl",
    [Enum.KeyCode.RightControl] = "RCtrl",
    [Enum.KeyCode.LeftShift]    = "LShift",
    [Enum.KeyCode.RightShift]   = "RShift",
    [Enum.KeyCode.LeftAlt]      = "LAlt",
    [Enum.KeyCode.RightAlt]     = "RAlt",
    [Enum.KeyCode.Return]       = "Enter",
    [Enum.KeyCode.Escape]       = "Esc",
    [Enum.KeyCode.Backspace]    = "Backspace",
}

local function keyName(keyCode)
    if keyCode == nil then
        return "None"
    end
    return KeyDisplayNames[keyCode] or keyCode.Name
end

-- Appelle un callback utilisateur sans casser l'UI en cas d'erreur
local function safeCall(callback, ...)
    if type(callback) ~= "function" then return end
    local ok, err = pcall(callback, ...)
    if not ok then
        warn("[AirFlow] callback error: " .. tostring(err))
    end
end

-- Arrondit une valeur au pas `step` et la borne ; formate avec le bon nombre de décimales
local function makeSnapper(min, max, step)
    local decimals = 0
    local stepText = tostring(step)
    local dotIndex = stepText:find("%.")
    if dotIndex then
        decimals = #stepText - dotIndex
    end
    local formatString = "%." .. decimals .. "f"

    return {
        snap = function(value)
            value = math.floor(value / step + 0.5) * step
            return math.clamp(value, min, max)
        end,
        format = function(value)
            return string.format(formatString, value)
        end,
    }
end

----------------------------------------------------------------------
-- Briques communes aux éléments (lignes de contrôle)
----------------------------------------------------------------------

-- Crée la "carte" d'une ligne. Retourne (ligne, contour).
local function createRow(tab, className, height)
    local props = {
        Size = UDim2.new(1, 0, 0, height),
        BackgroundColor3 = Theme.Surface2,
        BorderSizePixel = 0,
        LayoutOrder = tab:_nextOrder(),
        Parent = tab.List,
    }
    if className == "TextButton" then
        props.AutoButtonColor = false
        props.Text = ""
    end

    local row = create(className, props)
    row:SetAttribute("NoDrag", true) -- ne pas démarrer un drag de fenêtre depuis un contrôle
    addCorner(row)
    local stroke = addStroke(row, Theme.Stroke)
    return row, stroke
end

-- Titre (+ description optionnelle) à gauche d'une ligne. `reserve` = espace laissé à droite.
local function createRowLabels(row, title, description, reserve)
    local titleLabel, descriptionLabel
    if description then
        local top = (ROW_HEIGHT_DESC - 38) / 2
        titleLabel = createLabel({
            Position = UDim2.fromOffset(14, top),
            Size = UDim2.new(1, -(14 + reserve), 0, 18),
            Text = title,
            Parent = row,
        })
        descriptionLabel = createLabel({
            Position = UDim2.fromOffset(14, top + 20),
            Size = UDim2.new(1, -(14 + reserve), 0, 17),
            Text = description,
            TextSize = 13,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            Parent = row,
        })
    else
        titleLabel = createLabel({
            Position = UDim2.fromOffset(14, 0),
            Size = UDim2.new(1, -(14 + reserve), 1, 0),
            Text = title,
            Parent = row,
        })
    end
    return titleLabel, descriptionLabel
end

-- Normalise les options + crée la ligne (+ labels si `reserve` est donné).
-- Retourne (options, ligne, contour, hauteur, titre, description).
local function createControlRow(tab, options, aliases, className, reserve, defaultTitle)
    options = normalizeOptions(options, aliases)
    local height = options.Desc and ROW_HEIGHT_DESC or ROW_HEIGHT
    local row, stroke = createRow(tab, className or "Frame", height)
    hoverStroke(row, stroke)

    local titleLabel, descriptionLabel
    if reserve then
        titleLabel, descriptionLabel = createRowLabels(row, options.Name or defaultTitle, options.Desc, reserve)
    end
    return options, row, stroke, height, titleLabel, descriptionLabel
end

-- Ajuste la largeur des labels quand un contrôle à droite change de taille
local function setLabelReserve(titleLabel, descriptionLabel, reserve)
    if titleLabel then
        titleLabel.Size = UDim2.new(1, -(14 + reserve), titleLabel.Size.Y.Scale, titleLabel.Size.Y.Offset)
    end
    if descriptionLabel then
        descriptionLabel.Size = UDim2.new(1, -(14 + reserve), 0, descriptionLabel.Size.Y.Offset)
    end
end

----------------------------------------------------------------------
-- Classe Tab : éléments (Section, Button, Toggle, Slider, ...)
----------------------------------------------------------------------

local Tab = {}
Tab.__index = Tab

function Tab:_nextOrder()
    self._order += 1
    return self._order
end

function Tab:Section(name)
    if type(name) == "table" then
        name = name.Name or name.Title or ""
    end

    local holder = create("Frame", {
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundTransparency = 1,
        LayoutOrder = self:_nextOrder(),
        Parent = self.List,
    })

    local label = createLabel({
        Position = UDim2.fromOffset(2, 8),
        Size = UDim2.new(0, 0, 0, 16),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = string.upper(name),
        TextSize = 12,
        TextColor3 = Theme.Muted,
        TextTruncate = Enum.TextTruncate.None,
        Parent = holder,
    })

    local line = create("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0, 16),
        Size = UDim2.new(1, -12, 0, 1),
        BackgroundColor3 = Theme.Stroke,
        BorderSizePixel = 0,
        Parent = holder,
    })

    local function fitLine()
        line.Size = UDim2.new(1, -(label.AbsoluteSize.X + 14), 0, 1)
    end
    label:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitLine)
    task.defer(fitLine)

    return registerElement(self, {}, {
        Set = function(_, text)
            label.Text = string.upper(text)
        end,
    }, holder, "Section")
end

function Tab:Divider()
    local line = create("Frame", {
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Theme.Stroke,
        BorderSizePixel = 0,
        LayoutOrder = self:_nextOrder(),
        Parent = self.List,
    })
    return registerElement(self, {}, {}, line, "Divider")
end

function Tab:Label(options)
    options = normalizeOptions(options, { Name = "Text", Title = "Text" })

    local label = createLabel({
        Size = UDim2.new(1, 0, 0, 18),
        Text = options.Text or "",
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextColor3 = options.Color or Theme.Muted,
        LayoutOrder = self:_nextOrder(),
        Parent = self.List,
    })
    addPadding(label, 2)

    local element = {
        Set = function(_, value)
            label.Text = tostring(value)
        end,
        Get = function()
            return label.Text
        end,
    }

    -- Label "live" : `Update` est appelée périodiquement et renvoie le nouveau texte
    if type(options.Update) == "function" then
        local rate = math.max(tonumber(options.UpdateRate) or 1, 0.05)
        local running = true

        element._listeners = element._listeners or {}
        table.insert(element._listeners, function()
            running = false
        end)

        task.spawn(function()
            while running and label.Parent do
                local ok, result = pcall(options.Update)
                if ok and result ~= nil then
                    label.Text = tostring(result)
                elseif not ok then
                    warn("[AirFlow] label update error: " .. tostring(result))
                end
                task.wait(rate)
            end
        end)

        function element:SetUpdateRate(newRate)
            rate = math.max(tonumber(newRate) or rate, 0.05)
        end
    end

    return registerElement(self, options, element, label, "Label")
end

function Tab:Paragraph(options)
    options = normalizeOptions(options, { Title = "Name" })

    local card = createRow(self, "Frame", 0)
    card.AutomaticSize = Enum.AutomaticSize.Y
    addPadding(card, 14, 14, 11, 12)
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 4),
        Parent = card,
    })

    createLabel({
        Size = UDim2.new(1, 0, 0, 14),
        Text = options.Name or "",
        LayoutOrder = 1,
        Parent = card,
    })

    local body = createLabel({
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Text = options.Content or "",
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextWrapped = true,
        TextTruncate = Enum.TextTruncate.None,
        TextYAlignment = Enum.TextYAlignment.Top,
        LayoutOrder = 2,
        Parent = card,
    })

    return registerElement(self, options, {
        Set = function(_, text)
            body.Text = text
        end,
    }, card, "Paragraph")
end

function Tab:Button(options)
    options = normalizeOptions(options, { Title = "Name", Description = "Desc" })

    local isPrimary = options.Style == "Primary"
    local height = options.Desc and ROW_HEIGHT_DESC or ROW_HEIGHT
    local button, stroke = createRow(self, "TextButton", height)
    button.ClipsDescendants = true

    if isPrimary then
        button.BackgroundColor3 = Theme.Accent
        button.BackgroundTransparency = 0.12
        stroke.Color = Theme.Accent
        stroke.Transparency = 0.4
        button.MouseEnter:Connect(function()
            tween(button, { BackgroundTransparency = 0 }, 0.12)
            tween(stroke, { Transparency = 0 }, 0.12)
        end)
        button.MouseLeave:Connect(function()
            tween(button, { BackgroundTransparency = 0.12 }, 0.25)
            tween(stroke, { Transparency = 0.4 }, 0.25)
        end)
    else
        hoverStroke(button, stroke)
    end

    local textColor = isPrimary and Theme.AccentDark or Theme.Text
    local iconShift = 0

    if options.Icon then
        createIconFrame(button, options.Icon, isPrimary and Theme.AccentDark or Theme.Accent, UDim2.new(0, 14, 0.5, 0))
        iconShift = 26
    end

    local titleLabel = createRowLabels(button, options.Name or "Button", options.Desc, 30)

    -- Décale les textes pour laisser la place à l'icône
    if iconShift > 0 then
        for _, child in ipairs(button:GetChildren()) do
            if child:IsA("TextLabel") then
                child.Position += UDim2.fromOffset(iconShift, 0)
                child.Size -= UDim2.fromOffset(iconShift, 0)
            end
        end
    end

    if isPrimary then
        for _, child in ipairs(button:GetChildren()) do
            if child:IsA("TextLabel") then
                child.TextColor3 = textColor
            end
        end
    end

    createIconFrame(button, "chevron-right", isPrimary and Theme.AccentDark or Theme.Muted, UDim2.new(1, -30, 0.5, 0))

    button.MouseButton1Click:Connect(function()
        ripple(button)
        safeCall(options.Callback)
    end)

    return registerElement(self, options, {
        SetText = function(_, text)
            titleLabel.Text = text
        end,
    }, button, "Button")
end

function Tab:Toggle(options)
    local row, stroke
    options, row, stroke = createControlRow(self, options, {
        Title = "Name",
        Description = "Desc",
        CurrentValue = "Default",
        Value = "Default",
    }, "TextButton", 56, "Toggle")

    local track = create("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -14, 0.5, 0),
        Size = isTouch and UDim2.fromOffset(44, 24) or UDim2.fromOffset(36, 20),
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        Parent = row,
    })
    addCorner(track, UDim.new(1, 0))
    addStroke(track, Theme.Stroke)

    local knob = create("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 3, 0.5, 0),
        Size = isTouch and UDim2.fromOffset(18, 18) or UDim2.fromOffset(14, 14),
        BackgroundColor3 = Theme.Muted,
        BorderSizePixel = 0,
        Parent = track,
    })
    addCorner(knob, UDim.new(1, 0))

    local glow = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(1, 24, 1, 24),
        BackgroundTransparency = 1,
        Image = Assets.Glow,
        ImageColor3 = Theme.Accent,
        ImageTransparency = 1,
        ZIndex = 0,
        Parent = track,
    })

    local toggle = { Value = options.Default == true }

    local function render(animate)
        local on = toggle.Value
        local duration = animate and 0.25 or 0

        tween(track, { BackgroundColor3 = on and Theme.Accent or Theme.Surface3 }, duration)
        tween(glow, { ImageTransparency = on and 0.75 or 1 }, duration)

        local knobSize = isTouch and 18 or 14
        tween(knob, {
            Position = on and UDim2.new(0, (isTouch and 44 or 36) - 3 - knobSize, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
            BackgroundColor3 = on and Theme.AccentDark or Theme.Muted,
        }, duration, Enum.EasingStyle.Back)

        if animate then
            -- petit effet "squash" du bouton
            tween(knob, { Size = UDim2.fromOffset(knobSize + 4, knobSize - 2) }, 0.08)
            task.delay(0.08, function()
                tween(knob, { Size = UDim2.fromOffset(knobSize, knobSize) }, 0.2, Enum.EasingStyle.Back)
            end)
        end
    end

    local fromClick = false

    function toggle:Set(value, silent)
        value = value == true
        if value == toggle.Value then return end
        toggle.Value = value
        render(true)
        if not fromClick then
            flashStroke(stroke)
        end
        if not silent then
            safeCall(options.Callback, value)
        end
    end

    function toggle:Get()
        return toggle.Value
    end

    render(false)

    row.MouseButton1Click:Connect(function()
        fromClick = true
        toggle:Set(not toggle.Value)
        fromClick = false
    end)

    local element = registerElement(self, options, toggle, row, "Toggle")
    if toggle.Value then
        safeCall(options.Callback, true)
    end
    return element
end

function Tab:Slider(options)
    options = normalizeOptions(options, {
        Title = "Name",
        Description = "Desc",
        CurrentValue = "Default",
        Value = "Default",
        Increment = "Step",
    })

    local min = options.Min or 0
    local max = options.Max or 100
    local step = options.Step or 1
    local suffix = options.Suffix or ""
    local snapper = makeSnapper(min, max, step)
    local snap = snapper.snap

    local row, rowStroke = createRow(self, "Frame", ROW_HEIGHT_DESC)
    hoverStroke(row, rowStroke)

    createLabel({
        Position = UDim2.fromOffset(14, 12),
        Size = UDim2.new(1, -120, 0, 18),
        Text = options.Name or "Slider",
        Parent = row,
    })

    -- Petite boîte à droite qui affiche la valeur (cliquable pour taper une valeur)
    local valueBox = create("Frame", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -10, 0, 9),
        Size = UDim2.fromOffset(40, 24),
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = row,
    })
    addCorner(valueBox, UDim.new(0, 6))
    local boxStroke = addStroke(valueBox)

    local valueLabel = createLabel({
        Size = UDim2.new(1, 0, 1, 0),
        TextSize = 13,
        TextColor3 = Theme.Accent,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextTruncate = Enum.TextTruncate.None,
        Parent = valueBox,
    })

    local valueInput = create("TextBox", {
        Position = UDim2.fromOffset(9, 0),
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        Text = "",
        TextColor3 = Theme.Text,
        TextSize = 13,
        FontFace = Fonts.Medium,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
        Visible = false,
        Parent = valueBox,
    })
    create("UISizeConstraint", { MinSize = Vector2.new(14, 0), Parent = valueInput })

    local suffixLabel = createLabel({
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = suffix,
        TextSize = 13,
        TextColor3 = Theme.Accent,
        TextTruncate = Enum.TextTruncate.None,
        Visible = false,
        Parent = valueBox,
    })

    local clickCatcher = create("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 2,
        Parent = valueBox,
    })
    local editing = false

    local function fitValueBox(immediate)
        local width
        if editing then
            local inputWidth = valueInput.AbsoluteSize.X / self.Window.Scale.Scale
            width = 9 + inputWidth + suffixLabel.TextBounds.X + 9
            suffixLabel.Position = UDim2.fromOffset(9 + inputWidth, 0)
        else
            width = valueLabel.TextBounds.X + 18
        end
        width = math.max(width, 36)

        if immediate then
            valueBox.Size = UDim2.fromOffset(width, 24)
        else
            tween(valueBox, { Size = UDim2.fromOffset(width, 24) }, 0.2)
        end
    end

    valueLabel:GetPropertyChangedSignal("TextBounds"):Connect(function()
        if not editing then fitValueBox(false) end
    end)
    valueInput:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        if editing then fitValueBox(false) end
    end)

    -- Barre
    local track = create("Frame", {
        Position = UDim2.new(0, 14, 0, ROW_HEIGHT_DESC - 18),
        Size = UDim2.new(1, -28, 0, 5),
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        Parent = row,
    })
    addCorner(track, UDim.new(1, 0))

    local fill = create("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        Parent = track,
    })
    addCorner(fill, UDim.new(1, 0))

    local thumbGlow = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.fromOffset(28, 28),
        BackgroundTransparency = 1,
        Image = Assets.Glow,
        ImageColor3 = Theme.Accent,
        ImageTransparency = 0.85,
        ZIndex = 2,
        Parent = track,
    })

    local thumb = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.fromOffset(12, 12),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        ZIndex = 3,
        Parent = track,
    })
    addCorner(thumb, UDim.new(1, 0))

    -- Zone de drag (plus grande que la barre)
    local hitbox = create("TextButton", {
        Position = UDim2.new(0, 8, 0, ROW_HEIGHT_DESC - (isTouch and 37 or 31)),
        Size = UDim2.new(1, -16, 0, isTouch and 40 or 28),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 4,
        Parent = row,
    })

    local slider = { Value = math.clamp(options.Default or min, min, max) }
    local dragging = false

    clickCatcher.MouseEnter:Connect(function()
        tween(boxStroke, { Color = Theme.StrokeHover }, 0.12)
    end)
    clickCatcher.MouseLeave:Connect(function()
        if not valueInput:IsFocused() then
            tween(boxStroke, { Color = Theme.Stroke }, 0.2)
        end
    end)

    -- Clic sur la valeur => saisie manuelle
    clickCatcher.MouseButton1Click:Connect(function()
        editing = true
        valueInput.Text = snapper.format(slider.Value)
        valueLabel.Visible = false
        valueInput.Visible = true
        suffixLabel.Visible = suffix ~= ""
        clickCatcher.Visible = false
        tween(boxStroke, { Color = Theme.StrokeHover }, 0.12)
        valueInput:CaptureFocus()
        task.defer(fitValueBox, false)
    end)

    valueInput.FocusLost:Connect(function()
        local typed = tonumber(valueInput.Text)
        editing = false
        valueInput.Visible = false
        suffixLabel.Visible = false
        valueLabel.Visible = true
        clickCatcher.Visible = true
        tween(boxStroke, { Color = Theme.Stroke }, 0.2)
        if typed then
            slider:Set(typed)
        end
        fitValueBox(false)
    end)

    hitbox.MouseEnter:Connect(function()
        if not dragging then
            tween(thumbGlow, { ImageTransparency = 0.78, Size = UDim2.fromOffset(34, 34) }, 0.15)
        end
    end)
    hitbox.MouseLeave:Connect(function()
        if not dragging then
            tween(thumbGlow, { ImageTransparency = 0.85, Size = UDim2.fromOffset(28, 28) }, 0.2)
        end
    end)

    local function getFraction()
        if max - min == 0 then return 0 end
        return (slider.Value - min) / (max - min)
    end

    local function moveVisuals(fraction, duration, style)
        style = style or Enum.EasingStyle.Linear
        tween(fill, { Size = UDim2.new(fraction, 0, 1, 0) }, duration, style)
        tween(thumb, { Position = UDim2.new(fraction, 0, 0.5, 0) }, duration, style)
        tween(thumbGlow, { Position = UDim2.new(fraction, 0, 0.5, 0) }, duration, style)
    end

    local function syncVisuals(duration, style)
        moveVisuals(getFraction(), duration, style)
        valueLabel.Text = snapper.format(slider.Value) .. suffix
    end

    -- Quand la valeur change hors drag : petit "overshoot" puis retour
    local function nudgeVisuals(previousFraction)
        local fraction = getFraction()
        local width = math.max(track.AbsoluteSize.X, 1)
        local overshoot = (fraction >= previousFraction and 1 or -1) * (5 / width)

        moveVisuals(math.clamp(fraction + overshoot, 0, 1), 0.22, Enum.EasingStyle.Quint)
        task.delay(0.22, function()
            if not dragging then
                moveVisuals(getFraction(), 0.18, Enum.EasingStyle.Quint)
            end
        end)
        valueLabel.Text = snapper.format(slider.Value) .. suffix
    end

    local function pulseThumb()
        tween(thumb, { Size = UDim2.fromOffset(14, 12) }, 0.08)
        tween(thumbGlow, { Size = UDim2.fromOffset(32, 32), ImageTransparency = 0.78 }, 0.12)
        task.delay(0.1, function()
            tween(thumb, { Size = UDim2.fromOffset(12, 12) }, 0.25, Enum.EasingStyle.Quint)
            tween(thumbGlow, { Size = UDim2.fromOffset(28, 28), ImageTransparency = 0.85 }, 0.25)
        end)
    end

    function slider:Set(value, silent)
        value = snap(tonumber(value) or min)
        if value == slider.Value then return end

        local previousFraction = getFraction()
        slider.Value = value

        if dragging then
            syncVisuals(0.05)
        else
            nudgeVisuals(previousFraction)
            pulseThumb()
            flashStroke(rowStroke)
        end

        if not silent then
            safeCall(options.Callback, value)
        end
    end

    function slider:Get()
        return slider.Value
    end

    local function setFromMouseX(x)
        local fraction = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        slider:Set(min + (max - min) * fraction)
    end

    hitbox.InputBegan:Connect(function(input)
        if isPress(input) then
            dragging = true
            tween(thumb, { Size = UDim2.fromOffset(16, 16) }, 0.15, Enum.EasingStyle.Back)
            tween(thumbGlow, { Size = UDim2.fromOffset(44, 44), ImageTransparency = 0.7 }, 0.15)
            setFromMouseX(getMousePosition().X)
        end
    end)

    self.Window:_listen("Changed", function(input)
        if dragging and isMove(input) then
            setFromMouseX(getMousePosition().X)
        end
    end, slider)

    self.Window:_listen("Ended", function(input)
        if dragging and isPress(input) then
            dragging = false
            tween(thumb, { Size = UDim2.fromOffset(12, 12) }, 0.2)
            tween(thumbGlow, { Size = UDim2.fromOffset(28, 28), ImageTransparency = 0.85 }, 0.2)
        end
    end, slider)

    slider.Value = snap(slider.Value)
    syncVisuals(0)
    task.defer(fitValueBox, true)

    return registerElement(self, options, slider, row, "Slider")
end

function Tab:Dropdown(options)
    options = normalizeOptions(options, {
        Title = "Name",
        Description = "Desc",
        CurrentOption = "Default",
        Value = "Default",
        MultipleOptions = "Multi",
        Values = "Options",
    })

    -- Normalise la valeur par défaut selon le mode (simple / multiple)
    if options.Multi and type(options.Default) ~= "table" and options.Default ~= nil then
        options.Default = { options.Default }
    elseif not options.Multi and type(options.Default) == "table" then
        options.Default = options.Default[1]
    end

    local isMulti = options.Multi == true
    local optionList = options.Options or {}

    local row, rowStroke, headerHeight
    options, row, rowStroke, headerHeight = createControlRow(self, options, {}, "Frame")
    row.ClipsDescendants = true

    -- En-tête cliquable
    local header = create("TextButton", {
        Size = UDim2.new(1, 0, 0, headerHeight),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        Parent = row,
    })
    local titleLabel, descriptionLabel = createRowLabels(header, options.Name or "Dropdown", options.Desc, 180)

    -- Boîte de valeur à droite
    local valueBox = create("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.fromOffset(60, CONTROL_HEIGHT),
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = header,
    })
    addCorner(valueBox, UDim.new(0, 6))
    local boxStroke = addStroke(valueBox)

    local valueLabel = createLabel({
        Position = UDim2.fromOffset(10, 0),
        Size = UDim2.new(1, -34, 1, 0),
        TextColor3 = Theme.Muted,
        TextSize = 13,
        TextTruncate = Enum.TextTruncate.None,
        ClipsDescendants = true,
        Parent = valueBox,
    })
    local chevron = createChevron(valueBox, 1, -6)

    -- Label invisible utilisé pour mesurer la largeur du texte
    local measureLabel = createLabel({
        Size = UDim2.fromOffset(0, CONTROL_HEIGHT),
        AutomaticSize = Enum.AutomaticSize.X,
        TextSize = 13,
        Visible = false,
        Parent = valueBox,
    })
    local summaryText = ""

    -- Texte résumé, tronqué avec ".." si trop long
    local function getTruncatedSummary()
        measureLabel.Text = summaryText
        if measureLabel.TextBounds.X <= 146 then
            return summaryText
        end
        local shortened = summaryText
        while #shortened > 1 do
            shortened = shortened:sub(1, -2)
            measureLabel.Text = shortened .. ".."
            if measureLabel.TextBounds.X <= 146 then
                return shortened .. ".."
            end
        end
        return ".."
    end

    local function fitValueBox(immediate)
        local width = math.clamp(valueLabel.TextBounds.X + 10 + 34, 60, 190)
        setLabelReserve(titleLabel, descriptionLabel, width + 20)
        if immediate then
            valueBox.Size = UDim2.fromOffset(width, CONTROL_HEIGHT)
        else
            tween(valueBox, { Size = UDim2.fromOffset(width, CONTROL_HEIGHT) }, 0.2)
        end
    end
    valueLabel:GetPropertyChangedSignal("TextBounds"):Connect(function()
        fitValueBox(false)
    end)

    -- Liste d'options (sous l'en-tête)
    local optionsHolder = create("Frame", {
        Position = UDim2.new(0, 10, 0, headerHeight),
        Size = UDim2.new(1, -20, 0, 0),
        BackgroundTransparency = 1,
        Parent = row,
    })
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 4),
        Parent = optionsHolder,
    })

    local dropdown = { Open = false }
    local selected = {}          -- set des options sélectionnées : [option] = true
    local optionItems = {}       -- [option] = { Frame, Label, Check, CheckScale, Stroke, On }
    local searchQuery = ""
    local searchAfter = options.SearchAfter or 6 -- barre de recherche si plus de N options

    local searchBox = create("Frame", {
        Size = UDim2.new(1, 0, 0, OPTION_HEIGHT),
        BackgroundColor3 = Theme.Surface,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        LayoutOrder = 0,
        Visible = false,
        Parent = optionsHolder,
    })
    addCorner(searchBox, UDim.new(0, 6))
    local searchStroke = addStroke(searchBox, Theme.Stroke, 1)

    local searchInput = create("TextBox", {
        Position = UDim2.fromOffset(12, 0),
        Size = UDim2.new(1, -20, 1, 0),
        BackgroundTransparency = 1,
        Text = "",
        PlaceholderText = "Search",
        PlaceholderColor3 = Theme.Muted,
        TextColor3 = Theme.Text,
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
        TextTransparency = 1,
        Parent = searchBox,
    })

    local function matchesSearch(option)
        return searchQuery == "" or string.find(string.lower(tostring(option)), searchQuery, 1, true) ~= nil
    end

    if isMulti then
        for _, option in ipairs(options.Default or {}) do
            selected[option] = true
        end
    elseif options.Default ~= nil then
        selected[options.Default] = true
    end

    -- Valeur actuelle : table (multi) ou valeur simple
    local function getSelection()
        if isMulti then
            local list = {}
            for _, option in ipairs(optionList) do
                if selected[option] then
                    table.insert(list, option)
                end
            end
            return list
        end
        for _, option in ipairs(optionList) do
            if selected[option] then
                return option
            end
        end
        return nil
    end

    local function refreshSelectionVisuals()
        local selection = getSelection()
        if isMulti then
            summaryText = #selection > 0 and table.concat(selection, ", ") or "None"
        else
            summaryText = selection ~= nil and tostring(selection) or "None"
        end
        valueLabel.Text = getTruncatedSummary()

        for option, item in pairs(optionItems) do
            local isSelected = selected[option] == true
            if item.On ~= isSelected then
                item.On = isSelected
                tween(item.Label, { TextColor3 = isSelected and Theme.Text or Theme.Muted }, 0.15)
                if dropdown.Open then
                    tween(item.Check, { ImageTransparency = isSelected and 0 or 1 }, 0.15)
                    tween(item.CheckScale, { Scale = isSelected and 1 or 0.6 }, isSelected and 0.3 or 0.15,
                        isSelected and Enum.EasingStyle.Back or Enum.EasingStyle.Quint)
                end
            end
        end
    end

    local function countVisibleOptions()
        local count = 0
        for _, option in ipairs(optionList) do
            if matchesSearch(option) then
                count += 1
            end
        end
        return count
    end

    local function applyFilter()
        for option, item in pairs(optionItems) do
            item.Frame.Visible = matchesSearch(option)
        end
    end

    local function getOpenHeight()
        local count = countVisibleOptions() + (searchBox.Visible and 1 or 0)
        return headerHeight + count * (OPTION_HEIGHT + 4) + 8
    end

    local function setOpen(open)
        dropdown.Open = open
        searchBox.Visible = #optionList > searchAfter

        if not open then
            searchQuery = ""
            searchInput.Text = ""
            applyFilter()
        end

        tween(row, { Size = UDim2.new(1, 0, 0, open and getOpenHeight() or headerHeight) }, 0.3, Enum.EasingStyle.Quint)
        tween(searchBox, { BackgroundTransparency = open and 0 or 1 }, 0.2)
        tween(searchStroke, { Transparency = open and 0 or 1 }, 0.2)
        tween(searchInput, { TextTransparency = open and 0 or 1 }, 0.2)
        chevron:Set(open)
        tween(boxStroke, { Color = open and Theme.StrokeHover or Theme.Stroke }, 0.2)

        local function animateItem(item)
            if not item.Stroke then
                item.Stroke = addStroke(item.Frame, Theme.Stroke, 1)
            end
            local checked = open and item.On
            tween(item.Check, { ImageTransparency = checked and 0 or 1 }, 0.18)
            item.CheckScale.Scale = checked and 1 or 0.6
            tween(item.Label, { TextTransparency = open and 0 or 1 }, 0.18)
            tween(item.Stroke, { Transparency = open and 0 or 1 }, 0.18)
            tween(item.Frame, { BackgroundTransparency = open and 0 or 1 }, 0.18)
        end

        if open then
            -- Apparition en cascade de haut en bas
            local generation = (dropdown._openGeneration or 0) + 1
            dropdown._openGeneration = generation
            task.spawn(function()
                local first = true
                for _, option in ipairs(optionList) do
                    local item = optionItems[option]
                    if item and item.Frame.Visible then
                        if not first then
                            task.wait(0.025)
                            if dropdown._openGeneration ~= generation or not dropdown.Open then return end
                        end
                        first = false
                        animateItem(item)
                    end
                end
            end)
        else
            -- Disparition en cascade de bas en haut
            local generation = (dropdown._openGeneration or 0) + 1
            dropdown._openGeneration = generation
            local visibleItems = {}
            for _, option in ipairs(optionList) do
                local item = optionItems[option]
                if item and item.Frame.Visible then
                    table.insert(visibleItems, item)
                end
            end
            task.spawn(function()
                for index = #visibleItems, 1, -1 do
                    animateItem(visibleItems[index])
                    if index > 1 then
                        task.wait(0.015)
                        if dropdown._openGeneration ~= generation or dropdown.Open then return end
                    end
                end
            end)
        end
    end

    -- (Re)construit les boutons d'options à partir de `optionList`
    local function rebuildOptions()
        local indexByOption = {}
        for index, option in ipairs(optionList) do
            indexByOption[option] = index
        end

        -- Supprime les options qui n'existent plus
        for option, item in pairs(optionItems) do
            if not indexByOption[option] then
                item.Frame:Destroy()
                optionItems[option] = nil
            end
        end

        for index, option in ipairs(optionList) do
            local existing = optionItems[option]
            if existing then
                existing.Frame.LayoutOrder = index
                continue
            end

            local button = create("TextButton", {
                Size = UDim2.new(1, 0, 0, OPTION_HEIGHT),
                BackgroundColor3 = Theme.Surface,
                BackgroundTransparency = 1,
                Text = "",
                AutoButtonColor = false,
                LayoutOrder = index,
                Parent = optionsHolder,
            })
            addCorner(button, UDim.new(0, 6))

            local check = create("ImageLabel", {
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -10, 0.5, 0),
                Size = UDim2.fromOffset(14, 14),
                BackgroundTransparency = 1,
                ImageColor3 = Theme.Accent,
                ImageTransparency = 1,
                ScaleType = Enum.ScaleType.Fit,
                Parent = button,
            })
            setIcon(check, "check")
            local checkScale = create("UIScale", { Scale = 0.6, Parent = check })

            local label = createLabel({
                Position = UDim2.fromOffset(12, -1),
                Size = UDim2.new(1, -36, 1, 0),
                Text = tostring(option),
                TextSize = 13,
                TextColor3 = Theme.Muted,
                TextTransparency = 1,
                Parent = button,
            })

            button.MouseEnter:Connect(function()
                tween(label, { TextColor3 = Theme.Text }, 0.15)
                local item = optionItems[option]
                if item and item.Stroke then
                    tween(item.Stroke, { Color = Theme.StrokeHover }, 0.12)
                end
            end)
            button.MouseLeave:Connect(function()
                tween(label, { TextColor3 = selected[option] and Theme.Text or Theme.Muted }, 0.2)
                local item = optionItems[option]
                if item and item.Stroke then
                    tween(item.Stroke, { Color = Theme.Stroke }, 0.2)
                end
            end)

            button.MouseButton1Click:Connect(function()
                if selected[option] then
                    selected[option] = nil
                else
                    if not isMulti then
                        selected = {}
                    end
                    selected[option] = true
                end
                refreshSelectionVisuals()
                safeCall(options.Callback, getSelection())
                if not isMulti and selected[option] then
                    setOpen(false)
                end
            end)

            optionItems[option] = {
                Frame = button,
                Label = label,
                Check = check,
                CheckScale = checkScale,
                Stroke = nil,
                On = nil,
            }
        end

        applyFilter()
        if dropdown.Open then
            row.Size = UDim2.new(1, 0, 0, getOpenHeight())
        end
    end

    function dropdown:Set(value, silent)
        selected = {}
        if isMulti then
            for _, option in ipairs(type(value) == "table" and value or { value }) do
                selected[option] = true
            end
        elseif value ~= nil then
            selected[value] = true
        end
        refreshSelectionVisuals()
        flashStroke(rowStroke)
        if not silent then
            safeCall(options.Callback, getSelection())
        end
    end

    function dropdown:Get()
        return getSelection()
    end

    function dropdown:Refresh(newOptions, keepSelection)
        optionList = newOptions or {}
        if not keepSelection then
            selected = {}
        end
        rebuildOptions()
        refreshSelectionVisuals()
        if dropdown.Open then
            setOpen(true)
        end
    end

    function dropdown:SetOpen(open)
        setOpen(open == true)
    end

    header.MouseButton1Click:Connect(function()
        setOpen(not dropdown.Open)
    end)

    searchInput:GetPropertyChangedSignal("Text"):Connect(function()
        searchQuery = string.lower(searchInput.Text)
        applyFilter()
        if dropdown.Open then
            tween(row, { Size = UDim2.new(1, 0, 0, getOpenHeight()) }, 0.2, Enum.EasingStyle.Quint)
        end
    end)

    rebuildOptions()
    refreshSelectionVisuals()
    task.defer(fitValueBox, true)

    return registerElement(self, options, dropdown, row, "Dropdown")
end

function Tab:Input(options)
    local row, rowStroke, _, titleLabel, descriptionLabel
    options, row, rowStroke, _, titleLabel, descriptionLabel = createControlRow(self, options, {
        Title = "Name",
        Description = "Desc",
        PlaceholderText = "Placeholder",
        CurrentValue = "Default",
        Value = "Default",
    }, "Frame", 160, "Input")

    local box = create("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.fromOffset(170, 30),
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Parent = row,
    })
    addCorner(box, UDim.new(0, 6))
    local boxStroke = addStroke(box)

    local icon = options.Icon
    if icon then
        createIconFrame(box, icon, Theme.Muted, UDim2.new(0, 8, 0.5, 0))
    end

    local textBox = create("TextBox", {
        Position = UDim2.fromOffset(icon and 30 or 8, 0),
        Size = UDim2.new(1, icon and -38 or -16, 1, 0),
        BackgroundTransparency = 1,
        Text = options.Default or "",
        PlaceholderText = options.Placeholder or "",
        PlaceholderColor3 = Theme.Muted,
        TextColor3 = Theme.Text,
        TextSize = 14,
        FontFace = Fonts.Regular,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
        TextTruncate = Enum.TextTruncate.None,
        ClipsDescendants = true,
        Parent = box,
    })
    box.ClipsDescendants = true

    local focused = false
    local textInset = (icon and 30 or 8) + 8

    -- La boîte s'adapte au texte tapé, dans des limites
    local function fitBox(immediate)
        local rowWidth = row.AbsoluteSize.X / self.Window.Scale.Scale
        local maxWidth = math.clamp(rowWidth - 14 - 110 - 20, 100, 200)
        local text = textBox.Text
        local textWidth = textBox.TextBounds.X
        if #text == 0 then
            textWidth = math.min(textBox.TextBounds.X, 90)
        end

        local width = math.clamp(textWidth + textInset + 12, 90, maxWidth) + (focused and 8 or 0)
        width = math.min(width, maxWidth + 8)
        setLabelReserve(titleLabel, descriptionLabel, width + 20)

        if immediate then
            box.Size = UDim2.fromOffset(width, 30)
        else
            tween(box, { Size = UDim2.fromOffset(width, 30) }, 0.18)
        end
    end

    row:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() fitBox(true) end)
    textBox:GetPropertyChangedSignal("Text"):Connect(function() fitBox(false) end)
    textBox:GetPropertyChangedSignal("TextBounds"):Connect(function() fitBox(false) end)
    task.defer(fitBox, true)

    textBox.Focused:Connect(function()
        focused = true
        tween(boxStroke, { Color = Theme.StrokeHover }, 0.15)
        fitBox(false)
    end)

    textBox.FocusLost:Connect(function(enterPressed)
        focused = false
        tween(boxStroke, { Color = Theme.Stroke }, 0.15)
        fitBox(false)

        if options.Numeric then
            local number = tonumber(textBox.Text)
            if not number then
                textBox.Text = ""
                return
            end
        end
        safeCall(options.Callback, textBox.Text, enterPressed)
    end)

    return registerElement(self, options, {
        Set = function(_, value)
            textBox.Text = tostring(value)
            flashStroke(rowStroke)
        end,
        Get = function()
            return textBox.Text
        end,
    }, row, "Input")
end

function Tab:Keybind(options)
    local row, rowStroke, _, titleLabel, descriptionLabel
    options, row, rowStroke, _, titleLabel, descriptionLabel = createControlRow(self, options, {
        Title = "Name",
        Description = "Desc",
        CurrentKeybind = "Default",
        Value = "Default",
    }, "Frame", 110, "Keybind")

    if type(options.Default) == "string" then
        options.Default = Enum.KeyCode[options.Default]
    end

    local button = create("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.fromOffset(44, CONTROL_HEIGHT),
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ClipsDescendants = true,
        Parent = row,
    })
    addCorner(button, UDim.new(0, 6))
    local buttonStroke = addStroke(button)

    local keyLabel = createLabel({
        Size = UDim2.new(1, 0, 1, 0),
        TextSize = 13,
        TextColor3 = Theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextTruncate = Enum.TextTruncate.None,
        Parent = button,
    })

    local keybind = { Value = options.Default, Listening = false }

    local function fitButton(immediate)
        local width = math.max(keyLabel.TextBounds.X + 20, isTouch and 44 or 36)
        setLabelReserve(titleLabel, descriptionLabel, width + 20)
        if immediate then
            button.Size = UDim2.fromOffset(width, CONTROL_HEIGHT)
        else
            tween(button, { Size = UDim2.fromOffset(width, CONTROL_HEIGHT) }, 0.2)
        end
    end
    keyLabel:GetPropertyChangedSignal("TextBounds"):Connect(function()
        fitButton(false)
    end)

    local function render()
        keyLabel.Text = keybind.Listening and "..." or keyName(keybind.Value)
        tween(buttonStroke, { Color = keybind.Listening and Theme.StrokeHover or Theme.Stroke }, 0.15)
        tween(keyLabel, { TextColor3 = keybind.Listening and Theme.Accent or Theme.Muted }, 0.15)
    end

    function keybind:Set(keyCode, silent)
        local wasListening = keybind.Listening
        keybind.Value = keyCode
        keybind.Listening = false
        render()
        if not wasListening then
            flashStroke(rowStroke)
        end
        if not silent then
            safeCall(options.OnChanged, keyCode)
        end
    end

    button.MouseButton1Click:Connect(function()
        keybind.Listening = not keybind.Listening
        render()
    end)

    self.Window:_listen("Began", function(input, processed)
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

        if keybind.Listening then
            -- Empêche cette touche de déclencher aussi l'ouverture/fermeture de la fenêtre
            self.Window._consumedKey = input.KeyCode
            self.Window._consumedAt = os.clock()

            if input.KeyCode == Enum.KeyCode.Escape then
                keybind.Listening = false
                render()
            else
                keybind:Set(input.KeyCode)
            end
            return
        end

        if not processed and keybind.Value ~= nil and input.KeyCode == keybind.Value then
            safeCall(options.Callback, input.KeyCode)
        end
    end, keybind)

    render()
    task.defer(fitButton, true)

    function keybind:Get()
        return keybind.Value
    end

    return registerElement(self, options, keybind, row, "Keybind")
end

function Tab:ColorPicker(options)
    local row, rowStroke, rowHeight
    options, row, rowStroke, rowHeight = createControlRow(self, options, {
        Title = "Name",
        Description = "Desc",
        Color = "Default",
        CurrentValue = "Default",
        Value = "Default",
    }, "Frame")
    row.ClipsDescendants = true

    local header = create("TextButton", {
        Size = UDim2.new(1, 0, 0, rowHeight),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        Parent = row,
    })
    createRowLabels(header, options.Name or "Color", options.Desc, 90)

    -- Aperçu de la couleur
    local swatch = create("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -34, 0.5, 0),
        Size = UDim2.fromOffset(36, 20),
        BorderSizePixel = 0,
        Parent = header,
    })
    addCorner(swatch, UDim.new(0, 6))
    addStroke(swatch, Theme.Stroke)

    local chevron = createChevron(header, 1, -12)

    -- Panneau déroulant
    local panel = create("Frame", {
        Position = UDim2.fromOffset(14, rowHeight + 2),
        Size = UDim2.new(1, -28, 0, 156),
        BackgroundTransparency = 1,
        Visible = false,
        Parent = row,
    })

    -- Zone saturation / luminosité
    local svBox = create("TextButton", {
        Size = UDim2.new(1, -30, 0, 110),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ClipsDescendants = true,
        Parent = panel,
    })
    addCorner(svBox, UDim.new(0, 6))

    local svGradient = create("UIGradient", {
        Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(1, 0, 0)),
        Parent = svBox,
    })

    local blackOverlay = create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BorderSizePixel = 0,
        Parent = svBox,
    })
    create("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(1, 0),
        }),
        Rotation = 90,
        Parent = blackOverlay,
    })

    local svCursor = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(10, 10),
        BackgroundTransparency = 1,
        ZIndex = 3,
        Parent = svBox,
    })
    addCorner(svCursor, UDim.new(1, 0))
    addStroke(svCursor, Color3.new(1, 1, 1), 0, 2)

    -- Barre de teinte (arc-en-ciel)
    local hueBar = create("TextButton", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, 0),
        Size = UDim2.fromOffset(14, 110),
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        Parent = panel,
    })
    addCorner(hueBar, UDim.new(0, 6))
    create("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
            ColorSequenceKeypoint.new(1 / 6, Color3.fromRGB(255, 255, 0)),
            ColorSequenceKeypoint.new(2 / 6, Color3.fromRGB(0, 255, 0)),
            ColorSequenceKeypoint.new(3 / 6, Color3.fromRGB(0, 255, 255)),
            ColorSequenceKeypoint.new(4 / 6, Color3.fromRGB(0, 0, 255)),
            ColorSequenceKeypoint.new(5 / 6, Color3.fromRGB(255, 0, 255)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)),
        }),
        Rotation = 90,
        Parent = hueBar,
    })

    local hueCursor = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0, 0),
        Size = UDim2.fromOffset(18, 5),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        ZIndex = 3,
        Parent = hueBar,
    })
    addCorner(hueCursor, UDim.new(1, 0))
    addStroke(hueCursor, Theme.AccentDark, 0.4)

    -- Champ hexadécimal + affichage RGB
    local hexBox = create("Frame", {
        Position = UDim2.fromOffset(6, 122),
        Size = UDim2.fromOffset(118, 28),
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Parent = panel,
    })
    addCorner(hexBox, UDim.new(0, 6))
    local hexStroke = addStroke(hexBox)

    local hexInput = create("TextBox", {
        Position = UDim2.fromOffset(14, 0),
        Size = UDim2.new(1, -24, 1, 0),
        BackgroundTransparency = 1,
        Text = "",
        TextTruncate = Enum.TextTruncate.None,
        ClipsDescendants = false,
        TextColor3 = Theme.Text,
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
        Parent = hexBox,
    })

    local rgbLabel = createLabel({
        Position = UDim2.fromOffset(134, 122),
        Size = UDim2.new(1, -134, 0, 28),
        TextXAlignment = Enum.TextXAlignment.Right,
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        Parent = panel,
    })

    local picker = { Open = false }
    local hue, saturation, value = Color3.toHSV(options.Default or Theme.Accent)
    local dragMode -- "sv", "hue" ou nil

    local function toHex(color)
        return string.format("#%02X%02X%02X",
            math.floor(color.R * 255 + 0.5),
            math.floor(color.G * 255 + 0.5),
            math.floor(color.B * 255 + 0.5))
    end

    local function updateVisuals(duration)
        local color = Color3.fromHSV(hue, saturation, value)
        picker.Value = color
        swatch.BackgroundColor3 = color
        svGradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromHSV(hue, 1, 1))

        tween(svCursor, { Position = UDim2.fromScale(saturation, 1 - value) }, duration, Enum.EasingStyle.Linear)
        tween(hueCursor, { Position = UDim2.new(0.5, 0, hue, 0) }, duration, Enum.EasingStyle.Linear)

        if not hexInput:IsFocused() then
            hexInput.Text = toHex(color)
        end
        rgbLabel.Text = string.format("RGB %d, %d, %d",
            math.floor(color.R * 255 + 0.5),
            math.floor(color.G * 255 + 0.5),
            math.floor(color.B * 255 + 0.5))
    end

    local function apply(duration, silent)
        updateVisuals(duration)
        if not silent then
            safeCall(options.Callback, picker.Value)
        end
    end

    function picker:Set(color, silent)
        hue, saturation, value = Color3.toHSV(color)
        apply(0.25, silent)
        flashStroke(rowStroke)
    end

    function picker:Get()
        return picker.Value
    end

    local function setOpen(open)
        picker.Open = open
        tween(row, { Size = UDim2.new(1, 0, 0, open and rowHeight + 168 or rowHeight) }, 0.35, Enum.EasingStyle.Quint)
        chevron:Set(open)
        if open then
            panel.Visible = true
        else
            task.delay(0.35, function()
                if not picker.Open then
                    panel.Visible = false
                end
            end)
        end
    end

    function picker:SetOpen(open)
        setOpen(open == true)
    end

    header.MouseButton1Click:Connect(function()
        setOpen(not picker.Open)
    end)

    local function pickSaturationValue(position)
        saturation = math.clamp((position.X - svBox.AbsolutePosition.X) / svBox.AbsoluteSize.X, 0, 1)
        value = 1 - math.clamp((position.Y - svBox.AbsolutePosition.Y) / svBox.AbsoluteSize.Y, 0, 1)
        apply(0.04)
    end

    local function pickHue(position)
        hue = math.clamp((position.Y - hueBar.AbsolutePosition.Y) / hueBar.AbsoluteSize.Y, 0, 0.999)
        apply(0.04)
    end

    svBox.InputBegan:Connect(function(input)
        if isPress(input) then
            dragMode = "sv"
            tween(svCursor, { Size = UDim2.fromOffset(14, 14) }, 0.15, Enum.EasingStyle.Back)
            pickSaturationValue(getMousePosition())
        end
    end)

    hueBar.InputBegan:Connect(function(input)
        if isPress(input) then
            dragMode = "hue"
            tween(hueCursor, { Size = UDim2.fromOffset(20, 7) }, 0.15, Enum.EasingStyle.Back)
            pickHue(getMousePosition())
        end
    end)

    self.Window:_listen("Changed", function(input)
        if not dragMode or not isMove(input) then return end
        local mouse = getMousePosition()
        if dragMode == "sv" then
            pickSaturationValue(mouse)
        else
            pickHue(mouse)
        end
    end, picker)

    self.Window:_listen("Ended", function(input)
        if dragMode and isPress(input) then
            dragMode = nil
            tween(svCursor, { Size = UDim2.fromOffset(10, 10) }, 0.2)
            tween(hueCursor, { Size = UDim2.fromOffset(18, 5) }, 0.2)
        end
    end, picker)

    hexInput.Focused:Connect(function()
        tween(hexStroke, { Color = Theme.StrokeHover }, 0.15)
    end)

    hexInput.FocusLost:Connect(function()
        tween(hexStroke, { Color = Theme.Stroke }, 0.15)
        local r, g, b = hexInput.Text:match("^%s*#?(%x%x)(%x%x)(%x%x)%s*$")
        if r then
            picker:Set(Color3.fromRGB(tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)))
        else
            hexInput.Text = toHex(picker.Value)
        end
    end)

    updateVisuals(0)

    return registerElement(self, options, picker, row, "ColorPicker")
end

function Tab:Stepper(options)
    local row, rowStroke, _, titleLabel, descriptionLabel
    options, row, rowStroke, _, titleLabel, descriptionLabel = createControlRow(self, options, {
        Title = "Name",
        Description = "Desc",
        CurrentValue = "Default",
        Value = "Default",
        Increment = "Step",
    }, "Frame", 150, "Stepper")

    local min = options.Min or 0
    local max = options.Max or 100
    local step = options.Step or 1
    local suffix = options.Suffix or ""
    local snapper = makeSnapper(min, max, step)

    local container = create("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.fromOffset(0, CONTROL_HEIGHT),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Parent = row,
    })
    addCorner(container, UDim.new(0, 6))
    local containerStroke = addStroke(container)

    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        SortOrder = Enum.SortOrder.LayoutOrder,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Parent = container,
    })

    local function makeButton(text, order)
        local button = create("TextButton", {
            Size = UDim2.fromOffset(CONTROL_HEIGHT, CONTROL_HEIGHT),
            BackgroundTransparency = 1,
            Text = text,
            TextColor3 = Theme.Muted,
            TextSize = 18,
            FontFace = Fonts.Medium,
            AutoButtonColor = false,
            LayoutOrder = order,
            Parent = container,
        })
        button.MouseEnter:Connect(function()
            tween(button, { TextColor3 = Theme.Accent }, 0.12)
        end)
        button.MouseLeave:Connect(function()
            tween(button, { TextColor3 = Theme.Muted }, 0.2)
        end)
        return button
    end

    local minusButton = makeButton("−", 1)
    local valueLabel = createLabel({
        Size = UDim2.new(0, 30, 1, 0),
        TextSize = 13,
        TextColor3 = Theme.Accent,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextTruncate = Enum.TextTruncate.None,
        LayoutOrder = 2,
        Parent = container,
    })
    local plusButton = makeButton("+", 3)

    local function fitLabel(immediate)
        local width = math.max(valueLabel.TextBounds.X + 12, 30)
        if immediate then
            valueLabel.Size = UDim2.new(0, width, 1, 0)
        else
            tween(valueLabel, { Size = UDim2.new(0, width, 1, 0) }, 0.2)
        end
    end
    valueLabel:GetPropertyChangedSignal("TextBounds"):Connect(function()
        fitLabel(false)
    end)

    container:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        setLabelReserve(titleLabel, descriptionLabel, container.AbsoluteSize.X / self.Window.Scale.Scale + 20)
    end)

    local stepper = { Value = math.clamp(options.Default or min, min, max) }
    local snap = snapper.snap
    local suppressFlash = false

    local function render()
        valueLabel.Text = snapper.format(stepper.Value) .. suffix
        tween(minusButton, { TextTransparency = stepper.Value <= min and 0.6 or 0 }, 0.15)
        tween(plusButton, { TextTransparency = stepper.Value >= max and 0.6 or 0 }, 0.15)
    end

    function stepper:Set(newValue, silent)
        newValue = snap(tonumber(newValue) or min)
        if newValue == stepper.Value then return end
        stepper.Value = newValue
        render()
        if not suppressFlash then
            flashStroke(rowStroke)
        end
        if not silent then
            safeCall(options.Callback, newValue)
        end
    end

    function stepper:Get()
        return stepper.Value
    end

    local function nudge(direction)
        suppressFlash = true
        stepper:Set(stepper.Value + direction * step)
        suppressFlash = false
        tween(containerStroke, { Color = Theme.StrokeHover }, 0.08)
        task.delay(0.12, function()
            tween(containerStroke, { Color = Theme.Stroke }, 0.2)
        end)
    end

    -- Maintenir appuyé = répétition automatique
    local function attachRepeat(button, direction)
        local held = false
        button.InputBegan:Connect(function(input)
            if not isPress(input) then return end
            held = true
            nudge(direction)
            task.delay(0.4, function()
                while held do
                    nudge(direction)
                    task.wait(0.07)
                end
            end)
        end)
        button.InputEnded:Connect(function(input)
            if isPress(input) then
                held = false
            end
        end)
        button.MouseLeave:Connect(function()
            held = false
        end)
    end

    attachRepeat(minusButton, -1)
    attachRepeat(plusButton, 1)

    render()
    task.defer(fitLabel, true)

    return registerElement(self, options, stepper, row, "Stepper")
end

function Tab:Progress(options)
    options = normalizeOptions(options, {
        Title = "Name",
        Description = "Desc",
        CurrentValue = "Default",
        Value = "Default",
    })

    local row, rowStroke = createRow(self, "Frame", options.Desc and ROW_HEIGHT_DESC + 10 or ROW_HEIGHT + 10)
    hoverStroke(row, rowStroke)

    local top = options.Desc and (ROW_HEIGHT_DESC - 38) / 2 - 2 or 12

    createLabel({
        Position = UDim2.fromOffset(14, top),
        Size = UDim2.new(1, -110, 0, 18),
        Text = options.Name or "Progress",
        Parent = row,
    })

    if options.Desc then
        createLabel({
            Position = UDim2.fromOffset(14, top + 20),
            Size = UDim2.new(1, -110, 0, 17),
            Text = options.Desc,
            TextSize = 13,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            Parent = row,
        })
    end

    local percentLabel = createLabel({
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -14, 0, top),
        Size = UDim2.fromOffset(90, 18),
        TextXAlignment = Enum.TextXAlignment.Right,
        TextSize = 13,
        TextColor3 = Theme.Accent,
        Parent = row,
    })

    local track = create("Frame", {
        Position = UDim2.new(0, 14, 1, -16),
        Size = UDim2.new(1, -28, 0, 5),
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        Parent = row,
    })
    addCorner(track, UDim.new(1, 0))

    local fill = create("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = options.Color or Theme.Accent,
        BorderSizePixel = 0,
        Parent = track,
    })
    addCorner(fill, UDim.new(1, 0))

    local progress = { Value = math.clamp(options.Default or 0, 0, 1) }
    local formatter = options.Format

    local function render(duration)
        local fraction = progress.Value
        tween(fill, { Size = UDim2.new(fraction, 0, 1, 0) }, duration, Enum.EasingStyle.Quint)
        if type(formatter) == "function" then
            percentLabel.Text = tostring(formatter(fraction))
        else
            percentLabel.Text = string.format("%d%%", math.floor(fraction * 100 + 0.5))
        end
    end

    function progress:Set(newValue, silent)
        newValue = math.clamp(tonumber(newValue) or 0, 0, 1)
        if newValue == progress.Value then return end
        progress.Value = newValue
        render(0.35)
        if not silent then
            safeCall(options.Callback, newValue)
        end
    end

    function progress:Get()
        return progress.Value
    end

    function progress:SetColor(color)
        fill.BackgroundColor3 = color
    end

    render(0)

    return registerElement(self, options, progress, row, "Progress")
end

-- Section prête à l'emploi pour sauvegarder / charger / supprimer des configs
function Tab:ConfigManager(options)
    options = normalizeOptions(options, {})
    local window = self.Window
    local manager = {}

    self:Section(options.Name or "Configs")

    local nameInput = self:Input({
        Name = "Config name",
        Placeholder = window.ConfigName,
        Callback = function(text, enterPressed)
            if enterPressed and #text > 0 then
                manager:Save(text)
            end
        end,
    })

    local configDropdown = self:Dropdown({
        Name = "Saved configs",
        Options = window:ListConfigs(),
        Default = window.ConfigName,
        Callback = function(name)
            if name then
                nameInput:Set(name)
            end
        end,
    })

    function manager:Refresh()
        configDropdown:Refresh(window:ListConfigs(), true)
    end

    function manager:Save(name)
        name = name or configDropdown:Get() or window.ConfigName
        local ok, err = window:SaveConfig(name)
        manager:Refresh()
        configDropdown:Set(name, true)
        window:Notify({
            Title = ok and "Config saved" or "Save failed",
            Content = ok and name or tostring(err),
            Type = ok and "Success" or "Error",
            Duration = 3,
        })
    end

    function manager:Load(name)
        name = name or configDropdown:Get()
        if not name then return end
        local ok, err = window:LoadConfig(name)
        window:Notify({
            Title = ok and "Config loaded" or "Load failed",
            Content = ok and name or tostring(err),
            Type = ok and "Success" or "Error",
            Duration = 3,
        })
    end

    function manager:Delete(name)
        name = name or configDropdown:Get()
        if not name then return end
        local ok, err = window:DeleteConfig(name)
        manager:Refresh()
        window:Notify({
            Title = ok and "Config deleted" or "Delete failed",
            Content = ok and name or tostring(err),
            Type = ok and "Info" or "Error",
            Duration = 3,
        })
    end

    self:Button({
        Name = "Save",
        Desc = "Writes every flagged element to the selected name",
        Icon = "save",
        Style = "Primary",
        Callback = function()
            local text = nameInput:Get()
            manager:Save(#text > 0 and text or nil)
        end,
    })

    self:Button({
        Name = "Load",
        Icon = "folder-open",
        Callback = function()
            manager:Load()
        end,
    })

    self:Button({
        Name = "Delete",
        Icon = "trash-2",
        Callback = function()
            local name = configDropdown:Get()
            if not name then return end
            window:Confirm({
                Title = "Delete config",
                Content = "Remove " .. name .. "? This cannot be undone.",
                Icon = "trash-2",
                ConfirmText = "Delete",
                Callback = function()
                    manager:Delete(name)
                end,
            })
        end,
    })

    self:Toggle({
        Name = "Auto save",
        Desc = "Save whenever a flagged element changes",
        Default = window._autoSaveEnabled,
        Callback = function(enabled)
            window._autoSaveEnabled = enabled
        end,
    })

    return manager
end

-- Alias : Tab:CreateButton, Tab:CreateToggle, ... pour chaque méthode publique
for name, method in pairs(table.clone(Tab)) do
    if type(method) == "function" and name:sub(1, 1) ~= "_" and name:sub(1, 6) ~= "Create" then
        Tab["Create" .. name] = method
    end
end

----------------------------------------------------------------------
-- Infos système pour la page "Home"
----------------------------------------------------------------------

local function getExecutorName()
    local name
    pcall(function()
        if typeof(identifyexecutor) == "function" then
            name = (identifyexecutor())
        elseif typeof(getexecutorname) == "function" then
            name = getexecutorname()
        end
    end)
    if type(name) == "string" and #name > 0 then
        return name
    end
    return RunService:IsStudio() and "Studio" or "Unknown"
end

local function getGameName()
    local ok, info = pcall(function()
        return game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId)
    end)
    if ok and type(info) == "table" and info.Name then
        return info.Name
    end
    return "Unknown game"
end

local CountryNames = {
    US = "United States", GB = "United Kingdom", DE = "Germany", FR = "France",
    NL = "Netherlands", SG = "Singapore", JP = "Japan", AU = "Australia",
    BR = "Brazil", IN = "India", HK = "Hong Kong", CA = "Canada",
}

-- Récupère la région (ville, pays) via ipinfo.io, de façon asynchrone
local function fetchRegion(callback)
    task.spawn(function()
        local httpRequest = request or http_request or syn and syn.request or http and http.request
        local region

        if type(httpRequest) == "function" then
            pcall(function()
                local response = httpRequest({ Url = "https://ipinfo.io/json", Method = "GET" })
                local body = type(response) == "table" and (response.Body or response.body) or nil
                if type(body) == "string" then
                    local data = HttpService:JSONDecode(body)
                    if type(data) == "table" and data.country then
                        local country = CountryNames[data.country] or data.country
                        region = data.city and data.city .. ", " .. country or country
                    end
                end
            end)
        end

        callback(region or "Unavailable")
    end)
end

local NotificationColors = {
    Success = Theme.Success,
    Warning = Theme.Warning,
    Error   = Theme.Error,
}

----------------------------------------------------------------------
-- Classe Window
----------------------------------------------------------------------

local Window = {}
Window.__index = Window

function Airflow:Window(options)
    local DEFAULT_NAME = "AirflowUI"

    options = normalizeOptions(options, {
        Name = "Title",
        LoadingSubtitle = "Subtitle",
        ToggleUIKeybind = "Keybind",
    })

    if type(options.Keybind) == "string" then
        options.Keybind = Enum.KeyCode[options.Keybind]
    end

    local windowSize = options.Size or UDim2.fromOffset(640, 480)
    local toggleKey = options.Keybind or Enum.KeyCode.RightControl

    local window = setmetatable({
        Tabs = {},
        CurrentTab = nil,
        Open = true,
        Keybind = toggleKey,
        _connections = {},
        _controls = {},
        _inputListeners = { Began = {}, Changed = {}, Ended = {}, Render = {} },
        _frameSteps = {},
        _destroyed = false,
    }, Window)

    -- Distribue les événements d'entrée aux listeners enregistrés via :_listen
    local function dispatcher(eventName)
        return function(...)
            for _, listener in ipairs(window._inputListeners[eventName]) do
                listener(...)
            end
        end
    end

    local dispatchRender = dispatcher("Render")
    table.insert(window._connections, RunService.RenderStepped:Connect(function(deltaTime)
        dispatchRender(deltaTime)
        for _, step in ipairs(window._frameSteps) do
            step(deltaTime)
        end
    end))
    table.insert(window._connections, UserInputService.InputBegan:Connect(dispatcher("Began")))
    table.insert(window._connections, UserInputService.InputChanged:Connect(dispatcher("Changed")))
    table.insert(window._connections, UserInputService.InputEnded:Connect(dispatcher("Ended")))

    local screenGui = create("ScreenGui", {
        Name = options.Name or DEFAULT_NAME,
        IgnoreGuiInset = true,
        ResetOnSpawn = false,
        DisplayOrder = 999,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    })
    window.Gui = screenGui

    local root = create("Frame", {
        Name = "Window",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = windowSize,
        BackgroundTransparency = 1,
        Parent = screenGui,
    })
    window.Root = root

    local uiScale = create("UIScale", { Parent = root })
    window.Scale = uiScale

    local shadow = create("ImageLabel", {
        Position = UDim2.fromOffset(-25, -25),
        Size = UDim2.new(1, 50, 1, 50),
        BackgroundTransparency = 1,
        Image = Assets.Shadow,
        ImageColor3 = Color3.new(0, 0, 0),
        ImageTransparency = 0.6,
        ScaleType = Enum.ScaleType.Slice,
        SliceCenter = Rect.new(49, 49, 450, 450),
        Parent = root,
    })
    window.Shadow = shadow

    local body = create("CanvasGroup", {
        Name = "Body",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        Parent = root,
    })
    window.Body = body
    addCorner(body, UDim.new(0, 10))
    window.BodyStroke = addStroke(body, Theme.Stroke)
    addTopHighlight(body)
    addGlow(body, UDim2.fromOffset(500, 180), UDim2.new(0.5, 0, 1, 8), 0.86, 270)
    addGlow(body, UDim2.fromOffset(130, 60), UDim2.new(0, -10, 1, -10), 0.75, 90)
    addGlow(body, UDim2.fromOffset(520, 240), UDim2.new(1, -14, 0, 10), 0.92, 90)

    ------------------------------------------------------------------
    -- Barre latérale
    ------------------------------------------------------------------
    local sidebar = create("Frame", {
        Name = "Sidebar",
        Size = UDim2.new(0, 170, 1, 0),
        BackgroundTransparency = 1,
        Parent = body,
    })

    -- séparateur vertical
    create("Frame", {
        Position = UDim2.new(0, 170, 0, 28),
        Size = UDim2.new(0, 1, 1, -56),
        BackgroundColor3 = Theme.Stroke,
        BorderSizePixel = 0,
        Parent = body,
    })

    local header = create("Frame", {
        Name = "Header",
        Size = UDim2.new(1, 0, 0, 72),
        BackgroundTransparency = 1,
        Parent = sidebar,
    })

    local logo = create("ImageLabel", {
        Position = UDim2.fromOffset(22, 27),
        Size = UDim2.fromOffset(30, 28),
        BackgroundTransparency = 1,
        Image = "",
        ImageColor3 = Theme.Accent,
        ScaleType = Enum.ScaleType.Fit,
        Parent = header,
    })
    setIcon(logo, options.Icon or Assets.Logo)

    createLabel({
        Position = UDim2.fromOffset(60, 25),
        Size = UDim2.new(1, -70, 0, 20),
        Text = options.Title or "Airflow",
        TextSize = 20,
        Parent = header,
    })
    createLabel({
        Position = UDim2.fromOffset(60, 45),
        Size = UDim2.new(1, -70, 0, 14),
        Text = options.Subtitle or "",
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        Parent = header,
    })

    local tabList = create("ScrollingFrame", {
        Name = "Tabs",
        Position = UDim2.fromOffset(0, 80),
        Size = UDim2.new(1, 0, 1, -116),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 0,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(),
        Parent = sidebar,
    })
    window.TabList = tabList
    addPadding(tabList, 16, 16, 4, 4)
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 4),
        Parent = tabList,
    })

    -- Petite barre d'accent à gauche de l'onglet actif
    local indicator = create("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.fromOffset(6, 0),
        Size = UDim2.fromOffset(3, 18),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 2,
        Parent = sidebar,
    })
    addCorner(indicator, UDim.new(1, 0))
    window.Indicator = indicator

    -- Garde l'indicateur aligné quand la liste d'onglets défile
    local lastCanvasY = tabList.CanvasPosition.Y
    table.insert(window._frameSteps, function()
        local canvasY = tabList.CanvasPosition.Y
        if canvasY == lastCanvasY or not window.CurrentTab or not window._introDone then return end
        lastCanvasY = canvasY

        local indicatorY = window:_indicatorY(window.CurrentTab)
        local top = tabList.Position.Y.Offset
        local bottom = top + tabList.AbsoluteSize.Y / window.Scale.Scale
        indicator.Visible = indicatorY > top and indicatorY < bottom
        indicator.Position = UDim2.fromOffset(6, indicatorY)
    end)

    -- Pied de sidebar : rappel de la touche pour masquer
    local footer = create("Frame", {
        Position = UDim2.new(0, 22, 1, -36),
        Size = UDim2.new(1, -44, 0, 22),
        BackgroundTransparency = 1,
        Parent = sidebar,
    })

    local keyChip = create("Frame", {
        Size = UDim2.fromOffset(0, 22),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Parent = footer,
    })
    addCorner(keyChip, UDim.new(0, 5))
    addStroke(keyChip)
    addPadding(keyChip, 7, 7)

    window._keyChipLabel = createLabel({
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = keyName(toggleKey),
        TextSize = 11,
        TextColor3 = Theme.Muted,
        TextTruncate = Enum.TextTruncate.None,
        Parent = keyChip,
    })

    local hintLabel = createLabel({
        Size = UDim2.new(1, 0, 1, 0),
        Text = isTouch and "or tap the pill" or "to hide",
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        Parent = footer,
    })

    local function positionHint()
        hintLabel.Position = UDim2.fromOffset(keyChip.AbsoluteSize.X / window.Scale.Scale + 8, 0)
    end
    keyChip:GetPropertyChangedSignal("AbsoluteSize"):Connect(positionHint)
    task.defer(positionHint)

    ------------------------------------------------------------------
    -- Zone de contenu
    ------------------------------------------------------------------
    local content = create("Frame", {
        Name = "Content",
        Position = UDim2.fromOffset(171, 0),
        Size = UDim2.new(1, -171, 1, 0),
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        Parent = body,
    })
    window.Content = content

    -- Deux calques utilisés pour la transition entre onglets
    window._outLayer = create("CanvasGroup", {
        Name = "TransitionOut",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Visible = false,
        ZIndex = 2,
        Parent = content,
    })
    window._inLayer = create("CanvasGroup", {
        Name = "TransitionIn",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Visible = false,
        ZIndex = 3,
        Parent = content,
    })

    -- Bouton de fermeture
    local closeButton = create("TextButton", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -14, 0, 14),
        Size = UDim2.fromOffset(34, 34),
        BackgroundColor3 = Theme.Surface2,
        BackgroundTransparency = 1,
        Text = "×",
        TextColor3 = Theme.Muted,
        TextSize = 28,
        FontFace = Fonts.Bold,
        AutoButtonColor = false,
        ZIndex = 5,
        Parent = content,
    })
    addPadding(closeButton, 0, 0, 1, 0)
    addCorner(closeButton, UDim.new(0, 8))
    closeButton.MouseEnter:Connect(function()
        tween(closeButton, { BackgroundTransparency = 0, TextColor3 = Theme.Text }, 0.15)
    end)
    closeButton.MouseLeave:Connect(function()
        tween(closeButton, { BackgroundTransparency = 1, TextColor3 = Theme.Muted }, 0.2)
    end)
    closeButton.MouseButton1Click:Connect(function()
        window:Toggle(false)
    end)

    ------------------------------------------------------------------
    -- Notifications (empilées en bas à droite)
    ------------------------------------------------------------------
    local notifications = create("Frame", {
        Name = "Notifications",
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -20, 1, -20),
        Size = UDim2.new(0, 280, 1, -40),
        BackgroundTransparency = 1,
        Parent = screenGui,
    })

    local function fitNotifications()
        notifications.Size = UDim2.new(0, math.min(280, screenGui.AbsoluteSize.X - 40), 1, -40)
    end
    table.insert(window._connections, screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitNotifications))

    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        VerticalAlignment = Enum.VerticalAlignment.Bottom,
        Padding = UDim.new(0, 4),
        Parent = notifications,
    })

    window.NotifyHolder = notifications
    window._notifyOrder = 0
    window._toasts = {}
    window.MaxNotifications = options.MaxNotifications or 4

    -- Liste des contrôles (pour empêcher le drag de la fenêtre depuis un bouton, etc.)
    window._controlsDirty = true
    table.insert(window._connections, body.DescendantAdded:Connect(function()
        window._controlsDirty = true
    end))
    table.insert(window._connections, body.DescendantRemoving:Connect(function()
        window._controlsDirty = true
    end))

    window:_enableDrag()
    window.MaxSize = options.MaxSize
    window.KeepOnScreen = options.KeepOnScreen ~= false
    window:_enableResize(options.MinSize or Vector2.new(480, 360))

    ------------------------------------------------------------------
    -- Sauvegarde de configuration
    ------------------------------------------------------------------
    local saving = options.ConfigurationSaving
    if type(saving) == "table" and saving.Enabled ~= false then
        window.ConfigFolder = saving.FolderName or DEFAULT_NAME
        window.ConfigName = saving.FileName or "default"
        window._autoSaveEnabled = true
    else
        window.ConfigFolder = DEFAULT_NAME
        window.ConfigName = "default"
        window._autoSaveEnabled = false
    end

    -- Touche pour afficher / masquer la fenêtre
    table.insert(window._connections, UserInputService.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == window.Keybind then
            task.defer(function()
                -- ignore la touche si elle vient d'être utilisée pour un Keybind
                local consumed = window._consumedKey == input.KeyCode and os.clock() - (window._consumedAt or 0) < 0.2
                window._consumedKey = nil
                if not consumed and not window._destroyed then
                    window:Toggle(not window.Open)
                end
            end)
        end
    end))

    pcall(function()
        if typeof(syn) == "table" and typeof(syn.protect_gui) == "function" then
            syn.protect_gui(screenGui)
        end
    end)
    screenGui.Parent = options.Parent or getGuiParent()

    -- État initial (avant l'animation d'intro)
    uiScale.Scale = 0.9
    body.GroupTransparency = 1
    shadow.ImageTransparency = 1
    window.BodyStroke.Transparency = 1
    root.Visible = false

    window:_fitToScreen(true)
    table.insert(window._connections, screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        window:_fitToScreen()
        window:_clampToScreen()
    end))

    -- Bouton flottant pour ouvrir/fermer (par défaut sur mobile)
    if options.OpenButton ~= nil and options.OpenButton ~= false or options.OpenButton == nil and isTouch then
        window:_createOpenButton(type(options.OpenButton) == "table" and options.OpenButton or {})
    end

    window._introDone = false
    table.insert(Airflow.Windows, window)

    if options.Home then
        window:_buildHome(type(options.Home) == "table" and options.Home or {})
    end

    -- Écran de chargement
    local loading = options.Loading
    if type(loading) == "table" then
        options.LoadingDuration = loading.Duration or options.LoadingDuration
        options.LoadingText = loading.Text or loading.Subtitle or options.LoadingText
        options.LoadingSteps = loading.Steps or options.LoadingSteps
        options.LoadingTitle = loading.Title or options.LoadingTitle
        loading = loading.Enabled ~= false
    end

    if loading == false then
        task.defer(function()
            window:_playIntro()
        end)
    else
        window:_showLoader(options)
    end

    return window
end

Airflow.CreateWindow = Airflow.Window

-- Raccourcis : appliquent l'action à la dernière fenêtre créée
function Airflow:Notify(options)
    local window = Airflow.Windows[#Airflow.Windows]
    if window then
        return window:Notify(options)
    end
end

function Airflow:Confirm(options)
    local window = Airflow.Windows[#Airflow.Windows]
    if window then
        return window:Confirm(options)
    end
end

function Airflow:Dialog(options)
    local window = Airflow.Windows[#Airflow.Windows]
    if window then
        return window:Dialog(options)
    end
end

----------------------------------------------------------------------
-- Interaction : drag, redimensionnement, bouton flottant
----------------------------------------------------------------------

local function pointInGui(point, gui)
    local position, size = gui.AbsolutePosition, gui.AbsoluteSize
    return point.X >= position.X and point.X <= position.X + size.X
        and point.Y >= position.Y and point.Y <= position.Y + size.Y
end

-- Vrai si `gui` est réellement visible/cliquable à `point` (parents visibles, pas rognés)
local function isHitVisible(gui, rootGui, point)
    local current = gui
    while current and current ~= rootGui and current:IsA("GuiObject") do
        if not current.Visible then
            return false
        end
        local parent = current.Parent
        if parent and parent ~= rootGui and parent:IsA("GuiObject")
            and (parent.ClipsDescendants or parent:IsA("ScrollingFrame"))
            and not pointInGui(point, parent) then
            return false
        end
        current = parent
    end
    return true
end

function Window:_refreshControls()
    local controls = {}
    for _, descendant in ipairs(self.Body:GetDescendants()) do
        if descendant:IsA("GuiButton") or descendant:IsA("TextBox") or descendant:GetAttribute("NoDrag") then
            table.insert(controls, descendant)
        end
    end
    self._controls = controls
    self._controlsDirty = false
end

-- Le point est-il au-dessus d'un contrôle interactif ? (alors on ne drag pas la fenêtre)
function Window:_overControl(point)
    if self._dialog then
        return true
    end
    if self._controlsDirty then
        self:_refreshControls()
    end
    for _, control in ipairs(self._controls) do
        if control.Parent and pointInGui(point, control) and isHitVisible(control, self.Body, point) then
            return true
        end
    end
    return false
end

function Window:_enableDrag()
    local dragging = false
    local grabOffset = Vector2.zero
    local target

    local function getRootCenter()
        local root = self.Root
        return root.AbsolutePosition + root.AbsoluteSize * root.AnchorPoint - self.Gui.AbsolutePosition
    end

    table.insert(self._connections, UserInputService.InputBegan:Connect(function(input)
        if not isPress(input) then return end
        if not self.Open or not self.Root.Visible then return end

        local mouse = getMousePosition()
        if not pointInGui(mouse, self.Body) or self:_overControl(mouse) then return end

        dragging = true
        grabOffset = mouse - getRootCenter()
    end))

    table.insert(self._connections, UserInputService.InputEnded:Connect(function(input)
        if not dragging then return end
        if isPress(input) then
            dragging, target = false, nil
            self:_clampToScreen()
        end
    end))

    -- Déplacement lissé (interpolation exponentielle)
    table.insert(self._frameSteps, function(deltaTime)
        if not dragging then return end
        target = getMousePosition() - grabOffset
        local current = getRootCenter()
        local alpha = 1 - math.exp(-deltaTime * 45)
        local position = current:Lerp(target, alpha)
        self.Root.Position = UDim2.fromOffset(position.X, position.Y)
    end)
end

-- Petite animation d'apparition d'une carte (zoom depuis 94 %)
local function revealCard(frame, delay, force)
    if not frame.Visible and not force then return end
    frame.Visible = false
    task.delay(delay, function()
        if not frame.Parent then return end
        local scale = create("UIScale", { Scale = 0.94, Parent = frame })
        frame.Visible = true
        tween(scale, { Scale = 1 }, 0.4, Enum.EasingStyle.Back)
        task.delay(0.4, function()
            scale:Destroy()
        end)
    end)
end

function Window:_revealCards(tab, baseDelay)
    if tab._revealed then return end
    tab._revealed = true

    local index = 0
    for _, child in ipairs(tab.List:GetChildren()) do
        if child:IsA("GuiObject") then
            revealCard(child, (baseDelay or 0) + index * 0.035)
            index += 1
        end
    end
end

function Window:_playIntro(afterLoader)
    if self._introDone then return end
    self._introDone = true

    task.delay(1, function()
        self._autoSaveReady = true
    end)

    local root, body, shadow, scale = self.Root, self.Body, self.Shadow, self.Scale

    if self.CurrentTab then
        self:_revealCards(self.CurrentTab, afterLoader and 0.15 or 0.25)
    end
    root.Visible = true

    if afterLoader then
        scale.Scale = self._fitScale or 1
        root.Position = UDim2.fromScale(0.5, 0.5)
        tween(body, { GroupTransparency = 0 }, 0.3)
        tween(self.BodyStroke, { Transparency = 0 }, 0.3)
        tween(shadow, { ImageTransparency = 0.6 }, 0.3)
    else
        root.Position = UDim2.new(0.5, 0, 0.5, 24)
        tween(scale, { Scale = self._fitScale or 1 }, 0.5, Enum.EasingStyle.Back)
        tween(root, { Position = UDim2.fromScale(0.5, 0.5) }, 0.5, Enum.EasingStyle.Quint)
        tween(body, { GroupTransparency = 0 }, 0.35)
        tween(self.BodyStroke, { Transparency = 0 }, 0.35)
    end

    if not afterLoader then
        tween(shadow, { ImageTransparency = 0.6 }, 0.5)
    end

    for index, tab in ipairs(self.Tabs) do
        revealCard(tab._button, 0.1 + index * 0.05, true)
    end

    self.Indicator.Visible = false
    task.delay(0.15 + #self.Tabs * 0.05, function()
        if self.CurrentTab then
            self:_placeIndicator(self.CurrentTab)
        end
    end)
end

-- Écran de chargement : une carte qui se transforme ensuite en fenêtre
function Window:_showLoader(options)
    local duration = options.LoadingDuration or 1.6
    local gui = self.Gui

    local card = create("CanvasGroup", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 16),
        Size = UDim2.fromOffset(300, 132),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        GroupTransparency = 1,
        ZIndex = 10,
        Parent = gui,
    })
    local cardCorner = addCorner(card, UDim.new(0, 12))
    local cardStroke = addStroke(card, Theme.Stroke, 1)
    addTopHighlight(card)
    addGlow(card, UDim2.fromOffset(320, 140), UDim2.new(1, -20, 0, -20), 0.85, 90)
    addGlow(card, UDim2.fromOffset(240, 100), UDim2.new(0, 10, 1, 10), 0.9, 270)

    local cardScale = create("UIScale", { Scale = 0.92, Parent = card })

    local cardShadow = create("ImageLabel", {
        Position = UDim2.fromOffset(-25, -25),
        Size = UDim2.new(1, 50, 1, 50),
        BackgroundTransparency = 1,
        Image = Assets.Shadow,
        ImageColor3 = Color3.new(0, 0, 0),
        ImageTransparency = 1,
        ScaleType = Enum.ScaleType.Slice,
        SliceCenter = Rect.new(49, 49, 450, 450),
        ZIndex = 0,
        Parent = card,
    })

    local logoHolder = create("Frame", {
        Position = UDim2.fromOffset(24, 26),
        Size = UDim2.fromOffset(40, 40),
        BackgroundTransparency = 1,
        Parent = card,
    })
    local logoImage = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromScale(0.5, 0.5),
        Rotation = -14,
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Accent,
        ImageTransparency = 1,
        ScaleType = Enum.ScaleType.Fit,
        Parent = logoHolder,
    })
    setIcon(logoImage, options.Icon or Assets.Logo)

    task.delay(0.15, function()
        tween(logoImage, {
            Size = UDim2.fromScale(0.85, 0.85),
            Rotation = 0,
            ImageTransparency = 0,
        }, 0.6, Enum.EasingStyle.Back)
    end)

    createLabel({
        Position = UDim2.fromOffset(78, 30),
        Size = UDim2.new(1, -100, 0, 22),
        Text = options.LoadingTitle or options.Title or "Airflow",
        TextSize = 20,
        Parent = card,
    })
    local statusLabel = createLabel({
        Position = UDim2.fromOffset(78, 52),
        Size = UDim2.new(1, -100, 0, 16),
        Text = options.LoadingText or options.Subtitle or "Loading",
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        Parent = card,
    })

    -- Barre de progression + reflet qui glisse
    local bar = create("Frame", {
        Position = UDim2.new(0, 24, 1, -30),
        Size = UDim2.new(1, -48, 0, 4),
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = card,
    })
    addCorner(bar, UDim.new(1, 0))

    local barFill = create("Frame", {
        Size = UDim2.fromScale(0, 1),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        Parent = bar,
    })
    addCorner(barFill, UDim.new(1, 0))

    local shimmer = create("Frame", {
        Position = UDim2.fromScale(-0.4, 0),
        Size = UDim2.fromScale(0.4, 1),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BackgroundTransparency = 0.6,
        BorderSizePixel = 0,
        ZIndex = 2,
        Parent = bar,
    })
    create("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.5, 0),
            NumberSequenceKeypoint.new(1, 1),
        }),
        Parent = shimmer,
    })

    tween(card, { GroupTransparency = 0, Position = UDim2.fromScale(0.5, 0.5) }, 0.4, Enum.EasingStyle.Quint)
    tween(cardScale, { Scale = 1 }, 0.5, Enum.EasingStyle.Back)
    tween(cardShadow, { ImageTransparency = 0.6 }, 0.4)

    local shimmerTween = TweenService:Create(
        shimmer,
        TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1),
        { Position = UDim2.fromScale(1, 0) }
    )
    shimmerTween:Play()

    tween(barFill, { Size = UDim2.fromScale(0.85, 1) }, duration * 0.8, Enum.EasingStyle.Quart)

    -- Précharge les icônes pendant l'écran de chargement
    task.spawn(loadIcons)

    -- Textes d'étapes qui défilent
    local steps = options.LoadingSteps or { "Preparing interface", "Loading icons", "Almost there" }
    for index, text in ipairs(steps) do
        task.delay(duration * (index - 1) / #steps, function()
            if card.Parent then
                statusLabel.Text = text
            end
        end)
    end

    -- Fin du chargement : la carte grandit pour devenir la fenêtre
    task.delay(duration, function()
        tween(barFill, { Size = UDim2.fromScale(1, 1) }, 0.25, Enum.EasingStyle.Quint)

        task.delay(0.25, function()
            shimmerTween:Cancel()

            for _, child in ipairs(card:GetChildren()) do
                if child:IsA("TextLabel") then
                    tween(child, { TextTransparency = 1 }, 0.15)
                end
            end
            for _, child in ipairs(logoHolder:GetChildren()) do
                tween(child, { ImageTransparency = 1 }, 0.15)
            end
            tween(bar, { BackgroundTransparency = 1 }, 0.15)
            tween(barFill, { BackgroundTransparency = 1 }, 0.15)
            tween(shimmer, { BackgroundTransparency = 1 }, 0.1)

            local fitScale = self._fitScale or 1
            local rootSize = self.Root.Size
            tween(card, {
                Size = UDim2.fromOffset(rootSize.X.Offset * fitScale, rootSize.Y.Offset * fitScale),
                Position = UDim2.fromScale(0.5, 0.5),
            }, 0.5, Enum.EasingStyle.Quint)
            tween(cardCorner, { CornerRadius = UDim.new(0, 10) }, 0.5, Enum.EasingStyle.Quint)
            tween(cardScale, { Scale = 1 }, 0.5, Enum.EasingStyle.Quint)

            task.delay(0.28, function()
                self:_playIntro(true)
                tween(card, { GroupTransparency = 1 }, 0.25)
                tween(cardStroke, { Transparency = 1 }, 0.2)
                tween(cardShadow, { ImageTransparency = 1 }, 0.2)
            end)

            task.delay(0.6, function()
                card:Destroy()
            end)
        end)
    end)
end

-- Réduit la fenêtre si l'écran est trop petit (jamais en dessous de 45 %)
function Window:_fitToScreen(immediate)
    local screen = self.Gui.AbsoluteSize
    if screen.X == 0 or screen.Y == 0 then return end

    local size = self.Root.Size
    local fit = math.min(
        1,
        (screen.X - 24) / math.max(size.X.Offset, 1),
        (screen.Y - 24) / math.max(size.Y.Offset, 1)
    )
    self._fitScale = math.max(fit, 0.45)

    if self._introDone and self.Open then
        if immediate then
            self.Scale.Scale = self._fitScale
        else
            tween(self.Scale, { Scale = self._fitScale }, 0.2)
        end
    end
end

-- Empêche la fenêtre de sortir de l'écran
function Window:_clampToScreen()
    if not self.KeepOnScreen then return end

    local screen = self.Gui.AbsoluteSize
    local root = self.Root
    local half = root.AbsoluteSize / 2
    local center = root.AbsolutePosition + half - self.Gui.AbsolutePosition

    local clamped = Vector2.new(
        math.clamp(center.X, math.min(half.X, screen.X / 2), math.max(screen.X - half.X, screen.X / 2)),
        math.clamp(center.Y, math.min(half.Y, screen.Y / 2), math.max(screen.Y - half.Y, screen.Y / 2))
    )

    if (clamped - center).Magnitude > 0.5 then
        tween(root, { Position = UDim2.fromOffset(clamped.X, clamped.Y) }, 0.25, Enum.EasingStyle.Quint)
    end
end

-- Pastille flottante déplaçable pour ouvrir / fermer la fenêtre
function Window:_createOpenButton(options)
    local gui = self.Gui

    local button = create("TextButton", {
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 14),
        Size = UDim2.fromOffset(0, 40),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 30,
        Parent = gui,
    })
    addCorner(button, UDim.new(1, 0))
    addStroke(button, Theme.Stroke)
    addPadding(button, 12, 16)

    local icon = create("ImageLabel", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.fromOffset(20, 20),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Accent,
        ScaleType = Enum.ScaleType.Fit,
        ZIndex = 31,
        Parent = button,
    })
    setIcon(icon, options.Icon or Assets.Logo)

    createLabel({
        Position = UDim2.fromOffset(28, 0),
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = options.Title or "Airflow",
        TextSize = 13,
        TextTruncate = Enum.TextTruncate.None,
        ZIndex = 31,
        Parent = button,
    })

    self.OpenButton = button

    local pressed, moved = false, false
    local grabOffset = Vector2.zero

    button.InputBegan:Connect(function(input)
        if isPress(input) then
            pressed, moved = true, false
            grabOffset = getMousePosition() - button.AbsolutePosition
        end
    end)

    table.insert(self._connections, UserInputService.InputChanged:Connect(function(input)
        if not pressed then return end
        if isMove(input) then
            local position = getMousePosition() - grabOffset - gui.AbsolutePosition
            if (position - (button.AbsolutePosition - gui.AbsolutePosition)).Magnitude > 3 then
                moved = true
            end
            button.AnchorPoint = Vector2.new(0, 0)
            button.Position = UDim2.fromOffset(
                math.clamp(position.X, 0, math.max(gui.AbsoluteSize.X - button.AbsoluteSize.X, 0)),
                math.clamp(position.Y, 0, math.max(gui.AbsoluteSize.Y - button.AbsoluteSize.Y, 0))
            )
        end
    end))

    table.insert(self._connections, UserInputService.InputEnded:Connect(function(input)
        if pressed and isPress(input) then
            pressed = false
            if not moved then
                self:Toggle()
            end
        end
    end))
end

-- Poignée de redimensionnement en bas à droite
function Window:_enableResize(minSize)
    local maxSize = self.MaxSize or Vector2.new(math.huge, math.huge)

    local handle = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(1, 4, 1, 4),
        Size = UDim2.fromOffset(32, 32),
        BackgroundTransparency = 1,
        Active = true,
        ZIndex = 20,
        Parent = self.Root,
    })

    local grip = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, -16, 0.5, -16),
        Size = UDim2.fromOffset(96, 96),
        BackgroundTransparency = 1,
        Image = "rbxassetid://120997033468887",
        ImageColor3 = Theme.Accent,
        ImageTransparency = 0.8,
        ZIndex = 20,
        Parent = handle,
    })

    local resizing = false
    local startSize = self.Root.Size
    local startMouse = Vector2.zero
    local targetSize

    handle.InputBegan:Connect(function(input)
        if isPress(input) then
            resizing = true
            startSize = self.Root.Size
            startMouse = getMousePosition()
            tween(grip, { ImageTransparency = 0.35 }, 0.1)
        end
    end)
    handle.MouseEnter:Connect(function()
        if not resizing then
            tween(grip, { ImageTransparency = 0.35 }, 0.1)
        end
    end)
    handle.MouseLeave:Connect(function()
        if not resizing then
            tween(grip, { ImageTransparency = 0.8 }, 0.17)
        end
    end)

    table.insert(self._connections, UserInputService.InputEnded:Connect(function(input)
        if resizing and isPress(input) then
            resizing = false
            tween(grip, { ImageTransparency = 0.8 }, 0.17)
            if targetSize then
                self.Root.Size = UDim2.fromOffset(targetSize.X, targetSize.Y)
                targetSize = nil
            end
            self:_fitToScreen()
            self:_clampToScreen()
        end
    end))

    table.insert(self._frameSteps, function(deltaTime)
        if not resizing then return end

        local delta = (getMousePosition() - startMouse) / self.Scale.Scale
        targetSize = Vector2.new(
            math.clamp(startSize.X.Offset + delta.X * 2, minSize.X, maxSize.X),
            math.clamp(startSize.Y.Offset + delta.Y * 2, minSize.Y, maxSize.Y)
        )

        local current = Vector2.new(self.Root.Size.X.Offset, self.Root.Size.Y.Offset)
        local alpha = 1 - math.exp(-deltaTime * 35)
        local nextSize = current:Lerp(targetSize, alpha)
        nextSize = Vector2.new(math.floor(nextSize.X + 0.5), math.floor(nextSize.Y + 0.5))

        if nextSize ~= current then
            self.Root.Size = UDim2.fromOffset(nextSize.X, nextSize.Y)
        end
    end)
end

----------------------------------------------------------------------
-- Configurations (sauvegarde / chargement via l'API fichier de l'exécuteur)
----------------------------------------------------------------------

local function configPath(window, name)
    return window.ConfigFolder .. "/" .. name .. ".json"
end

local function fileApiAvailable()
    local functionType = "function"
    return type(writefile) == functionType and type(readfile) == functionType and type(isfile) == functionType
end

local function ensureFolder(folder)
    if type(isfolder) == "function" and type(makefolder) == "function" and not isfolder(folder) then
        makefolder(folder)
    end
end

-- Transforme un élément en table sérialisable en JSON
local function serializeElement(element)
    local elementType = element._type
    local value = element:Get()

    if elementType == "Keybind" then
        return { Type = elementType, Value = value and value.Name or nil }
    elseif elementType == "ColorPicker" then
        return { Type = elementType, Value = { value.R, value.G, value.B } }
    end
    return { Type = elementType, Value = value }
end

local function applySerialized(element, saved, silent)
    local elementType = element._type
    local value = saved.Value

    if elementType == "Keybind" then
        element:Set(value and Enum.KeyCode[value] or nil, silent)
    elseif elementType == "ColorPicker" then
        if type(value) == "table" then
            element:Set(Color3.new(value[1], value[2], value[3]), silent)
        end
    elseif value ~= nil then
        element:Set(value, silent)
    end
end

function Window:SaveConfig(name)
    name = name or self.ConfigName
    if not fileApiAvailable() then
        return false, "file API unavailable"
    end
    ensureFolder(self.ConfigFolder)

    local data = {}
    for flag, element in pairs(Airflow.Flags) do
        if element._type and type(element.Get) == "function" then
            data[flag] = serializeElement(element)
        end
    end

    local ok, err = pcall(function()
        writefile(configPath(self, name), HttpService:JSONEncode(data))
    end)
    if ok then
        self.ConfigName = name
    end
    return ok, err
end

function Window:LoadConfig(name, silent)
    name = name or self.ConfigName
    if not fileApiAvailable() then
        return false, "file API unavailable"
    end

    local path = configPath(self, name)
    if not isfile(path) then
        return false, "no config named " .. name
    end

    local ok, data = pcall(function()
        return HttpService:JSONDecode(readfile(path))
    end)
    if not ok or type(data) ~= "table" then
        return false, "config is not valid JSON"
    end

    -- Désactive l'auto-save le temps d'appliquer les valeurs
    local previousAutoSave = self._autoSaveEnabled
    self._autoSaveEnabled = false

    for flag, saved in pairs(data) do
        local element = Airflow.Flags[flag]
        if element and type(element.Set) == "function" and type(saved) == "table" and saved.Type == element._type then
            pcall(applySerialized, element, saved, silent == true)
        end
    end

    self._autoSaveEnabled = previousAutoSave
    self._autoSaveReady = true
    self.ConfigName = name
    return true
end

function Window:DeleteConfig(name)
    if not fileApiAvailable() or type(delfile) ~= "function" then
        return false, "file API unavailable"
    end

    local path = configPath(self, name)
    if not isfile(path) then
        return false, "no config named " .. name
    end
    delfile(path)
    return true
end

function Window:ListConfigs()
    local names = {}
    if type(listfiles) ~= "function" or type(isfolder) ~= "function" or not isfolder(self.ConfigFolder) then
        return names
    end
    for _, path in ipairs(listfiles(self.ConfigFolder)) do
        local name = path:match("([^/\\]+)%.json$")
        if name then
            table.insert(names, name)
        end
    end
    table.sort(names)
    return names
end

-- Sauvegarde différée (regroupe les changements rapprochés)
function Window:_autoSave()
    if not self._autoSaveEnabled or self._destroyed or not self._autoSaveReady then return end
    if self._autoSavePending then return end

    self._autoSavePending = true
    task.delay(0.5, function()
        self._autoSavePending = false
        if not self._destroyed then
            self:SaveConfig(self.ConfigName)
        end
    end)
end

----------------------------------------------------------------------
-- Petits composants utilisés par la page Home et les onglets
----------------------------------------------------------------------

-- Placeholder "Nothing here yet" affiché dans un onglet vide
local function createEmptyState(parent, icon, text)
    local holder = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, -10),
        Size = UDim2.fromOffset(200, 70),
        BackgroundTransparency = 1,
        Parent = parent,
    })

    local image = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 0),
        Size = UDim2.fromOffset(26, 26),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Muted,
        ImageTransparency = 0.15,
        ScaleType = Enum.ScaleType.Fit,
        Parent = holder,
    })
    setIcon(image, icon)

    local label = createLabel({
        Position = UDim2.fromOffset(0, 36),
        Size = UDim2.new(1, 0, 0, 16),
        Text = text,
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = holder,
    })

    return holder, label, image
end

-- Carte de statistique (FPS, ping, ...). Retourne le label de valeur.
local function createStatCard(grid, order, icon, title)
    local card = create("Frame", {
        Size = UDim2.new(0.5, -4, 0, 62),
        BackgroundColor3 = Theme.Surface2,
        BorderSizePixel = 0,
        LayoutOrder = order,
        Parent = grid,
    })
    addCorner(card)
    addStroke(card)
    card:SetAttribute("NoDrag", true)

    if icon then
        createIconFrame(card, icon, Theme.Muted, UDim2.new(0, 14, 0, 21))
    end

    createLabel({
        Position = UDim2.fromOffset(icon and 36 or 14, 12),
        Size = UDim2.new(1, -(icon and 50 or 28), 0, 16),
        Text = title,
        TextSize = 12,
        TextColor3 = Theme.Muted,
        Parent = card,
    })

    return createLabel({
        Position = UDim2.fromOffset(14, 34),
        Size = UDim2.new(1, -28, 0, 18),
        Text = "…",
        TextSize = 15,
        Parent = card,
    })
end

-- Fait réapparaître en fondu un élément et tous ses descendants
local function fadeInTree(root)
    local entries = {}

    local function collect(parent)
        for _, child in ipairs(parent:GetChildren()) do
            if child:IsA("TextLabel") or child:IsA("TextButton") or child:IsA("TextBox") then
                table.insert(entries, { child, "TextTransparency", child.TextTransparency })
            elseif child:IsA("ImageLabel") or child:IsA("ImageButton") then
                table.insert(entries, { child, "ImageTransparency", child.ImageTransparency })
            elseif child:IsA("UIStroke") then
                table.insert(entries, { child, "Transparency", child.Transparency })
            elseif child:IsA("Frame") then
                table.insert(entries, { child, "BackgroundTransparency", child.BackgroundTransparency })
            end
            collect(child)
        end
    end

    if root:IsA("Frame") then
        table.insert(entries, { root, "BackgroundTransparency", root.BackgroundTransparency })
    end
    collect(root)

    for _, entry in ipairs(entries) do
        entry[1][entry[2]] = 1
        tween(entry[1], { [entry[2]] = entry[3] }, 0.28)
    end
end

-- Glisse un CanvasGroup depuis le bas en fondu
local function slideIn(group, yOffset)
    yOffset = yOffset or 0
    group.GroupTransparency = 1
    group.Position = UDim2.fromOffset(0, yOffset + 14)
    group.Visible = true
    tween(group, { GroupTransparency = 0, Position = UDim2.fromOffset(0, yOffset) }, 0.32, Enum.EasingStyle.Quint)
end

----------------------------------------------------------------------
-- Page "Home" (infos système, pages d'info personnalisées)
----------------------------------------------------------------------

function Window:_buildHome(options)
    local homeTab = self:Tab({
        Name = options.Name or "Home",
        Desc = options.Desc,
        Icon = options.Icon or "house",
    })
    local list = homeTab.List

    local customPages = options.Pages or options.Tabs
    local pages = {} -- { Title, Icon, Frame }
    local pageBar

    -- Barre de sous-pages (seulement si des pages personnalisées sont fournies)
    if type(customPages) == "table" and #customPages > 0 then
        pageBar = create("Frame", {
            Size = UDim2.new(1, 0, 0, 32),
            BackgroundTransparency = 1,
            LayoutOrder = 1,
            Parent = list,
        })
        create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 6),
            Parent = pageBar,
        })
    end

    -- Message d'accueil selon l'heure
    local greeting = options.Greeting
    if greeting == nil then
        local hour = tonumber(os.date("%H")) or 12
        local period = hour < 12 and "morning" or (hour < 18 and "afternoon" or "evening")
        greeting = "Good " .. period .. "."
    end

    local welcomeCard = create("Frame", {
        Size = UDim2.new(1, 0, 0, 58),
        BackgroundColor3 = Theme.Surface2,
        BorderSizePixel = 0,
        LayoutOrder = 2,
        Parent = list,
    })
    welcomeCard:SetAttribute("NoDrag", true)
    addCorner(welcomeCard)
    addStroke(welcomeCard)

    local avatar = create("ImageLabel", {
        Position = UDim2.fromOffset(12, 11),
        Size = UDim2.fromOffset(36, 36),
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Parent = welcomeCard,
    })
    addCorner(avatar, UDim.new(0, 8))
    addStroke(avatar)

    task.spawn(function()
        local ok, thumbnail = pcall(function()
            return Players:GetUserThumbnailAsync(LocalPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
        end)
        if ok and thumbnail then
            avatar.Image = thumbnail
        end
    end)

    createLabel({
        Position = UDim2.fromOffset(58, 11),
        Size = UDim2.new(1, -72, 0, 18),
        Text = (options.Welcome or "Hello, ") .. LocalPlayer.DisplayName,
        TextSize = 15,
        Parent = welcomeCard,
    })
    createLabel({
        Position = UDim2.fromOffset(58, 30),
        Size = UDim2.new(1, -72, 0, 16),
        Text = greeting,
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        Parent = welcomeCard,
    })

    -- Section "System info"
    local statsSection = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = 3,
        Parent = list,
    })
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8),
        Parent = statsSection,
    })

    if options.Sections ~= false then
        local sectionHeader = create("Frame", {
            Size = UDim2.new(1, 0, 0, 24),
            BackgroundTransparency = 1,
            LayoutOrder = 1,
            Parent = statsSection,
        })
        local sectionLabel = createLabel({
            Position = UDim2.fromOffset(2, 6),
            Size = UDim2.new(0, 0, 0, 16),
            AutomaticSize = Enum.AutomaticSize.X,
            Text = string.upper(options.SectionName or "System info"),
            TextSize = 12,
            TextColor3 = Theme.Muted,
            TextTruncate = Enum.TextTruncate.None,
            Parent = sectionHeader,
        })
        local sectionLine = create("Frame", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, 0, 0, 14),
            Size = UDim2.new(1, -12, 0, 1),
            BackgroundColor3 = Theme.Stroke,
            BorderSizePixel = 0,
            Parent = sectionHeader,
        })
        local function fitSectionLine()
            sectionLine.Size = UDim2.new(1, -(sectionLabel.AbsoluteSize.X + 14), 0, 1)
        end
        sectionLabel:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitSectionLine)
        task.defer(fitSectionLine)
    end

    local statsGrid = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = 2,
        Parent = statsSection,
    })
    create("UIGridLayout", {
        CellSize = UDim2.new(0.5, -4, 0, 62),
        CellPadding = UDim2.fromOffset(8, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = statsGrid,
    })

    local requestedStats = options.Stats or { "FPS", "Ping", "Executor", "Game", "Region", "Time" }
    local enabledStats = {}
    for _, statName in ipairs(requestedStats) do
        enabledStats[statName] = true
    end

    local statCount = 0
    local function addStat(statName, icon, title)
        if not enabledStats[statName] then return nil end
        statCount += 1
        return createStatCard(statsGrid, statCount, icon, title)
    end

    local fpsLabel      = addStat("FPS", "activity", "FPS")
    local pingLabel     = addStat("Ping", "wifi", "Ping")
    local executorLabel = addStat("Executor", "terminal", "Executor")
    local gameLabel     = addStat("Game", "gamepad-2", "Game")
    local regionLabel   = addStat("Region", "globe", "Server region")
    local timeLabel     = addStat("Time", "clock", "Time of day")
    local playersLabel  = addStat("Players", "users", "Players")
    local uptimeLabel   = addStat("Uptime", "timer", "Session")

    if executorLabel then
        executorLabel.Text = getExecutorName()
    end
    if gameLabel then
        gameLabel.Text = "Loading"
        task.spawn(function()
            gameLabel.Text = getGameName()
        end)
    end
    if regionLabel then
        regionLabel.Text = "Loading"
        fetchRegion(function(region)
            regionLabel.Text = region
        end)
    end

    -- Boucle de mise à jour (1x par seconde, seulement quand la page Home est visible)
    local frameCount = 0
    local sessionStart = os.clock()
    self:_listen("Render", function()
        frameCount += 1
    end)

    task.spawn(function()
        while not self._destroyed and homeTab.List.Parent and homeTab._page.Parent do
            if not self.Open or self.CurrentTab ~= homeTab then
                frameCount = 0
                task.wait(1)
                continue
            end

            if fpsLabel then
                fpsLabel.Text = tostring(frameCount)
            end
            frameCount = 0

            if pingLabel then
                local ok, ping = pcall(function()
                    return math.floor(LocalPlayer:GetNetworkPing() * 1e3)
                end)
                pingLabel.Text = (ok and ping or 0) .. " ms"
            end
            if timeLabel then
                timeLabel.Text = os.date(options.TimeFormat or "%H:%M")
            end
            if playersLabel then
                playersLabel.Text = #Players:GetPlayers() .. " / " .. Players.MaxPlayers
            end
            if uptimeLabel then
                local seconds = math.floor(os.clock() - sessionStart)
                uptimeLabel.Text = string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
            end

            task.wait(1)
        end
    end)

    table.insert(pages, {
        Title = options.SectionName or "Details",
        Icon = options.TabIcon or "layout-grid",
        Frame = statsSection,
    })

    -- Pages personnalisées (texte, entrées de changelog, ou fonction Build)
    if pageBar then
        for _, pageData in ipairs(customPages) do
            local pageFrame = create("Frame", {
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1,
                Visible = false,
                LayoutOrder = 3,
                Parent = list,
            })
            create("UIListLayout", {
                SortOrder = Enum.SortOrder.LayoutOrder,
                Padding = UDim.new(0, 8),
                Parent = pageFrame,
            })

            if type(pageData.Content) == "string" then
                local textCard = create("Frame", {
                    Size = UDim2.new(1, 0, 0, 0),
                    AutomaticSize = Enum.AutomaticSize.Y,
                    BackgroundColor3 = Theme.Surface2,
                    BorderSizePixel = 0,
                    LayoutOrder = 1,
                    Parent = pageFrame,
                })
                textCard:SetAttribute("NoDrag", true)
                addCorner(textCard)
                addStroke(textCard)
                addPadding(textCard, 14, 14, 12, 14)
                createLabel({
                    Size = UDim2.new(1, 0, 0, 0),
                    AutomaticSize = Enum.AutomaticSize.Y,
                    Text = pageData.Content,
                    TextSize = 13,
                    FontFace = Fonts.Regular,
                    TextColor3 = Theme.Muted,
                    TextWrapped = true,
                    TextTruncate = Enum.TextTruncate.None,
                    TextYAlignment = Enum.TextYAlignment.Top,
                    Parent = textCard,
                })
            end

            if type(pageData.Entries) == "table" then
                for entryIndex, entry in ipairs(pageData.Entries) do
                    local entryCard = create("Frame", {
                        Size = UDim2.new(1, 0, 0, 0),
                        AutomaticSize = Enum.AutomaticSize.Y,
                        BackgroundColor3 = Theme.Surface2,
                        BorderSizePixel = 0,
                        LayoutOrder = entryIndex,
                        Parent = pageFrame,
                    })
                    entryCard:SetAttribute("NoDrag", true)
                    addCorner(entryCard)
                    addStroke(entryCard)
                    addPadding(entryCard, 14, 14, 12, 14)
                    create("UIListLayout", {
                        SortOrder = Enum.SortOrder.LayoutOrder,
                        Padding = UDim.new(0, 4),
                        Parent = entryCard,
                    })

                    local titleRow = create("Frame", {
                        Size = UDim2.new(1, 0, 0, 18),
                        BackgroundTransparency = 1,
                        LayoutOrder = 1,
                        Parent = entryCard,
                    })
                    createLabel({
                        Size = UDim2.new(1, -70, 1, 0),
                        Text = entry.Title or entry.Version or "Update",
                        TextSize = 14,
                        Parent = titleRow,
                    })

                    -- Pastille (date ou tag) à droite du titre
                    if entry.Date or entry.Tag then
                        local badge = create("Frame", {
                            AnchorPoint = Vector2.new(1, 0.5),
                            Position = UDim2.new(1, 0, 0.5, 0),
                            Size = UDim2.fromOffset(0, 20),
                            AutomaticSize = Enum.AutomaticSize.X,
                            BackgroundColor3 = Theme.Surface,
                            BorderSizePixel = 0,
                            Parent = titleRow,
                        })
                        addCorner(badge, UDim.new(0, 5))
                        addStroke(badge)
                        addPadding(badge, 8, 8)
                        createLabel({
                            Size = UDim2.new(0, 0, 1, 0),
                            AutomaticSize = Enum.AutomaticSize.X,
                            Text = entry.Tag or entry.Date,
                            TextSize = 11,
                            TextColor3 = Theme.Muted,
                            TextTruncate = Enum.TextTruncate.None,
                            Parent = badge,
                        })
                    end

                    local body = entry.Content or entry.Body
                    if type(entry.Changes) == "table" then
                        body = "• " .. table.concat(entry.Changes, "\n• ")
                    end
                    if body then
                        createLabel({
                            Size = UDim2.new(1, 0, 0, 0),
                            AutomaticSize = Enum.AutomaticSize.Y,
                            Text = body,
                            TextSize = 13,
                            FontFace = Fonts.Regular,
                            TextColor3 = Theme.Muted,
                            TextWrapped = true,
                            TextTruncate = Enum.TextTruncate.None,
                            TextYAlignment = Enum.TextYAlignment.Top,
                            LayoutOrder = 2,
                            Parent = entryCard,
                        })
                    end
                end
            end

            if type(pageData.Build) == "function" then
                safeCall(pageData.Build, pageFrame)
                for _, child in ipairs(pageFrame:GetChildren()) do
                    if child:IsA("GuiObject") then
                        child:SetAttribute("NoDrag", true)
                    end
                end
            end

            table.insert(pages, {
                Title = pageData.Name or pageData.Title or "Page",
                Icon = pageData.Icon,
                Frame = pageFrame,
            })
        end

        local pageButtons = {}

        local function selectPage(index, instant)
            local changed = self._homeIndex ~= index
            self._homeIndex = index
            welcomeCard.Visible = index == 1

            if index == 1 and changed and not instant then
                fadeInTree(welcomeCard)
            end

            for pageIndex, page in ipairs(pages) do
                local active = pageIndex == index
                local frame = page.Frame
                frame.Visible = active

                if active and changed and not instant then
                    for _, child in ipairs(frame:GetChildren()) do
                        if child:IsA("GuiObject") then
                            fadeInTree(child)
                        end
                    end
                end

                local pageButton = pageButtons[pageIndex]
                if pageButton then
                    tween(pageButton.Frame, { BackgroundTransparency = active and 0 or 1 }, 0.15)
                    tween(pageButton.Stroke, { Transparency = active and 0 or 1 }, 0.15)
                    tween(pageButton.Label, { TextColor3 = active and Theme.Text or Theme.Muted }, 0.15)
                    if pageButton.Icon then
                        tween(pageButton.Icon, { ImageColor3 = active and Theme.Accent or Theme.Muted }, 0.15)
                    end
                end
            end
        end

        for pageIndex, page in ipairs(pages) do
            local button = create("TextButton", {
                Size = UDim2.fromOffset(0, 32),
                AutomaticSize = Enum.AutomaticSize.X,
                BackgroundColor3 = Theme.Surface2,
                BackgroundTransparency = 1,
                Text = "",
                AutoButtonColor = false,
                LayoutOrder = pageIndex,
                Parent = pageBar,
            })
            addCorner(button, UDim.new(0, 7))
            local buttonStroke = addStroke(button, Theme.Stroke, 1)
            addPadding(button, 12, 12)

            local icon
            if page.Icon then
                icon = create("ImageLabel", {
                    AnchorPoint = Vector2.new(0, 0.5),
                    Position = UDim2.new(0, 0, 0.5, 0),
                    Size = UDim2.fromOffset(14, 14),
                    BackgroundTransparency = 1,
                    ImageColor3 = Theme.Muted,
                    ScaleType = Enum.ScaleType.Fit,
                    Parent = button,
                })
                setIcon(icon, page.Icon)
            end

            local label = createLabel({
                Position = UDim2.fromOffset(icon and 20 or 0, 0),
                Size = UDim2.new(0, 0, 1, 0),
                AutomaticSize = Enum.AutomaticSize.X,
                Text = page.Title,
                TextSize = 13,
                TextColor3 = Theme.Muted,
                TextTruncate = Enum.TextTruncate.None,
                Parent = button,
            })

            pageButtons[pageIndex] = { Frame = button, Stroke = buttonStroke, Label = label, Icon = icon }

            button.MouseEnter:Connect(function()
                if self._homeIndex ~= pageIndex then
                    tween(button, { BackgroundTransparency = 0.4 }, 0.12)
                    tween(buttonStroke, { Transparency = 0.5 }, 0.12)
                end
            end)
            button.MouseLeave:Connect(function()
                if self._homeIndex ~= pageIndex then
                    tween(button, { BackgroundTransparency = 1 }, 0.2)
                    tween(buttonStroke, { Transparency = 1 }, 0.2)
                end
            end)
            button.MouseButton1Click:Connect(function()
                selectPage(pageIndex)
            end)
        end

        selectPage(1)
    end

    homeTab._order = 10 -- les éléments ajoutés par l'utilisateur viennent après
    self.Home = homeTab
    return homeTab
end

----------------------------------------------------------------------
-- Onglets
----------------------------------------------------------------------

function Window:Tab(options, icon)
    options = normalizeOptions(options, { Title = "Name", Description = "Desc" })
    if icon ~= nil and options.Icon == nil then
        options.Icon = icon
    end

    local tab = setmetatable({
        Name = options.Name or "Tab",
        Window = self,
        _order = 0,
    }, Tab)

    -- Bouton dans la sidebar
    local button = create("TextButton", {
        Size = UDim2.new(1, 0, 0, 38),
        BackgroundColor3 = Theme.Surface2,
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        LayoutOrder = #self.Tabs + 1,
        Parent = self.TabList,
    })
    addCorner(button)
    local buttonStroke = addStroke(button, Theme.Stroke, 1)
    tab._button = button

    local hasIcon = options.Icon ~= nil
    if hasIcon then
        local tabIcon = create("ImageLabel", {
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 12, 0.5, 0),
            Size = UDim2.fromOffset(16, 16),
            BackgroundTransparency = 1,
            ImageColor3 = Theme.Muted,
            ScaleType = Enum.ScaleType.Fit,
            Parent = button,
        })
        setIcon(tabIcon, options.Icon)
        tab._icon = tabIcon
    end

    tab._label = createLabel({
        Position = UDim2.fromOffset(hasIcon and 36 or 14, 0),
        Size = UDim2.new(1, -(hasIcon and 44 or 22), 1, 0),
        Text = tab.Name,
        TextColor3 = Theme.Muted,
        Parent = button,
    })

    -- Page de l'onglet
    local page = create("Frame", {
        Name = tab.Name,
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Visible = false,
        Parent = self.Content,
    })
    tab._page = page

    createLabel({
        Position = UDim2.fromOffset(24, 20),
        Size = UDim2.new(1, -72, 0, 24),
        Text = tab.Name,
        TextSize = 22,
        Parent = page,
    })
    if options.Desc then
        createLabel({
            Position = UDim2.fromOffset(24, 44),
            Size = UDim2.new(1, -72, 0, 16),
            Text = options.Desc,
            TextSize = 13,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            Parent = page,
        })
    end

    local listTop = options.Desc and 70 or 58
    local list = create("ScrollingFrame", {
        Position = UDim2.fromOffset(0, listTop),
        Size = UDim2.new(1, 0, 1, -listTop),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = Theme.Accent,
        ScrollBarImageTransparency = 0.5,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(),
        Parent = page,
    })
    addPadding(list, 24, 24, 2, 24)
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8),
        Parent = list,
    })
    tab.List = list

    -- Message "vide" tant que l'onglet ne contient aucun élément
    local emptyState = createEmptyState(page, options.Icon or "layout-grid", options.EmptyText or "Nothing here yet")
    local childCount = 0

    list.ChildAdded:Connect(function(child)
        if child:IsA("GuiObject") then
            childCount += 1
            emptyState.Visible = false
        end
    end)
    list.ChildRemoved:Connect(function(child)
        if child:IsA("GuiObject") then
            childCount = math.max(childCount - 1, 0)
            emptyState.Visible = childCount <= 0
        end
    end)
    emptyState.Visible = true

    button.MouseEnter:Connect(function()
        if self.CurrentTab ~= tab then
            tween(button, { BackgroundTransparency = 0.4 }, 0.12)
            tween(buttonStroke, { Transparency = 0.5 }, 0.12)
        end
    end)
    button.MouseLeave:Connect(function()
        if self.CurrentTab ~= tab then
            tween(button, { BackgroundTransparency = 1 }, 0.2)
            tween(buttonStroke, { Transparency = 1 }, 0.2)
        end
    end)
    button.MouseButton1Click:Connect(function()
        self:SelectTab(tab)
    end)

    tab._stroke = buttonStroke

    if not self._introDone then
        button.Visible = false -- sera révélé par l'animation d'intro
    end

    table.insert(self.Tabs, tab)

    if #self.Tabs == 1 then
        task.defer(function()
            self:SelectTab(tab)
        end)
    end

    return tab
end

Window.CreateTab = Window.Tab

----------------------------------------------------------------------
-- Dialogues
----------------------------------------------------------------------

function Window:Dialog(options)
    options = normalizeOptions(options, { Text = "Content", Message = "Content" })

    if self._dialog then
        self._dialog.Close()
    end

    local PADDING = 18

    local backdrop = create("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 40,
        Parent = self.Body,
    })

    local dialogFrame = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 10),
        Size = UDim2.fromOffset(300, 120),
        BackgroundColor3 = Theme.Background,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 41,
        Parent = backdrop,
    })
    addCorner(dialogFrame, UDim.new(0, 10))
    local dialogStroke = addStroke(dialogFrame, Theme.Stroke, 1)
    local dialogScale = create("UIScale", { Scale = 0.94, Parent = dialogFrame })

    -- Liste des {instance, propriété, valeur finale} à faire apparaître en fondu
    local fades = {}
    local iconOffset = 0

    if options.Icon then
        local iconFrame, iconImage = createIconFrame(dialogFrame, options.Icon, Theme.Accent, UDim2.new(0, PADDING, 0, PADDING + 9))
        iconImage.ImageTransparency = 1
        iconFrame.ZIndex = 42
        iconImage.ZIndex = 42
        table.insert(fades, { iconImage, "ImageTransparency", 0 })
        iconOffset = 24
    end

    local titleLabel = createLabel({
        Position = UDim2.fromOffset(PADDING + iconOffset, PADDING),
        Size = UDim2.new(1, -(PADDING * 2 + iconOffset), 0, 18),
        Text = options.Title or "Are you sure?",
        TextSize = 15,
        TextTransparency = 1,
        ZIndex = 42,
        Parent = dialogFrame,
    })
    table.insert(fades, { titleLabel, "TextTransparency", 0 })

    local contentHeight = 0
    if options.Content then
        local contentLabel = createLabel({
            Position = UDim2.fromOffset(PADDING, PADDING + 24),
            Size = UDim2.new(1, -PADDING * 2, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            Text = options.Content,
            TextSize = 13,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            TextWrapped = true,
            TextTransparency = 1,
            TextTruncate = Enum.TextTruncate.None,
            TextYAlignment = Enum.TextYAlignment.Top,
            ZIndex = 42,
            Parent = dialogFrame,
        })
        table.insert(fades, { contentLabel, "TextTransparency", 0 })

        contentHeight = math.max(contentLabel.TextBounds.Y, 16) + 6

        -- Redimensionne la boîte quand le texte est mesuré / change
        contentLabel:GetPropertyChangedSignal("TextBounds"):Connect(function()
            local newHeight = math.max(contentLabel.TextBounds.Y, 16) + 6
            if newHeight ~= contentHeight then
                contentHeight = newHeight
                dialogFrame.Size = UDim2.fromOffset(300, PADDING + 24 + contentHeight + 12 + 34 + PADDING)
                local buttonRow = dialogFrame:FindFirstChild("ButtonRow")
                if buttonRow then
                    buttonRow.Position = UDim2.fromOffset(PADDING, PADDING + 24 + contentHeight + 12)
                end
            end
        end)
    end

    local buttonRow = create("Frame", {
        Name = "ButtonRow",
        Position = UDim2.fromOffset(PADDING, PADDING + 24 + contentHeight + 12),
        Size = UDim2.new(1, -PADDING * 2, 0, 34),
        BackgroundTransparency = 1,
        ZIndex = 42,
        Parent = dialogFrame,
    })
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8),
        Parent = buttonRow,
    })

    dialogFrame.Size = UDim2.fromOffset(300, PADDING + 24 + contentHeight + 12 + 34 + PADDING)

    local handle = {}
    local closed = false

    function handle.Close()
        if closed then return end
        closed = true
        if self._dialog == handle then
            self._dialog = nil
        end

        tween(backdrop, { BackgroundTransparency = 1 }, 0.18)
        tween(dialogFrame, { BackgroundTransparency = 1, Position = UDim2.new(0.5, 0, 0.5, 8) }, 0.18, Enum.EasingStyle.Quint)
        tween(dialogScale, { Scale = 0.96 }, 0.18, Enum.EasingStyle.Quint)
        tween(dialogStroke, { Transparency = 1 }, 0.12)
        for _, fade in ipairs(fades) do
            tween(fade[1], { [fade[2]] = 1 }, 0.12)
        end

        task.delay(0.2, function()
            backdrop:Destroy()
        end)
    end

    for index, buttonData in ipairs(options.Buttons or {}) do
        local isPrimary = buttonData.Variant == "Primary"

        local button = create("TextButton", {
            Size = UDim2.fromOffset(0, 34),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundColor3 = isPrimary and Theme.Accent or Theme.Surface2,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Text = "",
            AutoButtonColor = false,
            ClipsDescendants = true,
            LayoutOrder = index,
            ZIndex = 43,
            Parent = buttonRow,
        })
        addCorner(button, UDim.new(0, 7))
        local buttonStroke = addStroke(button, isPrimary and Theme.Accent or Theme.Stroke, 1)
        addPadding(button, 14, 14)

        local buttonLabel = createLabel({
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            Text = buttonData.Title or buttonData.Name or "OK",
            TextSize = 13,
            TextColor3 = isPrimary and Theme.AccentDark or Theme.Text,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextTransparency = 1,
            ZIndex = 44,
            Parent = button,
        })

        local restingBackground = isPrimary and 0.12 or 0
        local restingStroke = isPrimary and 0.4 or 0
        table.insert(fades, { button, "BackgroundTransparency", restingBackground })
        table.insert(fades, { buttonStroke, "Transparency", restingStroke })
        table.insert(fades, { buttonLabel, "TextTransparency", 0 })

        button.MouseEnter:Connect(function()
            if closed then return end
            if isPrimary then
                tween(button, { BackgroundTransparency = 0 }, 0.12)
                tween(buttonStroke, { Transparency = 0 }, 0.12)
            else
                tween(buttonStroke, { Color = Theme.StrokeHover }, 0.12)
            end
        end)
        button.MouseLeave:Connect(function()
            if closed then return end
            if isPrimary then
                tween(button, { BackgroundTransparency = restingBackground }, 0.2)
                tween(buttonStroke, { Transparency = restingStroke }, 0.2)
            else
                tween(buttonStroke, { Color = Theme.Stroke }, 0.2)
            end
        end)
        button.MouseButton1Click:Connect(function()
            handle.Close()
            safeCall(buttonData.Callback)
        end)
    end

    if options.CloseOnBackdrop ~= false then
        backdrop.MouseButton1Click:Connect(function()
            handle.Close()
            safeCall(options.OnCancel)
        end)
    end

    self._dialog = handle

    -- Animation d'ouverture
    tween(backdrop, { BackgroundTransparency = 0.45 }, 0.25)
    tween(dialogFrame, { BackgroundTransparency = 0, Position = UDim2.fromScale(0.5, 0.5) }, 0.3, Enum.EasingStyle.Quint)
    tween(dialogStroke, { Transparency = 0 }, 0.25)
    tween(dialogScale, { Scale = 1 }, 0.4, Enum.EasingStyle.Back)
    for _, fade in ipairs(fades) do
        tween(fade[1], { [fade[2]] = fade[3] }, 0.25)
    end

    return handle
end

-- Dialogue Annuler / Confirmer
function Window:Confirm(options)
    options = normalizeOptions(options, { Text = "Content", Message = "Content" })
    return self:Dialog({
        Title = options.Title or "Are you sure?",
        Content = options.Content,
        Icon = options.Icon,
        OnCancel = options.OnCancel,
        Buttons = {
            { Title = options.CancelText or "Cancel", Callback = options.OnCancel },
            { Title = options.ConfirmText or "Confirm", Variant = "Primary", Callback = options.Callback },
        },
    })
end

----------------------------------------------------------------------
-- Événements, sélection d'onglet, affichage
----------------------------------------------------------------------

-- Enregistre un listener ("Began" | "Changed" | "Ended" | "Render").
-- Retourne la fonction de désinscription ; si `owner` est fourni, elle est aussi ajoutée à owner._listeners.
function Window:_listen(eventName, callback, owner)
    local listeners = self._inputListeners[eventName]
    table.insert(listeners, callback)

    local function disconnect()
        for index, listener in ipairs(listeners) do
            if listener == callback then
                table.remove(listeners, index)
                break
            end
        end
    end

    if owner then
        owner._listeners = owner._listeners or {}
        table.insert(owner._listeners, disconnect)
    end
    return disconnect
end

-- Position verticale (en pixels non mis à l'échelle) du centre du bouton d'onglet
function Window:_indicatorY(tab)
    local list = self.TabList
    local scale = self.Scale.Scale
    return (tab._button.AbsolutePosition.Y - list.AbsolutePosition.Y + tab._button.AbsoluteSize.Y / 2) / scale
        + list.Position.Y.Offset
end

function Window:_placeIndicator(tab)
    local indicator = self.Indicator
    local y = self:_indicatorY(tab)

    if not indicator.Visible then
        indicator.Visible = true
        indicator.Position = UDim2.fromOffset(6, y)
        indicator.Size = UDim2.fromOffset(3, 0)
    end

    tween(indicator, {
        Position = UDim2.fromOffset(6, y),
        Size = UDim2.fromOffset(3, 18),
    }, 0.35, Enum.EasingStyle.Back)
end

function Window:SelectTab(tab)
    if self.CurrentTab == tab then return end

    local previous = self.CurrentTab
    self.CurrentTab = tab
    self:_settleTransition()

    local generation = (self._transitionGeneration or 0) + 1
    self._transitionGeneration = generation

    -- L'ancien onglet sort par le haut en fondu
    if previous then
        tween(previous._button, { BackgroundTransparency = 1 }, 0.2)
        tween(previous._stroke, { Transparency = 1 }, 0.2)
        tween(previous._label, { TextColor3 = Theme.Muted }, 0.2)
        if previous._icon then
            tween(previous._icon, { ImageColor3 = Theme.Muted }, 0.2)
        end

        local outLayer = self._outLayer
        previous._page.Parent = outLayer
        self._outPage = previous._page
        outLayer.GroupTransparency = 0
        outLayer.Position = UDim2.fromOffset(0, 0)
        outLayer.Visible = true
        tween(outLayer, { GroupTransparency = 1, Position = UDim2.fromOffset(0, -10) }, 0.18)

        task.delay(0.18, function()
            if self._transitionGeneration == generation then
                self:_settleOut()
            end
        end)
    end

    -- Le nouvel onglet est mis en surbrillance
    tween(tab._button, { BackgroundTransparency = 0 }, 0.2)
    tween(tab._stroke, { Transparency = 0 }, 0.2)
    tween(tab._label, { TextColor3 = Theme.Text }, 0.2)
    if tab._icon then
        tween(tab._icon, { ImageColor3 = Theme.Accent }, 0.2)
    end
    self:_placeIndicator(tab)

    -- ... et sa page entre par le bas en fondu
    local page = tab._page
    page.Position = UDim2.fromOffset(0, 0)
    page.Visible = true
    page.Parent = self._inLayer
    self._inPage = page
    slideIn(self._inLayer)

    task.delay(0.32, function()
        if self._transitionGeneration == generation then
            self:_settleIn()
        end
    end)
end

function Window:_settleOut()
    local page = self._outPage
    if page then
        page.Parent = self.Content
        page.Visible = false
        self._outPage = nil
    end
    self._outLayer.Visible = false
end

function Window:_settleIn()
    local page = self._inPage
    if page then
        page.Parent = self.Content
        page.Position = UDim2.fromOffset(0, 0)
        self._inPage = nil
    end
    self._inLayer.Visible = false
end

function Window:_settleTransition()
    self:_settleOut()
    self:_settleIn()
end

-- Affiche / masque la fenêtre
function Window:Toggle(open)
    if not self._introDone then return end
    if open == nil then
        open = not self.Open
    end
    if open == self.Open then return end
    self.Open = open

    if open then
        self.Root.Visible = true
        tween(self.Scale, { Scale = self._fitScale or 1 }, 0.4, Enum.EasingStyle.Back)
        tween(self.Body, { GroupTransparency = 0 }, 0.25)
        tween(self.BodyStroke, { Transparency = 0 }, 0.25)
        tween(self.Shadow, { ImageTransparency = 0.6 }, 0.3)
    else
        tween(self.Scale, { Scale = (self._fitScale or 1) * 0.94 }, 0.2, Enum.EasingStyle.Quint)
        tween(self.Body, { GroupTransparency = 1 }, 0.16)
        tween(self.BodyStroke, { Transparency = 1 }, 0.12)
        tween(self.Shadow, { ImageTransparency = 1 }, 0.16)
        task.delay(0.2, function()
            if not self.Open then
                self.Root.Visible = false
            end
        end)
    end
end

function Window:SetKeepOnScreen(enabled)
    self.KeepOnScreen = enabled ~= false
    if self.KeepOnScreen then
        self:_clampToScreen()
    end
end

function Window:SetKeybind(keyCode)
    self.Keybind = keyCode
    self._keyChipLabel.Text = keyName(keyCode)
end

----------------------------------------------------------------------
-- Notifications
----------------------------------------------------------------------

function Window:Notify(options)
    options = normalizeOptions(options, { Text = "Content", Message = "Content", Image = "Icon" })

    local duration = options.Duration or 4
    local color = NotificationColors[options.Type] or Theme.Text

    self._notifyOrder += 1

    -- Emplacement dans la pile (sa hauteur s'anime pour pousser les autres)
    local slot = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        BackgroundTransparency = 1,
        LayoutOrder = self._notifyOrder,
        Parent = self.NotifyHolder,
    })

    -- Conteneur qui glisse depuis la droite
    local slide = create("Frame", {
        Position = UDim2.fromOffset(320, 0),
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Parent = slot,
    })

    local shadow = create("ImageLabel", {
        Position = UDim2.fromOffset(-20, -20),
        Size = UDim2.new(1, 40, 1, 40),
        BackgroundTransparency = 1,
        Image = Assets.Shadow,
        ImageColor3 = Color3.new(0, 0, 0),
        ImageTransparency = 1,
        ScaleType = Enum.ScaleType.Slice,
        SliceCenter = Rect.new(49, 49, 450, 450),
        ZIndex = 0,
        Parent = slide,
    })

    local card = create("CanvasGroup", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        GroupTransparency = 1,
        Parent = slide,
    })
    addCorner(card, UDim.new(0, 10))
    local cardStroke = addStroke(card, Theme.Stroke)
    addTopHighlight(card)
    addGlow(card, UDim2.fromOffset(260, 120), UDim2.new(1, -10, 0, -10), 0.86, 90)

    local inner = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Parent = card,
    })
    addPadding(inner, 16, 16, 14, 24)

    local textOffset = 0
    if options.Icon then
        createIconFrame(inner, options.Icon, color == Theme.Text and Theme.Accent or color, UDim2.new(0, 0, 0, 8))
        textOffset = 24
    end

    createLabel({
        Position = UDim2.fromOffset(textOffset, 0),
        Size = UDim2.new(1, -28 - textOffset, 0, 16),
        Text = options.Title or "Notification",
        TextSize = 14,
        TextColor3 = color,
        Parent = inner,
    })

    local closeButton = create("TextButton", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 6, 0, -5),
        Size = UDim2.fromOffset(24, 24),
        BackgroundTransparency = 1,
        Text = "×",
        TextColor3 = Theme.Muted,
        TextSize = 22,
        FontFace = Fonts.Bold,
        AutoButtonColor = false,
        Parent = inner,
    })
    closeButton.MouseEnter:Connect(function()
        tween(closeButton, { TextColor3 = Theme.Text }, 0.15)
    end)
    closeButton.MouseLeave:Connect(function()
        tween(closeButton, { TextColor3 = Theme.Muted }, 0.2)
    end)

    if options.Content then
        createLabel({
            Position = UDim2.fromOffset(textOffset, 21),
            Size = UDim2.new(1, -textOffset, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            Text = options.Content,
            TextSize = 13,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            TextWrapped = true,
            TextTruncate = Enum.TextTruncate.None,
            TextYAlignment = Enum.TextYAlignment.Top,
            Parent = inner,
        })
    end

    -- Barre de temps restant
    local timerTrack = create("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 16, 1, -8),
        Size = UDim2.new(1, -32, 0, 3),
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        Parent = card,
    })
    addCorner(timerTrack, UDim.new(1, 0))

    local timerFill = create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        Parent = timerTrack,
    })
    addCorner(timerFill, UDim.new(1, 0))

    -- Une fois la carte mesurée, donne sa hauteur à l'emplacement
    task.defer(function()
        if slot.Parent then
            tween(slot, { Size = UDim2.new(1, 0, 0, card.AbsoluteSize.Y) }, 0.3, Enum.EasingStyle.Quint)
        end
    end)

    -- Animation d'entrée
    tween(slide, { Position = UDim2.fromOffset(0, 0) }, 0.5, Enum.EasingStyle.Back)
    tween(card, { GroupTransparency = 0 }, 0.3)
    tween(shadow, { ImageTransparency = 0.6 }, 0.4)
    tween(timerFill, { Size = UDim2.fromScale(0, 1) }, duration, Enum.EasingStyle.Linear)

    local dismissed = false
    local function dismiss()
        if dismissed then return end
        dismissed = true

        for index, toast in ipairs(self._toasts) do
            if toast == dismiss then
                table.remove(self._toasts, index)
                break
            end
        end

        tween(slide, { Position = UDim2.fromOffset(320, 0) }, 0.3, Enum.EasingStyle.Quint)
        tween(card, { GroupTransparency = 1 }, 0.2)
        tween(cardStroke, { Transparency = 1 }, 0.15)
        tween(shadow, { ImageTransparency = 1 }, 0.2)

        task.delay(0.22, function()
            slot.ClipsDescendants = true
            tween(slot, { Size = UDim2.new(1, 0, 0, -4) }, 0.22, Enum.EasingStyle.Quint)
            task.delay(0.24, function()
                slot:Destroy()
            end)
        end)
    end

    task.delay(duration, dismiss)
    closeButton.MouseButton1Click:Connect(dismiss)

    table.insert(self._toasts, dismiss)
    -- Trop de notifications : on ferme les plus anciennes
    while #self._toasts > self.MaxNotifications do
        local oldest = table.remove(self._toasts, 1)
        oldest()
    end

    return { Dismiss = dismiss }
end

----------------------------------------------------------------------
-- Destruction
----------------------------------------------------------------------

function Window:Destroy()
    if self._destroyed then return end
    self._destroyed = true

    for index, window in ipairs(Airflow.Windows) do
        if window == self then
            table.remove(Airflow.Windows, index)
            break
        end
    end

    for _, connection in ipairs(self._connections) do
        connection:Disconnect()
    end
    self._connections = {}

    tween(self.Scale, { Scale = 0.9 }, 0.2)
    tween(self.Body, { GroupTransparency = 1 }, 0.2)
    tween(self.BodyStroke, { Transparency = 1 }, 0.12)
    tween(self.Shadow, { ImageTransparency = 1 }, 0.2)

    task.delay(0.22, function()
        self.Gui:Destroy()
    end)
end

return Airflow
