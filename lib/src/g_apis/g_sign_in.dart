import '../base.dart' as lazy;
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as gd;

/// ### Lazy [GSignInMsg]
/// - [account] : [GoogleSignIn.currentUser]
/// - [status] == ([account] != `null`)
class GSignInMsg {
  bool get status => (account != null);
  GoogleSignInAccount? account;
  GSignInMsg({this.account});
}

/// ### Lazy [GSignIn]
/// - [GoogleSignIn] wrapper class with a [signInHandler]
/// - Build in listener for account status change, and a [GSignInMsg] notifier [msg]
class GSignIn {
  // --- Internal
  final GoogleSignIn _googleSignIn;

  // --- Input

  /// [scopes] of sign-in
  final List<String> scopes;

  /// Google OAuth [clientId]. Only work on Flutter web.
  /// - More information: https://github.com/flutter/plugins/tree/main/packages/google_sign_in/google_sign_in_web
  String? clientId;

  // --- Output

  /// A [GSignInMsg] notifier. Trigger when account status changes.
  ValueNotifier<GSignInMsg> msg = ValueNotifier<GSignInMsg>(GSignInMsg());

  GSignIn({
    this.clientId,
    this.scopes = const [gd.DriveApi.driveAppdataScope],
  }) : _googleSignIn = GoogleSignIn(
          clientId: clientId,
          scopes: scopes,
        ) {
    _googleSignIn.onCurrentUserChanged.listen((account) {
      msg.value = GSignInMsg(account: account);
    });
  }

  /// Return [GoogleSignIn.currentUser], same as [currentUser]
  GoogleSignInAccount? get account => _googleSignIn.currentUser;

  /// Return [GoogleSignIn.currentUser], same as [account]
  GoogleSignInAccount? get currentUser => _googleSignIn.currentUser;

  /// Return [GoogleSign.onCurrentUserChanged]
  Stream<GoogleSignInAccount?> get onCurrentUserChanged => _googleSignIn.onCurrentUserChanged;

  /// - Return [account] never null
  /// - Perform sign-in only if [account] is null;
  /// - Throw on error or sign-in fail
  Future signInHandler({
    Future Function(GoogleSignInAccount?)? onValue,
    Future Function(Object?)? onError,
    bool reAuthenticate = false,
    bool suppressErrors = true,
    bool silentOnly = false,
  }) async {
    var debugPrefix = '$runtimeType.signInHandler()';
    try {
      if (account == null) {
        lazy.log('$debugPrefix:_googleSignIn.signInSilently()');
        await _googleSignIn
            .signInSilently(
              reAuthenticate: reAuthenticate,
              suppressErrors: suppressErrors,
            )
            .onError((e, _) => throw ('_googleSignIn.signInSilently(): $e'));
      }
      // Try pop-up
      if (account == null && !silentOnly) {
        lazy.log('$debugPrefix:_googleSignIn.signIn()');
        await _googleSignIn.signIn().onError((e, _) => throw ('_googleSignIn.signIn(): $e'));
      }
      // Sign-in failed -> throw
      if (account == null) {
        throw ('Sign-in failed');
      }
      // Sign-in successful
      if (onValue == null) {
        return account!;
      } else {
        return onValue(account!);
      }
    } catch (e) {
      if (onError == null) {
        throw '$debugPrefix:catch:$e';
      } else {
        return onError('$debugPrefix:catch:$e');
      }
    }
  }

  /// - [account] return should always be null
  /// - Throw on sign-out error
  Future signOutHandler({
    Future Function(GoogleSignInAccount?)? onValue,
    Future Function(Object?)? onError,
  }) async {
    var debugPrefix = '$runtimeType.signOutHandler()';
    try {
      await _googleSignIn.signOut().onError((e, _) => throw ('_googleSignIn.signOut(): $e'));
      if (onValue == null) {
        return account;
      } else {
        return onValue(account);
      }
    } catch (error) {
      if (onError == null) {
        throw '$debugPrefix:catch:$error';
      } else {
        return onError(error);
      }
    }
  }
}
