class ServerStatus {
  const ServerStatus({
    required this.ready,
    required this.regions,
    required this.manager,
    required this.authenticatedUsers,
  });

  factory ServerStatus.fromJson(Map<String, dynamic> json) => ServerStatus(
        ready: json['ready'] as bool? ?? false,
        regions: (json['regions'] as List<dynamic>? ?? const [])
            .map((item) => item.toString())
            .toList(growable: false),
        manager: json['manager']?.toString() ?? '',
        authenticatedUsers:
            (json['authenticatedUsers'] as List<dynamic>? ?? const [])
                .map((item) => item.toString())
                .toList(growable: false),
      );

  final bool ready;
  final List<String> regions;
  final String manager;
  final List<String> authenticatedUsers;
}

class AuthResult {
  const AuthResult({
    required this.status,
    required this.authenticatedUsers,
    this.username,
  });

  factory AuthResult.fromJson(Map<String, dynamic> json) => AuthResult(
        status: json['status']?.toString() ?? 'signed_out',
        username: json['username']?.toString(),
        authenticatedUsers:
            (json['authenticatedUsers'] as List<dynamic>? ?? const [])
                .map((item) => item.toString())
                .toList(growable: false),
      );

  final String status;
  final String? username;
  final List<String> authenticatedUsers;

  bool get requiresTwoFactor => status == 'requires_2fa';
  bool get isAuthenticated => status == 'authenticated';
}

class DownloadTask {
  const DownloadTask({
    required this.adamId,
    required this.status,
    this.title,
    this.artist,
    this.album,
    this.error,
  });

  factory DownloadTask.fromJson(Map<String, dynamic> json) => DownloadTask(
        adamId: json['adamId']?.toString() ?? '',
        status: json['status']?.toString() ?? 'WAITING',
        title: json['title']?.toString(),
        artist: json['artist']?.toString(),
        album: json['album']?.toString(),
        error: json['error']?.toString(),
      );

  final String adamId;
  final String status;
  final String? title;
  final String? artist;
  final String? album;
  final String? error;

  bool get canCancel =>
      status == 'WAITING' ||
      status == 'DOWNLOADING' ||
      status == 'DECRYPTING';
}

class TaskSnapshot {
  const TaskSnapshot({
    required this.tasks,
    required this.downloadSpeed,
    required this.decryptSpeed,
    required this.running,
  });

  factory TaskSnapshot.fromJson(Map<String, dynamic> json) => TaskSnapshot(
        tasks: (json['tasks'] as List<dynamic>? ?? const [])
            .map((item) => DownloadTask.fromJson(item as Map<String, dynamic>))
            .toList(growable: false),
        downloadSpeed: json['downloadSpeed']?.toString() ?? '0.00 kB/s',
        decryptSpeed: json['decryptSpeed']?.toString() ?? '0.00 kB/s',
        running: json['running'] as int? ?? 0,
      );

  final List<DownloadTask> tasks;
  final String downloadSpeed;
  final String decryptSpeed;
  final int running;
}
