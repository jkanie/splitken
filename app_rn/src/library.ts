import type { ApiClient, GroupMeta } from './api';
import { GroupBook } from './groupBook';
import { randomId } from './ids';
import type { KeyValueStore } from './storage';

const clientKey = 'clientId';
const groupsKey = 'groups';

/** Every group on this device, and the device's client id. */
export class Library {
  private readonly listeners = new Set<() => void>();
  private version = 0;

  private constructor(
    readonly clientId: string,
    private readonly api: ApiClient,
    private readonly store: KeyValueStore,
    readonly books: GroupBook[],
  ) {}

  static async load(api: ApiClient, store: KeyValueStore): Promise<Library> {
    let clientId = await store.read(clientKey);
    if (clientId == null) {
      clientId = `c${randomId(11)}`;
      await store.write(clientKey, clientId);
    }
    const ids = JSON.parse((await store.read(groupsKey)) ?? '[]') as string[];
    const books: GroupBook[] = [];
    for (const id of ids) {
      const saved = await store.read(GroupBook.storageKey(id));
      if (saved != null) books.push(GroupBook.fromJson(saved, clientId, api, store));
    }
    return new Library(clientId, api, store, books);
  }

  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };

  getVersion = () => this.version;

  /** Makes a group on the server. This 1 step needs the network. */
  async create(name: string, currency: string, members: string[]): Promise<GroupBook> {
    return this.keep(await this.api.createGroup(name, currency, members));
  }

  /** Joins a group by the id someone shared, and fetches its history. */
  async join(id: string): Promise<GroupBook> {
    const existing = this.books.find((b) => b.meta.id === id.trim());
    if (existing) return existing;
    const book = await this.keep(await this.api.group(id.trim()));
    await book.sync();
    return book;
  }

  async remove(book: GroupBook): Promise<void> {
    this.books.splice(this.books.indexOf(book), 1);
    await this.store.delete(GroupBook.storageKey(book.meta.id));
    await this.saveIds();
    this.notify();
  }

  private async keep(meta: GroupMeta): Promise<GroupBook> {
    const book = new GroupBook(meta, this.clientId, this.api, this.store);
    this.books.push(book);
    await book.save();
    await this.saveIds();
    this.notify();
    return book;
  }

  private saveIds() {
    return this.store.write(groupsKey, JSON.stringify(this.books.map((b) => b.meta.id)));
  }

  private notify() {
    this.version++;
    for (const l of this.listeners) l();
  }
}
