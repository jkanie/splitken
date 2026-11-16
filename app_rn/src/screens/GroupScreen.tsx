import { useState, useSyncExternalStore } from 'react';
import { ScrollView, Share, Text, View } from 'react-native';

import { type Expense, SplitError, formatCents } from '../core';
import type { GroupBook } from '../groupBook';
import { Button, Field, Row, colors, styles } from './ui';

type Tab = 'Expenses' | 'Balances' | 'Members';

/** 1 group: its expenses, balances with settle-up payments, members. */
export function GroupScreen({
  book,
  onBack,
  onEdit,
}: {
  book: GroupBook;
  onBack: () => void;
  onEdit: (expense?: Expense) => void;
}) {
  useSyncExternalStore(book.subscribe, book.getVersion);
  const [tab, setTab] = useState<Tab>('Expenses');
  const cur = book.meta.currency;
  const syncLabel = book.syncing
    ? 'Syncing'
    : book.pending.length > 0
      ? `Sync (${book.pending.length})`
      : 'Sync';

  return (
    <View style={styles.screen}>
      <View style={styles.header}>
        <Button quiet label="Back" onPress={onBack} />
        <Text style={styles.title}>{book.meta.name}</Text>
        <Button quiet label="Share" onPress={() => Share.share({ message: book.meta.id })} />
        <Button
          label={syncLabel}
          testID="sync"
          disabled={book.syncing}
          onPress={() => book.sync()}
        />
      </View>
      {book.lastProblem && (
        <View style={styles.banner}>
          <Text style={styles.grow}>{book.lastProblem}</Text>
          <Button quiet label="Try again" onPress={() => book.sync()} />
        </View>
      )}
      <View style={styles.tabs}>
        {(['Expenses', 'Balances', 'Members'] as const).map((t) => (
          <Text
            key={t}
            accessibilityRole="tab"
            accessibilityState={{ selected: tab === t }}
            onPress={() => setTab(t)}
            style={[styles.tab, tab === t && styles.tabOn]}
          >
            {t}
          </Text>
        ))}
      </View>
      <ScrollView style={styles.grow}>
        {tab === 'Expenses' && <Expenses book={book} cur={cur} onEdit={onEdit} />}
        {tab === 'Balances' && <Balances book={book} cur={cur} />}
        {tab === 'Members' && <Members book={book} />}
      </ScrollView>
      <View style={{ padding: 16 }}>
        <Button label="Add an expense" onPress={() => onEdit()} />
      </View>
    </View>
  );
}

function Expenses({
  book,
  cur,
  onEdit,
}: {
  book: GroupBook;
  cur: string;
  onEdit: (e: Expense) => void;
}) {
  const expenses = [...book.state.expenses].reverse();
  if (expenses.length === 0) return <Text style={styles.empty}>No expenses yet.</Text>;
  return expenses.map((e) => (
    <Row
      key={e.id}
      onPress={e.isTransfer ? undefined : () => onEdit(e)}
      onLongPress={() => book.deleteExpense(e.id)}
    >
      <View style={styles.grow}>
        <Text>{e.description}</Text>
        <Text style={styles.muted}>{`${book.memberName(e.paidBy)} paid`}</Text>
      </View>
      <Text>{`${formatCents(e.amountCents)} ${cur}`}</Text>
    </Row>
  ));
}

function Balances({ book, cur }: { book: GroupBook; cur: string }) {
  const settle = book.settle;
  const spent = book.spent;
  return (
    <View>
      <Text style={{ padding: 16 }}>{`Spent ${formatCents(spent.spentCents)} ${cur}`}</Text>
      {book.state.members.map((m) => {
        const cents = book.net.get(m.id)!;
        return (
          <Row key={m.id}>
            <View style={styles.grow}>
              <Text>{m.name}</Text>
              <Text style={styles.muted}>
                {`Paid ${formatCents(spent.paid.get(m.id)!)}, share ${formatCents(spent.share.get(m.id)!)}`}
              </Text>
            </View>
            <Text style={{ color: cents < 0 ? colors.owes : colors.owed }}>
              {`${cents > 0 ? '+' : ''}${formatCents(cents)}`}
            </Text>
          </Row>
        );
      })}
      <Text style={{ padding: 16, fontWeight: '600' }}>
        {settle.length === 0 ? 'Everyone is settled.' : 'To settle up'}
      </Text>
      {settle.map((t) => (
        <Row key={`${t.from}>${t.to}`}>
          <View style={styles.grow}>
            <Text>{`${book.memberName(t.from)} pays ${book.memberName(t.to)}`}</Text>
            <Text style={styles.muted}>{`${formatCents(t.amountCents)} ${cur}`}</Text>
          </View>
          <Button quiet label="Mark paid" onPress={() => book.recordTransfer(t)} />
        </Row>
      ))}
    </View>
  );
}

function Members({ book }: { book: GroupBook }) {
  const [name, setName] = useState('');
  const [problem, setProblem] = useState<string | null>(null);
  return (
    <View>
      {book.state.members.map((m) => (
        <Row key={m.id}>
          <Text>{m.name}</Text>
        </Row>
      ))}
      <View style={{ padding: 16 }}>
        <Field label="Add a member" value={name} onChangeText={setName} />
        {problem && <Text style={{ color: colors.owes, marginBottom: 8 }}>{problem}</Text>}
        <Button
          label="Add"
          onPress={async () => {
            try {
              await book.addMember(name);
              setName('');
              setProblem(null);
            } catch (e) {
              if (e instanceof SplitError) setProblem(e.message);
              else throw e;
            }
          }}
        />
      </View>
    </View>
  );
}
