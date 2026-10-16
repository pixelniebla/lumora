/// An error whose message is a l10n key, so it can be shown in the user's language.
class LocalizedError implements Exception {
  final String key;
  final Map<String, String> args;
  const LocalizedError(this.key, [this.args = const {}]);

  @override
  String toString() => key; // never leaks anything; UI translates via errorText()
}
