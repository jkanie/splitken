import 'model.dart';

/// 1 payment that settles part of the group's balances.
class Transfer {
  const Transfer(this.from, this.to, this.amountCents);

  final String from;
  final String to;
  final int amountCents;

  Map<String, Object?> toJson() => {
    'from': from,
    'to': to,
    'amountCents': amountCents,
  };

  @override
  bool operator ==(Object other) =>
      other is Transfer &&
      other.from == from &&
      other.to == to &&
      other.amountCents == amountCents;

  @override
  int get hashCode => Object.hash(from, to, amountCents);

  @override
  String toString() => '$from -> $to: $amountCents';
}

/// Payments that bring every balance in [net] to 0.
///
/// Each step, the member who owes the most pays the member owed the most, as
/// much as settles 1 of them. Equal amounts go to the member listed 1st in
/// [members]. It makes at most 1 payment fewer than the members with a
/// balance, though not always the fewest possible.
List<Transfer> settleUp(List<Member> members, Map<String, int> net) {
  final order = {for (var i = 0; i < members.length; i++) members[i].id: i};
  final owedTo = <String, int>{};
  final owes = <String, int>{};
  net.forEach((id, cents) {
    if (cents > 0) owedTo[id] = cents;
    if (cents < 0) owes[id] = -cents;
  });

  String largest(Map<String, int> side) {
    final ids = side.keys.toList()
      ..sort((a, b) {
        final byAmount = side[b]!.compareTo(side[a]!);
        return byAmount != 0 ? byAmount : order[a]!.compareTo(order[b]!);
      });
    return ids.first;
  }

  final transfers = <Transfer>[];
  while (owedTo.isNotEmpty && owes.isNotEmpty) {
    final to = largest(owedTo);
    final from = largest(owes);
    final cents = owedTo[to]! < owes[from]! ? owedTo[to]! : owes[from]!;
    transfers.add(Transfer(from, to, cents));
    owedTo[to] = owedTo[to]! - cents;
    owes[from] = owes[from]! - cents;
    if (owedTo[to] == 0) owedTo.remove(to);
    if (owes[from] == 0) owes.remove(from);
  }
  return transfers;
}
