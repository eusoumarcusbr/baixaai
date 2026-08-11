// background.js — service worker
// Faz a ponte entre o popup, o content script (fallback de captura de tela)
// e o host nativo `baixaai_host.py`.
//
// Importante: para YouTube/Instagram/Globo/Facebook, o host nativo só
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
      host === 'fb.watch'
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

  return undefined;
});
