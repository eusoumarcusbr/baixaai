# BaixaAI — Contexto do projeto

Documento de referência técnica sobre a extensão BaixaAI: o que é, como
está construída, por que cada decisão foi tomada, e o histórico de
problemas já resolvidos. Serve pra retomar o desenvolvimento sem precisar
redescobrir tudo de novo.

## O que é

Extensão de Chrome (uso pessoal) com dois modos, escolhidos automaticamente
pela URL da aba ativa:

- **YouTube / Instagram / Globo / Facebook** (`*.globo.com`: g1, ge, gshow,
  globoplay, oglobo, redeglobo etc.; `facebook.com`/`fb.watch`, incluindo
  reels) → baixa o arquivo de vídeo original de verdade (via `yt-dlp` +
  `ffmpeg` rodando fora do Chrome), normalizado pra Full HD: 1920×1080
  (16:9) horizontal ou 1080×1920 (9:16) vertical.
- **Qualquer outro site** → grava a tela em tempo real (canvas +
  MediaRecorder), já que não dá pra extrair o arquivo original de forma
  confiável em sites genéricos.

## ⚠️ Três pastas diferentes no macOS do Marcus — não esquecer

Existem **três cópias** do projeto no Mac do usuário, e elas NÃO se
atualizam sozinhas umas pelas outras:

1. **`/Volumes/SSD_NVME/AgentesIA/BaixarVideos/baixaai/`** — a pasta
   versionada, ligada ao git/GitHub. É nela que eu (Claude) edito o código
   por padrão nas conversas, e é a fonte de verdade pra tudo.
2. **`~/Desktop/AgentesIA/baixaai/`** — cópia manual que o usuário mantém
   pra não depender do SSD estar conectado. É **esta pasta que o Chrome usa
   de fato como "Carregar sem compactação"** (a extensão em si —
   `manifest.json`, `background.js`, `popup.*`, `content.js`, `icons/`).
   O usuário copia manualmente do SSD pra cá quando quer atualizar.
3. **`~/baixaai-native-host/`** (`/Users/eusoumarcus/baixaai-native-host/`)
   — pasta separada que contém **só o `native-host/`** (o ajudante nativo:
   `baixaai_host.py`, `run_host.sh`, `paths.json`, o manifesto do Chrome).
   Existe porque o `native-host` **não pode viver dentro do Desktop** (nem
   Documents/Downloads) — ver decisão #17 (proteção TCC do macOS bloqueia
   silenciosamente o `bash` de ler arquivos ali, mesmo com o Chrome tendo
   Acesso Total ao Disco). O manifesto registrado no Chrome
   (`~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.baixaai.host.json`)
   aponta pro `run_host.sh` **desta** pasta, não da Desktop nem do SSD.

**Resumindo o fluxo real:** a extensão (JS/HTML/CSS) carrega da pasta 2
(Desktop); o ajudante nativo (Python) roda a partir da pasta 3
(`~/baixaai-native-host`). As duas pastas ficam desatualizadas em relação
à pasta 1 (SSD) até alguém copiar manualmente — **toda mudança em
qualquer arquivo do projeto precisa ser copiada nas três pastas**. Já
aconteceu de várias correções (Windows, Facebook, fix do YouTube/EJS, fix
da notificação, fix do AV1) ficarem só na pasta versionada por semanas sem
chegar nas pastas que o Chrome usa de verdade — isso é o que causou o
download parar de funcionar sem nenhuma mudança óbvia de causa (ver
histórico #17, #19). Sempre confirmar com `diff` entre as três cópias
depois de qualquer alteração.

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

12. **Suporte a Windows implementado de verdade (antes só estava
    documentado, não existia).** Descoberto ao revisar o projeto pra
    montar um guia de instalação: o `install.ps1` citado no `README.md`/
    `CONTEXTO.md` não existia, e `baixaai_host.py` não tinha nenhum código
    específico de Windows (a notificação e o som eram só `osascript`/
    `afplay`, que quebrariam em qualquer máquina Windows). Implementado:
    - `native-host/install.ps1`: confere/instala Python, `yt-dlp` (pip
      `--user`), `ffmpeg` e `deno` via `winget` (IDs confirmados:
      `Gyan.FFmpeg`, `DenoLand.Deno`), grava `paths.json`, gera
      `run_host.bat` (wrapper, já que o Chrome não roda `.py` direto no
      Windows) e registra o native messaging host em
      `HKCU\Software\Google\Chrome\NativeMessagingHosts\com.baixaai.host`
      (no Windows não existe uma pasta fixa como no macOS — é sempre via
      Registro).
    - `baixaai_host.py`: `notify_mac`/`play_sound` viraram dispatchers
      cross-platform (`notify()`/`play_sound()`) que checam `sys.platform`.
      Windows usa `winsound.PlaySound` (builtin do Python, sem dependência
      externa) pro som, e um toast nativo via PowerShell/WinRT
      (best-effort, mesma filosofia da decisão #7: se a notificação
      falhar, o som ainda avisa). As flags de processo desacoplado também
      viraram condicionais: `CREATE_NEW_PROCESS_GROUP | DETACHED_PROCESS`
      no Windows, `start_new_session=True` no POSIX.
    - **Não testado numa máquina Windows real** (só revisado com cuidado,
      sem ambiente Windows disponível pra rodar de ponta a ponta) — ao
      contrário do macOS, que foi validado pelo usuário de verdade. Tratar
      como implementação séria mas não comprovada.

13. **Facebook entrou na allowlist de download direto do mesmo jeito que o
    Globo — sem lógica nova no host nativo.** `isDirectDownloadSite()`
    (`background.js`) agora aceita `facebook.com`, qualquer
    `*.facebook.com` e o domínio curto `fb.watch` (usado em
    compartilhamentos de reels). O yt-dlp já tem extractors nativos
    (`FacebookIE`, `FacebookReelIE`, `FacebookPluginsVideoIE`) que cobrem
    posts, `/videos/`, `/watch`, `/reel/`, grupos e o domínio onion — não
    precisou mexer em `baixaai_host.py`, mesmo raciocínio da decisão #9.
    Confirmado com `yt-dlp -j` numa URL `facebook.com/watch/?v=...`: o
    extractor `[facebook]` reconheceu a URL (só não completou a extração
    porque o proxy do sandbox bloqueia facebook.com — mesma limitação já
    vista com o Globo, não é um problema do código). Muito conteúdo do
    Facebook exige login — a mesma lógica de retry com/sem cookies do
    Chrome (decisão #8) já cobre isso, sem precisar de nada extra.

14. **yt-dlp precisa do extra `[default]` (pacote `yt-dlp-ejs`), não só
    `--upgrade`.** O YouTube trocou o mecanismo de resolução de desafio JS
    de "JSInterp/PhantomJS" (e do esquema antigo baseado só em rodar
    `deno` com `--js-runtimes`) pro **EJS** (External JS Scripts, ver
    https://github.com/yt-dlp/yt-dlp/wiki/EJS). O `deno` continua sendo o
    runtime que executa os scripts, mas os scripts em si (pacote
    `yt-dlp-ejs`) só vêm junto se o yt-dlp for instalado via
    `pip install "yt-dlp[default]"` — um `pip install --upgrade yt-dlp`
    normal NÃO inclui esse pacote. Sem ele, o log mostra "Remote
    components challenge solver script (deno) ... were skipped", o
    YouTube só libera formatos de imagem, e mesmo quando cai num client
    alternativo (ex.: `android vr`) que não precisa do desafio, a URL
    resultante costuma dar `HTTP Error 403: Forbidden` no meio do
    download. `install.sh`/`install.ps1` foram ajustados pra sempre rodar
    o upgrade com `[default]`, mesmo se o yt-dlp já estiver instalado
    (antes, o script só instalava se `command -v yt-dlp` desse vazio —
    instalações já existentes nunca ganhavam o extra novo até rodar o
    install de novo manualmente).

15. **`json.dumps` sem `ensure_ascii=False` quebra o `display notification`
    do AppleScript.** Native da decisão #7 (som > notificação), mas o bug
    de fundo nunca tinha sido isolado: o padrão do `json.dumps` escreve
    acentos como `\uXXXX` (ex.: "não" vira `não`), e o AppleScript não
    reconhece `\u` como escape válido dentro de um literal de string —
    resultado: "syntax error: Esperava-se '"', encontrou-se token
    desconhecido", a notificação falha, e sobra só o som pra avisar (que
    funciona, mas sem nenhum texto legível do que deu errado). Corrigido
    passando `ensure_ascii=False` nos dois `json.dumps` do `notify_mac`, e
    colapsando quebras de linha da mensagem antes (evita jogar um log
    multi-linha cru do yt-dlp dentro do `-e` do osascript). Mesma classe
    de bug corrigida preventivamente no `notify_windows`: título/mensagem
    agora passam por um escape de XML (`&`, `<`, `>`, `"`, `'`) antes de
    entrar no `LoadXml`, já que aquele código ainda não tinha sido
    validado numa máquina Windows real.

16. **Barra de progresso no popup lendo o log do job, sem conexão viva com
    o worker.** O worker do download roda totalmente desacoplado do Chrome
    (decisão #1) — quando ele termina de responder "started", a porta de
    native messaging é fechada (`port.disconnect()` em `background.js`) e
    não há mais nenhum canal pra empurrar progresso em tempo real. Em vez
    de reabrir uma conexão persistente (o que reintroduziria o problema
    original do service worker do MV3 poder ser encerrado pelo Chrome no
    meio do caminho), o popup faz *polling*: a cada 1.5s, manda uma
    mensagem nova e curta (`{"type": "status", "job_id": ...}`) pro host
    nativo, que abre o log do job (`~/Downloads/BaixaAI/.logs/<job_id>.log`
    — o mesmo arquivo que o worker já escreve) e devolve o estado mais
    recente (parseando a última linha `[download] X% of Y at Z ETA W` que
    o yt-dlp já imprime com `--newline`). Como o job_id fica salvo em
    `chrome.storage.local`, fechar e reabrir o popup não perde o progresso
    — ele volta a consultar o mesmo job. Estados possíveis: `starting`
    (ainda extraindo cookies/resolvendo a página), `downloading` (com %,
    velocidade, ETA e tamanho total), `processing` (fase do ffmpeg, sem %
    disponível, barra fica com animação indeterminada), `done` e `error`
    (lidos das linhas `[BaixaAI] concluído: ...` / `[BaixaAI] ERRO: ...`
    que o worker já grava).

17. **`native-host/` não pode viver dentro de `~/Desktop` (nem
    `Documents`/`Downloads`) — proteção TCC do macOS bloqueia o `bash`
    silenciosamente.** Depois da barra de progresso (decisão #16), o
    ajudante nativo passou a rodar de dentro de `~/Desktop/AgentesIA/
    baixaai/native-host/` (o usuário reinstalou o `install.sh` a partir de
    lá) e todo download passou a falhar com "Native host has exited.".
    Diagnóstico levou horas: manifesto do Chrome válido, ID da extensão
    batendo, sem política de enterprise, sem processo zumbi, Acesso Total
    ao Disco concedido ao Google Chrome (sem efeito) — e um teste com
    injeção de trace (`echo ... >> /tmp/trace.log` como primeira linha do
    `run_host.sh`) provou que o Chrome **nunca chega a executar o
    processo**, nem com um host mínimo novo criado do zero só pra
    descartar bug de código. A causa real apareceu no log do kernel
    (`log stream --predicate 'subsystem == "com.apple.TCC" OR eventMessage
    CONTAINS "Sandbox"'`):
    ```
    sandboxd rejected approval request from bash for
    kTCCServiceSystemPolicyDesktopFolder (.../baixaai/native-host):
    would require prompt
    System Policy: bash(PID) deny(1) file-read-data .../native-host/run_host.sh
    ```
    O Desktop é uma pasta protegida (TCC) no macOS, e binários de sistema
    como `/bin/bash` são "platform binaries" — eles **nunca podem disparar
    um prompt de permissão** pra pastas protegidas, então o pedido é
    negado direto, sem diálogo nenhum. Dar Acesso Total ao Disco pro
    **Google Chrome** não resolve, porque quem está pedindo acesso ao
    arquivo não é o processo Chrome, é o `bash` que ele manda rodar (via
    shebang do `run_host.sh`) — cada binário tem sua própria identidade
    TCC. **Fix:** o `native-host/` (com `baixaai_host.py`, `run_host.sh`,
    `paths.json` e o manifesto do Chrome apontando pra lá) precisa ficar
    fora de Desktop/Documents/Downloads — voltou a usar
    `~/baixaai-native-host/native-host/` (fora de qualquer pasta
    protegida), reexecutando `install.sh` de lá. A extensão em si
    (`manifest.json`/`background.js`/`popup.*`) pode continuar carregando
    do Desktop sem problema, porque quem lê esses arquivos é o próprio
    processo Chrome (que já tem Acesso Total ao Disco), não um binário de
    sistema spawnado — só o `native-host` é afetado, por passar por
    `bash`/`python3` como processo filho. Ver aviso atualizado no topo do
    documento (agora "três pastas", não duas).

18. **`install.sh` agora prefere o ffmpeg do Homebrew (com decoder AV1) em
    vez do primeiro `ffmpeg` do PATH.** Um Reels do Facebook baixou em
    AV1 (`av01`), e o ffmpeg resolvido pelo `paths.json` (o do conda,
    `/opt/anaconda3/bin/ffmpeg` 4.3.2, de 2022) não tem o decoder — a
    normalização pra Full HD falhava com "Decoder (codec av1) not found"
    (o seletor de formato da decisão #4 já prioriza avc1/H.264, mas cai
    pra AV1 quando a plataforma só oferece esse codec pro vídeo em
    questão, o que Facebook/TikTok fazem com alguma frequência). Instalado
    Homebrew + `brew install ffmpeg` (que traz `libdav1d` como
    dependência) e `paths.json` das três pastas repontado pra
    `/opt/homebrew/bin/ffmpeg`. Pra essa correção não regredir numa
    próxima vez que `install.sh` rodar (ele normalmente pega o primeiro
    `ffmpeg` do PATH, que continua sendo o do conda em terminais com
    `(base)` ativo), o script agora: prefere explicitamente
    `/opt/homebrew/bin/ffmpeg`/`/usr/local/bin/ffmpeg` sobre `command -v
    ffmpeg`; se só achar um ffmpeg sem decoder de AV1 (`ffmpeg -decoders |
    grep -i av1` vazio), reinstala via Homebrew automaticamente.

19. **TikTok entrou na allowlist de download direto do mesmo jeito que
    Globo/Facebook — sem lógica nova no host nativo.**
    `isDirectDownloadSite()` (`background.js`) agora aceita `tiktok.com` e
    qualquer `*.tiktok.com` (cobre os links curtos `vm.`/`vt.tiktok.com`
    de compartilhamento). O yt-dlp já tem extractor nativo (`TikTokIE`),
    mesmo raciocínio das decisões #9 e #13 — não precisou mexer em
    `baixaai_host.py`. Vídeos do TikTok também podem vir em AV1, então
    depende do fix da decisão #18 pra normalizar sem erro.

20. **Integração com o TranscrevAI (v2.6.0): a extensão entrega o áudio
    de links pro site de transcrição.** O TranscrevAI
    (`https://eusoumarcus.com.br/transcrevai/`) transcreve 100% no
    navegador (Whisper via WebGPU), mas não consegue baixar YouTube/
    Instagram sozinho (CORS e bloqueio de servidores). Solução:
    - `manifest.json` ganhou `externally_connectable` para
      `eusoumarcus.com.br` (e `localhost`/`127.0.0.1` pra testes). Com
      isso a página chama `chrome.runtime.sendMessage(ID_DA_EXTENSAO, ...)`
      direto, sem content script. O ID fixo (campo `key`) é o que torna
      isso possível no Mac e no Windows.
    - `background.js`: `onMessageExternal` confere a origem e repassa pro
      host nativo as mensagens `TRANSCREVAI_PING`, `_AUDIO`, `_STATUS`,
      `_READ` e `_CLEANUP` (uma conexão nativa curta por mensagem, mesma
      filosofia da decisão #16).
    - `baixaai_host.py`: novos tipos `ping` (responde `pong` com
      `features: ["audio"]`; host antigo responde "Mensagem desconhecida",
      e o site mostra "atualize o ajudante"), `audio` (worker desacoplado
      `--audio-worker`: `yt-dlp -f "ba/b"` + ffmpeg para Opus mono 16 kHz,
      ~15 MB por hora, com fallback AAC .m4a se faltar libopus), `read`
      (pedaços de 700 KB em base64, porque native messaging limita cada
      mensagem host→Chrome a 1 MB) e `cleanup`. O áudio fica em
      `~/Downloads/BaixaAI/.transcrevai/` só até o site terminar de ler;
      sobras com mais de 6 h são apagadas no próximo pedido.
    - `popup`: em sites de download direto aparece o botão "Transcrever no
      TranscrevAI", que abre o site com `?url=<link da aba>`.
    - Testado de ponta a ponta num Chromium com a extensão carregada e o
      host registrado (página → extensão → host → yt-dlp → ffmpeg →
      pedaços → página), com arquivo de 20 min em 6 pedaços. Falta validar
      no Chrome do Mac com YouTube/Instagram reais.

21. **`install.sh` agora instala o Homebrew sozinho e prefere um Python
    moderno, em vez de depender do que já estiver no Mac.** Motivado pela
    primeira instalação de verdade num Mac de terceiro (Maria, machine
    `MacBook-Pro-2`), que expôs três problemas em cadeia que o `install.sh`
    de antes não tratava:
    - **TCC bloqueia `bash` também em `~/Downloads`, não só `~/Desktop`**
      (a decisão #17 só tinha confirmado Desktop). Mesmo erro "Native host
      has exited.", mesma causa (proteção de pasta do macOS negando
      silenciosamente o `bash` sem mostrar prompt nenhum), resolvido do
      mesmo jeito: mover o `native-host` pra fora de
      Desktop/Documents/Downloads.
    - **`error: externally-managed-environment` (PEP 668)** ao rodar
      `pip3 install --user` num Python instalado via Homebrew — precisa da
      flag `--break-system-packages` junto com `--user` (é a própria
      mensagem de erro do pip que recomenda essa combinação). Sem isso o
      script parava ali (`set -e`) antes até de chegar no ffmpeg/deno.
    - **Python do sistema (3.9, do Xcode Command Line Tools) capado numa
      versão antiga do yt-dlp.** yt-dlp releases recentes deixaram de dar
      suporte a Python tão antigo, então `pip3 install --upgrade
      "yt-dlp[default]"` nesse Python instala silenciosamente a última
      versão AINDA compatível com 3.9 (~1 ano desatualizada) — sem erro
      nenhum na hora, só quando o download real roda: `yt-dlp: error: no
      such option: --js-runtimes`, porque essa opção só existe em versões
      mais novas. Piorou por causa de um segundo bug: depois de instalar
      Python 3.13 via Homebrew e reinstalar o yt-dlp com ele, o
      `install.sh` antigo (`YTDLP_PATH="$(command -v yt-dlp)"`) continuava
      achando o yt-dlp VELHO do Python 3.9, porque a pasta de scripts do
      3.9 vinha antes da do 3.13 no PATH (instalada nesse Mac por algum
      mecanismo anterior, provavelmente o instalador oficial do
      python.org). Resultado: parecia que a reinstalação "não tinha
      funcionado".
    - **Fix, em ordem, tudo dentro do próprio `install.sh` agora:**
      (1) instala o Homebrew automaticamente se não existir
      (`NONINTERACTIVE=1`, só pede a senha do Mac uma vez, no sudo);
      (2) resolve um `python3` preferindo `/opt/homebrew/bin/python3` ou
      `/usr/local/bin/python3` (instala via `brew install python3` se
      nenhum existir) em vez de `command -v python3`, que pegaria o do
      sistema; (3) usa essa MESMA variável `$PYTHON3_PATH` do início ao
      fim do script — pra instalar o yt-dlp, pra resolver o caminho final
      do yt-dlp instalado (via `site.getuserbase()`, não `command -v`, o
      que elimina o bug do PATH com Python velho na frente) e pra gerar o
      `run_host.sh`; (4) adiciona `--break-system-packages` ao
      `pip install`, com fallback pro comando antigo se a flag não for
      reconhecida (Python mais antigo sem PEP 668). O README também ganhou
      avisos sobre o prompt de instalação das Command Line Tools do Xcode,
      que pode aparecer na primeira vez que qualquer comando de
      desenvolvedor roda num Mac novo (não é bug do BaixaAI, é do macOS).

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
   diretório do usuário, em `~/baixaai-native-host/` (caminho exato
   redescoberto no histórico #17 — ver aviso no topo do documento sobre as
   duas pastas).
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
14. Usuário pediu pra compartilhar a extensão com um amigo no Windows →
    ao investigar pra fazer o guia de instalação, descoberto que o suporte
    a Windows documentado nunca existiu de fato (decisão #12). Implementado
    de verdade antes de gerar qualquer guia pra não distribuir algo
    quebrado.
15. Pedido de suporte a vídeos do Facebook → domínios `facebook.com`,
    `*.facebook.com` e `fb.watch` adicionados à allowlist de download
    direto, sem mudança no host nativo (decisão #13).
16. YouTube parou de baixar (usuário reportou "só o som de erro", sem
    nenhuma notificação visível) → log mostrou "Only images are available"
    seguido de `HTTP Error 403: Forbidden` → causa raiz era o pacote
    `yt-dlp-ejs` faltando (decisão #14), `install.sh`/`install.ps1`
    corrigidos pra sempre reinstalar com `[default]`. De brinde, achado e
    corrigido o motivo de nenhuma notificação aparecer: `json.dumps` sem
    `ensure_ascii=False` gerando `\uXXXX` que o AppleScript não entende
    (decisão #15) — o usuário precisa rodar `install.sh` de novo pra
    aplicar o fix do yt-dlp-ejs (isso não dá pra fazer remotamente, o
    script roda no Mac dele).
17. Ao tentar aplicar o fix acima, o usuário rodou `install.sh` no caminho
    que eu sugeri (`~/Documents/baixaai-main/native-host`) e deu
    "No such file or directory" — esse caminho nunca existiu de verdade,
    era só um placeholder do guia de instalação genérico. Descoberto o
    caminho real lendo o manifesto já registrado no Chrome (`cat
    ~/Library/Application\ Support/Google/Chrome/NativeMessagingHosts/com.baixaai.host.json`),
    que apontava pra `~/baixaai-native-host/run_host.sh`. Comparando essa
    pasta com a versionada no SSD, ela estava parada em 13/jul — sem
    NENHUMA correção feita depois disso (Windows, Facebook, fix do
    YouTube/EJS, fix da notificação). Copiados `baixaai_host.py` e
    `install.sh` corrigidos pra lá. Ver aviso no topo do documento — essa
    divergência entre as duas pastas provavelmente é a causa real por
    trás de vários "parou de funcionar do nada" ao longo do projeto.
18. Depois do fix do YouTube, usuário testou e achou que "não tinha
    acontecido nada" ao clicar em baixar — na real o download estava
    rodando normalmente (confirmado lendo o log em tempo real, já em
    ~90%), só que um vídeo de 655 MB demora minutos e o popup não mostra
    nenhum progresso. Pedido de feedback visual → implementada barra de
    progresso por polling no log (decisão #16). Precisa recarregar a
    extensão em `chrome://extensions` pra pegar essa mudança (mexeu em
    `background.js`/`popup.js`/`popup.html`/`popup.css`, não só no host
    nativo) — não precisa rodar `install.sh` de novo (nenhuma dependência
    nova).
19. Depois de reinstalar o `native-host` a partir de dentro de
    `~/Desktop/AgentesIA/baixaai/` (achando que resolveria o "não
    encontrado" do item anterior), todo download passou a falhar com
    "Native host has exited." — causa raiz era a proteção TCC do Desktop
    bloqueando o `bash` (decisão #17). Resolvido apontando o `native-host`
    de volta pra `~/baixaai-native-host/` (fora do Desktop).
20. Facebook Reels específico deu "Erro: ffmpeg falhou ao normalizar o
    vídeo para Full HD." — vídeo tinha vindo em AV1 e o ffmpeg do conda
    não decodifica esse codec. Resolvido instalando ffmpeg via Homebrew
    (traz `libdav1d`) e apontando `paths.json` das três pastas pra lá;
    `install.sh` também foi endurecido pra não regredir nisso de novo
    (decisão #18).
21. Pedido de suporte a vídeos do TikTok → domínio `tiktok.com` e
    `*.tiktok.com` adicionados à allowlist de download direto, sem
    mudança no host nativo (decisão #19).

22. Pedido de integração com o TranscrevAI (ferramenta de transcrição no
    navegador) para transcrever links de YouTube/Instagram → áudio entregue
    pela extensão via `externally_connectable` (decisão #20). Precisa
    recarregar a extensão em `chrome://extensions`; o host nativo novo
    entra em uso sozinho (não há dependência nova, não precisa rodar
    `install.sh`).
23. Primeira instalação de verdade num Mac de terceiro (Maria), guiada
    passo a passo pelo Terminal. Cadeia de problemas, todos novos: zip
    inicial mandado pelo usuário estava cheio de sobras de depuração da
    sessão anterior (resolvido recomendando baixar limpo do GitHub);
    "Specified native messaging host not found" → `install.sh` nunca tinha
    rodado; pasta confundida entre Desktop/Downloads (o comando `find`
    tropeçou num teclado com `~` quebrado — resolvido usando `$HOME` em vez
    de `~`); "Native host has exited" de novo, dessa vez com o
    `native-host` dentro de `~/Downloads` → mesma causa da decisão #17, mas
    confirma que a proteção TCC cobre Downloads também, não só Desktop;
    depois de mover pra fora, veio `error: externally-managed-environment`
    (pip do Homebrew) e depois o yt-dlp instalado ficou preso numa versão
    de quase um ano atrás (Python 3.9 do sistema) com `no such option:
    --js-runtimes` mesmo depois de instalar Python 3.13 via Homebrew,
    porque o `command -v yt-dlp` ainda achava o script do Python velho.
    Todos os quatro problemas de Python/Homebrew motivaram a decisão #21 —
    `install.sh` agora resolve tudo isso sozinho, sem precisar de nenhum
    comando manual extra. Terminou com o Instagram baixando com sucesso no
    Mac dela.

## Estado atual

- **macOS**: testado de ponta a ponta pelo usuário (Marcus), funcionando
  pra YouTube, Instagram, Globo, Facebook e TikTok (v2.5.0), com todos os
  fixes acima aplicados — incluindo o fix do TCC do Desktop (decisão #17)
  e do ffmpeg/AV1 (decisão #18), ambos de 25/08/2026. Popup com barra de
  progresso (decisão #16). Estrutura real: extensão carrega de
  `~/Desktop/AgentesIA/baixaai/`, `native-host` roda de
  `~/baixaai-native-host/native-host/` — ver aviso "três pastas" no topo
  do documento. v2.6.0 (11/09/2026) adiciona a ponte com o TranscrevAI
  (decisão #20). v2.6.2 (29/09/2026): primeira instalação de ponta a ponta
  num Mac de terceiro (Maria), `install.sh` agora instala Homebrew e
  garante Python moderno sozinho (decisão #21, histórico #23).
- **Windows**: implementado de verdade em 03/08/2026 (`install.ps1` +
  notificação/som/flags de processo cross-platform em `baixaai_host.py`,
  decisão #12) — antes disso era só documentação sem código
  correspondente. **Ainda não testado numa máquina Windows real.** Se for
  testar, checar o log em `Downloads/BaixaAI/.logs/` se algo falhar, e
  esperar precisar de mais uma rodada de ajustes (padrão do projeto: cada
  SO novo sempre revela alguma coisa que só aparece rodando de verdade).
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
