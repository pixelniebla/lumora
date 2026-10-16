import 'package:http/http.dart' as http;

/// One shared client: keeps connections alive instead of reopening one per request.
final http.Client sharedClient = _UaClient(http.Client());

class _UaClient extends http.BaseClient {
  final http.Client _inner;
  _UaClient(this._inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.putIfAbsent('User-Agent', () => 'VLC/3.0.20 LibVLC/3.0.20');
    return _inner.send(request);
  }
}
