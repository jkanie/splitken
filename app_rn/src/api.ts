import { type Member, type Op, isJsonObject, memberFromJson, opFromJson, opToJson } from './core';

/** A group as the server describes it. */
export interface GroupMeta {
  id: string;
  name: string;
  currency: string;
  founders: Member[];
}

export function groupMetaFromJson(json: unknown): GroupMeta {
  if (
    !isJsonObject(json) ||
    typeof json.id !== 'string' ||
    typeof json.name !== 'string' ||
    typeof json.currency !== 'string' ||
    !Array.isArray(json.founders)
  ) {
    throw new OfflineError('The server sent a group in a form this app does not know.');
  }
  return {
    id: json.id,
    name: json.name,
    currency: json.currency,
    founders: json.founders.map(memberFromJson),
  };
}

/** What 1 member paid and what their share came to, in cents. */
export interface MemberTotal {
  id: string;
  name: string;
  paidCents: number;
  shareCents: number;
}

/**
 * What a group spent, from `GET /v1/groups/{id}/totals`. Transfers that
 * settle up are not spending, so they are left out.
 */
export interface GroupTotals {
  currency: string;
  spentCents: number;
  members: MemberTotal[];
}

export function groupTotalsFromJson(json: unknown): GroupTotals {
  const bad = () => new OfflineError('The server sent totals in a form this app does not know.');
  if (
    !isJsonObject(json) ||
    typeof json.currency !== 'string' ||
    !Number.isSafeInteger(json.spent) ||
    !Array.isArray(json.members)
  ) {
    throw bad();
  }
  return {
    currency: json.currency,
    spentCents: json.spent as number,
    members: json.members.map((m) => {
      if (
        !isJsonObject(m) ||
        typeof m.id !== 'string' ||
        typeof m.name !== 'string' ||
        !Number.isSafeInteger(m.paid) ||
        !Number.isSafeInteger(m.share)
      ) {
        throw bad();
      }
      return { id: m.id, name: m.name, paidCents: m.paid as number, shareCents: m.share as number };
    }),
  };
}

/** What a sync returns: the operations after `since`, and the newest seq. */
export interface SyncResult {
  seq: number;
  ops: Op[];
}

/** The server could not be reached, or answered with something unexpected. */
export class OfflineError extends Error {
  constructor(reason: string) {
    super(reason);
    this.name = 'OfflineError';
  }
}

/** The server refused a request. `opId` names the operation it refused. */
export class RefusedError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly opId?: string,
  ) {
    super(message);
    this.name = 'RefusedError';
  }
}

type Fetch = typeof fetch;

/** Talks to the splitken server. */
export class ApiClient {
  constructor(
    readonly base: string,
    private readonly fetcher: Fetch = (input, init) => fetch(input, init),
  ) {}

  async createGroup(name: string, currency: string, members: string[]): Promise<GroupMeta> {
    return groupMetaFromJson(await this.send('POST', '/v1/groups', { name, currency, members }));
  }

  async group(id: string): Promise<GroupMeta> {
    return groupMetaFromJson(await this.send('GET', `/v1/groups/${encodeURIComponent(id)}`));
  }

  async sync(groupId: string, since: number, ops: Op[]): Promise<SyncResult> {
    const json = await this.send('POST', `/v1/groups/${encodeURIComponent(groupId)}/sync`, {
      since,
      ops: ops.map(opToJson),
    });
    if (!Number.isSafeInteger(json.seq) || !Array.isArray(json.ops)) {
      throw new OfflineError('The server sent a sync answer in a form this app does not know.');
    }
    return { seq: json.seq as number, ops: json.ops.map(opFromJson) };
  }

  /**
   * What the group spent, from the operations the server holds. Changes
   * still pending on a device are not in it until they are synced.
   */
  async totals(groupId: string): Promise<GroupTotals> {
    return groupTotalsFromJson(
      await this.send('GET', `/v1/groups/${encodeURIComponent(groupId)}/totals`),
    );
  }

  private async send(
    method: string,
    path: string,
    body?: unknown,
  ): Promise<Record<string, unknown>> {
    let response: Response;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 15_000);
    try {
      response = await this.fetcher(this.base.replace(/\/$/, '') + path, {
        method,
        headers: { 'content-type': 'application/json' },
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: controller.signal,
      });
    } catch (e) {
      throw new OfflineError(String(e));
    } finally {
      clearTimeout(timer);
    }
    let json: unknown;
    try {
      json = await response.json();
    } catch {
      throw new OfflineError(`HTTP ${response.status} without JSON`);
    }
    if (!isJsonObject(json))
      throw new OfflineError(`HTTP ${response.status} without a JSON object`);
    if (response.status >= 500) throw new OfflineError(`HTTP ${response.status}`);
    if (response.status >= 400) {
      throw new RefusedError(
        typeof json.error === 'string' ? json.error : 'refused',
        typeof json.message === 'string' ? json.message : `HTTP ${response.status}`,
        typeof json.opId === 'string' ? json.opId : undefined,
      );
    }
    return json;
  }
}
