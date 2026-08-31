import 'dart:async';
import 'dart:convert';

import 'package:film2watch/components/movies/trailer_dialog.dart';
import 'package:film2watch/providers/tmdb_provider.dart';
import 'package:film2watch/screens/movies/movie_detail_screen.dart';
import 'package:film2watch/services/tmdb_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

/// Fake-Implementierung von `WebViewPlatform`, exakt nach dem offiziellen
/// Testmuster des `webview_flutter`-Pakets selbst
/// (`example/test/main_test.dart`) - `youtube_player_flutter` rendert
/// intern eine echte `WebView`, die ohne eine registrierte
/// `WebViewPlatform.instance` in Widget-Tests abstürzt. Löst dadurch nie
/// echte WebView-/YouTube-Requests aus.
class _FakeWebViewPlatform extends WebViewPlatform {
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) =>
      _FakeWebViewController(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) =>
      _FakeWebViewWidget(params);

  @override
  PlatformWebViewCookieManager createPlatformCookieManager(
    PlatformWebViewCookieManagerCreationParams params,
  ) =>
      _FakeCookieManager(params);

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) =>
      _FakeNavigationDelegate(params);
}

class _FakeWebViewController extends PlatformWebViewController {
  _FakeWebViewController(super.params) : super.implementation();

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setBackgroundColor(Color color) async {}

  @override
  Future<void> setPlatformNavigationDelegate(PlatformNavigationDelegate handler) async {}

  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams javaScriptChannelParams) async {
    // Simuliert sofort das "Ready"-Event, das die echte WebView normalerweise
    // erst nach dem Laden des YouTube-iFrames per JS-Channel meldet. Ohne
    // dieses Event wartet `JsBridge._waitReady()` beim Dialog-Dispose
    // (`YoutubePlayerController.close()` -> `stopVideo()`) bis zu 30s auf ein
    // Event, das in dieser Fake-Umgebung nie eintrifft, und hinterlässt
    // einen offenen Timer, den `flutter_test` als Fehler meldet.
    // `JavaScriptChannelParams.name` entspricht der `playerId`, mit der der
    // echte Player seine Nachrichten taggt (siehe
    // `YoutubePlayerController`: `..addJavaScriptChannel(playerId, ...)`).
    scheduleMicrotask(() {
      javaScriptChannelParams.onMessageReceived(
        JavaScriptMessage(
          message: jsonEncode({'playerId': javaScriptChannelParams.name, 'Ready': 1}),
        ),
      );
    });
  }

  @override
  Future<void> loadRequest(LoadRequestParams params) async {}

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {}

  @override
  Future<void> enableZoom(bool enabled) async {}

  @override
  Future<String?> currentUrl() async => null;

  @override
  Future<void> setUserAgent(String? userAgent) async {}

  @override
  Future<void> runJavaScript(String javaScript) async {}

  @override
  Future<Object> runJavaScriptReturningResult(String javaScript) async => '';

  @override
  Future<void> removeJavaScriptChannel(String javaScriptChannelName) async {}
}

class _FakeCookieManager extends PlatformWebViewCookieManager {
  _FakeCookieManager(super.params) : super.implementation();
}

class _FakeWebViewWidget extends PlatformWebViewWidget {
  _FakeWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _FakeNavigationDelegate extends PlatformNavigationDelegate {
  _FakeNavigationDelegate(super.params) : super.implementation();

  @override
  Future<void> setOnNavigationRequest(NavigationRequestCallback onNavigationRequest) async {}

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async {}

  @override
  Future<void> setOnPageStarted(PageEventCallback onPageStarted) async {}

  @override
  Future<void> setOnProgress(ProgressCallback onProgress) async {}

  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback onWebResourceError) async {}

  @override
  Future<void> setOnUrlChange(UrlChangeCallback onUrlChange) async {}

  @override
  Future<void> setOnHttpAuthRequest(HttpAuthRequestCallback handler) async {}

  @override
  Future<void> setOnHttpError(HttpResponseErrorCallback onHttpError) async {}
}

Map<String, dynamic> _movieDetailsJson(int id, {String title = 'Testfilm'}) => {
      'id': id,
      'title': title,
      'genres': <dynamic>[],
      'overview': '',
    };

/// TMDB-Mock: Filmdetails immer verfügbar, `/videos` antwortet mit [videos]
/// (leer = kein Trailer). Löst nie echte HTTP-/YouTube-Requests aus.
TmdbService _tmdbService({List<Map<String, dynamic>> videos = const []}) {
  final client = MockClient((request) async {
    if (request.url.path.contains('/videos')) {
      return http.Response(jsonEncode({'results': videos}), 200);
    }
    if (request.url.path.contains('/watch/providers')) {
      return http.Response(jsonEncode({'results': <String, dynamic>{}}), 200);
    }
    final match = RegExp(r'/movie/(\d+)$').firstMatch(request.url.path);
    if (match != null) {
      return http.Response(jsonEncode(_movieDetailsJson(int.parse(match.group(1)!))), 200);
    }
    return http.Response('{}', 404);
  });
  return TmdbService(client, accessToken: 'test-token');
}

Map<String, dynamic> _trailerVideo(String key) => {
      'key': key,
      'site': 'YouTube',
      'type': 'Trailer',
      'official': true,
      'published_at': '2020-01-01T00:00:00Z',
      'name': 'Official Trailer',
    };

void main() {
  setUp(() {
    WebViewPlatform.instance = _FakeWebViewPlatform();
  });

  group('MovieDetailScreen - Trailer-Button', () {
    testWidgets('zeigt den Trailer-Button, wenn TMDB einen Trailer liefert', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tmdbServiceProvider.overrideWithValue(_tmdbService(videos: [_trailerVideo('abc123')])),
          ],
          child: const MaterialApp(home: MovieDetailScreen(tmdbId: 550)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Trailer ansehen'), findsOneWidget);
    });

    testWidgets('zeigt keinen Trailer-Button, wenn TMDB keinen Trailer liefert (kein Platzhalter)',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tmdbServiceProvider.overrideWithValue(_tmdbService(videos: const [])),
          ],
          child: const MaterialApp(home: MovieDetailScreen(tmdbId: 550)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Trailer ansehen'), findsNothing);
    });

    testWidgets('zeigt keinen Trailer-Button, wenn TMDB nur einen Teaser liefert (kein Trailer-Typ)',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tmdbServiceProvider.overrideWithValue(_tmdbService(videos: [
              {
                'key': 'teaser1',
                'site': 'YouTube',
                'type': 'Teaser',
                'official': true,
                'published_at': '2020-01-01T00:00:00Z',
                'name': 'Teaser',
              },
            ])),
          ],
          child: const MaterialApp(home: MovieDetailScreen(tmdbId: 550)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Trailer ansehen'), findsNothing);
    });

    testWidgets('Antippen des Trailer-Buttons öffnet den Trailer als Popup-Dialog', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tmdbServiceProvider.overrideWithValue(_tmdbService(videos: [_trailerVideo('abc123')])),
          ],
          child: const MaterialApp(home: MovieDetailScreen(tmdbId: 550)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Trailer ansehen'));
      await tester.pump();

      expect(find.byType(TrailerDialog), findsOneWidget);
      // Ein echtes Dialog-Widget, keine neue Vollbild-Seite/Navigation -
      // der zugrundeliegende MovieDetailScreen bleibt im Widget-Baum.
      expect(find.byType(MovieDetailScreen), findsOneWidget);
    });

    testWidgets('TMDB-Fehler beim Laden der Videos blockiert nicht den Rest der Filmdetails',
        (tester) async {
      final client = MockClient((request) async {
        if (request.url.path.contains('/videos')) {
          return http.Response('{}', 500);
        }
        if (request.url.path.contains('/watch/providers')) {
          return http.Response(jsonEncode({'results': <String, dynamic>{}}), 200);
        }
        return http.Response(jsonEncode(_movieDetailsJson(550, title: 'Ein Film')), 200);
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tmdbServiceProvider.overrideWithValue(TmdbService(client, accessToken: 'test-token')),
          ],
          child: const MaterialApp(home: MovieDetailScreen(tmdbId: 550)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ein Film'), findsOneWidget);
      expect(find.text('Trailer ansehen'), findsNothing);
    });
  });
}
