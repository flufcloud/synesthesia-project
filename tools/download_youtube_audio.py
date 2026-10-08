#!/usr/bin/env python3

import argparse
import json
import re
import shutil
import subprocess
import sys
import unicodedata
from pathlib import Path
from urllib.parse import urlparse


YOUTUBE_HOSTS = {
    "youtu.be",
    "youtube.com",
    "www.youtube.com",
    "m.youtube.com",
    "music.youtube.com",
}


class DownloadError(Exception):
    pass


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Download one permitted YouTube video's audio as an M4A file."
    )
    parser.add_argument("url", help="YouTube video URL")
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("audio/downloads"),
        help="Destination directory (default: audio/downloads)",
    )
    return parser.parse_args()


def validate_url(url: str) -> None:
    parsed = urlparse(url)
    if parsed.scheme not in {"http", "https"} or parsed.hostname not in YOUTUBE_HOSTS:
        raise DownloadError("Provide a valid youtube.com or youtu.be video URL.")


def require_program(name: str, install_command: str) -> str:
    path = shutil.which(name)
    if path is None:
        raise DownloadError(f"Missing {name}. Install it with: {install_command}")
    return path


def load_video_metadata(yt_dlp: str, url: str) -> dict:
    result = subprocess.run(
        [yt_dlp, "--dump-single-json", "--skip-download", "--no-playlist", url],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        message = result.stderr.strip() or "yt-dlp could not read the video."
        raise DownloadError(message)

    try:
        metadata = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise DownloadError("yt-dlp returned invalid video metadata.") from error

    if metadata.get("_type") == "playlist":
        raise DownloadError("Playlist downloads are not supported. Provide one video URL.")
    return metadata


def friendly_stem(title: str, video_id: str) -> str:
    ascii_title = unicodedata.normalize("NFKD", title).encode("ascii", "ignore").decode()
    clean_title = re.sub(r"[^a-z0-9]+", "-", ascii_title.lower()).strip("-")
    clean_title = clean_title[:100].rstrip("-") or "youtube-audio"
    clean_id = re.sub(r"[^a-z0-9_-]", "", video_id.lower())
    return f"{clean_title}-{clean_id}"


def download_audio(yt_dlp: str, url: str, output_dir: Path, stem: str) -> Path:
    output_dir.mkdir(parents=True, exist_ok=True)
    destination = output_dir.resolve() / f"{stem}.m4a"
    if destination.exists():
        return destination

    command = [
        yt_dlp,
        "--no-playlist",
        "--format",
        "bestaudio/best",
        "--extract-audio",
        "--audio-format",
        "m4a",
        "--audio-quality",
        "0",
        "--no-overwrites",
        "--output",
        str(destination.with_suffix(".%(ext)s")),
        url,
    ]
    result = subprocess.run(command)
    if result.returncode != 0:
        raise DownloadError("yt-dlp failed to download or convert the audio.")
    if not destination.exists():
        raise DownloadError("Download finished, but the expected M4A file was not created.")
    return destination


def main() -> int:
    arguments = parse_arguments()

    try:
        validate_url(arguments.url)
        yt_dlp = require_program("yt-dlp", "brew install yt-dlp")
        require_program("ffmpeg", "brew install ffmpeg")
        metadata = load_video_metadata(yt_dlp, arguments.url)
        stem = friendly_stem(metadata.get("title") or "youtube-audio", metadata.get("id") or "video")
        destination = download_audio(yt_dlp, arguments.url, arguments.output_dir, stem)
    except DownloadError as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1

    print(f"Saved: {destination}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
