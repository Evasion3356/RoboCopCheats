# Builds the Nexus release zips into dist\ from Win64\ (the tested, deployed files).
#   RoboCopCheats-<ver>-full.zip     UE4SS v4.0.0 + mod, extract into the game's root folder
#   RoboCopCheats-<ver>-modonly.zip  just ue4ss\Mods\RoboCopCheats (needs UE4SS v4.0.0)
# Release changes vs. the dev tree: ConsoleEnabled = 0, no dlc_weapon.txt.
# Refuses to build if DEV_TOOLS is on in main.lua.
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$lua  = Join-Path $root 'Win64\ue4ss\Mods\RoboCopCheats\Scripts\main.lua'
$luaText = Get-Content $lua -Raw

$ver = [regex]::Match($luaText, 'local MOD_VERSION = "([^"]+)"').Groups[1].Value
if (-not $ver) { throw 'MOD_VERSION not found in main.lua' }
if ($luaText -notmatch '(?m)^local DEV_TOOLS = false') { throw 'DEV_TOOLS must be false for a release' }
if ((Get-Content (Join-Path $root 'README.txt') -Raw) -notmatch "v$([regex]::Escape($ver))\b") {
    throw "README.txt doesn't mention v$ver"
}

$dist  = Join-Path $root 'dist'
$stage = Join-Path $dist 'stage'
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force $dist | Out-Null

function New-Zip($name, [scriptblock]$fill) {
    $dir = Join-Path $stage $name
    $bin = Join-Path $dir 'Game\Binaries\Win64'
    New-Item -ItemType Directory -Force $bin | Out-Null
    & $fill $bin
    Remove-Item (Join-Path $bin 'ue4ss\Mods\RoboCopCheats\dlc_weapon.txt') -ErrorAction SilentlyContinue
    Copy-Item (Join-Path $root 'README.txt') (Join-Path $dir 'RoboCopCheats-README.txt')
    $zip = Join-Path $dist "$name.zip"
    if (Test-Path $zip) { Remove-Item $zip -Force }
    Compress-Archive -Path (Join-Path $dir '*') -DestinationPath $zip
    Write-Host "Built $zip"
}

New-Zip "RoboCopCheats-$ver-full" {
    param($bin)
    Copy-Item (Join-Path $root 'Win64\*') $bin -Recurse
    $ini = Join-Path $bin 'ue4ss\UE4SS-settings.ini'
    $text = [IO.File]::ReadAllText($ini)
    $new  = [regex]::Replace($text, '(?m)^ConsoleEnabled = 1', 'ConsoleEnabled = 0')
    if ($new -eq $text -and $text -notmatch '(?m)^ConsoleEnabled = 0') { throw 'ConsoleEnabled line not found' }
    foreach ($k in 'GuiConsoleEnabled = 1', 'GuiConsoleVisible = 1', 'GraphicsAPI = dx11') {
        if ($new -notmatch "(?m)^$k") { throw "UE4SS-settings.ini must have '$k'" }
    }
    [IO.File]::WriteAllText($ini, $new)   # keeps the original bytes/line endings otherwise
}

New-Zip "RoboCopCheats-$ver-modonly" {
    param($bin)
    $mods = Join-Path $bin 'ue4ss\Mods'
    New-Item -ItemType Directory -Force $mods | Out-Null
    Copy-Item (Join-Path $root 'Win64\ue4ss\Mods\RoboCopCheats') $mods -Recurse
    if (-not (Test-Path (Join-Path $mods 'RoboCopCheats\enabled.txt'))) { throw 'enabled.txt missing' }
}

Remove-Item $stage -Recurse -Force
