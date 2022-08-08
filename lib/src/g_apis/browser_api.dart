@JS()
library ext_api;

import 'dart:async';
import 'package:js/js.dart';
import 'package:lazy_collection/lazy_collection.dart' as lazy;

@JS()
@anonymous
class TokenDetails {
  external bool? interactive;
  external List<String>? scopes;
  external factory TokenDetails({bool interactive = true, List<String>? scopes});
}

@JS()
@anonymous
class GetAuthTokenResult {
  external String? token;
  external List? grantedScopes;
  external factory GetAuthTokenResult({token, grantedScopes});
}

// Check Firefox browser api
@JS('identity')
external String get jsIdentity;

// Check Chrome browser api
@JS('chrome.identity')
external String get jsChromeIdentity;

@JS('chrome.identity.getAuthToken')
external jsChromeIdentityGetAuthToken(TokenDetails details, Function callback);

/// return token
class BrowserApi {
  /// Change js callback to dart future
  Future identityGetAuthToken(TokenDetails details) async {
    Completer c = Completer();
    lazy.log('directGetAuthToken()');

    // Javascript callback with 2 parameters
    callback(String? token, List? scopes) {
      // js cannot assign to class object to callback
      // c.complete(JsGetAuthTokenResult(token: token, grantedScopes: scopes));
      // Create map object directly
      c.complete({'token': token, 'grantedScopes': scopes});
    }

    if (jsChromeIdentity != 'undefined') {
      jsChromeIdentityGetAuthToken(details, allowInterop(callback));
    }

    return c.future;
  }
}
