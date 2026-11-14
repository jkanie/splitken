import { StatusBar } from 'expo-status-bar';
import { useEffect, useState } from 'react';
import { ActivityIndicator } from 'react-native';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';

import { ApiClient } from './api';
import type { Expense } from './core';
import type { GroupBook } from './groupBook';
import { Library } from './library';
import { ExpenseForm } from './screens/ExpenseForm';
import { GroupScreen } from './screens/GroupScreen';
import { HomeScreen } from './screens/HomeScreen';
import { styles } from './screens/ui';
import { type KeyValueStore, asyncStorageStore } from './storage';

/** The server to sync with. Set EXPO_PUBLIC_SPLITKEN_API when starting Expo. */
export const apiBase = process.env.EXPO_PUBLIC_SPLITKEN_API ?? 'http://localhost:8080';

type Route =
  | { name: 'home' }
  | { name: 'group'; book: GroupBook }
  | { name: 'expense'; book: GroupBook; editing?: Expense };

export function SplitkenApp({ library }: { library: Library }) {
  const [route, setRoute] = useState<Route>({ name: 'home' });
  switch (route.name) {
    case 'home':
      return <HomeScreen library={library} onOpen={(book) => setRoute({ name: 'group', book })} />;
    case 'group':
      return (
        <GroupScreen
          book={route.book}
          onBack={() => setRoute({ name: 'home' })}
          onEdit={(editing) => setRoute({ name: 'expense', book: route.book, editing })}
        />
      );
    case 'expense':
      return (
        <ExpenseForm
          book={route.book}
          editing={route.editing}
          onDone={() => setRoute({ name: 'group', book: route.book })}
        />
      );
  }
}

const defaultApi = new ApiClient(apiBase);

export default function App({
  store = asyncStorageStore,
  api = defaultApi,
}: {
  store?: KeyValueStore;
  api?: ApiClient;
}) {
  const [library, setLibrary] = useState<Library | null>(null);
  useEffect(() => {
    Library.load(api, store).then(setLibrary);
  }, [api, store]);
  return (
    <SafeAreaProvider>
      <SafeAreaView style={styles.screen}>
        <StatusBar style="auto" />
        {library ? (
          <SplitkenApp library={library} />
        ) : (
          <ActivityIndicator style={{ marginTop: 64 }} />
        )}
      </SafeAreaView>
    </SafeAreaProvider>
  );
}
