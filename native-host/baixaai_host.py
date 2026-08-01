#!/usr/bin/env python3
"""
baixaai_host.py — Native Messaging host da extensão BaixaAI.

Modo normal (chamado pelo Chrome via native messaging):
  Recebe {"type": "download", "url": "...", "fitMode": "contain"|"cover"},
  dispara um processo-filho TOTALMENTE DESACOPLADO do Chrome (própria sessão
  do SO) que faz o trabalho pesado, e responde na hora {"type": "started"}.
  Isso é necessário porque o Chrome pode derrubar o service worker da
  extensão (e a conexão nativa junto) no meio de um download longo — o
  trabalho real não pode depender de o Chrome continuar vivo.

Modo worker (--worker <job_id> <url> <fitMode>):
  Roda de fato o yt-dlp + ffmpeg, grava um log e dispara uma notificação
  nativa do macOS (via osascript) quando termina — com sucesso ou erro.
"""

import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path

OUTPUT_DIR = Path.home() / "Downloads" / "BaixaAI"
LOG_DIR = OUTPUT_DIR / ".logs"
SCRIPT_PATH = Path(__file__).resolve()
SCRIPT_DIR = SCRIPT_PATH.parent
PATHS_FILE = SCRIPT_DIR / "paths.json"


def load_resolved_paths():
    """Lê os caminhos absolutos que o install.sh encontrou (yt-dlp/ffmpeg/
    ffprobe) em tempo de instalação. Necessário porque o Chrome inicia este
    script sem o PATH do shell interativo (não carrega .zshrc/conda), então
    um simples shutil.which() pode não achar binários instalados via
    conda/homebrew/pip --user."""
    if PATHS_FILE.exists():
        try:
            return json.loads(PATHS_FILE.read_text())
        except Exception:
            return {}
    return {}


RESOLVED_PATHS = load_resolved_paths()


def which_or_none(binary):
    resolved = RESOLVED_PATHS.get(binary)
    if resolved and Path(resolved).exists():
        return resolved
    return shutil.which(binary)


# ---------------------------------------------------------------------
# Protocolo de Native Messaging (só usado no modo normal, falando com o
# Chrome por stdin/stdout).
# ---------------------------------------------------------------------

def read_message():
    raw_length = sys.stdin.buffer.read(4)
    if len(raw_length) == 0:
        return None
    length = struct.unpack('<I', raw_length)[0]
    data = sys.stdin.buffer.read(length)
    return json.loads(data.decode('utf-8'))


def send_message(message):
    data = json.dumps(message).encode('utf-8')
    sys.stdout.buffer.write(struct.pack('<I', len(data)))
    sys.stdout.buffer.write(data)
    sys.stdout.buffer.flush()


# ---------------------------------------------------------------------
# Trabalho pesado (roda só dentro do processo worker desacoplado)
# ---------------------------------------------------------------------

def run_ytdlp(url, workdir, log):
    ytdlp_bin = which_or_none("yt-dlp")
    if not ytdlp_bin:
        raise RuntimeError(
            "yt-dlp não encontrado. Rode install.sh (ele instala com pip3 install --user yt-dlp)."
        )

    out_template = str(Path(workdir) / "%(title).80s.%(ext)s")

    ffmpeg_bin = which_or_none("ffmpeg")
    deno_bin = which_or_none("deno")

    base_cmd = [
        ytdlp_bin,
        # Prioriza H.264 (avc1) em vez de AV1: nem todo ffmpeg (ex.: builds
        # mais antigas do conda) sabe decodificar AV1, o que gera um arquivo
        # de 0 bytes na etapa de normalização. H.264 é universalmente
        # suportado. Só cai pra "melhor disponível" (pode incluir AV1) se
        # não houver opção em H.264.
        "-f", "bv*[vcodec^=avc1]+ba/b[vcodec^=avc1]/bv*+ba/b",
        "--merge-output-format", "mp4",
        "--restrict-filenames",
        # Evita baixar a playlist inteira quando a URL da aba contém um
        # parâmetro &list=... (comum ao assistir um vídeo dentro de uma
        # playlist) — sem isso, o yt-dlp tenta baixar todos os itens.
        "--no-playlist",
        "--newline",
        "-o", out_template,
    ]
    if ffmpeg_bin:
        # yt-dlp faz sua própria busca por ffmpeg usando o PATH do processo —
        # que aqui é o PATH mínimo do Chrome, sem conda/homebrew. Sem isso,
        # ele baixa vídeo e áudio separados e NÃO junta (fica sem som).
        base_cmd += ["--ffmpeg-location", ffmpeg_bin]
    if deno_bin:
        # O YouTube exige resolver um desafio em JavaScript pra liberar as
        # URLs de vídeo (assinatura/"n challenge"). Sem um runtime JS, o
        # yt-dlp só consegue ver imagens, não os formatos de vídeo reais.
        base_cmd += ["--js-runtimes", f"deno:{deno_bin}"]
    base_cmd += [url]

    # Tenta reaproveitar os cookies do Chrome primeiro (necessário para muito
    # conteúdo do Instagram); se falhar, tenta de novo sem cookies.
    attempts = [
        base_cmd[:1] + ["--cookies-from-browser", "chrome"] + base_cmd[1:],
        base_cmd,
    ]

    last_err = ""
    for cmd in attempts:
        proc = subprocess.Popen(
            cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, bufsize=1,
        )
        lines = []
        for line in proc.stdout:
            line = line.strip()
            if line:
                lines.append(line)
                log(line)
        proc.wait()
        if proc.returncode == 0:
            break
        last_err = "\n".join(lines[-15:])
    else:
        raise RuntimeError(
            "yt-dlp não conseguiu baixar o vídeo (conteúdo privado, "
            "removido, ou exige login). Detalhe:\n" + last_err
        )

    downloaded = sorted(
        Path(workdir).glob("*.mp4"), key=lambda p: p.stat().st_mtime
    )
    if not downloaded:
        raise RuntimeError("yt-dlp terminou mas nenhum .mp4 foi encontrado.")
    return downloaded[-1]


def probe_dimensions(path):
    ffprobe_bin = which_or_none("ffprobe")
    if not ffprobe_bin:
        raise RuntimeError("ffprobe não encontrado (instale o ffmpeg).")
    cmd = [
        ffprobe_bin, "-v", "error", "-select_streams", "v:0",
        "-show_entries", "stream=width,height",
        "-of", "csv=s=x:p=0", str(path),
    ]
    out = subprocess.check_output(cmd, text=True).strip()
    w, h = out.split("x")
    return int(w), int(h)


def normalize_video(input_path, fit_mode, log):
    ffmpeg_bin = which_or_none("ffmpeg")
    if not ffmpeg_bin:
        raise RuntimeError("ffmpeg não encontrado. Rode install.sh ou instale manualmente.")

    w, h = probe_dimensions(input_path)
    horizontal = w >= h
    target_w, target_h = (1920, 1080) if horizontal else (1080, 1920)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    stem = re.sub(r"[^\w\-.]+", "_", input_path.stem)[:80]
    suffix = "16x9" if horizontal else "9x16"
    output_path = OUTPUT_DIR / f"{stem}_fullhd_{suffix}.mp4"

    # Evita sobrescrever: títulos genéricos (comum no Instagram, tipo
    # "Video by usuario") podem colidir entre vídeos diferentes.
    counter = 2
    while output_path.exists():
        output_path = OUTPUT_DIR / f"{stem}_fullhd_{suffix}_{counter}.mp4"
        counter += 1

    if fit_mode == "cover":
        vf = (
            f"scale={target_w}:{target_h}:force_original_aspect_ratio=increase,"
            f"crop={target_w}:{target_h}"
        )
    else:
        vf = (
            f"scale={target_w}:{target_h}:force_original_aspect_ratio=decrease,"
            f"pad={target_w}:{target_h}:(ow-iw)/2:(oh-ih)/2:black"
        )

    cmd = [
        ffmpeg_bin, "-y", "-i", str(input_path),
        "-vf", vf,
        "-c:v", "libx264", "-preset", "veryfast", "-crf", "20",
        "-c:a", "aac", "-b:a", "160k",
        str(output_path),
    ]
    proc = subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1,
    )
    for line in proc.stdout:
        line = line.strip()
        if line:
            log("ffmpeg: " + line)
    proc.wait()
    if proc.returncode != 0:
        raise RuntimeError("ffmpeg falhou ao normalizar o vídeo para Full HD.")

    return output_path


def notify_mac(title, message, log=None):
    try:
        script = f'display notification {json.dumps(message)} with title {json.dumps(title)}'
        env = {**os.environ, "LANG": "en_US.UTF-8", "LC_ALL": "en_US.UTF-8"}
        result = subprocess.run(
            ["/usr/bin/osascript", "-e", script], check=False,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=env,
        )
        if result.returncode != 0 and log:
            log(f"[BaixaAI] notify_mac falhou (código {result.returncode}): {result.stdout.strip()}")
    except Exception as exc:
        if log:
            log(f"[BaixaAI] notify_mac exceção: {exc}")


def play_sound(success, log=None):
    # Toca um som do sistema diretamente (não passa pela Central de
    # Notificações, então não é bloqueado por modos de Foco como o "Trabalho").
    sound = "/System/Library/Sounds/Glass.aiff" if success else "/System/Library/Sounds/Basso.aiff"
    try:
        result = subprocess.run(
            ["/usr/bin/afplay", sound], check=False,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        )
        if result.returncode != 0 and log:
            log(f"[BaixaAI] play_sound falhou (código {result.returncode}): {result.stdout.strip()}")
    except Exception as exc:
        if log:
            log(f"[BaixaAI] play_sound exceção: {exc}")


def run_worker(job_id, url, fit_mode):
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    log_path = LOG_DIR / f"{job_id}.log"
    with open(log_path, "a", encoding="utf-8") as logf:
        def log(msg):
            logf.write(msg + "\n")
            logf.flush()

        try:
            log(f"[BaixaAI] job {job_id} — baixando: {url}")
            with tempfile.TemporaryDirectory(prefix="baixaai_") as workdir:
                downloaded = run_ytdlp(url, workdir, log)
                log("[BaixaAI] normalizando para Full HD...")
                final_path = normalize_video(downloaded, fit_mode, log)
            log(f"[BaixaAI] concluído: {final_path}")
            notify_mac("BaixaAI - download concluido", final_path.name, log=log)
            play_sound(success=True, log=log)
        except Exception as exc:  # noqa: BLE001
            log("[BaixaAI] ERRO: " + str(exc))
            notify_mac("BaixaAI - erro no download", str(exc)[:200], log=log)
            play_sound(success=False, log=log)


# ---------------------------------------------------------------------
# Modo normal: fala com o Chrome, só dispara o worker e responde rápido.
# ---------------------------------------------------------------------

def handle_message(message):
    if message.get("type") == "download":
        job_id = uuid.uuid4().hex[:10]
        worker_cmd = [
            sys.executable, str(SCRIPT_PATH),
            "--worker", job_id, message["url"], message.get("fitMode", "contain"),
        ]
        subprocess.Popen(
            worker_cmd,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,  # sobrevive mesmo se o Chrome matar este processo
            cwd=str(Path.home()),
        )
        send_message({
            "type": "started",
            "job_id": job_id,
            "output_dir": str(OUTPUT_DIR),
        })
    else:
        send_message({"type": "error", "message": "Mensagem desconhecida."})


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--worker":
        _, _, job_id, url, fit_mode = sys.argv[:5]
        run_worker(job_id, url, fit_mode)
        return

    try:
        while True:
            message = read_message()
            if message is None:
                break
            try:
                handle_message(message)
            except Exception as exc:  # noqa: BLE001
                send_message({"type": "error", "message": str(exc)})
    except Exception as exc:  # noqa: BLE001
        try:
            send_message({"type": "error", "message": "Erro inesperado no ajudante local: " + str(exc)})
        except Exception:
            pass


if __name__ == "__main__":
    main()
