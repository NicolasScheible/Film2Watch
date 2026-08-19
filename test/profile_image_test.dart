import 'dart:io';
import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/components/friends/user_avatar.dart';
import 'package:film2watch/providers/auth_provider.dart';
import 'package:film2watch/providers/profile_image_controller.dart';
import 'package:film2watch/providers/storage_provider.dart';
import 'package:film2watch/repositories/user_repository.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  testWidgets('UserAvatar zeigt Initialen, wenn kein Profilbild vorhanden ist', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: UserAvatar(name: 'Nico Scheible'))),
    );

    expect(find.text('NS'), findsOneWidget);
  });

  group('ProfileImageController', () {
    late FakeFirebaseFirestore firestore;
    late UserRepository userRepository;
    late ProviderContainer container;
    late File imageFile;

    setUp(() async {
      // MockFirebaseAuth feuert sein initiales Sign-in-Event auf einem
      // Broadcast-Stream ohne Replay - der Listener muss deshalb im selben
      // synchronen Abschnitt registriert werden, noch vor jedem `await`.
      firestore = FakeFirebaseFirestore();
      userRepository = UserRepository(firestore);
      final mockUser = MockUser(uid: 'alice', email: 'alice@film2watch.app', displayName: 'Alice');
      final auth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);

      container = ProviderContainer(
        overrides: [
          firebaseAuthProvider.overrideWithValue(auth),
          firestoreProvider.overrideWithValue(firestore),
          firebaseStorageProvider.overrideWithValue(MockFirebaseStorage()),
        ],
      );
      addTearDown(container.dispose);
      container.listen(authStateChangesProvider, (previous, next) {});

      await userRepository.ensureUserDocument(
        uid: 'alice',
        email: 'alice@film2watch.app',
        name: 'Alice',
      );

      imageFile = File(
        '${Directory.systemTemp.path}/film2watch_test_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await imageFile.writeAsBytes(Uint8List.fromList(List.filled(1024, 1)));
      addTearDown(() => imageFile.delete());

      // Initialen Notifier-Build sowie den ersten Auth-State abwarten, bevor
      // Aktionen ausgelöst werden.
      await container.read(profileImageControllerProvider.future);
      await container.read(authStateChangesProvider.future);
    });

    test('Upload-State durchläuft loading und landet danach fehlerfrei', () async {
      final states = <bool>[];
      container.listen(
        profileImageControllerProvider,
        (previous, next) => states.add(next.isLoading),
        fireImmediately: true,
      );

      final controller = container.read(profileImageControllerProvider.notifier);
      await controller.uploadPickedFile(XFile(imageFile.path, name: 'photo.jpg'));

      expect(states, contains(true));
      expect(states.last, isFalse);
      expect(container.read(profileImageControllerProvider).hasError, isFalse);
    });

    test('erfolgreicher Upload aktualisiert profile_picture', () async {
      final controller = container.read(profileImageControllerProvider.notifier);

      await controller.uploadPickedFile(XFile(imageFile.path, name: 'photo.jpg'));

      final user = await userRepository.getUser('alice');
      expect(user!.profilePicture, isNotNull);
      expect(user.profilePicture, isNotEmpty);
    });

    test('nicht unterstütztes Dateiformat wird als Fehler behandelt', () async {
      final txtFile = File('${Directory.systemTemp.path}/film2watch_test_doc.txt');
      await txtFile.writeAsBytes(Uint8List.fromList([1, 2, 3]));
      addTearDown(() => txtFile.delete());

      final controller = container.read(profileImageControllerProvider.notifier);
      await controller.uploadPickedFile(XFile(txtFile.path, name: 'document.txt'));

      expect(container.read(profileImageControllerProvider).hasError, isTrue);
      final user = await userRepository.getUser('alice');
      expect(user!.profilePicture, isNull);
    });

    test('Profilbild entfernen setzt profile_picture zurück', () async {
      final controller = container.read(profileImageControllerProvider.notifier);
      await controller.uploadPickedFile(XFile(imageFile.path, name: 'photo.jpg'));
      expect((await userRepository.getUser('alice'))!.profilePicture, isNotNull);

      await controller.removeImage();

      final user = await userRepository.getUser('alice');
      expect(user!.profilePicture, isNull);
    });

    test('friend_code bleibt beim Profilbild-Update unverändert', () async {
      final before = (await userRepository.getUser('alice'))!.friendCode;

      final controller = container.read(profileImageControllerProvider.notifier);
      await controller.uploadPickedFile(XFile(imageFile.path, name: 'photo.jpg'));

      final after = (await userRepository.getUser('alice'))!.friendCode;
      expect(after, before);
    });
  });
}
