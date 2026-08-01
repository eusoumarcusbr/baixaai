#!/usr/bin/env bash
# install.sh — instala o ajudante local do BaixaAI (macOS).
#
# O que este script faz:
#   1. Confere/instala yt-dlp (via pip3) e avisa se o ffmpeg estiver faltando.
#   2. Registra o native messaging host no Chrome, apontando para o caminho
#      absoluto real deste script no seu computador.
#
# Rode com: bash install.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST_SCRIPT="$SCRIPT_DIR/baixaai_host.py"
CHROME_NMH_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"

echo "==> Verificando yt-dlp..."
if ! command -v yt-dlp >/dev/null 2>&1; then
  echo "    Instalando yt-dlp via pip3 (--user)..."
  pip3 install --user --upgrade yt-dlp
else
  echo "    OK: $(yt-dlp --version)"
fi

echo "==> Verificando ffmpeg..."
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "    ffmpeg não encontrado."
  if command -v brew >/dev/null 2>&1; then
    echo "    Instalando com Homebrew..."
    brew install ffmpeg
  else
    echo "    Instale manualmente (ex.: 'brew install ffmpeg') e rode este script de novo."
    exit 1
  fi
else
  echo "    OK: $(ffmpeg -version | head -n1)"
fi

echo "==> Verificando deno (necessário pro yt-dlp resolver o desafio JS do YouTube)..."
if ! command -v deno >/dev/null 2>&1; then
  echo "    deno não encontrado."
  if command -v conda >/dev/null 2>&1; then
    echo "    Instalando com conda..."
    conda install -c conda-forge deno -y
  elif command -v brew >/dev/null 2>&1; then
    echo "    Instalando com Homebrew..."
    brew install deno
  else
    echo "    Não achei conda nem Homebrew. Instale manualmente:"
    echo "    curl -fsSL https://deno.land/install.sh | sh"
    echo "    e rode este script de novo (sem o deno, o YouTube pode falhar)."
  fi
else
  echo "    OK: $(deno --version | head -n1)"
fi

echo "==> Gravando caminhos absolutos (o Chrome não carrega seu .zshrc/conda)..."
YTDLP_PATH="$(command -v yt-dlp)"
FFMPEG_PATH="$(command -v ffmpeg)"
FFPROBE_PATH="$(command -v ffprobe)"
DENO_PATH="$(command -v deno)"
cat > "$SCRIPT_DIR/paths.json" << PATHSEOF
{
  "yt-dlp": "$YTDLP_PATH",
  "ffmpeg": "$FFMPEG_PATH",
  "ffprobe": "$FFPROBE_PATH",
  "deno": "$DENO_PATH"
}
PATHSEOF
echo "    yt-dlp:  $YTDLP_PATH"
echo "    ffmpeg:  $FFMPEG_PATH"
echo "    ffprobe: $FFPROBE_PATH"
echo "    deno:    $DENO_PATH"

echo "==> Registrando o native messaging host no Chrome..."
mkdir -p "$CHROME_NMH_DIR"
chmod +x "$HOST_SCRIPT"

PYTHON3_PATH="$(command -v python3)"
echo "    python3: $PYTHON3_PATH"

# O Chrome executa o "path" do manifesto diretamente (sem shell de login),
# então um shebang "env python3" pode falhar se o python3 do conda não
# estiver no PATH mínimo do Chrome. Por isso geramos um wrapper com shebang
# fixo (/bin/bash sempre existe) que chama o python3 certo por caminho
# absoluto.
WRAPPER="$SCRIPT_DIR/run_host.sh"
cat > "$WRAPPER" << WRAPPEREOF
#!/bin/bash
exec "$PYTHON3_PATH" "$HOST_SCRIPT"
WRAPPEREOF
chmod +x "$WRAPPER"

sed "s|__SCRIPT_PATH__|$WRAPPER|g" \
  "$SCRIPT_DIR/com.baixaai.host.json.template" \
  > "$CHROME_NMH_DIR/com.baixaai.host.json"

echo "    Criado: $CHROME_NMH_DIR/com.baixaai.host.json"
echo
echo "Pronto! Feche e reabra o Chrome (Chrome > Sair, não só fechar a janela)"
echo "e recarregue a extensão BaixaAI em chrome://extensions."
