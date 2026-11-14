import { useState, useSyncExternalStore } from 'react';
import { Pressable, ScrollView, Text, TextInput, View } from 'react-native';

import {
  type Expense,
  SplitError,
  type SplitMethod,
  formatCents,
  parseCents,
  splitExpense,
} from '../core';
import type { GroupBook } from '../groupBook';
import { randomId } from '../ids';
import { Button, Field, colors, styles } from './ui';

const methods: { value: SplitMethod; label: string }[] = [
  { value: 'equal', label: 'Equal' },
  { value: 'exact', label: 'Exact' },
  { value: 'shares', label: 'Shares' },
  { value: 'percent', label: '%' },
];

function showWeight(method: SplitMethod, weight: number) {
  return method === 'shares' ? String(weight) : formatCents(weight);
}

/**
 * Reads 1 weight: whole shares, or an amount or percent with up to 2
 * decimals (12.5 % is 1250 basis points, as 12.50 is 1250 cents).
 */
function readWeight(method: SplitMethod, text: string): number {
  const t = text.trim();
  if (t.length === 0) return 0;
  if (method === 'shares') {
    if (!/^\d{1,7}$/.test(t)) throw new SplitError('bad_split', 'Shares are whole numbers.');
    return Number(t);
  }
  const match = /^(\d{1,8})(?:\.(\d{1,2}))?$/.exec(t);
  if (match == null)
    throw new SplitError('bad_split', `"${t}" is not a number with up to 2 decimals.`);
  return Number(match[1]) * 100 + Number((match[2] ?? '').padEnd(2, '0'));
}

/** Adds an expense, or changes `editing`. The split is worked out as the user types. */
export function ExpenseForm({
  book,
  editing,
  onDone,
}: {
  book: GroupBook;
  editing?: Expense;
  onDone: () => void;
}) {
  useSyncExternalStore(book.subscribe, book.getVersion);
  const members = book.state.members;
  const [description, setDescription] = useState(editing?.description ?? '');
  const [amount, setAmount] = useState(editing ? formatCents(editing.amountCents) : '');
  const [paidBy, setPaidBy] = useState(editing?.paidBy ?? members[0].id);
  const [method, setMethod] = useState<SplitMethod>(editing?.method ?? 'equal');
  const [participants, setParticipants] = useState(
    new Set(editing?.participants ?? members.map((m) => m.id)),
  );
  const [weights, setWeights] = useState<Record<string, string>>(() => {
    const out: Record<string, string> = {};
    editing?.participants.forEach((id, i) => {
      if (editing.weights.length > 0) out[id] = showWeight(editing.method, editing.weights[i]);
    });
    return out;
  });
  const [saveProblem, setSaveProblem] = useState<string | null>(null);

  function build(): Expense {
    const ordered = members.filter((m) => participants.has(m.id)).map((m) => m.id);
    return {
      id: editing?.id ?? randomId(),
      description: description.trim(),
      amountCents: parseCents(amount),
      paidBy,
      participants: ordered,
      method,
      weights: method === 'equal' ? [] : ordered.map((id) => readWeight(method, weights[id] ?? '')),
      isTransfer: false,
    };
  }

  let parts: Map<string, number> | null = null;
  let problem: string | null = null;
  try {
    const expense = build();
    const split = splitExpense(expense);
    parts = new Map(expense.participants.map((id, i) => [id, split[i]]));
  } catch (e) {
    if (!(e instanceof SplitError)) throw e;
    problem = e.message;
  }

  async function save() {
    try {
      await book.saveExpense(build());
      onDone();
    } catch (e) {
      if (!(e instanceof SplitError)) throw e;
      setSaveProblem(e.message);
    }
  }

  function toggle(id: string) {
    const next = new Set(participants);
    if (!next.delete(id)) next.add(id);
    setParticipants(next);
  }

  return (
    <View style={styles.screen}>
      <View style={styles.header}>
        <Button quiet label="Cancel" onPress={onDone} />
        <Text style={styles.title}>{editing ? 'Change expense' : 'New expense'}</Text>
        <Button label="Save" testID="save" onPress={save} />
      </View>
      <ScrollView contentContainerStyle={{ padding: 16 }}>
        <Field
          label="What was it for"
          testID="description"
          value={description}
          onChangeText={setDescription}
        />
        <Field
          label={`Amount (${book.meta.currency})`}
          testID="amount"
          keyboardType="decimal-pad"
          value={amount}
          onChangeText={setAmount}
        />
        <Text style={styles.label}>Paid by</Text>
        <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8, marginBottom: 12 }}>
          {members.map((m) => (
            <Pressable
              key={m.id}
              accessibilityRole="radio"
              accessibilityState={{ checked: paidBy === m.id }}
              onPress={() => setPaidBy(m.id)}
              style={[styles.chip, paidBy === m.id && styles.chipOn]}
            >
              <Text style={{ color: paidBy === m.id ? '#fff' : '#000' }}>{m.name}</Text>
            </Pressable>
          ))}
        </View>
        <View style={{ flexDirection: 'row', gap: 8, marginBottom: 12 }}>
          {methods.map((m) => (
            <Pressable
              key={m.value}
              accessibilityRole="button"
              accessibilityState={{ selected: method === m.value }}
              onPress={() => setMethod(m.value)}
              style={[styles.chip, method === m.value && styles.chipOn]}
            >
              <Text style={{ color: method === m.value ? '#fff' : '#000' }}>{m.label}</Text>
            </Pressable>
          ))}
        </View>
        {members.map((m) => {
          const on = participants.has(m.id);
          const part = parts?.get(m.id);
          return (
            <View
              key={m.id}
              style={{ flexDirection: 'row', alignItems: 'center', gap: 8, paddingVertical: 6 }}
            >
              <Pressable
                accessibilityRole="checkbox"
                accessibilityState={{ checked: on }}
                accessibilityLabel={m.name}
                onPress={() => toggle(m.id)}
                style={styles.grow}
              >
                <Text>{`${on ? '☑' : '☐'} ${m.name}`}</Text>
                <Text testID={`part-${m.id}`} style={styles.muted}>
                  {part === undefined ? '' : `${formatCents(part)} ${book.meta.currency}`}
                </Text>
              </Pressable>
              {method !== 'equal' && on && (
                <TextInput
                  testID={`weight-${m.id}`}
                  style={styles.weight}
                  keyboardType="decimal-pad"
                  placeholder={method === 'exact' ? '0.00' : method === 'shares' ? '1' : '%'}
                  value={weights[m.id] ?? ''}
                  onChangeText={(text) => setWeights({ ...weights, [m.id]: text })}
                />
              )}
            </View>
          );
        })}
        {(problem ?? saveProblem) && (
          <Text testID="problem" style={{ color: colors.owes, marginTop: 12 }}>
            {problem ?? saveProblem}
          </Text>
        )}
      </ScrollView>
    </View>
  );
}
