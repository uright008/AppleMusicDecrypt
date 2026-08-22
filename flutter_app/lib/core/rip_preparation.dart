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
    this.coverSize = '5000x5000',
    this.downloadCover = true,
    this.downloadLyrics = true,
    this.codecAlternative = false,
    this.codecPriority = AudioCodec.values,
    this.includeParticipateSongs = false,
  });

  final AudioCodec codec;
  final String language;
  final String coverFormat;
  final String coverSize;
  final bool downloadCover;
  final bool downloadLyrics;
  final bool codecAlternative;
  final List<AudioCodec> codecPriority;
  final bool includeParticipateSongs;
}

final class PreparedSong {
  const PreparedSong({
    required this.url,
    required this.song,
    required this.album,
    required this.media,
    required this.cover,
    required this.lyrics,
    this.outputContext,
  });

  final AppleMusicUrl url;
  final Map<String, dynamic> song;
  final Map<String, dynamic> album;
  final M3u8Info media;
  final List<int>? cover;
  final String? lyrics;
  final RipOutputContext? outputContext;

  String get title =>
      (_map(song['attributes'])?['name'] ?? url.id).toString();

  String? get artist => _map(song['attributes'])?['artistName']?.toString();

  PreparedSong withOutputContext(RipOutputContext? value) => PreparedSong(
        url: url,
        song: song,
        album: album,
        media: media,
        cover: cover,
        lyrics: lyrics,
        outputContext: value,
      );
}

final class RipOutputContext {
  const RipOutputContext({
    required this.playlistName,
    required this.playlistCuratorName,
    required this.playlistIndex,
  });

  final String playlistName;
  final String playlistCuratorName;
  final int playlistIndex;
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
  downloading,
  extracting,
  decrypting,
  packaging,
  done,
  expanded,
  skipped,
  failed,
  cancelled,
}

typedef NativeMediaTaskHandler = Future<void> Function(
  PreparedSong prepared,
  void Function(NativeRipTaskStatus status) onStatus,
);

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
    this.outputContext,
    this.childCount = 0,
  });

  final String id;
  final String sourceUrl;
  final NativeRipTaskStatus status;
  final String? adamId;
  final String? title;
  final String? artist;
  final String? error;
  final PreparedSong? prepared;
  final RipOutputContext? outputContext;
  final int childCount;

  NativeRipTask copyWith({
    NativeRipTaskStatus? status,
    String? adamId,
    String? title,
    String? artist,
    String? error,
    PreparedSong? prepared,
    RipOutputContext? outputContext,
    int? childCount,
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
        outputContext: outputContext ?? this.outputContext,
        childCount: childCount ?? this.childCount,
      );
}

/// Bounded task queue equivalent to the registration/semaphore part of
/// upstream `DownloadManager`. A media handler can continue prepared songs
/// through download, decryption, packaging, and saving.
final class NativeRipCoordinator {
  NativeRipCoordinator({
    required AppleMusicDataSource appleMusic,
    required RipPreparationService preparation,
    NativeMediaTaskHandler? mediaHandler,
    this.maxRunningTasks = 4,
  })  : _appleMusic = appleMusic,
        _preparation = preparation,
        _mediaHandler = mediaHandler;

  final AppleMusicDataSource _appleMusic;
  final RipPreparationService _preparation;
  final NativeMediaTaskHandler? _mediaHandler;
  final int maxRunningTasks;
  final Queue<
      ({
        String id,
        RipPreparationOptions options,
      })> _pending = Queue();
  final Map<String, NativeRipTask> _tasks = {};
  final Set<String> _cancelled = {};
  final Set<String> _claimedAdamIds = {};
  final StreamController<List<NativeRipTask>> _changes =
      StreamController.broadcast();
  var _running = 0;
  var _sequence = 0;
  var _closed = false;

  Stream<List<NativeRipTask>> get changes => _changes.stream;

  List<NativeRipTask> get tasks => List.unmodifiable(_tasks.values);

  String enqueue(
    String sourceUrl,
    RipPreparationOptions options, {
    RipOutputContext? outputContext,
  }) {
    if (_closed) throw StateError('Native rip coordinator is closed');
    final id = 'task-${++_sequence}';
    _tasks[id] = NativeRipTask(
      id: id,
      sourceUrl: sourceUrl,
      status: NativeRipTaskStatus.waiting,
      outputContext: outputContext,
    );
    _pending.add((
      id: id,
      options: options,
    ));
    _emit();
    _drain();
    return id;
  }

  void cancel(String id) {
    final task = _tasks[id];
    if (task == null ||
        task.status == NativeRipTaskStatus.done ||
        task.status == NativeRipTaskStatus.expanded ||
        task.status == NativeRipTaskStatus.skipped ||
        task.status == NativeRipTaskStatus.failed ||
        task.status == NativeRipTaskStatus.cancelled) {
      return;
    }
    _cancelled.add(id);
    if (task.adamId != null) _claimedAdamIds.remove(task.adamId);
    _tasks[id] = task.copyWith(status: NativeRipTaskStatus.cancelled);
    _emit();
  }

  void _drain() {
    if (_closed) return;
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
        await _expand(id, url, options);
        return;
      }
      if (_cancelled.contains(id)) return;
      if (!_claimedAdamIds.add(url.id)) {
        _update(
          id,
          status: NativeRipTaskStatus.skipped,
          adamId: url.id,
        );
        return;
      }
      _update(
        id,
        status: NativeRipTaskStatus.preparing,
        adamId: url.id,
      );
      var prepared = await _preparation.prepareSong(url, options);
      prepared = prepared.withOutputContext(task.outputContext);
      if (_cancelled.contains(id)) return;
      _update(
        id,
        status: NativeRipTaskStatus.readyForMedia,
        adamId: url.id,
        title: prepared.title,
        artist: prepared.artist,
        prepared: prepared,
      );
      final mediaHandler = _mediaHandler;
      if (mediaHandler != null) {
        await mediaHandler(prepared, (status) {
          if (!_cancelled.contains(id)) _update(id, status: status);
        });
        if (_cancelled.contains(id)) return;
        _update(id, status: NativeRipTaskStatus.done);
      }
    } catch (error) {
      if (_cancelled.contains(id)) return;
      _claimedAdamIds.remove(_tasks[id]?.adamId);
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
    int? childCount,
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
      childCount: childCount,
    );
    _emit();
  }

  void _emit() {
    if (!_closed) _changes.add(tasks);
  }

  Future<void> _expand(
    String id,
    AppleMusicUrl url,
    RipPreparationOptions options,
  ) async {
    _update(id, status: NativeRipTaskStatus.preparing, adamId: url.id);
    late final List<({String url, RipOutputContext? outputContext})> children;
    String? title;
    String? artist;
    switch (url.type) {
      case AppleMusicUrlType.album:
        final album = await _appleMusic.getAlbumInfo(
          albumId: url.id,
          storefront: url.storefront,
          language: options.language,
        );
        final resource = _firstData(album);
        final attributes = _map(resource?['attributes']);
        title = attributes?['name']?.toString();
        artist = attributes?['artistName']?.toString();
        var tracks = _relationshipData(resource, 'tracks');
        if (_relationshipHasNext(resource, 'tracks') || tracks.isEmpty) {
          tracks = await _appleMusic.getAlbumTracks(
            albumId: url.id,
            storefront: url.storefront,
          );
        }
        children = _songUrls(tracks, url.storefront)
            .map((child) => (url: child, outputContext: null))
            .toList(growable: false);
        break;
      case AppleMusicUrlType.playlist:
        final playlist = await _appleMusic.getPlaylistInfo(
          playlistId: url.id,
          storefront: url.storefront,
          language: options.language,
        );
        final resource = _firstData(playlist);
        final attributes = _map(resource?['attributes']);
        title = attributes?['name']?.toString();
        artist = attributes?['curatorName']?.toString();
        var tracks = _relationshipData(resource, 'tracks');
        if (_relationshipHasNext(resource, 'tracks') || tracks.isEmpty) {
          tracks = await _appleMusic.getPlaylistTracks(
            playlistId: url.id,
            storefront: url.storefront,
            language: options.language,
          );
        }
        children = [];
        for (var index = 0; index < tracks.length; index++) {
          final songId = tracks[index]['id']?.toString();
          if (songId == null || songId.isEmpty) continue;
          children.add((
            url: 'https://music.apple.com/${url.storefront}/song/-/$songId',
            outputContext: RipOutputContext(
              playlistName: title ?? url.id,
              playlistCuratorName: artist ?? '',
              playlistIndex: index + 1,
            ),
          ));
        }
        break;
      case AppleMusicUrlType.artist:
        final artistInfo = await _appleMusic.getArtistInfo(
          artistId: url.id,
          storefront: url.storefront,
          language: options.language,
        );
        final resource = _firstData(artistInfo);
        title = _map(resource?['attributes'])?['name']?.toString();
        if (options.includeParticipateSongs) {
          final urls = await _appleMusic.getSongsFromArtist(
            artistId: url.id,
            storefront: url.storefront,
            language: options.language,
          );
          children = urls
              .map((child) => (url: child, outputContext: null))
              .toList(growable: false);
        } else {
          final urls = await _appleMusic.getAlbumsFromArtist(
            artistId: url.id,
            storefront: url.storefront,
            language: options.language,
          );
          children = urls
              .map((child) => (url: child, outputContext: null))
              .toList(growable: false);
        }
        break;
      case AppleMusicUrlType.song:
        throw StateError('Song cannot be expanded');
    }
    if (_cancelled.contains(id)) return;
    _update(
      id,
      status: NativeRipTaskStatus.expanded,
      title: title,
      artist: artist,
      childCount: children.length,
    );
    final claimed = <String>{};
    for (final child in children) {
      if (!claimed.add(child.url)) continue;
      enqueue(
        child.url,
        options,
        outputContext: child.outputContext,
      );
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _pending.clear();
    _cancelled.addAll(_tasks.keys);
    await _changes.close();
  }
}

Map<String, dynamic>? _firstData(Map<String, dynamic> body) {
  final data = body['data'];
  return data is List && data.isNotEmpty ? _map(data.first) : null;
}

List<Map<String, dynamic>> _relationshipData(
  Map<String, dynamic>? resource,
  String name,
) {
  final relationships = _map(resource?['relationships']);
  final relationship = _map(relationships?[name]);
  final data = relationship?['data'];
  return data is List
      ? data.map(_map).whereType<Map<String, dynamic>>().toList()
      : <Map<String, dynamic>>[];
}

bool _relationshipHasNext(Map<String, dynamic>? resource, String name) {
  final relationships = _map(resource?['relationships']);
  return _map(relationships?[name])?['next'] != null;
}

List<String> _songUrls(List<Map<String, dynamic>> rows, String storefront) =>
    rows
        .map((row) => row['id']?.toString())
        .whereType<String>()
        .map((id) => 'https://music.apple.com/$storefront/song/-/$id')
        .toList(growable: false);

Map<String, dynamic>? _map(Object? value) =>
    value is Map<String, dynamic> ? value : null;
