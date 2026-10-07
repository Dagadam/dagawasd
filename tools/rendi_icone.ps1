# DagaWASD — icone PNG dagli SVG di pubblicazione\ (con Edge headless, già in Windows).
#   pubblicazione\icona_barra.svg → icons\wasd_32.png, icons\wasd_24.png (barra degli strumenti)
#   pubblicazione\icona.svg       → pubblicazione\icona_512.png (scheda dell'Extension Warehouse)
# Edge disegna ogni SVG alla misura finale, su fondo trasparente: più nitido che
# rimpicciolire un'immagine grande.
$radice = Split-Path -Parent $PSScriptRoot
$edge = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
if (-not (Test-Path $edge)) { $edge = "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe" }
if (-not (Test-Path $edge)) { Write-Host '  [X] Microsoft Edge non trovato'; exit 1 }

function Rendi([string]$svg, [string]$png, [int]$lato) {
  $svg = Join-Path $radice $svg; $png = Join-Path $radice $png
  $html = Join-Path $env:TEMP ("dagawasd_icona_" + [guid]::NewGuid() + ".html")
  $uri = ([Uri]$svg).AbsoluteUri
  Set-Content -Path $html -Encoding utf8 -Value "<!doctype html><html><body style='margin:0;background:transparent'><img src='$uri' width='$lato' height='$lato' style='display:block'></body></html>"
  $prof = Join-Path $env:TEMP ("dagawasd_edge_" + [guid]::NewGuid())
  if (Test-Path $png) { Remove-Item $png }
  & $edge --headless=new --disable-gpu --hide-scrollbars --default-background-color=00000000 --user-data-dir="$prof" `
    --window-size="$lato,$lato" --screenshot="$png" ([Uri]$html).AbsoluteUri 2>$null | Out-Null
  Start-Sleep -Milliseconds 300
  Remove-Item $html -ErrorAction SilentlyContinue
  Remove-Item $prof -Recurse -Force -ErrorAction SilentlyContinue
  if (Test-Path $png) { Write-Host "  $png ($lato px)" } else { Write-Host "  [X] $png non creato"; exit 1 }
}

Rendi 'pubblicazione\icona_barra.svg' 'icons\wasd_32.png' 32
Rendi 'pubblicazione\icona_barra.svg' 'icons\wasd_24.png' 24
Rendi 'pubblicazione\icona.svg' 'pubblicazione\icona_512.png' 512
