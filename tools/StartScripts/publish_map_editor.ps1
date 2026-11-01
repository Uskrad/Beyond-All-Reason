# Copy this repo's map editor into the BAR install write-dir so the game
# actually running on this PC (Chobby / test archive / Dev) loads it.
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$barRoots = @(
	"C:\Program Files\Beyond-All-Reason",
	(Join-Path $env:LOCALAPPDATA "Programs\Beyond-All-Reason")
)
$bar = $null
foreach ($c in $barRoots) {
	if (Test-Path $c) { $bar = $c; break }
}
if (-not $bar) {
	Write-Error "Beyond All Reason install not found."
	exit 1
}
$data = Join-Path $bar "data"

function Publish-File($rel) {
	$from = Join-Path $repo $rel
	$to = Join-Path $data $rel
	$dir = Split-Path $to -Parent
	New-Item -ItemType Directory -Path $dir -Force | Out-Null
	Copy-Item $from $to -Force
	Write-Output "  $rel"
}

$dev = Join-Path $data "devmode.txt"
if (-not (Test-Path $dev)) {
	New-Item -ItemType File -Path $dev -Force | Out-Null
}

Write-Output "Publishing map editor into $data"
Publish-File "luarules\gadgets\map_editor.lua"
Publish-File "luarules\gadgets\include\map_editor_compile.lua"
Publish-File "luaui\RmlWidgets\gui_map_editor\gui_map_editor.lua"
Publish-File "luaui\RmlWidgets\gui_map_editor\gui_map_editor.rml"
Publish-File "luaui\RmlWidgets\gui_map_editor\gui_map_editor.rcss"
Publish-File "luaui\Widgets\gui_map_editor_dock.lua"

$luaMenu = Join-Path $data "LuaMenu\widgets"
New-Item -ItemType Directory -Path $luaMenu -Force | Out-Null
Copy-Item (Join-Path $PSScriptRoot "luamenu_map_editor_dev_redirect.lua") (Join-Path $luaMenu "gui_map_editor_dev_redirect.lua") -Force
Write-Output "  LuaMenu/widgets/gui_map_editor_dev_redirect.lua"

$cfg = Join-Path $data "springsettings.cfg"
if (Test-Path $cfg) {
	$txt = Get-Content $cfg -Raw
	if ($txt -notmatch '(?i)DevLua\s*=') {
		Add-Content $cfg "`nDevLua = 1`n"
		Write-Output "  enabled DevLua in springsettings.cfg"
	}
}

Write-Output "Published. Close the current match and start Map Editor again."
