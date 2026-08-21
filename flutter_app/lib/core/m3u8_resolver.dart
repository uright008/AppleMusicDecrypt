import 'dart:convert';

typedef M3u8Loader = Future<String> Function(String url);

enum AudioCodec {
  alac('alac'),
  ec3('ec3'),
  ac3('ac3'),
  aac('aac'),
  aacBinaural('aac-binaural'),
  aacDownmix('aac-downmix'),
  aacLegacy('aac-legacy');

  const AudioCodec(this.value);

  factory AudioCodec.parse(String value) => values.firstWhere(
        (codec) => codec.value == value,
        orElse: () => throw FormatException('Unsupported codec: $value'),
      );

  final String value;
}

final class M3u8Info {
  const M3u8Info({
    required this.uri,
    required this.keys,
    required this.codecId,
    this.bitDepth,
    this.sampleRate,
  });

  final String uri;
  final List<String> keys;
  final String codecId;
  final int? bitDepth;
  final int? sampleRate;
}

final class CodecNotFoundException implements Exception {
  const CodecNotFoundException(this.codec);

  final AudioCodec codec;

  @override
  String toString() => 'Audio codec ${codec.value} was not found';
}

/// Pure-Dart port of `src.mp4.extract_media` and `utils.find_best_codec`.
final class M3u8Resolver {
  const M3u8Resolver({
    this.maxBitDepth = 24,
    this.maxSampleRate = 192000,
  });

  static const prefetchKey = 'skd://itunes.apple.com/P000000000/s1/e1';

  final int maxBitDepth;
  final int maxSampleRate;

  Future<M3u8Info> resolve({
    required String masterUrl,
    required AudioCodec codec,
    required M3u8Loader load,
    bool codecAlternative = false,
    List<AudioCodec> codecPriority = AudioCodec.values,
  }) async {
    final master = await load(masterUrl);
    var selectedCodec = codec;
    var variant = _findBest(masterUrl, master, selectedCodec);
    if (variant == null && codecAlternative) {
      for (final alternative in codecPriority) {
        variant = _findBest(masterUrl, master, alternative);
        if (variant != null) {
          selectedCodec = alternative;
          break;
        }
      }
    }
    if (variant == null) throw CodecNotFoundException(codec);

    final media = await load(variant.uri);
    final mapUri = _mapUri(media);
    if (mapUri == null) {
      throw const FormatException('Media playlist has no EXT-X-MAP URI');
    }
    final keySuffix = switch (selectedCodec) {
      AudioCodec.alac => 'c23',
      AudioCodec.ec3 || AudioCodec.ac3 => 'c24',
      AudioCodec.aac => 'c22',
      AudioCodec.aacBinaural || AudioCodec.aacDownmix => 'c24',
      AudioCodec.aacLegacy => 'c6',
    };
    final keys = <String>[prefetchKey];
    for (final key in _keyUris(media)) {
      if ((key.endsWith(keySuffix) || key.endsWith('c6')) &&
          !keys.contains(key)) {
        keys.add(key);
      }
    }
    return M3u8Info(
      uri: Uri.parse(variant.uri).resolve(mapUri).toString(),
      keys: List.unmodifiable(keys),
      codecId: variant.audioGroup,
      bitDepth: selectedCodec == AudioCodec.alac ? variant.bitDepth : null,
      sampleRate:
          selectedCodec == AudioCodec.alac ? variant.sampleRate : null,
    );
  }

  _Variant? _findBest(String masterUrl, String source, AudioCodec codec) {
    final mediaByGroup = <String, Map<String, String>>{};
    for (final line in const LineSplitter().convert(source)) {
      if (!line.startsWith('#EXT-X-MEDIA:')) continue;
      final attributes = _attributes(line.substring(line.indexOf(':') + 1));
      final group = attributes['GROUP-ID'];
      if (attributes['TYPE'] == 'AUDIO' && group != null) {
        mediaByGroup[group] = attributes;
      }
    }

    final lines = const LineSplitter().convert(source);
    final variants = <_Variant>[];
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      if (!line.startsWith('#EXT-X-STREAM-INF:')) continue;
      final attributes = _attributes(line.substring(line.indexOf(':') + 1));
      final group = attributes['AUDIO'];
      if (group == null || !_codecPattern(codec).hasMatch(group)) continue;
      String? relativeUri;
      for (var cursor = index + 1; cursor < lines.length; cursor++) {
        final candidate = lines[cursor].trim();
        if (candidate.isEmpty || candidate.startsWith('#')) continue;
        relativeUri = candidate;
        break;
      }
      if (relativeUri == null) continue;
      final media = mediaByGroup[group] ?? const {};
      final bitDepth = int.tryParse(
        media['BIT-DEPTH'] ?? media['bit_depth'] ?? '',
      );
      final sampleRate = int.tryParse(
        media['SAMPLE-RATE'] ?? media['sample_rate'] ?? '',
      );
      if (codec == AudioCodec.alac &&
          ((bitDepth ?? 0) > maxBitDepth ||
              (sampleRate ?? 0) > maxSampleRate)) {
        continue;
      }
      variants.add(_Variant(
        uri: Uri.parse(masterUrl).resolve(relativeUri).toString(),
        audioGroup: group,
        averageBandwidth: int.tryParse(
              attributes['AVERAGE-BANDWIDTH'] ?? '',
            ) ??
            int.tryParse(attributes['BANDWIDTH'] ?? '') ??
            0,
        bitDepth: bitDepth,
        sampleRate: sampleRate,
      ));
    }
    variants.sort(
      (left, right) => right.averageBandwidth.compareTo(left.averageBandwidth),
    );
    return variants.isEmpty ? null : variants.first;
  }

  static RegExp _codecPattern(AudioCodec codec) => switch (codec) {
        AudioCodec.ec3 => RegExp(r'^audio-(atmos|ec3)-\d{4}$'),
        AudioCodec.ac3 => RegExp(r'^audio-ac3-\d{3}$'),
        AudioCodec.alac => RegExp(r'^audio-alac-stereo-\d{5,6}-\d{2}$'),
        AudioCodec.aacBinaural => RegExp(r'^audio-stereo-\d{3}-binaural$'),
        AudioCodec.aacDownmix => RegExp(r'^audio-stereo-\d{3}-downmix$'),
        AudioCodec.aac || AudioCodec.aacLegacy =>
          RegExp(r'^audio-stereo-\d{3}$'),
      };

  static Map<String, String> _attributes(String value) {
    final result = <String, String>{};
    final pattern = RegExp(r'([A-Za-z0-9_-]+)=("[^"]*"|[^,]*)');
    for (final match in pattern.allMatches(value)) {
      final raw = match.group(2) ?? '';
      result[match.group(1)!] =
          raw.startsWith('"') && raw.endsWith('"')
              ? raw.substring(1, raw.length - 1)
              : raw;
    }
    return result;
  }

  static String? _mapUri(String source) {
    for (final line in const LineSplitter().convert(source)) {
      if (!line.startsWith('#EXT-X-MAP:')) continue;
      return _attributes(line.substring(line.indexOf(':') + 1))['URI'];
    }
    return null;
  }

  static Iterable<String> _keyUris(String source) sync* {
    for (final line in const LineSplitter().convert(source)) {
      if (!line.startsWith('#EXT-X-KEY:')) continue;
      final uri = _attributes(line.substring(line.indexOf(':') + 1))['URI'];
      if (uri != null && RegExp(r'^skd?://').hasMatch(uri)) yield uri;
    }
  }
}

final class _Variant {
  const _Variant({
    required this.uri,
    required this.audioGroup,
    required this.averageBandwidth,
    required this.bitDepth,
    required this.sampleRate,
  });

  final String uri;
  final String audioGroup;
  final int averageBandwidth;
  final int? bitDepth;
  final int? sampleRate;
}
