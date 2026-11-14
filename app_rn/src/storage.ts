import AsyncStorage from '@react-native-async-storage/async-storage';

/** Where the app keeps its groups. AsyncStorage on a phone, a map in tests. */
export interface KeyValueStore {
  read(key: string): Promise<string | null>;
  write(key: string, value: string): Promise<void>;
  delete(key: string): Promise<void>;
}

export const asyncStorageStore: KeyValueStore = {
  read: (key) => AsyncStorage.getItem(key),
  write: (key, value) => AsyncStorage.setItem(key, value),
  delete: (key) => AsyncStorage.removeItem(key),
};

export class MemoryStore implements KeyValueStore {
  readonly values = new Map<string, string>();

  async read(key: string) {
    return this.values.get(key) ?? null;
  }

  async write(key: string, value: string) {
    this.values.set(key, value);
  }

  async delete(key: string) {
    this.values.delete(key);
  }
}
