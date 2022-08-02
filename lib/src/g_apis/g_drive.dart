import '../base.dart' as lazy;
import 'g_apis.dart';
import '../http_client.dart';
import 'dart:async';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as gd;

const String errorNotSignIn = "'account' cannot be null(Not sign-in).";

/// ### Lazy [GDrive]
/// - [account] is null during instantiate. However it must be set before calling any calling any method [create], [get], [list], [searchLatest].
class GDrive {
  // --- internal
  GoogleSignInAccount? _account;
  final HttpClient _httpClient = HttpClient();
  gd.DriveApi? _driveApi;

  // --- option
  bool debugLogList = true;

  // --- Getter/Setter
  bool get isSignedIn => _account != null;
  bool get notSignedIn => _account == null;

  /// Hold [GoogleSignInAccount]. Will throw if `null`.
  GoogleSignInAccount get account {
    if (notSignedIn) throw ('$runtimeType:$errorNotSignIn');
    return _account!;
  }

  set account(GoogleSignInAccount? currentUser) {
    if (currentUser == null) throw ('$runtimeType:$errorNotSignIn');
    if (_account != currentUser) _account = currentUser;
    // Setup
    _httpClient.headers = headers;
    _driveApi = gd.DriveApi(_httpClient);
  }

  Future<Map<String, String>> get headers => account.authHeaders;

  HttpClient get lazyGHttpClient {
    if (notSignedIn) throw ('$runtimeType:$errorNotSignIn');
    return _httpClient;
  }

  gd.DriveApi get driveApi {
    if (notSignedIn) throw ('$runtimeType:$errorNotSignIn');
    return _driveApi as gd.DriveApi;
  }

// Methods

  /// [driveApi.files.create] wrapper
  Future<gd.File> create({
    required gd.File file,
    required gd.Media uploadMedia,
  }) async {
    lazy.log('$runtimeType.create():\n${lazy.jsonPretty(file)}');
    return driveApi.files.create(file, uploadMedia: uploadMedia);
  }

  /// [driveApi.files.list] wrapper
  Future<gd.FileList> list({
    String fields = defaultGDriveFields,
    String orderBy = defaultGDriveOrderByModifiedTime,
    String spaces = defaultGDriveSpace,
    String? q,
  }) async =>
      driveApi.files.list(
        $fields: fields,
        orderBy: orderBy,
        q: q,
        spaces: spaces,
      );

  /// [driveApi.files.get] wrapper
  Future<Object> get(
    String fileId, {
    gd.DownloadOptions downloadOptions = defaultGDriveDownloadOptions,
  }) async =>
      driveApi.files.get(fileId, downloadOptions: downloadOptions);

  /// [driveApi.files.del] wrapper
  Future del(String fileId) async => driveApi.files.delete(fileId);

  /// Get the latest copy of a given file
  /// - Throw if error or not found
  Future<gd.File> searchLatest(String name) async {
    var debugPrefix = '$runtimeType.searchLatest()';
    // Get FileList containing name
    String q = "name: '$name'";
    List<gd.File> gFiles = (await list(q: q)).files ?? [];
    if (debugLogList) lazy.log('$debugPrefix:gFiles:\n${lazy.jsonPretty(gFiles)}');
    // Get file meta, which contain id
    if (gFiles.isEmpty) throw ('$name not found.');
    lazy.log('$debugPrefix:gFiles.last:\n${lazy.jsonPretty(gFiles.last)}');
    return gFiles.last;
  }
}
