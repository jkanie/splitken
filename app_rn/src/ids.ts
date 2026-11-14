const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';

/**
 * A random id of a-z and 0-9. Math.random is enough here: ids only need to
 * differ between devices, they guard nothing.
 */
export function randomId(length = 12): string {
  let id = '';
  for (let i = 0; i < length; i++) id += alphabet[Math.floor(Math.random() * alphabet.length)];
  return id;
}
