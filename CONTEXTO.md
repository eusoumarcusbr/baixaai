# BaixaAI — Contexto do projeto

Documento de referência técnica sobre a extensão BaixaAI: o que é, como
está construída, por que cada decisão foi tomada, e o histórico de
problemas já resolvidos. Serve pra retomar o desenvolvimento sem precisar
redescobrir tudo de novo.

## O que é

Extensão de Chrome (uso pessoal) com dois modos, escolhidos automaticamente
pela URL da aba ativa:

- **YouTube / Instagram / Globo** (`*.globo.com`: g1, ge, gshow, globoplay,
  oglobo, redeglobo etc.) → baixa o arquivo de vídeo original de verdade
  (via `yt-dlp` + `ffmpeg` rodando fora do Chrome), normalizado pra Full HD:
  1920×1080 (16:9) horizontal ou 1080×1920 (9:16) vertical.
- **Qualquer outro site** → grava a tela em tempo real (canvas +
  MediaRecorder), já que não dá pra extrair o arquivo original de forma
  confiável em sites genéricos.

## Arquitetura

### Extensão (roda dentro do Chrome)

- `manifest.json` — Manifest V3. Tem um campo `key` fixo (a chave pública
  gerada uma vez) pra garantir que o **ID da extensão nunca muda**, mesmo
  recarregada como "unpacked" — isso é o que permite o native messaging
  host saber de antemão qual `allowed_origins` aceitar. ID atual:
  `dflppeifdophmkfncbkkafpfnbnfhajp`.
- `popup.html/css/js` — UI. Detecta o modo (download real vs captura),
  mostra o seletor de proporção (ajustar/preencher) e dispara a ação.
- `content.js` — só usado no modo de captura de tela: acha o `<video>` da
  página, desenha frame a frame num canvas do tamanho-alvo (letterbox ou
  crop conforme escolhido) e grava com `MediaRecorder`, disparando o
  download via `<a download>` (sem precisar de `chrome.downloads`).
- `background.js` — ponte entre popup, content script e o ajudante nativo.

### Ajudante local (roda fora do Chrome, via Native Messaging)

- `native-host/baixaai_host.py` — o host nativo. Ver decisões abaixo pra
  entender por que ele é mais complexo do que parece necessário.
- `native-host/install.sh` (macOS) / `install.ps1` (Windows) — instalam
  `yt-dlp`/`ffmpeg`/`deno`, resolvem caminhos absolutos, geram o wrapper
  (`run_host.sh`/`run_host.bat`) e registram o host no Chrome.
- `native-host/com.baixaai.host.json.template` — manifesto do native
  messaging host (mesmo formato nos dois SOs; só o mecanismo de registro
  muda — pasta fixa no macOS, Registro do Windows no Windows).

## Decisões de design (e por quê)

1. **Processo worker totalmente desacoplado do Chrome.**
   O Chrome (Manifest V3) pode encerrar o service worker da extensão a
   qualquer momento por inatividade — e isso mata a conexão de native
   messaging junto, mesmo no meio de um download longo. Por isso
   `baixaai_host.py`, ao receber um pedido de download, só dispara um
   **subprocesso separado** (`--worker <job_id> <url> <fitMode>`, com
   `start_new_session=True` no macOS/Linux ou
   `CREATE_NEW_PROCESS_GROUP | DETACHED_PROCESS` no Windows) e responde
   `"started"` na hora. O trabalho pesado roda imune ao Chrome.

2. **`paths.json` com caminhos absolutos resolvidos na instalação.**
   O Chrome inicia o host nativo sem o PATH de um shell interativo — não
   carrega `.zshrc`/conda/Homebrew. Sem isso, `yt-dlp`/`ffmpeg`/`deno`
   simplesmente não são encontrados. O instalador resolve os caminhos reais
   (`command -v` / `Get-Command`) e grava em `paths.json`; o script lê
   dali antes de cair pro PATH normal.

3. **`--ffmpeg-location` e `--js-runtimes deno:<path>` passados
   explicitamente pro yt-dlp.** Mesmo motivo do item 2, mas aplicado
   dentro do próprio yt-dlp — ele faz sua própria busca por binários e não
   sabe do `paths.json`. Sem isso: vídeo e áudio baixam separados e não
   são unidos (sem `--ffmpeg-location`), ou o YouTube só libera imagens em
   vez de vídeo real (sem `--js-runtimes` apontando pro deno).

4. **Prioriza H.264 (avc1) sobre AV1 no seletor de formato do yt-dlp**
   (`-f "bv*[vcodec^=avc1]+ba/b[vcodec^=avc1]/bv*+ba/b"`). Builds mais
   antigas de ffmpeg (comum via conda) não têm decoder de AV1, o que o
   YouTube manda com frequência — resultado sem esse filtro: arquivo final
   de 0 bytes, sem erro óbvio até olhar o log do ffmpeg.

5. **`--no-playlist`.** Sem isso, se a URL da aba tiver `&list=...`
   (comum ao assistir dentro de uma playlist), o yt-dlp baixa a playlist
   inteira em vez do vídeo clicado.

6. **Nome de arquivo final com contador automático (`_2`, `_3`...) se já
   existir.** Títulos genéricos (comum no Instagram, tipo "Video by
   usuario") colidem entre vídeos diferentes; sem checagem, o `ffmpeg -y`
   sobrescreve silenciosamente.

7. **Aviso de conclusão por som (`afplay`/`winsound`), não só notificação
   nativa.** Notificação via `osascript` no macOS depende de permissão
   (modo Foco bloqueia sem avisar nada) e quebra com caracteres não-ASCII
   no texto (travessão "—" já causou erro de sintaxe do AppleScript). Som
   direto não passa pela Central de Notificações e não depende de
   permissão nenhuma.

8. **Retry com/sem cookies do Chrome no yt-dlp.** Primeiro tenta
   `--cookies-from-browser chrome` (necessário pra muito conteúdo do
   Instagram e pra passar do "confirme que você não é um robô" do
   YouTube); se falhar, tenta de novo sem cookies.

9. **Globo entrou na allowlist de download direto sem lógica nova no host
   nativo.** `isDirectDownloadSite()` (`background.js`) agora aceita
   qualquer `host === 'globo.com' || host.endsWith('.globo.com')`. Não
   precisou mexer em `baixaai_host.py` porque ele já roda `yt-dlp` genérico
   sobre qualquer URL — o yt-dlp tem extractor nativo pra Globo
   (`GloboIE`/`GloboArticleIE`) que lê o HTML da página em busca do player
   embutido (`data-video-id`, `data-player-videosids` etc.), então o mesmo
   fluxo de YouTube/Instagram já funciona sem alteração no worker.
   Confirmado com `yt-dlp -j` numa URL AMP do g1.globo.com: o extractor
   `[GloboArticle]` reconheceu a URL (mesmo path com `google/amp/` no
   meio — a regex do extractor não se importa com segmentos extras de
   path). Se uma página AMP específica não expuser a marcação que o
   extractor procura, a versão "normal" da notícia (sem `google/amp/` na
   URL) costuma funcionar.

10. **Versionamento com git direto na pasta `baixaai`, dentro do disco
    externo — mesmo essa pasta bloqueando exclusão/rename de arquivo por
    padrão.** O git precisa criar e apagar arquivos de lock internos
    (`HEAD.lock`, `refs/heads/*.lock`, objetos temporários) a cada
    operação; num volume externo montado neste ambiente, `unlink`/`rename`
    desses arquivos vinha falhando com "Operation not permitted",
    quebrando `git commit`/`git branch -M` etc. Resolvido chamando a
    ferramenta `allow_cowork_file_delete` sobre a pasta (`BaixarVideos`),
    o que libera exclusão de arquivo nela — depois disso, `git init -b
    main` + commit + reset funcionam normalmente ali, sem precisar de
    pasta temporária. Testado de ponta a ponta (commit de teste + reset
    --hard) antes de confirmar como resolvido.

11. **Token do GitHub nunca vai pro repositório — mas fica salvo
    localmente pra não pedir de novo a cada sessão.** Testei primeiro
    `git config credential.helper "store --file=.git-credentials"` (arquivo
    local, listado no `.gitignore`), mas o helper não pegou a credencial
    (`fatal: could not read Username for 'https://github.com'`) — não
    investiguei a fundo o motivo. Solução que funcionou: o token fica
    embutido direto na URL do remote (`git remote set-url origin
    https://<token>@github.com/...`), que é gravada em `.git/config` —
    arquivo de metadados local do git, nunca enviado ao GitHub nem
    versionado (diferente de `CONTEXTO.md`/qualquer arquivo do
    repositório, que vai pro GitHub público). Importante: isso significa
    que o token fica em texto puro em
    `baixaai/.git/config` neste disco — não é um problema de vazamento
    público, mas se algum dia zipar/enviar essa pasta inteira (incluindo
    `.git/`) pra outro lugar, o token vai junto. Se quiser revogar, é em
    https://github.com/settings/tokens. Se o usuário preferir não ter o
    token salvo em lugar nenhum, pode rodar `git push` ele mesmo do
    Terminal do Mac — lá o `git-credential-osxkeychain` (Keychain do
    macOS) guarda a credencial persistentemente depois da
    primeira autenticação.

## Versionamento (Git/GitHub)

- Repositório remoto: https://github.com/eusoumarcusbr/baixaai (público).
- Branch principal: `main`.
- O repositório git vive dentro da própria pasta `baixaai/` no disco
  externo (`/Volumes/SSD_NVME/AgentesIA/BaixarVideos/baixaai`), não numa
  pasta temporária — ver decisão #10 sobre o ajuste de permissão que isso
  exigiu.
- `.gitignore` exclui `native-host/paths.json` (gerado pelo `install.sh`,
  específico de cada máquina), `run_host.sh`/`run_host.bat` (idem), logs
  do host nativo, e lixo de metadados do macOS (`.DS_Store`, `._*`) comum
  em volumes externos/exFAT.
- Fluxo normal pra versionar mudanças novas: `git add -A`, `git commit -m
  "..."`, `git push` — a partir da própria pasta `baixaai`.
- Ver decisão #11 sobre autenticação: sem token salvo em disco por
  padrão.

## Histórico de depuração (problemas já resolvidos)

Nesta ordem, ao longo do desenvolvimento:

1. Extensão não reconhecida em abas já abertas antes de instalar/recarregar
   → corrigido com injeção automática do content script sob demanda.
2. `ffmpeg`/`yt-dlp` não encontrados pelo host nativo → `paths.json`.
3. `python3` do shebang não resolvido pelo Chrome → wrapper com shebang
   fixo (`/bin/bash`) chamando o python3 por caminho absoluto.
4. "Native host has exited" mesmo com tudo certo → pasta da extensão
   estava num volume externo (`/Volumes/...`), o macOS bloqueia o Chrome
   de rodar processos ali; resolvido movendo o `native-host` pra dentro do
   diretório do usuário.
5. Download travava/zerava no meio (MV3 mata o service worker) → worker
   desacoplado (decisão de design #1).
6. Vídeo sem áudio → `--ffmpeg-location` (decisão #3).
7. Notificação do macOS falhando silenciosamente → logging dos erros de
   `osascript`/`afplay` + depois trocado por som (decisão #7); causa raiz
   real era permissão do modo Foco + encoding do travessão.
8. YouTube pedindo "confirme que não é robô" → faltava `deno` (decisão #3).
9. Baixava playlist inteira em vez do vídeo → `--no-playlist` (decisão #5).
10. Arquivo final de 0 bytes → codec AV1 sem decoder no ffmpeg do conda →
    prioriza H.264 (decisão #4).
11. Dois vídeos com nome igual se sobrescrevendo → contador automático
    (decisão #6).
12. Pedido de suporte a vídeos do G1/Globo (ex.: link AMP de notícia) →
    domínio `*.globo.com` adicionado à allowlist de download direto, sem
    mudança no host nativo (decisão #9).
13. `git commit`/`git branch -M` falhando com "Operation not permitted" ao
    tentar versionar a pasta `baixaai` no disco externo → liberada
    exclusão de arquivo na pasta via `allow_cowork_file_delete`, git
    inicializado direto com `-b main` pra evitar rename de branch
    (decisão #10). Push do Cowork pro GitHub deu 403 na primeira tentativa
    → token fine-grained tinha sido gerado sem nenhuma permissão de
    repositório marcada; corrigido adicionando "Contents: Read and write"
    nas permissões do token.

## Estado atual

- **macOS**: testado de ponta a ponta pelo usuário (Marcus), funcionando
  pra YouTube e Instagram, com todos os fixes acima aplicados.
- **Windows**: implementado (`install.ps1`, trechos cross-platform em
  `baixaai_host.py`) mas **ainda não testado em máquina real** — só
  validado sintaticamente. Se for testar, esperar precisar da mesma
  rodada de ajustes que o macOS precisou (caminhos, permissões, etc.).
- **Versionamento**: com backup no GitHub desde 01/08/2026
  (https://github.com/eusoumarcusbr/baixaai, branch `main`). Ver seção
  "Versionamento (Git/GitHub)" acima.

## Estrutura de arquivos

```
baixaai/
  manifest.json          # MV3, key fixo → ID: dflppeifdophmkfncbkkafpfnbnfhajp
  background.js           # ponte popup <-> native messaging
  content.js               # fallback: captura de tela (sites genéricos)
  popup.html / .css / .js  # UI
  icons/
  GUIA_INSTALACAO.md      # guia passo a passo (usuário final)
  CONTEXTO.md              # este arquivo
  README.md
  native-host/
    baixaai_host.py                # host nativo + worker desacoplado
    install.sh                     # instalador macOS
    install.ps1                    # instalador Windows
    com.baixaai.host.json.template # manifesto do native messaging host
```
