/// The money rules of splitken: amounts in cents, the 4 ways to split an
/// expense, balances, settle-up transfers, the operation log that keeps
/// devices in step.
///
/// The React Native app has a TypeScript copy of these rules. Both copies run
/// the cases in `spec/cases.json`, such that they give the same cents.
library;

export 'src/balances.dart';
export 'src/errors.dart';
export 'src/model.dart';
export 'src/money.dart';
export 'src/ops.dart';
export 'src/settle.dart';
export 'src/spending.dart';
export 'src/split.dart';
