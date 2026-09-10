# The item-protection padlock (OTCLIENT modules/game_protect, drawn by the
# Item style in data/styles/10-items.otui at the top-right of a slot).
# Pixel art at its exact drawn size, 8x10, so nothing is scaled: a steel
# shackle over a gold body with a dark outline and a keyhole. Between the two
# sizes tried before it: 12x14 covered a quarter of the item, 6x7 vanished.
#   powershell -File make_lock.ps1
Add-Type -AssemblyName System.Drawing

$W = 8; $H = 10
# . clear  # outline  s shackle  L gold light  g gold  d gold dark  k keyhole
# (L, not G: PowerShell hash keys are case-insensitive, so G and g would collide)
$ART = @(
    '..ssss..',
    '.s....s.',
    '.s....s.',
    '########',
    '#LLLLLg#',
    '#LLkkLg#',
    '#LLkkgg#',
    '#ggkggd#',
    '#gggggd#',
    '########'
)
$PALETTE = @{
    '#' = @(30, 22, 14, 255)
    's' = @(214, 216, 226, 255)
    'L' = @(255, 222, 110, 255)
    'g' = @(226, 176, 46, 255)
    'd' = @(166, 118, 24, 255)
    'k' = @(44, 30, 12, 255)
}
$bmp = New-Object System.Drawing.Bitmap $W, $H, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
for ($y = 0; $y -lt $H; $y++) {
    for ($x = 0; $x -lt $W; $x++) {
        $c = $PALETTE[[string]$ART[$y][$x]]
        if ($c) { $bmp.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($c[3], $c[0], $c[1], $c[2])) }
    }
}
$out = Join-Path $PSScriptRoot 'lock.png'
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
"lock written {0}x{1} -> {2}" -f $W, $H, $out
