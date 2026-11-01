# Launch THIS repo as Beyond All Reason Dev with the map editor startscript.
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script = Join-Path $PSScriptRoot "startscript_map_editor.txt"
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
& (Join-Path $PSScriptRoot "publish_map_editor.ps1")
$games = Join-Path $data "games"
$link = Join-Path $games "BAR.sdd"
New-Item -ItemType Directory -Path $games -Force | Out-Null
$dev = Join-Path $data "devmode.txt"
if (-not (Test-Path $dev)) { New-Item -ItemType File -Path $dev -Force | Out-Null }
if (Test-Path $link) {
	$item = Get-Item $link -Force
	$target = $null
	if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
		$target = (cmd /c dir /al "$games" | Select-String "BAR.sdd").ToString()
	}
	Write-Output "BAR.sdd exists: $link"
	Write-Output "BAR.sdd listing: $target"
} else {
	cmd /c mklink /J "$link" "$repo"
	Write-Output "Created junction $link -> $repo"
}
$engineRoot = Join-Path $data "engine"
$spring = Get-ChildItem $engineRoot -Recurse -Filter "spring.exe" -ErrorAction SilentlyContinue |
	Sort-Object LastWriteTime -Descending |
	Select-Object -First 1 -ExpandProperty FullName
if (-not $spring) {
	Write-Error "spring.exe not found under $engineRoot"
	exit 1
}
$runScript = Join-Path $data "_map_editor_script.txt"
Copy-Item $script $runScript -Force
$luaMenu = Join-Path $data "LuaMenu\widgets"
New-Item -ItemType Directory -Path $luaMenu -Force | Out-Null
Copy-Item (Join-Path $PSScriptRoot "luamenu_map_editor_dev_redirect.lua") (Join-Path $luaMenu "gui_map_editor_dev_redirect.lua") -Force
Write-Output "Installed Chobby Map Editor redirect -> Beyond All Reason `$VERSION"
Write-Output "Launching $spring"
Write-Output "Game: $link"
Write-Output "Script: $runScript"
Start-Process -FilePath $spring -ArgumentList @("--isolation-dir", $data, $runScript) -WorkingDirectory $data
