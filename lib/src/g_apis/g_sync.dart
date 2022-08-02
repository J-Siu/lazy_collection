import '../base.dart' as lazy;
import '../extensions/string.dart';
import 'dart:async';
import 'g_apis.dart';
import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as gd;

/// ### Lazy [GSync]
/// - Syncing single file with Google Drive `appData` space
/// - A bridge between [GDrive], [GSignIn] and local data/content
class GSync {
  // --- Internal

  DateTime _lastSync = lazy.dayZero;
  Timer? _timer;
  bool _enableAutoSync = false;
  bool _enableSync = false;

  // --- Output

  /// `true` on [sync] error.
  /// `false` on [sync] success(no error).
  final ValueNotifier<bool> syncError = ValueNotifier<bool>(false);

  /// `true` when [sync] start
  /// `false` when [sync] stop
  final ValueNotifier<bool> syncing = ValueNotifier<bool>(false);

  // --- Input

  /// A Lazy [GSignIn] instance, initialized with the desired [scope]
  /// - [GSignIn] default [scope] is [DriveApi.driveAppdataScope] | https://www.googleapis.com/auth/drive.appdata
  final GSignIn lazyGSignIn;

  /// A Lazy [GDrive] instance
  /// - [appDataFolder] (default) is used for [GDrive]'s [spaces]
  final GDrive lazyGDrive;

  /// `Listenable` to trigger [sync] when [enableAutoSync] is `true`
  /// - Value/content of the `Listenable` is not being used.
  Listenable? localSaveNotifier;

  /// Should return last local save time
  DateTime Function()? getLocalSaveTime;

  /// Should return the content in [String] to be saved remotely
  String Function()? getLocalContent;

  /// Should return the remote filename in [String] to be used remotely
  String Function()? getFilename;

  /// Call when content is downloaded from remote
  /// - [String] : content of the download
  /// - [DateTime]? : remote last save time. Can be use to set local save time when applying content locally.
  void Function(String, DateTime?)? setContent;

  GSync({
    required this.lazyGDrive,
    required this.lazyGSignIn,
    this.getLocalContent,
    this.getFilename,
    this.getLocalSaveTime,
    this.localSaveNotifier,
    this.setContent,
  });

  /// Return last sync `DateTime`
  DateTime get lastSync => _lastSync;

  /// Return last save time of content/data saved locally (eg. in [shared_preferences])
  ///
  /// [getLocalSaveTime] must be set
  DateTime get localSaveTime {
    assert(getLocalSaveTime != null);
    return getLocalSaveTime!();
  }

  /// Return filename used when saving to Google Drive
  ///
  /// [getFilename] must be set
  String get filename {
    assert(getFilename != null);
    return getFilename!();
  }

  /// Return content to be saved to Google Drive
  ///
  /// [getLocalContent] must be set
  String get content {
    assert(getLocalContent != null);
    return getLocalContent!();
  }

  // --- Options

  /// Auto sync interval, time between [lastSync] till next sync
  int autoSyncIntervalMin = 10;

  /// [enableSync] control listening to localSaveNotifier
  ///
  /// - Start listening if `true`
  /// - Stop listening if `false`
  ///
  /// Will trigger [sync] one time when changing from `false` to `true`
  bool get enableSync => _enableSync;
  set enableSync(bool v) {
    assert(localSaveNotifier != null);
    if (_enableSync != v) {
      _enableSync = v;
      if (v) {
        // Enable Sites preference saving to trigger sync()
        localSaveNotifier!.addListener(() => sync());
        // Sync once when enable
        sync();
      } else {
        // Disable Sites preference saving to trigger sync()
        localSaveNotifier!.removeListener(() => sync());
      }
    }
  }

  /// [enableAutoSync] control period sync with interval = [autoSyncIntervalMin]
  ///
  /// - If [enableSync] == false, it will have no actual effect, as [sync] does check enable
  /// - interval always count from [lastSync].
  bool get enableAutoSync => _enableAutoSync;
  set enableAutoSync(bool v) {
    if (_enableAutoSync != v) {
      _enableAutoSync = v;
      if (v) {
        // add 30min listener
        _timer = Timer.periodic(const Duration(minutes: 1), (timer) {
          Duration sinceLastSync = DateTime.now().difference(_lastSync);
          if (sinceLastSync.inMinutes > autoSyncIntervalMin) {
            sync();
          }
        });
      } else {
        // remove listener
        _timer?.cancel();
      }
    }
  }

  /// Most of the time triggered by [localSaveNotifier].
  ///
  /// - Trigger sign-in if necessary. Handle by [GSignIn]
  /// - Initiate download from remote if [getLocalSaveTime] < google drive save time
  /// - Initiate upload to remote if [getLocalSaveTime] > google drive save time
  /// - Auto skip(no error) if [enableSync] is `false`, except when [forceDownload] or [forceUpload] is `true`
  ///
  /// - [syncing] : will be set to `true` at beginning and to `false` when done.
  /// - [syncError] : will be set to `true` on error. Reset(to `false`) on successful sync.
  ///
  /// - [forceDownload] : when set to `true`, will initiate download from remote regardless of save time on both sides
  /// - [forceUpload] : when set to `true`, will initiate upload to remote regardless of save time on both sides
  ///
  /// Assertion: [forceDownload] or [forceUpload] cannot be `true` in the same call.
  Future sync({
    bool forceDownload = false,
    bool forceUpload = false,
  }) async {
    String debugPrefix = '$runtimeType.sync()';
    assert(forceDownload != true && forceUpload != true);
    if (enableSync) {
      lazy.log(debugPrefix);
      syncing.value = true;
      _lastSync = DateTime.now();
      try {
        // Login + setup GDrive
        lazyGDrive.account = await lazyGSignIn.signInHandler();
        lazy.log('$debugPrefix:done sign-in');
        // remote info
        String q = "name: '$filename'";
        var gFileList = await lazyGDrive.list(orderBy: defaultGDriveOrderByModifiedTime, q: q);
        lazy.log('$debugPrefix:$gFileList');
        List<gd.File> gFiles = gFileList.files ?? [];
        lazy.log('$debugPrefix:${gFiles.length}');
        int lastSaveMillisecondsGDrive = lazy.dayZero.millisecondsSinceEpoch;
        if (gFiles.isNotEmpty) {
          lastSaveMillisecondsGDrive = (gFiles.last.modifiedTime ?? lazy.dayZero).millisecondsSinceEpoch;
          lazy.log('$debugPrefix:gFiles.last:\n${lazy.jsonPretty(gFiles.last)}');
          lazy.log('$debugPrefix:lastSaveTimeGDrive:${gFiles.last.modifiedTime!.toUtc().toIso8601String()}');
        }
        // Local info
        int lastSaveMillisecondsLocal = localSaveTime.millisecondsSinceEpoch;
        lazy.log('$debugPrefix:lastSaveTimeLocal :${localSaveTime.toUtc().toIso8601String()}');
        // Sync logic
        if (gFiles.isNotEmpty && (forceDownload || lastSaveMillisecondsGDrive > lastSaveMillisecondsLocal)) {
          // remote is newer -> download
          _download(gFiles.last);
        } else if (gFiles.isEmpty || lastSaveMillisecondsGDrive < lastSaveMillisecondsLocal) {
          // no remote or local is newer -> upload
          _upload();
        } else {
          lazy.log('$debugPrefix:already up to date');
        }
        // clean up
        await _cleanUpOldFiles(gFiles);
        syncError.value = false;
        syncing.value = false;
      } catch (e) {
        syncError.value = true;
        syncing.value = false;
        lazy.log('$debugPrefix:catch:$e');
      }
    } else {
      lazy.log('$debugPrefix:called while disabled');
    }
  }

  /// _download()
  ///
  /// Download also apply data to [sites]
  Future _download(gd.File gFile) async {
    assert(setContent != null);
    String debugPrefix = '$runtimeType._download()';
    lazy.log(debugPrefix);

    try {
      String content = '';
      lazyGDrive.account = await lazyGSignIn.signInHandler();
      var media = await lazyGDrive.get(gFile.id!, downloadOptions: gd.DownloadOptions.fullMedia);
      if (media is gd.Media) {
        content = await lazy.mediaStreamToString(media.stream);
        lazy.log('$debugPrefix:size:${content.length} byte');
      } else {
        throw ('$debugPrefix:File is not Google DriveApi Media.');
      }
      // Apply to sites
      setContent!(content, gFile.modifiedTime);
    } catch (e) {
      lazy.log('$debugPrefix:catch:$e');
    }
  }

  Future _upload() async {
    String debugPrefix = '$runtimeType._upload()';
    lazy.log(debugPrefix);

    try {
      // Login + setup GDrive
      lazyGDrive.account = await lazyGSignIn.signInHandler();
      // File meta + content
      var file = gDriveFileMeta(name: filename, modifiedTime: localSaveTime);
      var media = content.toMedia();
      lazy.log('$debugPrefix:size:${media.length}byte');
      // Upload
      var result = await lazyGDrive.create(file: file, uploadMedia: media);
      lazy.log('$debugPrefix:result(should be empty):\n${lazy.jsonPretty(result)}');
    } catch (e) {
      lazy.log('$debugPrefix:catch:$e');
    }
  }

  Future _cleanUpOldFiles(List<gd.File> gFiles, {int keepNumberOfLatest = 5}) async {
    var debugPrefix = '$runtimeType._cleanUpOldFiles()';
    if (gFiles.length > keepNumberOfLatest) {
      for (var gFile in gFiles.sublist(0, gFiles.length - keepNumberOfLatest)) {
        if (gFile.id != null) {
          lazyGDrive.del(gFile.id!);
          lazy.log('$debugPrefix: deleted $filename id: ${gFile.id}');
        }
      }
    }
  }
}
