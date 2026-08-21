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
}
