# BaixaAI

Extensão de Chrome para uso pessoal, com dois modos:

- **YouTube, Instagram e Globo** (g1, ge, gshow, globoplay, oglobo,
  redeglobo etc. — qualquer `*.globo.com`) → baixa o **arquivo de vídeo
  original** (usa um ajudante local que roda `yt-dlp` + `ffmpeg`),
  normalizado para Full HD: **1920×1080 (16:9)** horizontal ou
  **1080×1920 (9:16)** vertical.
- **Qualquer outro site** → grava a tela em tempo real (fallback), já que
  não dá pra extrair o arquivo original de forma confiável em sites
  genéricos.

A extensão detecta sozinha em qual dos dois modos está, com base na URL da
aba ativa.

**Importante sobre o modo YouTube/Instagram/Globo:** o Chrome pode encerrar a
extensão (service worker) sozinho depois de um tempo, o que mataria um
download longo no meio. Por isso o ajudante local dispara um **processo
totalmente separado do Chrome** para baixar+normalizar — ele roda até o
fim mesmo que você feche o popup ou o Chrome derrube a extensão. Quando
terminar (ou der erro), você recebe uma **notificação nativa do macOS**.
Na primeira vez, o macOS pode pedir permissão de notificação — autorize.

## Estrutura

```
baixaai/
  manifest.json, popup.*, content.js, background.js, icons/   → a extensão
  native-host/
    baixaai_host.py                → o ajudante local (native messaging host)
    com.baixaai.host.json.template → registrado no Chrome pelo install.sh
    install.sh                     → instala tudo (macOS)
```

## Instalação

### 1) Carregar a extensão no Chrome

1. Abra `chrome://extensions`.
2. Ative o **Modo desenvolvedor**.
3. **Carregar sem compactação** → selecione a pasta `baixaai`.

### 2) Instalar o ajudante local (necessário para YouTube/Instagram/Globo)

Requer Python 3 e `pip3` (o macOS já vem com eles; se faltar, instale via
`brew install python3` ou use o conda, se já tiver).

```bash
cd baixaai/native-host
bash install.sh
```

O script instala o `yt-dlp` (via `pip3 install --user`), confere/instala o
`ffmpeg`, grava os caminhos absolutos encontrados (importante quando você
usa conda/homebrew) e registra o host nativo no Chrome.

Depois, **feche o Chrome completamente** (Chrome ▸ Sair do Google Chrome,
não só a janela) e abra de novo — native messaging hosts só são lidos
quando o Chrome inicia.

> **Pasta em volume externo?** Se a pasta `baixaai` estiver num HD/SSD
> externo (ex.: `/Volumes/...`), o Chrome pode ser bloqueado pelo macOS de
> rodar processos ali. Se dois passos acima não funcionarem (erro "Native
> host has exited" mesmo com tudo certo), mova pelo menos a pasta
> `native-host` para dentro do seu diretório pessoal (`~`) e rode o
> `install.sh` de lá.

## Como usar

1. Abra o vídeo do YouTube, Instagram ou Globo (g1, ge, gshow, globoplay
   etc.) — ou qualquer outro site.
2. Clique no ícone da extensão.
3. Escolha o ajuste de proporção (barras pretas ou corte).
4. Clique em **Baixar**. O popup confirma que o download começou em
   segundo plano — pode fechar. Quando terminar, uma notificação do macOS
   avisa, e o arquivo está em `~/Downloads/BaixaAI/`.
5. Se algo der errado, o log fica em `~/Downloads/BaixaAI/.logs/<job_id>.log`.

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
- **Conteúdo com DRM** (raro fora de plataformas de streaming pago) não é
  suportado por nenhum dos dois modos.
- O modo de **captura de tela** (sites genéricos) grava em tempo real —
  um vídeo de 10 minutos leva 10 minutos pra gravar.
- yt-dlp muda com frequência para acompanhar mudanças das plataformas.
  Se algo parar de funcionar, rode `pip3 install --user --upgrade yt-dlp`
  (ou o equivalente via conda, se foi por ali que instalou).

## Sobre Termos de Uso

Isto é uma ferramenta de **uso pessoal e privado**. Baixar vídeos do
YouTube e do Instagram viola os Termos de Uso dessas plataformas,
independente da técnica usada — evite redistribuir conteúdo de terceiros
e tenha isso em mente ao usar.

