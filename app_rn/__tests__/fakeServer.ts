// A small copy of the splitken server's rules for the Jest tests: the same
// routes, the same checks (api.dart _check), the same error shapes. The
// Flutter tests run the real Dart server in-process instead, which Jest
// cannot do.
import { ApiClient } from '../src/api';
import {
  type Member,
  type Op,
  SplitError,
  fold,
  opFromJson,
  opToJson,
  splitExpense,
  validateExpense,
} from '../src/core';

type Reply = { status: number; body: unknown };

export class FakeServer {
  online = true;
  requests = 0;
  private readonly groups = new Map<
    string,
    { id: string; name: string; currency: string; founders: Member[] }
  >();
  private readonly ops = new Map<string, Op[]>();
  private seq = 0;
  private nextId = 1;

  client(): ApiClient {
    return new ApiClient('http://splitken.test', async (input, init) => {
      this.requests++;
      if (!this.online) throw new TypeError('Network request failed');
      const url = new URL(String(input));
      const body = init?.body ? JSON.parse(String(init.body)) : undefined;
      const reply = this.handle(init?.method ?? 'GET', url.pathname, body);
      return { status: reply.status, json: async () => reply.body } as Response;
    });
  }

  private handle(method: string, path: string, body: any): Reply {
    if (method === 'POST' && path === '/v1/groups') {
      const names = (body.members as string[]).map((name) => name.trim());
      const twice = names.find(
        (name, i) => names.findIndex((n) => n.toLowerCase() === name.toLowerCase()) !== i,
      );
      if (twice !== undefined) {
        return {
          status: 422,
          body: {
            error: 'bad_member',
            message: `"${twice}" is listed twice. Each member needs a name of their own.`,
          },
        };
      }
      const id = `g${this.nextId++}`;
      const group = {
        id,
        name: String(body.name).trim(),
        currency: body.currency,
        founders: (body.members as string[]).map((name, i) => ({ id: `m${i + 1}`, name })),
      };
      this.groups.set(id, group);
      this.ops.set(id, []);
      return { status: 201, body: { ...group, seq: 0 } };
    }
    const match = /^\/v1\/groups\/([^/]+)(\/sync)?$/.exec(path);
    const group = match && this.groups.get(decodeURIComponent(match[1]));
    if (!match || !group)
      return { status: 404, body: { error: 'not_found', message: 'No group with that id.' } };
    const stored = this.ops.get(group.id)!;
    if (!match[2]) return { status: 200, body: { ...group, seq: stored.at(-1)?.seq ?? 0 } };

    const fresh: Op[] = (body.ops as unknown[]).map(
      (o) => opToJson(opFromJson(o)) as unknown as Op,
    );
    const seen = [...stored];
    const keys = new Set(stored.map((op) => `${op.clientId}\u0000${op.opId}`));
    const adding: Op[] = [];
    for (const op of fresh) {
      const key = `${op.clientId}\u0000${op.opId}`;
      if (keys.has(key)) continue;
      const state = fold(group.founders, seen);
      const ids = new Set(state.members.map((m) => m.id));
      try {
        if (op.kind === 'expense') {
          validateExpense(op.expense!, ids);
          splitExpense(op.expense!);
        }
        if (op.kind === 'member' && !ids.has(op.member!.id) && /^m\d+$/.test(op.member!.id)) {
          throw new SplitError('bad_member', 'Member ids m1, m2 and so on are for founders.');
        }
      } catch (e) {
        const err = e as SplitError;
        return { status: 422, body: { error: err.code, message: err.message, opId: op.opId } };
      }
      keys.add(key);
      seen.push(op);
      adding.push(op);
    }
    for (const op of adding) stored.push({ ...op, seq: ++this.seq });
    return {
      status: 200,
      body: {
        stored: adding.length,
        seq: stored.at(-1)?.seq ?? 0,
        ops: stored.filter((op) => op.seq! > body.since),
      },
    };
  }
}
