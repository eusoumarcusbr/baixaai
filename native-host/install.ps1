# install.ps1 — instala o ajudante local do BaixaAI (Windows).
#
# O que este script faz:
#   1. Confere/instala yt-dlp (via pip) e confere ffmpeg/deno (via winget,
#      se disponível).
#   2. Resolve os caminhos absolutos dos binários e grava em paths.json
#      (o Chrome não herda o PATH completo do usuário).
#   3. Gera um wrapper run_host.bat (o Chrome no Windows precisa de um
#      executável, não de um .py direto) e registra o native messaging
#      host no Registro do Windows (HKCU), apontando pro manifesto JSON.
#
# Rode com: powershell -ExecutionPolicy Bypass -File install.ps1
# (ou clique com o botão direito no arquivo > Executar com PowerShell)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$HostScript = Join-Path $ScriptDir "baixaai_host.py"

function Find-Python {
    foreach ($cmd in @("python", "py")) {
        $found = Get-Command $cmd -ErrorAction SilentlyContinue
        if ($found) { return $found.Source }
    }
    return $null
}

function Find-Command($name) {
    $found = Get-Command $name -ErrorAction SilentlyContinue
    if ($found) { return $found.Source }
    return $null
}

Write-Host "==> Verificando Python..."
$PythonPath = Find-Python
if (-not $PythonPath) {
    Write-Host "    Python não encontrado."
    Write-Host "    Instale em https://www.python.org/downloads/ (marque 'Add python.exe to PATH')"
    Write-Host "    e rode este script de novo."
    exit 1
}
Write-Host "    OK: $PythonPath"

Write-Host "==> Instalando/atualizando yt-dlp (com o pacote yt-dlp-ejs)..."
# Sempre roda o upgrade, mesmo se o yt-dlp já existir: o YouTube passou a
# exigir um novo mecanismo de resolucao de desafio JS (EJS, ver
# https://github.com/yt-dlp/yt-dlp/wiki/EJS) que substituiu o esquema
# antigo baseado so no deno. O pacote com os scripts do EJS
# (yt-dlp-ejs) so vem junto se pedirmos o extra "[default]".
& $PythonPath -m pip install --user --upgrade "yt-dlp[default]"
$YtdlpPath = Find-Command "yt-dlp"
if (-not $YtdlpPath) {
    # depois de instalar, o executável fica em
    # %APPDATA%\Python\PythonXY\Scripts — garante que está no PATH desta sessão
    $UserScripts = & $PythonPath -c "import site, os; print(os.path.normpath(os.path.join(site.getusersitepackages(), '..', 'Scripts')))"
    $env:Path = "$UserScripts;$env:Path"
    $YtdlpPath = Find-Command "yt-dlp"
    if (-not $YtdlpPath) {
        Write-Host "    yt-dlp instalado mas não encontrado no PATH desta sessão."
        Write-Host "    Abra um novo PowerShell e rode este script de novo."
        exit 1
    }
}
Write-Host "    OK: $YtdlpPath"

Write-Host "==> Verificando ffmpeg..."
$FfmpegPath = Find-Command "ffmpeg"
$FfprobePath = Find-Command "ffprobe"
if (-not $FfmpegPath) {
    Write-Host "    ffmpeg não encontrado."
    $winget = Find-Command "winget"
    if ($winget) {
        Write-Host "    Instalando com winget..."
        winget install --id Gyan.FFmpeg -e --accept-source-agreements --accept-package-agreements
        # winget instala num local próprio; precisa de um PowerShell novo
        # pra herdar o PATH atualizado — orienta o usuário nesse caso.
        $FfmpegPath = Find-Command "ffmpeg"
        if (-not $FfmpegPath) {
            Write-Host "    ffmpeg instalado, mas este PowerShell ainda não enxerga o PATH novo."
            Write-Host "    Feche esta janela, abra um PowerShell novo e rode este script de novo."
            exit 1
        }
    } else {
        Write-Host "    winget não disponível. Baixe manualmente em https://www.gyan.dev/ffmpeg/builds/"
        Write-Host "    descompacte, adicione a pasta 'bin' ao PATH do Windows, e rode este script de novo."
        exit 1
    }
} else {
    Write-Host "    OK: $FfmpegPath"
}
if (-not $FfprobePath) { $FfprobePath = Find-Command "ffprobe" }

Write-Host "==> Verificando deno (necessário pro yt-dlp resolver o desafio JS do YouTube)..."
$DenoPath = Find-Command "deno"
if (-not $DenoPath) {
    Write-Host "    deno não encontrado."
    $winget = Find-Command "winget"
    if ($winget) {
        Write-Host "    Instalando com winget..."
        winget install --id DenoLand.Deno -e --accept-source-agreements --accept-package-agreements
        $DenoPath = Find-Command "deno"
        if (-not $DenoPath) {
            Write-Host "    deno instalado, mas este PowerShell ainda não enxerga o PATH novo."
            Write-Host "    Feche esta janela, abra um PowerShell novo e rode este script de novo."
        }
    } else {
        Write-Host "    winget não disponível. Instale manualmente:"
        Write-Host "    irm https://deno.land/install.ps1 | iex"
        Write-Host "    e rode este script de novo (sem o deno, o YouTube pode falhar)."
    }
} else {
    Write-Host "    OK: $DenoPath"
}

Write-Host "==> Gravando caminhos absolutos (o Chrome não herda o PATH do usuário)..."
$PathsJson = @{
    "yt-dlp"  = $YtdlpPath
    "ffmpeg"  = $FfmpegPath
    "ffprobe" = $FfprobePath
    "deno"    = $DenoPath
} | ConvertTo-Json
Set-Content -Path (Join-Path $ScriptDir "paths.json") -Value $PathsJson -Encoding UTF8
Write-Host "    yt-dlp:  $YtdlpPath"
Write-Host "    ffmpeg:  $FfmpegPath"
Write-Host "    ffprobe: $FfprobePath"
Write-Host "    deno:    $DenoPath"

Write-Host "==> Gerando wrapper (run_host.bat)..."
# O Chrome executa o "path" do manifesto diretamente — no Windows isso
# precisa ser um .exe/.bat, não um .py. O wrapper chama o python certo por
# caminho absoluto, do mesmo jeito que o run_host.sh faz no macOS.
$WrapperPath = Join-Path $ScriptDir "run_host.bat"
$WrapperContent = "@echo off`r`n`"$PythonPath`" `"$HostScript`"`r`n"
Set-Content -Path $WrapperPath -Value $WrapperContent -Encoding ASCII -NoNewline

Write-Host "==> Registrando o native messaging host no Chrome (Registro do Windows)..."
# O caminho no JSON precisa ter as barras invertidas escapadas (\\) — cada
# "\" literal do caminho vira "\\" no texto JSON.
$WrapperPathJson = $WrapperPath -replace '\\', '\\'
$Template = Get-Content (Join-Path $ScriptDir "com.baixaai.host.json.template") -Raw
$Manifest = $Template -replace '__SCRIPT_PATH__', $WrapperPathJson
$ManifestPath = Join-Path $ScriptDir "com.baixaai.host.json"
Set-Content -Path $ManifestPath -Value $Manifest -Encoding UTF8

$RegPath = "HKCU:\Software\Google\Chrome\NativeMessagingHosts\com.baixaai.host"
New-Item -Path $RegPath -Force | Out-Null
Set-Item -Path $RegPath -Value $ManifestPath

Write-Host "    Manifesto: $ManifestPath"
Write-Host "    Chave de registro: $RegPath"
Write-Host ""
Write-Host "Pronto! Feche TODAS as janelas do Chrome e abra de novo"
Write-Host "e recarregue a extensão BaixaAI em chrome://extensions."
