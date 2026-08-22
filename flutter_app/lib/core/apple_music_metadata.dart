import 'rip_preparation.dart';

final class AppleMusicMetadata {
  const AppleMusicMetadata({
    required this.songId,
    required this.title,
    required this.artist,
    required this.albumId,
    required this.albumArtist,
    required this.album,
    required this.trackNumber,
    required this.trackTotal,
    required this.discNumber,
    required this.discTotal,
    required this.genres,
    required this.rating,
    required this.cover,
    required this.coverIsPng,
    required this.outputContext,
    this.albumCreated,
    this.composer,
    this.created,
    this.lyrics,
    this.copyright,
    this.recordCompany,
    this.upc,
    this.isrc,
    this.artistId,
  });

  factory AppleMusicMetadata.fromPrepared(PreparedSong prepared) {
    final songAttributes = _map(prepared.song['attributes']) ?? const {};
    final albumResource = _firstData(prepared.album);
    final albumAttributes = _map(albumResource?['attributes']) ?? const {};
    final songRelationships = _map(prepared.song['relationships']);
    final albumRelationship = _firstRelationship(songRelationships, 'albums');
    final artistRelationship = _firstRelationship(songRelationships, 'artists');
    final albumRelationshipAttributes =
        _map(albumRelationship?['attributes']) ?? const {};

    final title = _text(songAttributes['name']) ?? prepared.url.id;
    final artist = _text(songAttributes['artistName']) ?? 'Unknown Artist';
    final album = _text(songAttributes['albumName']) ??
        _text(albumAttributes['name']) ??
        _text(albumRelationshipAttributes['name']) ??
        'Unknown Album';
    final albumArtist = _text(albumAttributes['artistName']) ??
        _text(albumRelationshipAttributes['artistName']) ??
        artist;
    final trackNumber = _integer(songAttributes['trackNumber']) ?? 1;
    final discNumber = _integer(songAttributes['discNumber']) ?? 1;
    var trackTotal = trackNumber;
    var discTotal = discNumber;
    final albumRelationships = _map(albumResource?['relationships']);
    final trackRelationship = _map(albumRelationships?['tracks']);
    final tracks = trackRelationship?['data'];
    if (tracks is List) {
      for (final row in tracks) {
        final attributes = _map(_map(row)?['attributes']);
        final rowDisc = _integer(attributes?['discNumber']);
        final rowTrack = _integer(attributes?['trackNumber']);
        if (rowDisc != null && rowDisc > discTotal) discTotal = rowDisc;
        if (rowDisc == discNumber &&
            rowTrack != null &&
            rowTrack > trackTotal) {
          trackTotal = rowTrack;
        }
      }
    }

    final recordLabel = _text(albumAttributes['recordLabel']) ??
        _text(_map(_firstRelationship(
          albumRelationships,
          'record-labels',
        )?['attributes'])?['name']);
    final genreValues = songAttributes['genreNames'];
    final genres = genreValues is List
        ? genreValues
            .map(_text)
            .whereType<String>()
            .toList(growable: false)
        : const <String>[];
    final rating = switch (_text(songAttributes['contentRating'])) {
      'explicit' => 1,
      'clean' => 2,
      _ => 0,
    };
    final cover = prepared.cover;
    final coverIsPng = cover != null &&
        cover.length >= 8 &&
        cover[0] == 0x89 &&
        cover[1] == 0x50 &&
        cover[2] == 0x4e &&
        cover[3] == 0x47;

    return AppleMusicMetadata(
      songId: prepared.url.id,
      title: title,
      artist: artist,
      albumId: _text(albumResource?['id']) ??
          _text(albumRelationship?['id']) ??
          '',
      albumArtist: albumArtist,
      album: album,
      albumCreated: _text(albumAttributes['releaseDate']) ??
          _text(albumRelationshipAttributes['releaseDate']),
      composer: _text(songAttributes['composerName']),
      created: _text(songAttributes['releaseDate']),
      trackNumber: trackNumber,
      trackTotal: trackTotal,
      discNumber: discNumber,
      discTotal: discTotal,
      lyrics: ttmlToLrc(prepared.lyrics),
      cover: cover,
      coverIsPng: coverIsPng,
      genres: genres,
      copyright: _text(albumAttributes['copyright']) ??
          _text(albumRelationshipAttributes['copyright']),
      recordCompany:
          recordLabel ?? _text(albumRelationshipAttributes['recordLabel']),
      upc: _text(albumAttributes['upc']) ??
          _text(albumRelationshipAttributes['upc']),
      isrc: _text(songAttributes['isrc']),
      rating: rating,
      artistId: _text(artistRelationship?['id']),
      outputContext: prepared.outputContext,
    );
  }

  final String songId;
  final String title;
  final String artist;
  final String albumId;
  final String albumArtist;
  final String album;
  final String? albumCreated;
  final String? composer;
  final List<String> genres;
  final String? created;
  final int trackNumber;
  final int trackTotal;
  final int discNumber;
  final int discTotal;
  final String? lyrics;
  final List<int>? cover;
  final bool coverIsPng;
  final String? copyright;
  final String? recordCompany;
  final String? upc;
  final String? isrc;
  final int rating;
  final String? artistId;
  final RipOutputContext? outputContext;

  String get relativePath {
    final playlist = outputContext;
    if (playlist != null) {
      return 'AppleMusicDecrypt/playlists/${safePathPart(playlist.playlistName)}';
    }
    return 'AppleMusicDecrypt/${safePathPart(albumArtist)}/${safePathPart(album)}';
  }

  String get fileBaseName {
    final playlist = outputContext;
    if (playlist != null) {
      final index = playlist.playlistIndex.toString().padLeft(2, '0');
      return safeFileName('$index. $artist - $title');
    }
    final track = trackNumber.toString().padLeft(2, '0');
    return safeFileName('$discNumber-$track $title');
  }

  static String safeFileName(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[<>:"/\\|?*\u0000-\u001f]'), '')
        .trim();
    return cleaned.isEmpty ? 'Unknown Song' : cleaned;
  }

  static String safePathPart(String value) {
    final cleaned = safeFileName(value).replaceFirst(RegExp(r'[. ]+$'), '');
    return cleaned.isEmpty ? 'Unknown' : cleaned;
  }
}

String? ttmlToLrc(String? source) {
  if (source == null || source.trim().isEmpty) return null;
  final lines = <String>[];
  final paragraph = RegExp(
    r'<p\b([^>]*)>(.*?)</p>',
    caseSensitive: false,
    dotAll: true,
  );
  for (final match in paragraph.allMatches(source)) {
    final attributes = match.group(1) ?? '';
    final begin = RegExp(
      r'\bbegin\s*=\s*["\x27]([^"\x27]+)',
      caseSensitive: false,
    ).firstMatch(attributes)?.group(1);
    final timestamp = _lrcTimestamp(begin);
    if (timestamp == null) continue;
    final text = _decodeXml(
      (match.group(2) ?? '').replaceAll(RegExp(r'<[^>]+>'), ''),
    ).trim();
    if (text.isNotEmpty) lines.add('[$timestamp]$text');
  }
  return lines.isEmpty ? null : lines.join('\n');
}

String? _lrcTimestamp(String? value) {
  if (value == null) return null;
  final parts = value.replaceFirst(RegExp(r's$'), '').split(':');
  final numbers = parts.map(double.tryParse).toList(growable: false);
  if (numbers.any((number) => number == null)) return null;
  double seconds;
  if (numbers.length == 3) {
    seconds = numbers[0]! * 3600 + numbers[1]! * 60 + numbers[2]!;
  } else if (numbers.length == 2) {
    seconds = numbers[0]! * 60 + numbers[1]!;
  } else if (numbers.length == 1) {
    seconds = numbers[0]!;
  } else {
    return null;
  }
  final minutes = seconds ~/ 60;
  final remaining = seconds - minutes * 60;
  final hundredths = (remaining * 100).round().clamp(0, 5999);
  final secondPart = (hundredths ~/ 100).toString().padLeft(2, '0');
  final fractionPart = (hundredths % 100).toString().padLeft(2, '0');
  return '${minutes.toString().padLeft(2, '0')}:$secondPart.$fractionPart';
}

String _decodeXml(String value) => value
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'");

Map<String, dynamic>? _map(Object? value) =>
    value is Map<String, dynamic> ? value : null;

Map<String, dynamic>? _firstData(Map<String, dynamic> body) {
  final data = body['data'];
  return data is List && data.isNotEmpty ? _map(data.first) : null;
}

Map<String, dynamic>? _firstRelationship(
  Map<String, dynamic>? relationships,
  String name,
) {
  final data = _map(relationships?[name])?['data'];
  return data is List && data.isNotEmpty ? _map(data.first) : null;
}

String? _text(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

int? _integer(Object? value) =>
    value is int ? value : int.tryParse(value?.toString() ?? '');
