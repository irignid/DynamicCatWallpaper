<#
  Dynamic wallpaper for Windows: picks a wallpaper by time of day and crossfades between images.

  .\Set-Wallpaper.ps1                    apply the wallpaper for the current time
  .\Set-Wallpaper.ps1 -At 18:45 -DryRun  show what 18:45 would look like, change nothing
  .\Set-Wallpaper.ps1 -At 18:45          actually apply the 18:45 look (preview)
  .\Set-Wallpaper.ps1 -Force             apply even if nothing changed since last run
#>
param(
    [string]$At,
    [switch]$DryRun,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$STEPS = 20   # crossfade resolution (5% per step)

$root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$cfg     = Get-Content (Join-Path $root 'config.json') -Raw | ConvertFrom-Json
$wallDir = Join-Path $root 'wallpapers'
$base    = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { [IO.Path]::GetTempPath() }
$dataDir = Join-Path $base 'CatWallpaper'

# ---------- work out which image(s) to show ----------
if ($At) {
    $nowMin = [int][math]::Floor([TimeSpan]::Parse($At).TotalMinutes)
} else {
    $d = Get-Date
    $nowMin = $d.Hour * 60 + $d.Minute
}

$entries = @($cfg.schedule | ForEach-Object {
    $p = Join-Path $wallDir $_.image
    if (-not (Test-Path $p)) { throw "Image not found: $p" }
    [pscustomobject]@{ Min = [int][TimeSpan]::Parse($_.time).TotalMinutes; Image = $p }
} | Sort-Object Min)

$n = $entries.Count
if ($n -eq 0) { throw 'config.json has an empty schedule.' }

# latest entry whose start time has passed (wraps to the last one before the first entry of the day)
$idx = -1
for ($i = 0; $i -lt $n; $i++) { if ($entries[$i].Min -le $nowMin) { $idx = $i } }
if ($idx -lt 0) { $idx = $n - 1 }

$cur   = $entries[$idx]
$prev  = $entries[($idx - 1 + $n) % $n]
$since = $nowMin - $cur.Min;  if ($since -lt 0) { $since += 1440 }
$gap   = $cur.Min - $prev.Min; if ($gap -le 0)   { $gap   += 1440 }
$trans = [math]::Min([int]$cfg.transitionMinutes, $gap)

$mode = 'static'
$file = $cur.Image
$step = $STEPS
if ($n -gt 1 -and $trans -gt 0 -and $since -lt $trans) {
    $step = [int][math]::Round($since / $trans * $STEPS)
    if ($step -le 0)           { $file = $prev.Image }
    elseif ($step -lt $STEPS)  { $mode = 'blend' }
}

$curName  = [IO.Path]::GetFileNameWithoutExtension($cur.Image)
$prevName = [IO.Path]::GetFileNameWithoutExtension($prev.Image)
$key = if ($mode -eq 'blend') { "blend|$prevName|$curName|$step" } else { "static|$file" }

$hh = '{0:00}:{1:00}' -f [math]::Floor($nowMin / 60), ($nowMin % 60)
if ($mode -eq 'blend') {
    Write-Host ("{0}  fading {1} -> {2}  ({3}%)" -f $hh, $prevName, $curName, ($step * 100 / $STEPS))
} else {
    Write-Host ("{0}  showing {1}" -f $hh, [IO.Path]::GetFileNameWithoutExtension($file))
}
if ($DryRun) { exit 0 }

# ---------- skip if nothing changed ----------
if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Path $dataDir | Out-Null }
$stateFile = Join-Path $dataDir 'state.txt'
if (-not $Force -and (Test-Path $stateFile) -and ((Get-Content $stateFile -Raw).Trim() -eq $key)) { exit 0 }

# ---------- build the crossfade image if needed ----------
function New-Blend($pathA, $pathB, [single]$alpha, $outPath) {
    Add-Type -AssemblyName System.Drawing
    $a = [System.Drawing.Image]::FromFile($pathA)
    $b = [System.Drawing.Image]::FromFile($pathB)
    try {
        $w = $a.Width; $h = $a.Height
        $bmp = New-Object System.Drawing.Bitmap($w, $h)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.DrawImage($a, 0, 0, $w, $h)

        $cm = New-Object System.Drawing.Imaging.ColorMatrix
        $cm.Matrix33 = $alpha
        $ia = New-Object System.Drawing.Imaging.ImageAttributes
        $ia.SetColorMatrix($cm)
        $rect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
        $g.DrawImage($b, $rect, 0, 0, $b.Width, $b.Height, [System.Drawing.GraphicsUnit]::Pixel, $ia)
        $g.Dispose()

        $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
        $ep = New-Object System.Drawing.Imaging.EncoderParameters(1)
        $ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]93)
        $bmp.Save($outPath, $codec, $ep)
        $bmp.Dispose()
    } finally {
        $a.Dispose(); $b.Dispose()
    }
}

if ($mode -eq 'blend') {
    $file = Join-Path $dataDir ('blend_{0}_{1}_{2:00}.jpg' -f $prevName, $curName, $step)
    if (-not (Test-Path $file)) { New-Blend $prev.Image $cur.Image ($step / $STEPS) $file }
}

# ---------- set the wallpaper ----------
$styles = @{ Fill = '10'; Fit = '6'; Stretch = '2'; Center = '0'; Tile = '0'; Span = '22' }
$fill = if ($cfg.fillMode) { [string]$cfg.fillMode } else { 'Fill' }
if (-not $styles.ContainsKey($fill)) { throw "Unknown fillMode '$fill'. Use Fill, Fit, Stretch, Center, Tile or Span." }
$desk = 'HKCU:\Control Panel\Desktop'
Set-ItemProperty -Path $desk -Name WallpaperStyle -Value $styles[$fill]
Set-ItemProperty -Path $desk -Name TileWallpaper  -Value $(if ($fill -eq 'Tile') { '1' } else { '0' })

if (-not ('Win32.Native' -as [type])) {
    Add-Type -Namespace Win32 -Name Native -MemberDefinition '[DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern bool SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);'
}
# SPI_SETDESKWALLPAPER = 20, flags = UPDATEINIFILE | SENDCHANGE
if (-not [Win32.Native]::SystemParametersInfo(20, 0, $file, 3)) { throw 'SystemParametersInfo failed.' }

Set-Content -Path $stateFile -Value $key -Encoding ASCII

# tidy old blend images
Get-ChildItem $dataDir -Filter 'blend_*.jpg' | Where-Object { $_.FullName -ne $file } | Remove-Item -Force -ErrorAction SilentlyContinue
