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

echo "==> Instalando/atualizando yt-dlp (com o pacote yt-dlp-ejs)..."
# Sempre roda o upgrade, mesmo se o yt-dlp já existir: o YouTube passou a
# exigir um novo mecanismo de resolução de desafio JS (EJS, ver
# https://github.com/yt-dlp/yt-dlp/wiki/EJS) que substituiu o esquema
# antigo baseado só no deno. O pacote com os scripts do EJS
# (`yt-dlp-ejs`) só vem junto se pedirmos o extra "[default]" — instalação
# feita antes dessa mudança (ou um "pip install yt-dlp" simples) não tem
# esse pacote, e por isso os downloads do YouTube passam a falhar (fica
# só em "imagens disponíveis" ou cai num formato que dá 403 no meio do
# download).
pip3 install --user --upgrade "yt-dlp[default]"
echo "    OK: $(yt-dlp --version)"

echo "==> Verificando ffmpeg..."
# Prefere o ffmpeg do Homebrew (que inclui o decoder AV1 via libdav1d) em vez
# do que vier primeiro no PATH (ex.: o do conda, que em builds antigas não
# decodifica AV1). Facebook/Instagram às vezes só oferecem AV1 pra um vídeo,
# e sem esse decoder o ffmpeg falha ao normalizar pra Full HD com "Decoder
# (codec av1) not found". Isso já causou esse bug uma vez — essa checagem
# evita que uma reinstalação futura regrida pro mesmo problema.
FFMPEG_PATH=""
for candidate in "/opt/homebrew/bin/ffmpeg" "/usr/local/bin/ffmpeg" "$(command -v ffmpeg 2>/dev/null || true)"; do
  if [ -n "$candidate" ] && [ -x "$candidate" ]; then
    FFMPEG_PATH="$candidate"
    break
  fi
done

if [ -z "$FFMPEG_PATH" ]; then
  echo "    ffmpeg não encontrado."
  if command -v brew >/dev/null 2>&1; then
    echo "    Instalando com Homebrew..."
    brew install ffmpeg
    FFMPEG_PATH="$(brew --prefix)/bin/ffmpeg"
  else
    echo "    Instale manualmente (ex.: 'brew install ffmpeg') e rode este script de novo."
    exit 1
  fi
elif ! "$FFMPEG_PATH" -decoders 2>/dev/null | grep -qi "av1"; then
  echo "    $FFMPEG_PATH não decodifica AV1 (usado por alguns vídeos do Facebook/Instagram)."
  if command -v brew >/dev/null 2>&1; then
    echo "    Instalando ffmpeg do Homebrew (com suporte a AV1)..."
    brew install ffmpeg
    FFMPEG_PATH="$(brew --prefix)/bin/ffmpeg"
  else
    echo "    Aviso: seguindo com $FFMPEG_PATH mesmo assim — instale o Homebrew"
    echo "    e rode 'brew install ffmpeg' pra suporte completo a AV1."
  fi
fi
echo "    OK: $("$FFMPEG_PATH" -version | head -n1)"

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
FFPROBE_PATH="$(dirname "$FFMPEG_PATH")/ffprobe"
if [ ! -x "$FFPROBE_PATH" ]; then
  FFPROBE_PATH="$(command -v ffprobe)"
fi
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
