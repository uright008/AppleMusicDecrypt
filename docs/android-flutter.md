# Flutter Android native port

The Android app is being implemented as a native port of the Python `v2` core,
with Flutter as the GUI. It follows
`WorldObservationLog/AppleMusicDecrypt@d1a9a10079a72a454ce013589a5a47d5c17c8aee`.
The upstream repository is reference-only; all Android work stays in
`uright008/AppleMusicDecrypt`.

## Current architecture

Flutter connects directly to `WrapperManagerService` over HTTP/2 gRPC. Do not
put `http://` or `https://` in the app's manager setting:

- `grpcs://wm.wol.moe:443` for TLS.
- `grpc://192.168.1.7:8080` for an explicitly insecure LAN service.

`curl` is not a valid wrapper-manager client. An HTTP/0.9 or HTTP/2 error from
curl does not mean the gRPC service is broken.

Status, streaming login/2FA, logout, and the bidirectional decrypt protocol are
implemented in Dart from the unchanged upstream `src/grpc/manager.proto`.
No FastAPI control plane is used by these calls.

## Port status

| Python v2 module | Android implementation | State |
| --- | --- | --- |
| `src/grpc/manager.py` | Dart gRPC transport, long-lived decrypt session and proto wire models | Complete for all upstream RPCs |
| `src/url.py` | `core/apple_music_url.dart` | Complete |
| `src/api.py` | Dart Apple Music catalog/download client | Complete for current rip path |
| `src/task.py`, `src/rip.py` | Bounded Dart queue and end-to-end native media handler | Connected to the Flutter queue |
| `src/mp4.py` | HLS selector, sample parser, clear fragmented-M4A muxer and raw Atmos packager | ALAC/AAC M4A and raw EC3/AC3 implemented |
| `src/metadata.py`, `src/save.py` | Dart iTunes-tag writer, output service and Android MediaStore bridge | Complete for current M4A/raw output path |

The download button now runs the native Dart pipeline and publishes completed
files under `Download/AppleMusicDecrypt`. Album downloads follow upstream's
`{album_artist}/{album}/{disk}-{tracknum:02d} {title}` layout. Playlist
downloads use `playlists/{playlistName}/{playlistSongIndex:02d}. {artist} -
{title}`. Album folders also receive upstream-compatible `cover.jpg`; every
timed-lyrics download receives a same-name `.lrc` file. Existing paths are
replaced instead of accumulating MediaStore duplicates. The first download
lazily discovers the current Apple Music catalog token, so it can take slightly
longer to enter the queue than later downloads.

## Native media boundary

Upstream shells out to GPAC/MP4Box, Bento4, and FFmpeg for fragmented MP4 sample
extraction, remuxing, metadata, and validation. HLS selection and the common
`moof/traf/tfhd/trun/mdat` sample-extraction path are now implemented in pure
Dart. The clear M4A path preserves Apple's fragmented MP4 timing and offsets,
replaces equal-length decrypted samples in place, restores the original audio
sample entry from `frma`, and neutralizes CENC-only boxes without bundling
GPAC/FFmpeg. Matching upstream's `atmosConvent = false` branch, EC3/AC3 can
also be saved as raw `.ec3`/`.ac3`. M4A output embeds the upstream iTunes tag
set, including title, artists, album, date, composer, genre, track/disc numbers,
lyrics, artwork, copyright, label, UPC/ISRC, rating, and catalog IDs. Remaining
work is integrity validation, broader real-media fixtures, and a
streaming/file-backed pipeline for very large downloads.

## Build

```shell
cd flutter_app
flutter pub get
flutter run
```

For a debug APK:

```shell
flutter build apk --debug --no-pub
```

The repository commits the manager wire implementation, so builds do not need
to install `protoc` or regenerate sources. This keeps repeated CI builds fast.

> Use this software only with media you are legally entitled to access and
> process. Prefer TLS for credentials and verification codes.
