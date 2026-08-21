import 'dart:async';
import 'dart:collection';

import '../api_client.dart';
import 'apple_music_api.dart';
import 'apple_music_url.dart';
import 'm3u8_resolver.dart';

final class RipPreparationOptions {
  const RipPreparationOptions({
    required this.codec,
    required this.language,
    this.coverFormat = 'jpg',
    this.coverSize = '3000x3000',
    this.downloadCover = true,
    this.downloadLyrics = true,
    this.codecAlternative = false,
    this.codecPriority = AudioCodec.values,
  });

  final AudioCodec codec;
  final String language;
  final String coverFormat;
  final String coverSize;
  final bool downloadCover;
  final bool downloadLyrics;
  final bool codecAlternative;
  final List<AudioCodec> codecPriority;
}

final class PreparedSong {
  const PreparedSong({
    required this.url,
    required this.song,
    required this.album,
    required this.media,
    required this.cover,
    required this.lyrics,
  });

  final AppleMusicUrl url;
  final Map<String, dynamic> song;
  final Map<String, dynamic> album;
  final M3u8Info media;
  final List<int>? cover;
  final String? lyrics;

  String get title =>
      (_map(song['attributes'])?['name'] ?? url.id).toString();

  String? get artist => _map(song['attributes'])?['artistName']?.toString();
}

final class RipPreparationService {
  const RipPreparationService({
    required AppleMusicDataSource appleMusic,
    required ManagerMediaTransport manager,
    M3u8Resolver resolver = const M3u8Resolver(),
  })  : _appleMusic = appleMusic,
        _manager = manager,
        _resolver = resolver;

  final AppleMusicDataSource _appleMusic;
  final ManagerMediaTransport _manager;
  final M3u8Resolver _resolver;

  Future<PreparedSong> prepareSong(
    AppleMusicUrl url,
    RipPreparationOptions options,
  ) async {
    if (url.type != AppleMusicUrlType.song) {
      throw ArgumentError.value(url.type, 'url', 'Expected a song URL');
    }
    final song = await _appleMusic.getSongInfo(
      songId: url.id,
      storefront: url.storefront,
      language: options.language,
    );
    if (song == null) throw StateError('Song ${url.id} was not found');

    final albumId = _albumId(song);
    final album = await _appleMusic.getAlbumInfo(
      albumId: albumId,
      storefront: url.storefront,
      language: options.language,
    );
    final attributes = _map(song['attributes']) ?? const {};

    List<int>? cover;
    final artwork = _map(attributes['artwork']);
    final coverUrl = artwork?['url']?.toString();
    if (options.downloadCover && coverUrl != null && coverUrl.isNotEmpty) {
      cover = await _appleMusic.getCover(
        coverUrl,
        format: options.coverFormat,
        size: options.coverSize,
      );
    }

    String? lyrics;
    if (options.downloadLyrics && attributes['hasTimeSyncedLyrics'] == true) {
      lyrics = await _manager.lyrics(
        adamId: url.id,
        region: url.storefront,
        language: options.language,
      );
    }

    final masterUrl = await _masterUrl(url.id, attributes, options.codec);
    final media = await _resolver.resolve(
      masterUrl: masterUrl,
      codec: options.codec,
      codecAlternative: options.codecAlternative,
      codecPriority: options.codecPriority,
      load: _appleMusic.downloadM3u8,
    );
    return PreparedSong(
      url: url,
      song: song,
      album: album,
      media: media,
      cover: cover,
      lyrics: lyrics,
    );
  }

  Future<String> _masterUrl(
    String adamId,
    Map<String, dynamic> attributes,
    AudioCodec codec,
  ) async {
    final extended = _map(attributes['extendedAssetUrls']);
    if (extended == null) {
      throw StateError('Audio assets do not exist for $adamId');
    }
    final enhancedHls = extended['enhancedHls']?.toString();
    if (codec == AudioCodec.aacLegacy) {
      return _manager.webPlayback(adamId);
    }
    if (codec == AudioCodec.alac &&
        enhancedHls != null &&
        enhancedHls.isNotEmpty) {
      return _manager.m3u8(adamId);
    }
    if (enhancedHls == null || enhancedHls.isEmpty) {
      throw StateError('Requested audio does not exist for $adamId');
    }
    return enhancedHls;
  }

  static String _albumId(Map<String, dynamic> song) {
    final relationships = _map(song['relationships']);
    final albums = _map(relationships?['albums']);
    final data = albums?['data'];
    if (data is List && data.isNotEmpty) {
      final id = _map(data.first)?['id']?.toString();
      if (id != null && id.isNotEmpty) return id;
    }
    throw const FormatException('Song response has no album relationship');
  }
}

enum NativeRipTaskStatus {
  waiting,
  resolving,
  preparing,
  readyForMedia,
  failed,
  cancelled,
}

final class NativeRipTask {
  const NativeRipTask({
    required this.id,
    required this.sourceUrl,
    required this.status,
    this.adamId,
    this.title,
    this.artist,
    this.error,
    this.prepared,
  });

  final String id;
  final String sourceUrl;
  final NativeRipTaskStatus status;
  final String? adamId;
  final String? title;
  final String? artist;
  final String? error;
  final PreparedSong? prepared;

  NativeRipTask copyWith({
    NativeRipTaskStatus? status,
    String? adamId,
    String? title,
    String? artist,
    String? error,
    PreparedSong? prepared,
  }) =>
      NativeRipTask(
        id: id,
        sourceUrl: sourceUrl,
        status: status ?? this.status,
        adamId: adamId ?? this.adamId,
        title: title ?? this.title,
        artist: artist ?? this.artist,
        error: error ?? this.error,
        prepared: prepared ?? this.prepared,
      );
}

/// Bounded task queue equivalent to the registration/semaphore part of
/// upstream `DownloadManager`. It currently stops at the native media boundary.
final class NativeRipCoordinator {
  NativeRipCoordinator({
    required AppleMusicDataSource appleMusic,
    required RipPreparationService preparation,
    this.maxRunningTasks = 4,
  })  : _appleMusic = appleMusic,
        _preparation = preparation;

  final AppleMusicDataSource _appleMusic;
  final RipPreparationService _preparation;
  final int maxRunningTasks;
  final Queue<({String id, RipPreparationOptions options})> _pending = Queue();
  final Map<String, NativeRipTask> _tasks = {};
  final Set<String> _cancelled = {};
  final StreamController<List<NativeRipTask>> _changes =
      StreamController.broadcast();
  var _running = 0;
  var _sequence = 0;

  Stream<List<NativeRipTask>> get changes => _changes.stream;

  List<NativeRipTask> get tasks => List.unmodifiable(_tasks.values);

  String enqueue(String sourceUrl, RipPreparationOptions options) {
    final id = 'task-${++_sequence}';
    _tasks[id] = NativeRipTask(
      id: id,
      sourceUrl: sourceUrl,
      status: NativeRipTaskStatus.waiting,
    );
    _pending.add((id: id, options: options));
    _emit();
    _drain();
    return id;
  }

  void cancel(String id) {
    final task = _tasks[id];
    if (task == null ||
        task.status == NativeRipTaskStatus.readyForMedia ||
        task.status == NativeRipTaskStatus.failed) {
      return;
    }
    _cancelled.add(id);
    _tasks[id] = task.copyWith(status: NativeRipTaskStatus.cancelled);
    _emit();
  }

  void _drain() {
    while (_running < maxRunningTasks && _pending.isNotEmpty) {
      final item = _pending.removeFirst();
      if (_cancelled.contains(item.id)) continue;
      _running++;
      _run(item.id, item.options).whenComplete(() {
        _running--;
        _drain();
      });
    }
  }

  Future<void> _run(String id, RipPreparationOptions options) async {
    try {
      _update(id, status: NativeRipTaskStatus.resolving);
      final task = _tasks[id]!;
      var url = AppleMusicUrl.tryParse(task.sourceUrl);
      if (url == null) {
        final resolved = await _appleMusic.resolveUrl(task.sourceUrl);
        url = AppleMusicUrl.tryParse(resolved);
      }
      if (url == null) throw const FormatException('Unsupported Apple Music URL');
      if (url.type != AppleMusicUrlType.song) {
        throw const FormatException('Album/playlist/artist expansion is pending');
      }
      if (_cancelled.contains(id)) return;
      _update(
        id,
        status: NativeRipTaskStatus.preparing,
        adamId: url.id,
      );
      final prepared = await _preparation.prepareSong(url, options);
      if (_cancelled.contains(id)) return;
      _update(
        id,
        status: NativeRipTaskStatus.readyForMedia,
        adamId: url.id,
        title: prepared.title,
        artist: prepared.artist,
        prepared: prepared,
      );
    } catch (error) {
      if (_cancelled.contains(id)) return;
      _update(
        id,
        status: NativeRipTaskStatus.failed,
        error: error.toString(),
      );
    }
  }

  void _update(
    String id, {
    required NativeRipTaskStatus status,
    String? adamId,
    String? title,
    String? artist,
    String? error,
    PreparedSong? prepared,
  }) {
    final task = _tasks[id];
    if (task == null) return;
    _tasks[id] = task.copyWith(
      status: status,
      adamId: adamId,
      title: title,
      artist: artist,
      error: error,
      prepared: prepared,
    );
    _emit();
  }

  void _emit() => _changes.add(tasks);

  Future<void> close() => _changes.close();
}

Map<String, dynamic>? _map(Object? value) =>
    value is Map<String, dynamic> ? value : null;
