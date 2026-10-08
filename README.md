# Synesthesia Tools

Two small macOS apps for collecting and displaying timestamped music-to-color data.

## Run

Requirements: macOS 13 or later and Swift 6.

```sh
swift run SynesthesiaCollector
```

## Use

1. Choose a local audio file.
2. Start playback.
3. Click **Start Recording**.
4. Move or drag across the primary, secondary, and tertiary color fields as the music plays.
5. Select **No primary color**, **No secondary color**, or **No tertiary color** when that color is absent.
6. Click **Stop & Save** and save the JSON file.

The app samples the current optional primary, secondary, and tertiary colors at 10 Hz while audio is playing. Seeking back replaces samples for revisited time positions. The JSON file stores the source audio path, duration, sampling metadata, timestamps, hexadecimal colors, and normalized sRGB values.

Every sample includes `primary`, `secondary`, and `tertiary` keys. An absent color is written as JSON `null` rather than leaving out the key.

The audio file is not copied or split. Keeping the original audio and small JSON label files avoids unnecessary storage use. Audio windowing can be performed later during model preprocessing.

## Color show

Run the separate playback app with:

```sh
swift run ColorShow
```

Choose an audio file and its matching color JSON. Playback remains disabled until both files are present and the stored audio filename and duration match.

Use Play, Pause, Stop, or drag the progress bar to change the playback position.

During playback:

- The primary color appears as a solid dot in the center when present.
- The secondary color appears as a gradient around the primary dot.
- The tertiary color moves inward from the window edges.
- Null colors produce no corresponding layer.

## YouTube audio downloader

This separate command-line helper downloads one permitted YouTube video's audio as an M4A file. It does not support playlists.

Install its external tools once:

```sh
brew install yt-dlp ffmpeg
```

Run it from the project directory:

```sh
python3 tools/download_youtube_audio.py "https://www.youtube.com/watch?v=VIDEO_ID"
```

Files are saved under `audio/downloads` by default with lowercase ASCII kebab-case names. Use `--output-dir PATH` to select another directory. Only download media you own or have permission to download.

## Web tools

The static web version is in `docs/`. Its tabs provide the recorder and color show. Files remain in the browser, and the recorder downloads dataset-format-5 JSON locally.

Preview it locally:

```sh
python3 -m http.server 8000 --directory docs
```

Then open `http://localhost:8000`.

To publish with GitHub Pages:

1. Push this project to a GitHub repository.
2. Open the repository's **Settings → Pages**.
3. Under **Build and deployment**, select **Deploy from a branch**.
4. Select the branch containing the project, choose the `/docs` folder, and save.

GitHub will publish it at `https://YOUR_USERNAME.github.io/REPOSITORY_NAME/`. Relative asset paths allow it to work from that repository subpath.
