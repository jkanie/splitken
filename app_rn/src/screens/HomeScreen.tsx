import { useState, useSyncExternalStore } from 'react';
import { ScrollView, Text, View } from 'react-native';

import { OfflineError, RefusedError } from '../api';
import type { GroupBook } from '../groupBook';
import type { Library } from '../library';
import { Button, Field, Row, styles } from './ui';

type Mode = 'list' | 'create' | 'join';

/** The groups on this device, with forms to make or join 1. */
export function HomeScreen({
  library,
  onOpen,
}: {
  library: Library;
  onOpen: (book: GroupBook) => void;
}) {
  useSyncExternalStore(library.subscribe, library.getVersion);
  const [mode, setMode] = useState<Mode>('list');
  const [name, setName] = useState('');
  const [currency, setCurrency] = useState('CAD');
  const [members, setMembers] = useState('');
  const [groupId, setGroupId] = useState('');
  const [problem, setProblem] = useState<string | null>(null);

  async function run(action: () => Promise<GroupBook>) {
    setProblem(null);
    try {
      const book = await action();
      setMode('list');
      onOpen(book);
    } catch (e) {
      if (e instanceof RefusedError) setProblem(e.message);
      else if (e instanceof OfflineError)
        setProblem('Making or joining a group needs the network.');
      else throw e;
    }
  }

  return (
    <View style={styles.screen}>
      <View style={styles.header}>
        <Text style={styles.title}>splitken</Text>
        <Button quiet label="Join" onPress={() => setMode('join')} />
        <Button label="New group" onPress={() => setMode('create')} />
      </View>
      {problem && (
        <View style={styles.banner}>
          <Text>{problem}</Text>
        </View>
      )}
      {mode === 'create' && (
        <View style={{ padding: 16 }}>
          <Field label="Name" value={name} onChangeText={setName} />
          <Field
            label="Currency (3 letters)"
            value={currency}
            onChangeText={setCurrency}
            autoCapitalize="characters"
          />
          <Field label="Members, split by commas" value={members} onChangeText={setMembers} />
          <View style={{ flexDirection: 'row', gap: 8 }}>
            <Button quiet label="Cancel" onPress={() => setMode('list')} />
            <Button
              label="Make"
              testID="make"
              onPress={() =>
                run(() =>
                  library.create(
                    name,
                    currency.trim().toUpperCase(),
                    members
                      .split(',')
                      .map((s) => s.trim())
                      .filter((s) => s.length > 0),
                  ),
                )
              }
            />
          </View>
        </View>
      )}
      {mode === 'join' && (
        <View style={{ padding: 16 }}>
          <Field label="Group id" value={groupId} onChangeText={setGroupId} autoCapitalize="none" />
          <View style={{ flexDirection: 'row', gap: 8 }}>
            <Button quiet label="Cancel" onPress={() => setMode('list')} />
            <Button label="Join group" onPress={() => run(() => library.join(groupId))} />
          </View>
        </View>
      )}
      <ScrollView>
        {library.books.length === 0 ? (
          <Text style={styles.empty}>No groups yet. Make 1, or join 1 with its id.</Text>
        ) : (
          library.books.map((book) => (
            <Row key={book.meta.id} onPress={() => onOpen(book)}>
              <View style={styles.grow}>
                <Text style={{ fontSize: 16 }}>{book.meta.name}</Text>
                <Text style={styles.muted}>
                  {`${book.state.members.length} members, ${book.meta.currency}`}
                  {book.pending.length > 0 ? `, ${book.pending.length} not sent` : ''}
                </Text>
              </View>
            </Row>
          ))
        )}
      </ScrollView>
    </View>
  );
}
