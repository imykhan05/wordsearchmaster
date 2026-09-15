# Captures Play Store screenshots from a real device, and frames them.
#
# WHY A DEVICE AND NOT A RENDERED MOCK-UP
#
# Play requires screenshots to represent the actual app. A headless render of
# the widget tree was tried and abandoned: it produces the real layout but
# without the bundled background artwork or the icon font, because the test
# harness serves no asset bundle — so the images were real UI and still a
# misleading picture of what a player gets. A device screenshot has no such
# gap.
#
# USAGE
#   1. Install the build you are shipping:      flutter install --flavor prod
#   2. Put the phone on the screen you want.
#   3. Run:   .\tool\capture_store_screenshots.ps1 -Name 01_game
#   4. Repeat for each screen.
#   5. Frame them all:  .\tool\capture_store_screenshots.ps1 -FrameAll
#
# Play wants at least 2 phone screenshots; 4-8 is the practical range, and the
# first two are what almost everyone actually looks at.

param(
    [string]$Name = "",
    [switch]$FrameAll,
    [string]$OutDir = "docs/store-listing/assets/screenshots"
)

$ErrorActionPreference = "Stop"
$raw = Join-Path $OutDir "raw"
New-Item -ItemType Directory -Force -Path $raw | Out-Null

function Assert-Device {
    $devices = & adb devices | Select-String -Pattern "\tdevice$"
    if (-not $devices) {
        throw "No device. Enable USB debugging and run 'adb devices' to confirm."
    }
}

if ($Name) {
    Assert-Device
    $target = Join-Path $raw "$Name.png"
    & adb exec-out screencap -p > $target
    if (-not (Test-Path $target) -or (Get-Item $target).Length -lt 1000) {
        throw "Capture failed or came back empty: $target"
    }
    Write-Host "Captured $target"
    Write-Host "Next: put the phone on the next screen and run again with a new -Name."
    return
}

if ($FrameAll) {
    # Play accepts a bare screenshot, but a caption band lifts the listing a
    # lot: the first two images are doing the selling, and a phone screenshot
    # on its own makes a reader work out what they are looking at.
    $shots = Get-ChildItem -Path $raw -Filter *.png | Sort-Object Name
    if (-not $shots) { throw "Nothing in $raw yet - capture some screens first." }

    $captions = @{
        "01_game"      = "Three scripts, each in its own alphabet"
        "02_journey"   = "300 levels, no timer, no pressure"
        "03_languages" = "Urdu, Hindi and English"
        "04_urdu"      = "Real Urdu, right to left"
        "05_daily"     = "A new puzzle every day"
        "06_themes"    = "Eight themes, or follow the clock"
    }

    foreach ($shot in $shots) {
        $key = [System.IO.Path]::GetFileNameWithoutExtension($shot.Name)
        $caption = $captions[$key]
        if (-not $caption) { $caption = "" }
        $out = Join-Path $OutDir "$key.png"

        # Scale to a Play-friendly 1080 wide, then add a caption band on top.
        # 9:16 is the safest phone ratio; Play accepts 1080x1920 without
        # complaint and it is what most devices produce anyway.
        if ($caption) {
            & ffmpeg -y -loglevel error -i $shot.FullName `
                -vf "scale=1080:-1,pad=1080:1920:0:(1920-ih)/2:color=0x141A17,drawtext=text='$caption':fontcolor=white:fontsize=46:x=(w-text_w)/2:y=64" `
                $out
        } else {
            & ffmpeg -y -loglevel error -i $shot.FullName -vf "scale=1080:-1" $out
        }
        Write-Host "Framed $out"
    }
    Write-Host ""
    Write-Host "Upload the framed PNGs in $OutDir (not the ones in raw\)."
    return
}

Write-Host "Pass -Name <label> to capture, or -FrameAll to frame what you captured."
Write-Host "Screens worth having, in the order they sell best:"
Write-Host "  01_game       the grid mid-word, a few words already found"
Write-Host "  02_journey    the level map, showing the trail and some stars"
Write-Host "  03_languages  the language picker"
Write-Host "  04_urdu       the grid in Urdu"
Write-Host "  05_daily      the daily challenge"
Write-Host "  06_themes     Settings, theme row visible"
