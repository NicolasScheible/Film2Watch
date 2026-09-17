import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/components/friends/friend_list_tile.dart';
import 'package:film2watch/providers/auth_provider.dart';
import 'package:film2watch/providers/tmdb_provider.dart';
import 'package:film2watch/screens/profile/friend_detail_screen.dart';
import 'package:film2watch/services/tmdb_service.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Testet den Freundes-Profil-Bereich (§4: "gemeinsame Gruppen und
/// vergangene Matches"). `FriendDetailScreen` selbst enthält keine
/// Datenmodell-Logik (siehe `GroupRepository.watchCommonGroups`/
/// `pastMatchesWithFriendProvider`, dort separat getestet) - hier wird nur
/// geprüft, dass die UI die Provider-Ergebnisse korrekt anzeigt.

TmdbService _tmdbService(Map<int, String> movies) {
  final client = MockClient((request) async {
    final match = RegExp(r'/movie/(\d+)$').firstMatch(request.url.path);
    if (match != null) {
      final id = int.parse(match.group(1)!);
      final title = movies[id];
      if (title != null) {
        return http.Response(
          jsonEncode({'id': id, 'title': title, 'genres': <dynamic>[], 'overview': ''}),
          200,
        );
      }
      return http.Response('{"status_message":"not found"}', 404);
    }
    return http.Response('{}', 404);
  });
  return TmdbService(client, accessToken: 'test-token');
}

Future<void> _seedPublicProfile(
  FakeFirebaseFirestore firestore,
  String uid, {
  required String name,
  String? profilePicture,
}) {
  return firestore.collection('public_profiles').doc(uid).set({
    'uid': uid,
    'name': name,
    'friend_code': 'CODE-$uid',
    'profile_picture': profilePicture,
  });
}

Future<void> _seedGroup(
  FakeFirebaseFirestore firestore,
  String groupId, {
  required List<String> memberUids,
}) async {
  final now = DateTime.now();
  await firestore.collection('groups').doc(groupId).set({
    'id': groupId,
    'name': 'Gruppe $groupId',
    'photo_url': null,
    'created_by': memberUids.first,
    'created_at': now,
    'updated_at': now,
  });
  for (final uid in memberUids) {
    await firestore.collection('groups').doc(groupId).collection('members').doc(uid).set({
      'uid': uid,
      'role': uid == memberUids.first ? 'admin' : 'member',
      'joined_at': now,
    });
  }
}

Future<void> _seedUserGroupIndex(FakeFirebaseFirestore firestore, String uid, String groupId) {
  return firestore.collection('users').doc(uid).collection('groups').doc(groupId).set({
    'groupId': groupId,
  });
}

Future<void> _seedMatch(
  FakeFirebaseFirestore firestore,
  String groupId,
  int movieId, {
  required List<String> memberUids,
}) {
  return firestore.collection('groups').doc(groupId).collection('matches').doc('$movieId').set({
    'movie_id': movieId,
    'member_uids': memberUids,
    'matched_at': DateTime.now(),
  });
}

void main() {
  group('FriendListTile', () {
    testWidgets('öffnet beim Antippen den übergebenen Callback (Navigation zum Freundes-Profil)', (
      tester,
    ) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FriendListTile(
              name: 'Bob',
              friendCode: 'ABC123',
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Bob'));
      expect(tapped, isTrue);
    });
  });

  group('FriendDetailScreen', () {
    late FakeFirebaseFirestore firestore;
    late MockFirebaseAuth auth;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'alice', email: 'alice@film2watch.app'),
        signedIn: true,
      );
    });

    Future<void> pumpScreen(
      WidgetTester tester, {
      Map<int, String> movies = const {},
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseAuthProvider.overrideWithValue(auth),
            firestoreProvider.overrideWithValue(firestore),
            tmdbServiceProvider.overrideWithValue(_tmdbService(movies)),
          ],
          child: const MaterialApp(home: FriendDetailScreen(friendUid: 'bob')),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('zeigt den Namen des Freundes', (tester) async {
      await _seedPublicProfile(firestore, 'bob', name: 'Bob');

      await pumpScreen(tester);

      expect(find.text('Bob'), findsWidgets);
    });

    testWidgets('fehlendes Profilbild führt zu keinem Absturz (Fallback-Initialen)', (tester) async {
      await _seedPublicProfile(firestore, 'bob', name: 'Bob', profilePicture: null);

      await pumpScreen(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Bob'), findsWidgets);
    });

    testWidgets('zeigt Empty States, wenn es keine gemeinsamen Gruppen und keine Matches gibt', (
      tester,
    ) async {
      await _seedPublicProfile(firestore, 'bob', name: 'Bob');

      await pumpScreen(tester);

      expect(find.text('Keine gemeinsamen Gruppen.'), findsOneWidget);
      expect(find.text('Noch keine gemeinsamen Matches.'), findsOneWidget);
    });

    testWidgets('zeigt eine tatsächlich gemeinsame Gruppe an', (tester) async {
      await _seedPublicProfile(firestore, 'bob', name: 'Bob');
      await _seedGroup(firestore, 'g1', memberUids: ['alice', 'bob']);
      await _seedUserGroupIndex(firestore, 'alice', 'g1');

      await pumpScreen(tester);

      expect(find.text('Gruppe g1'), findsOneWidget);
      expect(find.text('Keine gemeinsamen Gruppen.'), findsNothing);
    });

    testWidgets('zeigt ein vergangenes gemeinsames Match an', (tester) async {
      await _seedPublicProfile(firestore, 'bob', name: 'Bob');
      await _seedGroup(firestore, 'g1', memberUids: ['alice', 'bob']);
      await _seedUserGroupIndex(firestore, 'alice', 'g1');
      await _seedMatch(firestore, 'g1', 550, memberUids: ['alice', 'bob']);

      await pumpScreen(tester, movies: {550: 'Fight Club'});

      expect(find.text('Fight Club'), findsOneWidget);
      expect(find.text('Noch keine gemeinsamen Matches.'), findsNothing);
    });
  });
}
