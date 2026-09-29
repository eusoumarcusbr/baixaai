// background.js — service worker
// Faz a ponte entre o popup, o content script (fallback de captura de tela)
// e o host nativo `baixaai_host.py`.
//
// Importante: para YouTube/Instagram/Globo/Facebook/TikTok, o host nativo só
// dispara um processo desacoplado (imune ao service worker ser encerrado
// pelo Chrome) e responde "started" na hora — o download em si roda fora
// do Chrome, e o aviso de conclusão chega por notificação nativa do macOS.

const NATIVE_HOST = 'com.baixaai.host';

function isDirectDownloadSite(url) {
  try {
    const u = new URL(url);
    const host = u.hostname.replace(/^www\./, '');
    return (
      host === 'youtube.com' ||
      host === 'youtu.be' ||
      host === 'm.youtube.com' ||
      host === 'instagram.com' ||
      // Qualquer subdomínio *.globo.com (g1, ge, gshow, globoplay,
      // redeglobo, oglobo etc.) — o yt-dlp já tem extractor nativo
      // (GloboIE/GloboArticleIE) que lê o HTML da página em busca do
      // player embutido, então não precisa de tratamento especial aqui,
      // só entrar na mesma allowlist do modo "baixa arquivo original".
      host === 'globo.com' ||
      host.endsWith('.globo.com') ||
      // Facebook (posts, videos, reels, watch, grupos) e o domínio curto
      // fb.watch usado em compartilhamentos — o yt-dlp tem extractors
      // nativos (FacebookIE/FacebookReelIE) pra tudo isso, mesma lógica
      // do Globo: só precisa entrar na allowlist.
      host === 'facebook.com' ||
      host.endsWith('.facebook.com') ||
      host === 'fb.watch' ||
      // TikTok (vídeos, fotos e os links curtos vm./vt.tiktok.com de
      // compartilhamento) — o yt-dlp tem extractor nativo (TikTokIE), então
      // é só entrar na allowlist, igual Globo/Facebook.
      host === 'tiktok.com' ||
      host.endsWith('.tiktok.com')
    );
  } catch (e) {
    return false;
  }
}

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg.type === 'CHECK_SITE') {
    sendResponse({ directDownload: isDirectDownloadSite(msg.url) });
    return true;
  }

  if (msg.type === 'NATIVE_DOWNLOAD') {
    let port;
    try {
      port = chrome.runtime.connectNative(NATIVE_HOST);
    } catch (e) {
      sendResponse({
        ok: false,
        error: 'Ajudante local (BaixaAI Helper) não encontrado. Rode o install.sh primeiro.',
      });
      return true;
    }

    let answered = false;

    port.onMessage.addListener((response) => {
      if (answered) return;
      if (response.type === 'started') {
        answered = true;
        sendResponse({ ok: true, jobId: response.job_id, outputDir: response.output_dir });
        port.disconnect(); // a partir daqui o download roda independente do Chrome
      } else if (response.type === 'error') {
        answered = true;
        sendResponse({ ok: false, error: response.message });
        port.disconnect();
      }
    });

    port.onDisconnect.addListener(() => {
      if (!answered) {
        answered = true;
        const err = chrome.runtime.lastError
          ? chrome.runtime.lastError.message
          : 'Conexão com o ajudante local foi encerrada inesperadamente.';
        sendResponse({
          ok: false,
          error:
            'Não consegui falar com o ajudante local (' + err + '). ' +
            'Confira se o install.sh foi rodado e se o yt-dlp/ffmpeg estão instalados.',
        });
      }
    });

    port.postMessage({
      type: 'download',
      url: msg.url,
      fitMode: msg.fitMode,
    });

    return true; // resposta assíncrona
  }

  if (msg.type === 'GET_STATUS') {
    // Consulta rápida e sem estado: abre uma conexão nova com o ajudante
    // local só pra ele ler o log do job em disco e devolver o progresso —
    // não há conexão viva com o worker desacoplado, então isso é seguro de
    // chamar em polling (ex.: a cada 1.5s enquanto o popup estiver aberto).
    let port;
    try {
      port = chrome.runtime.connectNative(NATIVE_HOST);
    } catch (e) {
      sendResponse({ state: 'unknown' });
      return true;
    }

    let answered = false;

    port.onMessage.addListener((response) => {
      if (answered) return;
      answered = true;
      sendResponse(response);
      port.disconnect();
    });

    port.onDisconnect.addListener(() => {
      if (!answered) {
        answered = true;
        sendResponse({ state: 'unknown' });
      }
    });

    port.postMessage({ type: 'status', job_id: msg.jobId });

    return true; // resposta assíncrona
  }

  return undefined;
});

// ---------------------------------------------------------------------
// TranscrevAI (eusoumarcus.com.br/transcrevai)
// O site transcreve no navegador, mas não consegue baixar YouTube/Instagram
// sozinho. Pelo "externally_connectable" do manifest ele manda mensagens
// direto pra cá; a extensão repassa pro ajudante local (yt-dlp), que baixa só
// o áudio num worker desacoplado (mesma lógica do download de vídeo).
// ---------------------------------------------------------------------

function isTranscrevaiOrigin(origin) {
  try {
    const u = new URL(origin);
    const h = u.hostname;
    if (h === 'localhost' || h === '127.0.0.1') return true;
    return u.protocol === 'https:' && (h === 'eusoumarcus.com.br' || h.endsWith('.eusoumarcus.com.br'));
  } catch (e) {
    return false;
  }
}

// Uma pergunta, uma resposta: abre a conexão nativa, manda a mensagem,
// devolve a primeira resposta e fecha.
function nativeOnce(message, timeoutMs = 30000) {
  return new Promise((resolve, reject) => {
    let port;
    try {
      port = chrome.runtime.connectNative(NATIVE_HOST);
    } catch (e) {
      reject(new Error('Ajudante local (BaixaAI Helper) não encontrado.'));
      return;
    }
    let done = false;
    const timer = setTimeout(() => {
      if (done) return;
      done = true;
      try { port.disconnect(); } catch (e) { /* ok */ }
      reject(new Error('O ajudante local não respondeu a tempo.'));
    }, timeoutMs);
    port.onMessage.addListener((resp) => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      resolve(resp);
      try { port.disconnect(); } catch (e) { /* ok */ }
    });
    port.onDisconnect.addListener(() => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      const err = chrome.runtime.lastError ? chrome.runtime.lastError.message : 'conexão encerrada';
      reject(new Error('Não consegui falar com o ajudante local (' + err + ').'));
    });
    port.postMessage(message);
  });
}

chrome.runtime.onMessageExternal.addListener((msg, sender, sendResponse) => {
  if (!isTranscrevaiOrigin(sender.origin || sender.url || '')) {
    sendResponse({ ok: false, error: 'Origem não autorizada.' });
    return undefined;
  }
  const type = msg && msg.type;
  const version = chrome.runtime.getManifest().version;

  if (type === 'TRANSCREVAI_PING') {
    nativeOnce({ type: 'ping' }, 8000)
      .then((r) => {
        const ok = r && r.type === 'pong' && Array.isArray(r.features) && r.features.includes('audio');
        sendResponse({ ok: true, version, host: ok ? 'ok' : 'outdated', hostVersion: r && r.version });
      })
      .catch((e) => sendResponse({ ok: true, version, host: 'missing', hostError: e.message }));
    return true;
  }

  if (type === 'TRANSCREVAI_AUDIO') {
    if (!/^https?:\/\//.test(String(msg.url || ''))) {
      sendResponse({ ok: false, error: 'Link inválido.' });
      return undefined;
    }
    nativeOnce({ type: 'audio', url: msg.url })
      .then((r) => {
        if (r && r.type === 'started') sendResponse({ ok: true, jobId: r.job_id });
        else sendResponse({ ok: false, error: (r && r.message) || 'Não consegui iniciar o download do áudio.' });
      })
      .catch((e) => sendResponse({ ok: false, error: e.message }));
    return true;
  }

  if (type === 'TRANSCREVAI_STATUS') {
    nativeOnce({ type: 'status', job_id: msg.jobId }, 15000)
      .then((r) => sendResponse(r))
      .catch(() => sendResponse({ state: 'unknown' }));
    return true;
  }

  if (type === 'TRANSCREVAI_READ') {
    nativeOnce({ type: 'read', job_id: msg.jobId, offset: Number(msg.offset) || 0 }, 30000)
      .then((r) => {
        if (r && r.type === 'chunk') {
          sendResponse({ ok: true, data: r.data, offset: r.offset, total: r.total, eof: r.eof, title: r.title, ext: r.ext, mime: r.mime });
        } else {
          sendResponse({ ok: false, error: (r && r.message) || 'Falha ao ler o áudio.' });
        }
      })
      .catch((e) => sendResponse({ ok: false, error: e.message }));
    return true;
  }

  if (type === 'TRANSCREVAI_CLEANUP') {
    nativeOnce({ type: 'cleanup', job_id: msg.jobId }, 10000)
      .then(() => sendResponse({ ok: true }))
      .catch(() => sendResponse({ ok: false }));
    return true;
  }

  sendResponse({ ok: false, error: 'Mensagem desconhecida.' });
  return undefined;
});
