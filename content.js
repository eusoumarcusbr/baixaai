// content.js — roda no contexto da página
// Responsável por: (1) listar vídeos presentes na página, (2) capturar o vídeo
// selecionado desenhando cada frame num canvas em Full HD (letterbox/crop) e
// (3) gravar com MediaRecorder, disparando o download via <a download>.

(function () {
  const BADGE_ID = '__vgfhd_badge__';

  function getVideos() {
    return Array.from(document.querySelectorAll('video')).filter(
      (v) => v.videoWidth > 0 && v.videoHeight > 0
    );
  }

  function describeVideo(v) {
    const w = v.videoWidth;
    const h = v.videoHeight;
    return {
      width: w,
      height: h,
      duration: Number.isFinite(v.duration) ? v.duration : 0,
      orientation: w >= h ? 'horizontal' : 'vertical',
    };
  }

  function showBadge(text) {
    let badge = document.getElementById(BADGE_ID);
    if (!badge) {
      badge = document.createElement('div');
      badge.id = BADGE_ID;
      Object.assign(badge.style, {
        position: 'fixed',
        bottom: '16px',
        right: '16px',
        zIndex: 2147483647,
        background: 'rgba(20,20,20,0.88)',
        color: '#fff',
        padding: '10px 16px',
        borderRadius: '10px',
        font: '13px/1.4 -apple-system, system-ui, sans-serif',
        pointerEvents: 'none',
        boxShadow: '0 4px 16px rgba(0,0,0,0.35)',
      });
      document.documentElement.appendChild(badge);
    }
    badge.textContent = text;
  }

  function removeBadge() {
    const badge = document.getElementById(BADGE_ID);
    if (badge) badge.remove();
  }

  async function startCapture(videoIndex, fitMode) {
    const videos = getVideos();
    const video = videos[videoIndex];
    if (!video) throw new Error('Vídeo não encontrado nesta página.');

    const vw = video.videoWidth;
    const vh = video.videoHeight;
    const horizontal = vw >= vh;
    const targetW = horizontal ? 1920 : 1080;
    const targetH = horizontal ? 1080 : 1920;

    const canvas = document.createElement('canvas');
    canvas.width = targetW;
    canvas.height = targetH;
    const ctx = canvas.getContext('2d');

    // Tenta capturar a trilha de áudio original do vídeo (se existir)
    let audioTracks = [];
    try {
      const rawStream = video.captureStream
        ? video.captureStream()
        : video.mozCaptureStream();
      audioTracks = rawStream.getAudioTracks();
    } catch (e) {
      audioTracks = [];
    }

    const canvasStream = canvas.captureStream(30);
    const outputStream = new MediaStream([
      ...canvasStream.getVideoTracks(),
      ...audioTracks,
    ]);

    let recorder;
    try {
      recorder = new MediaRecorder(outputStream, {
        mimeType: 'video/webm;codecs=vp9,opus',
      });
    } catch (e) {
      recorder = new MediaRecorder(outputStream);
    }

    const chunks = [];
    recorder.ondataavailable = (e) => {
      if (e.data && e.data.size > 0) chunks.push(e.data);
    };

    const recordingFinished = new Promise((resolve, reject) => {
      recorder.onstop = resolve;
      recorder.onerror = (e) => reject(e.error || new Error('Erro na gravação.'));
    });

    let rafId;
    function drawFrame() {
      const scale =
        fitMode === 'cover'
          ? Math.max(targetW / vw, targetH / vh)
          : Math.min(targetW / vw, targetH / vh);
      const dw = vw * scale;
      const dh = vh * scale;
      const dx = (targetW - dw) / 2;
      const dy = (targetH - dh) / 2;
      ctx.fillStyle = '#000';
      ctx.fillRect(0, 0, targetW, targetH);
      ctx.drawImage(video, dx, dy, dw, dh);
      rafId = requestAnimationFrame(drawFrame);
    }

    const wasMuted = video.muted;
    video.muted = false;
    try {
      video.currentTime = 0;
    } catch (e) {
      /* alguns players não permitem resetar currentTime; segue do ponto atual */
    }
    await video.play().catch(() => {
      /* autoplay pode ser bloqueado; se o vídeo já estiver tocando, ok */
    });

    drawFrame();
    recorder.start(250);
    showBadge('Gravando vídeo... 0%');

    const progressTimer = setInterval(() => {
      if (video.duration) {
        const pct = Math.min(
          100,
          Math.round((video.currentTime / video.duration) * 100)
        );
        showBadge(`Gravando vídeo... ${pct}%`);
      }
    }, 500);

    await new Promise((resolve) => {
      video.addEventListener('ended', resolve, { once: true });
    });

    cancelAnimationFrame(rafId);
    clearInterval(progressTimer);
    recorder.stop();
    video.muted = wasMuted;

    await recordingFinished;

    const blob = new Blob(chunks, { type: 'video/webm' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `video_${horizontal ? '16x9' : '9x16'}_fullhd_${Date.now()}.webm`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 10000);

    showBadge('Download iniciado ✔');
    setTimeout(removeBadge, 3000);
  }

  chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
    if (msg.type === 'LIST_VIDEOS') {
      sendResponse({ videos: getVideos().map(describeVideo) });
      return true;
    }
    if (msg.type === 'START_CAPTURE') {
      startCapture(msg.videoIndex, msg.fitMode)
        .then(() => sendResponse({ ok: true }))
        .catch((err) => {
          removeBadge();
          sendResponse({ ok: false, error: err.message });
        });
      return true; // resposta assíncrona
    }
    return undefined;
  });
})();
