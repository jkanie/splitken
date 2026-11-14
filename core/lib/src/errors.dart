/// A rule broken by an expense, an amount or an operation. [code] is stable
/// and is what the API sends back; [message] is for people.
class SplitError implements Exception {
  SplitError(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'SplitError($code): $message';
}
