# BaixaAI

Extensão de Chrome para uso pessoal, com dois modos:

- **YouTube, Instagram, Globo, Facebook e TikTok** (g1, ge, gshow, globoplay,
  oglobo, redeglobo etc. — qualquer `*.globo.com` — `facebook.com` /
  `fb.watch`, incluindo reels — e `tiktok.com`, incluindo os links curtos
  `vm.tiktok.com`/`vt.tiktok.com`) → baixa o **arquivo de vídeo original**
  (usa um ajudante local que roda `yt-dlp` + `ffmpeg`), normalizado para
  Full HD: **1920×1080 (16:9)** horizontal ou **1080×1920 (9:16)** vertical.
- **Qualquer outro site** → grava a tela em tempo real (fallback), já que
  não dá pra extrair o arquivo original de forma confiável em sites
  genéricos.

A extensão detecta sozinha em qual dos dois modos está, com base na URL da
aba ativa.

**Importante sobre o modo YouTube/Instagram/Globo/Facebook/TikTok:** o Chrome pode encerrar a
extensão (service worker) sozinho depois de um tempo, o que mataria um
download longo no meio. Por isso o ajudante local dispara um **processo
totalmente separado do Chrome** para baixar+normalizar — ele roda até o
fim mesmo que você feche o popup ou o Chrome derrube a extensão. Quando
terminar (ou der erro), você recebe uma notificação nativa (macOS: Central
de Notificações; Windows: toast) **e** um som — se a notificação falhar
por qualquer motivo, o som ainda avisa.

## Estrutura

```
baixaai/
  manifest.json, popup.*, content.js, background.js, icons/   → a extensão
  native-host/
    baixaai_host.py                → o ajudante local (native messaging host)
    com.baixaai.host.json.template → registrado no Chrome pelo install.sh/.ps1
    install.sh                     → instala tudo (macOS)
    install.ps1                    → instala tudo (Windows)
```

## Instalação

### 1) Carregar a extensão no Chrome

1. Abra `chrome://extensions`.
2. Ative o **Modo desenvolvedor**.
3. **Carregar sem compactação** → selecione a pasta `baixaai`.

### 2) Instalar o ajudante local (necessário para YouTube/Instagram/Globo/Facebook/TikTok)

#### macOS

Não precisa instalar nada antes — o script cuida de tudo (Homebrew, Python
moderno, yt-dlp, ffmpeg com suporte a AV1). Só precisa de conexão com a
internet.

```bash
cd baixaai/native-host
bash install.sh
```

O script instala o Homebrew se faltar (pode pedir sua senha do Mac — só da
primeira vez), garante um Python moderno (evita ficar preso na versão antiga
do sistema, que trava o yt-dlp numa versão sem os recursos mais novos),
instala o `yt-dlp` e o `ffmpeg` (com suporte a AV1), grava os caminhos
absolutos encontrados e registra o host nativo no Chrome. Em Macs que nunca
tiveram nada de desenvolvedor instalado, pode aparecer uma janela do sistema
pedindo pra instalar as "Command Line Tools" — clique em **Instalar**, espere
terminar (10–20 min, precisa de internet) e rode `bash install.sh` de novo.

> **Pasta em Desktop, Documents, Downloads ou volume externo?** Se der erro
> "Native host has exited" mesmo com tudo certo (manifesto correto, yt-dlp/
> ffmpeg instalados), é quase sempre isso: o macOS protege as pastas
> **Desktop, Documents e Downloads** (proteção TCC) e bloqueia
> silenciosamente o `bash` de ler arquivos ali quando é o Chrome quem manda
> rodar o processo — mesmo com o Chrome tendo Acesso Total ao Disco, porque
> quem pede o acesso é o `bash`, não o Chrome. Pastas em HD/SSD externo
> (`/Volumes/...`) têm o mesmo tipo de bloqueio, por outro motivo. **Fix:**
> mova pelo menos a pasta `native-host` para um lugar comum dentro do seu
> diretório pessoal, fora dessas três pastas — por exemplo `~/baixaai` ou
> `~/Documents` não, mas algo como `~/.baixaai` ou simplesmente
> `~/baixaai-native-host` — e rode o `install.sh` de lá. A extensão em si
> (o resto da pasta, carregada via "Carregar sem compactação") pode
> continuar em Desktop/Downloads sem problema, só o `native-host` é afetado.

> **`error: externally-managed-environment` ao instalar o yt-dlp?** Comum
> em Macs com Python instalado via Homebrew (ou builds recentes do
> python.org): o pip recusa instalar pacotes sem a flag
> `--break-system-packages`. O `install.sh` já tenta essa flag
> automaticamente — se ainda assim der erro, rode manualmente:
> `python3 -m pip install --user --break-system-packages --upgrade "yt-dlp[default]"`
> e depois `bash install.sh` de novo.

> **Mac com mais de um Python instalado?** Se o `yt-dlp --version` mostrar
> uma versão antiga mesmo depois de reinstalar (ou der erro tipo
> `no such option: --js-runtimes`), o PATH provavelmente está achando um
> `yt-dlp` de uma instalação de Python mais antiga primeiro. O `install.sh`
> já resolve isso automaticamente a partir da v2.5.1 (usa sempre o mesmo
> `python3` do começo ao fim do script) — se estiver numa versão mais
> antiga do `install.sh`, baixe a mais recente do repositório
> (github.com/eusoumarcusbr/baixaai) e rode de novo.

#### Windows

Requer Python 3 (baixe em [python.org](https://www.python.org/downloads/) e
marque **"Add python.exe to PATH"** na instalação, se ainda não tiver).

Abra o **PowerShell** dentro da pasta `native-host` e rode:

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1
```

O script instala o `yt-dlp` (via `pip install --user`), instala `ffmpeg`
e `deno` via `winget` (se disponível), grava os caminhos absolutos em
`paths.json`, gera um `run_host.bat` (wrapper necessário porque o Chrome
não executa `.py` diretamente) e registra o native messaging host no
Registro do Windows (`HKCU\Software\Google\Chrome\NativeMessagingHosts`).

> **Suporte a Windows é recente e ainda não foi validado numa máquina
> Windows real** — só revisado com cuidado. Se algo falhar, o log fica em
> `%USERPROFILE%\Downloads\BaixaAI\.logs\<job_id>.log` e ajuda bastante a
> diagnosticar.

> **Nada acontece ao clicar em "Baixar"?** No modo YouTube/Instagram/
> Globo/Facebook/TikTok o download roda em segundo plano, fora do Chrome —
> sem notificação nenhuma, pode parecer que travou mesmo estando
> progredindo normalmente (arquivos grandes demoram). O popup mostra uma
> barra de progresso com %/velocidade/ETA em tempo real; se ela não
> aparecer, feche e reabra o popup.

Depois de instalar (em qualquer sistema), **feche o Chrome completamente**
(não só a janela — no Windows, confira no Gerenciador de Tarefas se não
sobrou nenhum processo `chrome.exe`) e abra de novo. Native messaging
hosts só são lidos quando o Chrome inicia.

## Como usar

1. Abra o vídeo do YouTube, Instagram, Globo (g1, ge, gshow, globoplay
   etc.), Facebook (posts, reels, fb.watch) ou TikTok — ou qualquer outro
   site.
2. Clique no ícone da extensão.
3. Escolha o ajuste de proporção (barras pretas ou corte).
4. Clique em **Baixar**. O popup confirma que o download começou em
   segundo plano — pode fechar. Quando terminar, uma notificação e um som
   avisam, e o arquivo está em `Downloads/BaixaAI/`.
5. Se algo der errado, o log fica em `Downloads/BaixaAI/.logs/<job_id>.log`.

## TranscrevAI (transcrição de links)

A partir da v2.6.0 o BaixaAI também serve o site **TranscrevAI**
(`https://eusoumarcus.com.br/transcrevai/`), que transcreve no próprio
navegador. Quando o site recebe um link de YouTube, Instagram, TikTok,
Facebook ou Globo, ele pede o áudio para a extensão, que baixa só o áudio
com o yt-dlp (arquivo leve, apagado depois) e devolve para a página.

- No popup, em sites de download direto, o botão **Transcrever no
  TranscrevAI** abre o site já com o link da aba.
- Depois de atualizar, recarregue a extensão em `chrome://extensions`. O
  ajudante local não precisa ser reinstalado.

## Limitações e observações

- **Instagram** costuma exigir estar logado para muitos vídeos. O ajudante
  tenta reaproveitar automaticamente os cookies do Chrome
  (`--cookies-from-browser chrome`); se isso falhar (às vezes o Chrome
  aberto trava o acesso ao arquivo de cookies), ele tenta de novo sem
  cookies — funciona para conteúdo público.
- **Globo (g1, ge, gshow, globoplay...)**: o yt-dlp extrai o vídeo lendo o
  HTML da página em busca do player embutido. Funciona em páginas normais
  e também nas versões AMP (ex.: `g1.globo.com/google/amp/...`), mas se um
  link específico não funcionar, tente abrir a versão "normal" da notícia
  (sem o `google/amp/` no caminho da URL) — às vezes o AMP simplifica o
  HTML e remove a marcação que o extractor procura. Conteúdo do Globoplay
  que exige assinatura (DRM) não é suportado, só o vídeo em si dá erro
  claro no log.
- **Facebook**: muito conteúdo (posts de perfis privados, alguns reels,
  watch parties) exige estar logado — mesma lógica de cookies do
  Instagram (tenta com os cookies do Chrome, senão sem). Conteúdo público
  de páginas costuma funcionar sem login.
- **TikTok**: vídeos públicos baixam sem login. Alguns vídeos são
  codificados em **AV1** — o ffmpeg precisa ter suporte a esse codec pra
  normalizar pra Full HD (o `install.sh` já garante isso preferindo o
  ffmpeg do Homebrew, que inclui o decoder via `libdav1d`).
- **Conteúdo com DRM** (raro fora de plataformas de streaming pago) não é
  suportado por nenhum dos dois modos.
- O modo de **captura de tela** (sites genéricos) grava em tempo real —
  um vídeo de 10 minutos leva 10 minutos pra gravar.
- yt-dlp muda com frequência para acompanhar mudanças das plataformas.
  Se algo parar de funcionar, rode `pip3 install --user --upgrade "yt-dlp[default]"`
  no macOS ou `python -m pip install --user --upgrade "yt-dlp[default]"` no
  Windows (ou o equivalente via conda, se foi por ali que instalou) — o
  `[default]` é importante, não só o `--upgrade` (ver observação sobre o
  YouTube logo abaixo).
- **YouTube parou de baixar (só imagens/thumbnail, ou erro 403 no meio do
  download)**: o YouTube exige um mecanismo de resolução de desafio
  JavaScript chamado EJS (substituiu o esquema antigo baseado só no
  `deno`). O pacote com os scripts do EJS (`yt-dlp-ejs`) só é instalado
  junto se o yt-dlp for instalado/atualizado com o extra `[default]`
  (comando acima). Rode `bash native-host/install.sh` (ou o `install.ps1`
  no Windows) de novo pra aplicar — o script sempre reinstala o yt-dlp com
  esse extra agora, mesmo se já estiver instalado.

## Sobre Termos de Uso

Isto é uma ferramenta de **uso pessoal e privado**. Baixar vídeos do
YouTube, Instagram, Globo, Facebook ou TikTok viola os Termos de Uso
dessas plataformas, independente da técnica usada — evite redistribuir
conteúdo de terceiros e tenha isso em mente ao usar.

