# Synesthesia Project Instructions

## Working Style

- Use minimal, direct, technical wording.
- Do not add praise, filler, or unnecessary emojis.
- Keep changes small and incremental.
- Do not add features beyond the requested scope.
- Reuse existing logic when it improves readability and avoids duplication.
- Prefer compact, modular, readable code with few moving parts.
- Avoid one-line wrapper functions unless they provide clear value.
- After coding, review the changes for style and compliance with this file.
- Keep this file current when project requirements or architecture change.

## Project Goal

Build a small local tool for collecting music-to-color time-series data for a later machine-learning project.

The project has three stages:

1. Curate paired music and color time-series data.
2. Train a model that maps music time series to color time series.
3. Build a creative use for the predicted color series.

Stage 1 and the first small stage 3 color-show prototype are currently in scope.

## Stage 1 Requirements

- Build an extremely basic local interface, not a browser interface.
- Place audio controls on the left.
- Let the user choose a local audio file.
- Provide standard playback controls such as play and pause.
- Place three two-dimensional color gradients or color wheels on the right for primary, secondary, and tertiary colors.
- Let the user move the pointer over any color control to indicate the colors that match the current musical moment.
- Allow the primary, secondary, and tertiary colors to be null independently.
- Record color selections against audio playback timestamps in a form suitable for later time-series model training.
- Keep the original downloaded audio files local.
- Keep the collected dataset within an approximate 1 GB total budget.

## Data Guidance

- Prefer timestamped color labels that reference the source audio file over creating many tiny audio files during annotation.
- Defer audio windowing or feature extraction until model preprocessing unless later evidence requires another format.
- Store enough metadata to reproduce training windows later, including the audio reference, playback time, color representation, and sampling details.
- Encode every absent color as an explicit JSON `null` value rather than omitting its key.
- Name dataset audio files with lowercase ASCII kebab-case while retaining disc and track prefixes.

## Color Show Requirements

- Keep the color show separate from the data collector.
- Require both an audio file and its matching color JSON before enabling playback.
- Validate the pair using the audio filename and duration stored in the JSON.
- Provide play, pause, stop, elapsed-time display, and a draggable playback-position slider.
- Display the primary color as a solid dot in the center when present.
- Display the secondary color as a gradient around the primary dot when present.
- Display the tertiary color as a gradient moving inward from the window edges when present.
- Render any absent color as no corresponding layer.

## Audio Download Helper

- Keep the YouTube audio downloader separate from both macOS apps.
- Download one video at a time and reject playlists.
- Use `yt-dlp` with `ffmpeg` to produce compact M4A audio files.
- Save downloads under `audio/downloads` by default.
- Normalize downloaded filenames to lowercase ASCII kebab-case.
- Use the downloader only for media the user owns or has permission to download.

## Web Collector

- Keep the web collector separate from the native collector and color show.
- Implement it as buildless static HTML, CSS, and JavaScript under `docs/` for GitHub Pages.
- Keep the interface functional and minimal. Do not add introductory copy, privacy banners, numbered sections, or decorative footer text.
- Keep selected audio inside the visitor's browser; do not upload or store it remotely.
- Match dataset format 5, including explicit null values for absent colors.
- Sample colors at 10 Hz and let the visitor download the resulting JSON locally.
- Support pointer and touch input for primary, secondary, and tertiary color fields.

## Current Implementation

- `SynesthesiaCollector` and `ColorShow` are separate dependency-free macOS Swift executables using AppKit and AVFoundation.
- Both executables share only the JSON data definitions in `SynesthesiaData`.
- The collector samples the selected color at 10 Hz while audio is playing.
- The collector exports JSON containing the source audio reference, duration, sampling metadata, and timestamped optional primary, secondary, and tertiary sRGB labels.
- Seeking to an already sampled time replaces that time slot instead of creating duplicate labels.
