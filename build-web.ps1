# Rebuilds the browser version of Plotline into .\web (needs Node.js).
# Only the love.js runtime files are replaced; the page itself (web\index.html) is hand-written and kept.
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$tmp = Join-Path $env:TEMP 'plotline-web-build'
if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
New-Item -ItemType Directory $tmp | Out-Null

# The web build runs at the game's native 960x540 so it fits the page.
$utf8 = New-Object System.Text.UTF8Encoding($false)
$conf = [IO.File]::ReadAllText("$root\conf.lua") -replace 'width = 1280', 'width = 960' -replace 'height = 720', 'height = 540'
[IO.File]::WriteAllText("$tmp\conf.lua", $conf, $utf8)
Copy-Item "$root\main.lua" $tmp

Compress-Archive -Path "$tmp\main.lua", "$tmp\conf.lua" -DestinationPath "$tmp\plotline.zip"
Move-Item "$tmp\plotline.zip" "$tmp\plotline.love"

npm install --silent --prefix $tmp love.js@11.4.1
node "$tmp\node_modules\love.js\index.js" -c -t Plotline -m 67108864 "$tmp\plotline.love" "$tmp\out"

New-Item -ItemType Directory -Force "$root\web" | Out-Null
foreach ($f in 'love.js', 'love.wasm') { Copy-Item "$tmp\out\$f" "$root\web\$f" -Force }

# Ship the game package as a script (game-data.js) instead of a raw .data file, so it can be
# hosted anywhere that serves .js; game.js is patched to take the bytes from Module.gameData.
$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes("$tmp\out\game.data"))
[IO.File]::WriteAllText("$root\web\game-data.js", "window.PLOTLINE_DATA = '$b64';`n", $utf8)
$sig = 'function fetchRemotePackage(packageName, packageSize, callback, errback) {'
$js = [IO.File]::ReadAllText("$tmp\out\game.js")
if (-not $js.Contains($sig)) { throw 'game.js layout changed; cannot patch fetchRemotePackage' }
$js = $js.Replace($sig, $sig + "`n      if (Module.gameData) { setTimeout(function () { callback(Module.gameData); }, 0); return; }")
[IO.File]::WriteAllText("$root\web\game.js", $js, $utf8)
if (Test-Path "$root\web\game.data") { Remove-Item "$root\web\game.data" }
Write-Host "Web build updated in $root\web"
