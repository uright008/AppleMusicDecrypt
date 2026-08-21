# Flutter Android client

The Flutter client is a mobile control surface for the upstream `v2` Python
core. The first release keeps the proven downloader/decryption pipeline in the
Termux Debian environment and talks to it over a loopback-only HTTP API. This
avoids shipping incompatible Python, FFmpeg, GPAC, Bento4 and gRPC binaries in
the APK while giving Android users a native Material UI.

> Use this software only with media you are legally entitled to access and
> process. Keep the API bound to `127.0.0.1`; it has no remote authentication.

## 1. Install the backend in Termux

Follow the existing [Android deployment guide](../android-deploy.md) through
configuration, then install the optional server dependencies:

```shell
pd login debian
cd AppleMusicDecrypt
poetry install --with server
```

Recommended Android paths in `config.toml`:

```toml
[instance]
url = "wm.wol.moe"
secure = true

[download]
parallelNum = 2
maxRunningTasks = 4
dirPathFormat = "/sdcard/Music/{album_artist}/{album}"
playlistDirPathFormat = "/sdcard/Music/playlists/{playlistName}"
```

Start the loopback API:

```shell
poetry run python server.py --host 127.0.0.1 --port 10020
```

The backend is ready when this returns JSON:

```shell
curl http://127.0.0.1:10020/api/v1/health
```

## 2. Build the Flutter app

Install a current stable Flutter SDK and Android toolchain, then run:

```shell
cd flutter_app
flutter pub get
flutter run
```

For an APK:

```shell
flutter build apk --release
```

The output is `build/app/outputs/flutter-apk/app-release.apk`. The app defaults
to `http://127.0.0.1:10020`; change it in Settings if the API uses another
loopback port.

## Architecture

```mermaid
flowchart TD
    A["Flutter Android UI"] -->|"HTTP on 127.0.0.1"| B["FastAPI control plane"]
    B --> C["Upstream v2 Ripper"]
    C --> D["FFmpeg / GPAC / Bento4"]
    C --> E["wrapper-manager gRPC"]
```

The API exposes health, enqueue, task list/speed, and cancellation endpoints.
It does not duplicate or modify the upstream media pipeline. A future
standalone APK can replace the Python control plane behind the same API models
after every native dependency has a maintained Android ARM64 build.
