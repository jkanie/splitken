/**
 * A rule broken by an expense, an amount or an operation. `code` is stable
 * and matches the Dart core and the API. `message` is for people.
 */
export class SplitError extends Error {
  constructor(
    readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = 'SplitError';
  }
}
