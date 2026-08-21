enum AppleMusicUrlType { song, album, playlist, artist }

final class AppleMusicUrl {
  const AppleMusicUrl({
    required this.url,
    required this.storefront,
    required this.type,
    required this.id,
  });

  static AppleMusicUrl? tryParse(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'music.apple.com' ||
        uri.pathSegments.length < 4) {
      return null;
    }
    final storefront = uri.pathSegments[0];
    if (!RegExp(r'^[A-Za-z]{2}$').hasMatch(storefront)) return null;
    final type = switch (uri.pathSegments[1]) {
      'song' => AppleMusicUrlType.song,
      'album' => AppleMusicUrlType.album,
      'playlist' => AppleMusicUrlType.playlist,
      'artist' => AppleMusicUrlType.artist,
      _ => null,
    };
    if (type == null) return null;

    var id = uri.pathSegments.last;
    var resolvedType = type;
    if (type == AppleMusicUrlType.album) {
      final songId = uri.queryParameters['i'];
      if (songId != null && songId.isNotEmpty) {
        id = songId;
        resolvedType = AppleMusicUrlType.song;
      }
    }
    final validId = resolvedType == AppleMusicUrlType.playlist
        ? RegExp(r'^pl\.[A-Za-z0-9.-]+$').hasMatch(id)
        : RegExp(r'^\d+$').hasMatch(id);
    if (!validId) return null;

    return AppleMusicUrl(
      url: value.trim(),
      storefront: storefront.toLowerCase(),
      type: resolvedType,
      id: id,
    );
  }

  final String url;
  final String storefront;
  final AppleMusicUrlType type;
  final String id;
}
