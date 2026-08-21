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
| `src/task.py`, `src/rip.py` | Bounded Dart queue, container expansion and preparation pipeline | Complete through ordered sample decryption |
| `src/mp4.py` | Dart HLS selector and fragmented MP4 sample parser | Extraction complete; re-encapsulation pending |
| `src/metadata.py`, `src/save.py` | Dart metadata and Android MediaStore output | Pending |

The download button stays disabled until the local rip path is usable. This is
intentional: a connected wrapper-manager is only the decrypt service, not the
download/remux pipeline.

## Native media boundary

Upstream shells out to GPAC/MP4Box, Bento4, and FFmpeg for fragmented MP4 sample
extraction, remuxing, metadata, and validation. HLS selection and the common
`moof/traf/tfhd/trun/mdat` sample-extraction path are now implemented in pure
Dart. The remaining boundary is rebuilding playable M4A containers, writing
metadata, saving through Android MediaStore, and integrity validation. Those
parts can use additional ISO-BMFF code or a maintained Android native/JNI layer.

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
