import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/repositories/device_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeviceRepository', () {
    late FakeFirebaseFirestore firestore;
    late DeviceRepository repository;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repository = DeviceRepository(firestore);
    });

    test('registerDevice legt ein neues Gerät mit deterministischer ID an', () async {
      await repository.registerDevice(uid: 'alice', token: 'tok-1', platform: 'android');

      final doc = await firestore.collection('users/alice/devices').doc('tok-1').get();
      expect(doc.exists, isTrue);
      expect(doc.data()!['token'], 'tok-1');
      expect(doc.data()!['platform'], 'android');
    });

    test('erneutes Registrieren desselben Tokens erzeugt kein Duplikat', () async {
      await repository.registerDevice(uid: 'alice', token: 'tok-1', platform: 'android');
      await repository.registerDevice(uid: 'alice', token: 'tok-1', platform: 'android');

      final snapshot = await firestore.collection('users/alice/devices').get();
      expect(snapshot.docs, hasLength(1));
    });

    test('removeDevice entfernt nur das angegebene Gerät', () async {
      await repository.registerDevice(uid: 'alice', token: 'tok-1', platform: 'android');
      await repository.registerDevice(uid: 'alice', token: 'tok-2', platform: 'ios');

      await repository.removeDevice(uid: 'alice', token: 'tok-1');

      final snapshot = await firestore.collection('users/alice/devices').get();
      expect(snapshot.docs.map((d) => d.id), ['tok-2']);
    });
  });
}
