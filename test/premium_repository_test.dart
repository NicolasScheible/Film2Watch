import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:film2watch/repositories/premium_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PremiumRepository', () {
    test('liefert false, wenn kein premium_status-Dokument existiert (Free-User)', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = PremiumRepository(firestore);

      expect(await repository.isPremium('alice'), isFalse);
    });

    test('liefert true, wenn is_premium == true gesetzt ist', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('premium_status').doc('alice').set({'is_premium': true});
      final repository = PremiumRepository(firestore);

      expect(await repository.isPremium('alice'), isTrue);
    });

    test('liefert false, wenn is_premium explizit false ist', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('premium_status').doc('alice').set({'is_premium': false});
      final repository = PremiumRepository(firestore);

      expect(await repository.isPremium('alice'), isFalse);
    });

    test('der Premium-Status eines anderen Users beeinflusst das Ergebnis nicht', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('premium_status').doc('bob').set({'is_premium': true});
      final repository = PremiumRepository(firestore);

      expect(await repository.isPremium('alice'), isFalse);
    });
  });

  group('PremiumRepository.watchIsPremium', () {
    test('liefert zunächst false, wenn kein premium_status-Dokument existiert', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = PremiumRepository(firestore);

      expect(await repository.watchIsPremium('alice').first, isFalse);
    });

    test('liefert true, sobald is_premium == true gesetzt ist', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('premium_status').doc('alice').set({'is_premium': true});
      final repository = PremiumRepository(firestore);

      expect(await repository.watchIsPremium('alice').first, isTrue);
    });

    test('reagiert live auf eine spätere Änderung des Premium-Status', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = PremiumRepository(firestore);

      final values = <bool>[];
      final subscription = repository.watchIsPremium('alice').listen(values.add);
      await Future<void>.delayed(Duration.zero);

      await firestore.collection('premium_status').doc('alice').set({'is_premium': true});
      await Future<void>.delayed(Duration.zero);

      await subscription.cancel();
      expect(values, [false, true]);
    });
  });
}
