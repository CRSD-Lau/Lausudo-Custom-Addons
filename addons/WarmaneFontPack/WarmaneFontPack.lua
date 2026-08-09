local LSM = LibStub("LibSharedMedia-3.0", true)
if not LSM then return end

local ADDON_PATH = "Interface\\AddOns\\WarmaneFontPack\\fonts\\"
local fonts = {
	["Anonymous Pro"] = "AnonymousPro-Regular.ttf",
	["Atkinson Hyperlegible Next"] = "AtkinsonHyperlegibleNext-Regular.ttf",
	["Cabin"] = "Cabin-Regular.ttf",
	["Celestia Redux"] = "CelestiaMediumRedux1.55.ttf",
	["DejaVu Sans"] = "DejaVuSans.ttf",
	["DejaVu Sans Bold"] = "DejaVuSans-Bold.ttf",
	["JetBrains Mono"] = "JetBrainsMono-Regular.ttf",
	["Nanum Gothic"] = "NanumGothic-Regular.ttf",
	["Nunito"] = "Nunito-Regular.ttf",
	["PT Sans Narrow Bold"] = "PTSansNarrow-Bold.ttf",
	["Ubuntu Condensed"] = "Ubuntu-C.ttf",
	["Ubuntu Light"] = "Ubuntu-L.ttf",
}

for name, fileName in pairs(fonts) do
	LSM:Register("font", name, ADDON_PATH .. fileName)
end

