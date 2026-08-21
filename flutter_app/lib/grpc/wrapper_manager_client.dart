import 'package:grpc/grpc.dart' as grpc;

import 'manager_messages.dart';

final class WrapperManagerServiceClient extends grpc.Client {
  WrapperManagerServiceClient(
    super.channel, {
    super.options,
    super.interceptors,
  });

  static final _status = grpc.ClientMethod<EmptyMessage, StatusReply>(
    '/manager.v1.WrapperManagerService/Status',
    (value) => value.writeToBuffer(),
    StatusReply.fromBuffer,
  );
  static final _login = grpc.ClientMethod<LoginRequest, LoginReply>(
    '/manager.v1.WrapperManagerService/Login',
    (value) => value.writeToBuffer(),
    LoginReply.fromBuffer,
  );
  static final _logout = grpc.ClientMethod<LogoutRequest, LogoutReply>(
    '/manager.v1.WrapperManagerService/Logout',
    (value) => value.writeToBuffer(),
    LogoutReply.fromBuffer,
  );
  static final _decrypt = grpc.ClientMethod<DecryptRequest, DecryptReply>(
    '/manager.v1.WrapperManagerService/Decrypt',
    (value) => value.writeToBuffer(),
    DecryptReply.fromBuffer,
  );
  static final _m3u8 = grpc.ClientMethod<M3U8Request, M3U8Reply>(
    '/manager.v1.WrapperManagerService/M3U8',
    (value) => value.writeToBuffer(),
    M3U8Reply.fromBuffer,
  );
  static final _lyrics = grpc.ClientMethod<LyricsRequest, LyricsReply>(
    '/manager.v1.WrapperManagerService/Lyrics',
    (value) => value.writeToBuffer(),
    LyricsReply.fromBuffer,
  );
  static final _license = grpc.ClientMethod<LicenseRequest, LicenseReply>(
    '/manager.v1.WrapperManagerService/License',
    (value) => value.writeToBuffer(),
    LicenseReply.fromBuffer,
  );
  static final _webPlayback =
      grpc.ClientMethod<WebPlaybackRequest, WebPlaybackReply>(
    '/manager.v1.WrapperManagerService/WebPlayback',
    (value) => value.writeToBuffer(),
    WebPlaybackReply.fromBuffer,
  );

  grpc.ResponseFuture<StatusReply> status({grpc.CallOptions? options}) =>
      $createUnaryCall(_status, const EmptyMessage(), options: options);

  grpc.ResponseStream<LoginReply> login(
    Stream<LoginRequest> requests, {
    grpc.CallOptions? options,
  }) =>
      $createStreamingCall(_login, requests, options: options);

  grpc.ResponseFuture<LogoutReply> logout(
    LogoutRequest request, {
    grpc.CallOptions? options,
  }) =>
      $createUnaryCall(_logout, request, options: options);

  grpc.ResponseStream<DecryptReply> decrypt(
    Stream<DecryptRequest> requests, {
    grpc.CallOptions? options,
  }) =>
      $createStreamingCall(_decrypt, requests, options: options);

  grpc.ResponseFuture<M3U8Reply> m3u8(
    M3U8Request request, {
    grpc.CallOptions? options,
  }) =>
      $createUnaryCall(_m3u8, request, options: options);

  grpc.ResponseFuture<LyricsReply> lyrics(
    LyricsRequest request, {
    grpc.CallOptions? options,
  }) =>
      $createUnaryCall(_lyrics, request, options: options);

  grpc.ResponseFuture<LicenseReply> license(
    LicenseRequest request, {
    grpc.CallOptions? options,
  }) =>
      $createUnaryCall(_license, request, options: options);

  grpc.ResponseFuture<WebPlaybackReply> webPlayback(
    WebPlaybackRequest request, {
    grpc.CallOptions? options,
  }) =>
      $createUnaryCall(_webPlayback, request, options: options);
}
