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

echo "==> Verificando Homebrew..."
# Homebrew é usado logo abaixo pra garantir um Python moderno e, mais adiante,
# um ffmpeg com suporte a AV1 — instalar ele primeiro simplifica o resto do
# script inteiro (deixa de precisar de instruções manuais separadas).
if ! command -v brew >/dev/null 2>&1; then
  for shellenv_bin in "/opt/homebrew/bin/brew" "/usr/local/bin/brew"; do
    [ -x "$shellenv_bin" ] && eval "$("$shellenv_bin" shellenv)"
  done
fi
if ! command -v brew >/dev/null 2>&1; then
  echo "    Homebrew não encontrado. Instalando (pode pedir sua senha do Mac e"
  echo "    demorar alguns minutos — só acontece uma vez)..."
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  for shellenv_bin in "/opt/homebrew/bin/brew" "/usr/local/bin/brew"; do
    [ -x "$shellenv_bin" ] && eval "$("$shellenv_bin" shellenv)"
  done
  # Persiste no .zprofile pra sessões futuras do Terminal também enxergarem
  # o Homebrew, não só esta.
  if command -v brew >/dev/null 2>&1 && ! grep -q "brew shellenv" "$HOME/.zprofile" 2>/dev/null; then
    { echo; echo "eval \"\$($(command -v brew) shellenv)\""; } >> "$HOME/.zprofile"
  fi
fi
if command -v brew >/dev/null 2>&1; then
  echo "    OK: $(brew --version | head -n1)"
else
  echo "    Não consegui instalar o Homebrew automaticamente — seguindo sem ele."
  echo "    ffmpeg pode ficar sem suporte a AV1, e o Python usado pode ser uma"
  echo "    versão antiga demais pro yt-dlp mais recente."
fi

echo "==> Verificando Python..."
# Prefere um Python do Homebrew (mais novo) em vez do Python do sistema/Xcode
# Command Line Tools, que no macOS costuma ser uma versão antiga (ex.: 3.9).
# yt-dlp deixou de dar suporte a Python tão antigo em versões recentes, então
# o pip trava silenciosamente numa versão desatualizada do yt-dlp — sem
# opções novas como --js-runtimes, e sem nenhum erro na hora da instalação,
# só quando o download real é tentado. Resolvido uma vez aqui e reusado pra
# instalar o yt-dlp e pra gerar o wrapper do Chrome mais abaixo — assim os
# dois usam sempre o MESMO Python.
PYTHON3_PATH=""
for candidate in "/opt/homebrew/bin/python3" "/usr/local/bin/python3"; do
  [ -x "$candidate" ] && PYTHON3_PATH="$candidate" && break
done
if [ -z "$PYTHON3_PATH" ] && command -v brew >/dev/null 2>&1; then
  echo "    Instalando Python do Homebrew (garante uma versão compatível com o"
  echo "    yt-dlp mais recente)..."
  brew install python3
  for candidate in "/opt/homebrew/bin/python3" "/usr/local/bin/python3"; do
    [ -x "$candidate" ] && PYTHON3_PATH="$candidate" && break
  done
fi
if [ -z "$PYTHON3_PATH" ]; then
  PYTHON3_PATH="$(command -v python3 || true)"
fi
if [ -z "$PYTHON3_PATH" ]; then
  echo "python3 não encontrado. Instale (ex.: 'brew install python3' ou"
  echo "https://www.python.org/downloads/) e rode este script de novo."
  exit 1
fi
echo "==> Usando python3: $PYTHON3_PATH ($("$PYTHON3_PATH" --version 2>&1))"

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
#
# --break-system-packages: necessário no Python do Homebrew (e em builds
# recentes do python.org), que marca o ambiente como "externally managed"
# (PEP 668) e recusa `pip install` sem essa flag — mesmo com --user, que já
# é a combinação seguro-o-suficiente que a própria mensagem de erro do pip
# recomenda. Em Pythons mais antigos que não têm essa proteção, a flag é
# simplesmente ignorada (não quebra nada).
"$PYTHON3_PATH" -m pip install --user --break-system-packages --upgrade "yt-dlp[default]" \
  || "$PYTHON3_PATH" -m pip install --user --upgrade "yt-dlp[default]"

# Resolve o yt-dlp recém-instalado pelo MESMO python3 acima (site.getuserbase()),
# em vez de confiar em `command -v yt-dlp`. Motivo: se o Mac tiver mais de um
# Python instalado (comum — o do sistema/Xcode Command Line Tools, mais um
# do Homebrew ou python.org instalado depois), cada um tem sua própria pasta
# de scripts `--user`, e o PATH pode ter a pasta do Python ERRADO (mais
# antigo) na frente. Isso já causou "yt-dlp: error: no such option:
# --js-runtimes" — o `command -v` achava um yt-dlp de meses atrás, instalado
# por um Python 3.9 do sistema, que nem tinha essa opção, mesmo com a
# reinstalação atual (via Python novo) tendo funcionado normalmente.
USER_SCRIPTS_DIR="$("$PYTHON3_PATH" -c 'import site, os; print(os.path.join(site.getuserbase(), "bin"))' 2>/dev/null || true)"
if [ -n "$USER_SCRIPTS_DIR" ] && [ -x "$USER_SCRIPTS_DIR/yt-dlp" ]; then
  YTDLP_PATH="$USER_SCRIPTS_DIR/yt-dlp"
else
  YTDLP_PATH="$(command -v yt-dlp)"
fi
echo "    OK: $("$YTDLP_PATH" --version)"

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
# YTDLP_PATH e PYTHON3_PATH já foram resolvidos lá em cima.
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
