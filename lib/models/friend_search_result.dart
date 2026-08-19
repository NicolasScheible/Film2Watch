import 'public_profile.dart';

/// Ergebnis einer Freundescode-Suche. Deckt alle in Schritt 3 geforderten
/// Zustände ab (nicht gefunden, eigener Code, bereits Freunde, ...).
sealed class FriendSearchResult {
  const FriendSearchResult();
}

class FriendSearchNotFound extends FriendSearchResult {
  const FriendSearchNotFound();
}

class FriendSearchOwnCode extends FriendSearchResult {
  const FriendSearchOwnCode();
}

class FriendSearchAlreadyFriends extends FriendSearchResult {
  const FriendSearchAlreadyFriends(this.profile);
  final PublicProfile profile;
}

class FriendSearchRequestAlreadySent extends FriendSearchResult {
  const FriendSearchRequestAlreadySent(this.profile);
  final PublicProfile profile;
}

class FriendSearchIncomingRequestExists extends FriendSearchResult {
  const FriendSearchIncomingRequestExists(this.profile);
  final PublicProfile profile;
}

class FriendSearchFound extends FriendSearchResult {
  const FriendSearchFound(this.profile);
  final PublicProfile profile;
}
