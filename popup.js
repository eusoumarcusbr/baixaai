const statusEl = document.getElementById('status');
const listEl = document.getElementById('video-list');
const btn = document.getElementById('downloadBtn');
const fitModeEl = document.getElementById('fitMode');
const modeLabelEl = document.getElementById('modeLabel');
const hintEl = document.getElementById('hint');
const progressWrap = document.getElementById('progressWrap');
const progressBar = document.getElementById('progressBar');
const progressText = document.getElementById('progressText');

let currentTabId = null;
let currentTabUrl = null;
let selectedIndex = 0;
let directDownloadMode = false;
let pollTimer = null;

// ---------------------------------------------------------------------
// Progresso do download (modo direto YouTube/Instagram/Globo/Facebook).
// O download roda fora do Chrome, então não há "push" de progresso — o
// popup pergunta periodicamente ao ajudante local (que lê o log do job em
// disco) enquanto estiver aberto. O job em andamento fica salvo no
// chrome.storage.local pra sobreviver a fechar/reabrir o popup.
// ---------------------------------------------------------------------

const LAST_JOB_KEY = 'lastJob';
const LAST_JOB_MAX_AGE_MS = 3 * 60 * 60 * 1000; // 3h — depois disso, ignora

function stopPolling() {
  if (pollTimer) {
    clearInterval(pollTimer);
    pollTimer = null;
  }
}

function renderStatus(status) {
  if (!status || status.state === 'unknown') {
    progressWrap.hidden = true;
    progressBar.classList.remove('indeterminate');
    stopPolling();
    return;
  }

  progressWrap.hidden = false;

  if (status.state === 'starting') {
    progressBar.classList.remove('indeterminate');
    progressBar.style.width = '4%';
    progressText.textContent = 'Iniciando (extraindo cookies, abrindo a página)...';
  } else if (status.state === 'downloading') {
    progressBar.classList.remove('indeterminate');
    progressBar.style.width = status.percent + '%';
    progressText.textContent =
      `${status.percent.toFixed(1)}% · ${status.speed} · ETA ${status.eta} · ${status.total}`;
  } else if (status.state === 'processing') {
    progressBar.classList.add('indeterminate');
    progressText.textContent = 'Convertendo para Full HD (ffmpeg)...';
  } else if (status.state === 'done') {
    progressBar.classList.remove('indeterminate');
    progressBar.style.width = '100%';
    progressText.textContent = 'Concluído: ' + status.message;
    stopPolling();
    chrome.storage.local.remove(LAST_JOB_KEY);
  } else if (status.state === 'error') {
    progressBar.classList.remove('indeterminate');
    progressText.textContent = 'Erro: ' + status.message;
    stopPolling();
    chrome.storage.local.remove(LAST_JOB_KEY);
  }
}

function pollStatus(jobId) {
  chrome.runtime.sendMessage({ type: 'GET_STATUS', jobId }, renderStatus);
}

function startPolling(jobId) {
  stopPolling();
  pollStatus(jobId);
  pollTimer = setInterval(() => pollStatus(jobId), 1500);
}

function checkLastJob() {
  chrome.storage.local.get([LAST_JOB_KEY], (res) => {
    const job = res[LAST_JOB_KEY];
    if (!job) return;
    if (Date.now() - job.startedAt > LAST_JOB_MAX_AGE_MS) {
      chrome.storage.local.remove(LAST_JOB_KEY);
      return;
    }
    startPolling(job.jobId);
  });
}

chrome.storage.sync.get(['fitMode'], (res) => {
  if (res.fitMode) fitModeEl.value = res.fitMode;
});
fitModeEl.addEventListener('change', () => {
  chrome.storage.sync.set({ fitMode: fitModeEl.value });
});

function orientationLabel(o) {
  return o === 'horizontal' ? '16:9 horizontal' : '9:16 vertical';
}

// Envia mensagem ao content script; se ele ainda não estiver injetado nesta
// aba (ex.: aba já estava aberta antes da extensão ser instalada/recarregada),
// injeta na hora e tenta de novo uma vez.
function sendToContent(tabId, message) {
  return new Promise((resolve) => {
    chrome.tabs.sendMessage(tabId, message, (response) => {
      if (chrome.runtime.lastError || !response) {
        chrome.scripting.executeScript(
          { target: { tabId }, files: ['content.js'] },
          () => {
            if (chrome.runtime.lastError) {
              resolve(null);
              return;
            }
            chrome.tabs.sendMessage(tabId, message, (response2) => {
              resolve(chrome.runtime.lastError ? null : response2);
            });
          }
        );
      } else {
        resolve(response);
      }
    });
  });
}

async function init() {
  checkLastJob(); // independe da aba atual — um download pode estar rodando em segundo plano

  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  currentTabId = tab.id;
  currentTabUrl = tab.url;

  chrome.runtime.sendMessage({ type: 'CHECK_SITE', url: currentTabUrl }, async (siteResp) => {
    directDownloadMode = !!(siteResp && siteResp.directDownload);

    if (directDownloadMode) {
      modeLabelEl.textContent = 'YouTube/Instagram/Globo/Facebook/TikTok detectado — baixa o arquivo original.';
      statusEl.textContent = 'Pronto para baixar o vídeo desta página.';
      btn.textContent = 'Baixar arquivo original';
      btn.disabled = false;
      hintEl.textContent =
        'O download roda em segundo plano, fora do Chrome — pode fechar este ' +
        'popup logo depois de clicar. Uma notificação do macOS avisa quando ' +
        'terminar (o arquivo não é uma gravação de tela, é o vídeo original).';
      return;
    }

    modeLabelEl.textContent = 'Site genérico — grava a tela em tempo real.';
    hintEl.textContent =
      'A gravação dura o mesmo tempo do vídeo. Você pode fechar este popup ' +
      'depois de clicar — a aba continua gravando sozinha.';
    statusEl.textContent = 'Buscando vídeos na página...';
    const response = await sendToContent(currentTabId, { type: 'LIST_VIDEOS' });

    if (!response) {
      statusEl.textContent =
        'Não encontrei vídeo nesta aba. Recarregue a página e tente de novo.';
      return;
    }

    const videos = response.videos || [];
    if (videos.length === 0) {
      statusEl.textContent = 'Nenhum vídeo encontrado nesta página.';
      return;
    }

    statusEl.textContent = `${videos.length} vídeo(s) encontrado(s):`;
    listEl.innerHTML = '';
    videos.forEach((v, i) => {
      const label = document.createElement('label');
      label.className = 'video-option';
      label.innerHTML = `
        <input type="radio" name="video" value="${i}" ${i === 0 ? 'checked' : ''}>
        ${v.width}×${v.height} · ${orientationLabel(v.orientation)} · ${Math.round(v.duration)}s
      `;
      listEl.appendChild(label);
    });
    listEl.querySelectorAll('input[name="video"]').forEach((input) => {
      input.addEventListener('change', (e) => {
        selectedIndex = Number(e.target.value);
      });
    });

    btn.textContent = 'Baixar em Full HD';
    btn.disabled = false;
  });
}

chrome.runtime.onMessage.addListener((msg) => {
  if (msg.type === 'DOWNLOAD_PROGRESS') {
    statusEl.textContent = msg.text;
  }
});

btn.addEventListener('click', () => {
  btn.disabled = true;
  const originalLabel = btn.textContent;
  btn.textContent = directDownloadMode ? 'Baixando...' : 'Gravando...';

  if (directDownloadMode) {
    statusEl.textContent = 'Conectando ao ajudante local...';
    chrome.runtime.sendMessage(
      { type: 'NATIVE_DOWNLOAD', url: currentTabUrl, fitMode: fitModeEl.value },
      (response) => {
        if (response && response.ok) {
          statusEl.textContent =
            'Baixando em segundo plano — pode fechar este popup. ' +
            'Uma notificação avisa quando terminar (arquivo em ' +
            response.outputDir + '). Acompanhe o progresso abaixo:';
          btn.disabled = false;
          btn.textContent = 'Iniciado ✔ (baixar de novo)';
          chrome.storage.local.set({
            lastJob: { jobId: response.jobId, outputDir: response.outputDir, startedAt: Date.now() },
          });
          startPolling(response.jobId);
        } else {
          statusEl.textContent = 'Erro: ' + (response ? response.error : 'desconhecido');
          btn.disabled = false;
          btn.textContent = originalLabel;
        }
      }
    );
    return;
  }

  statusEl.textContent = 'Gravando — acompanhe o indicador na própria página.';
  sendToContent(currentTabId, {
    type: 'START_CAPTURE',
    videoIndex: selectedIndex,
    fitMode: fitModeEl.value,
  }).then((response) => {
    if (response && response.ok) {
      statusEl.textContent = 'Download concluído!';
    } else {
      statusEl.textContent = 'Erro: ' + (response ? response.error : 'desconhecido');
    }
    btn.disabled = false;
    btn.textContent = originalLabel;
  });
});

init();
