import { fireEvent, render, screen } from '@testing-library/react-native';

import App, { SplitkenApp } from '../src/App';
import { Library } from '../src/library';
import { MemoryStore } from '../src/storage';
import { FakeServer } from './fakeServer';

test('add an expense, see the split, then the settle-up', async () => {
  const library = await Library.load(new FakeServer().client(), new MemoryStore());
  await library.create('Trip', 'CAD', ['Ana', 'Ben', 'Cy']);
  await render(<SplitkenApp library={library} />);

  expect(screen.getByText('Trip')).toBeOnTheScreen();
  expect(screen.getByText('3 members, CAD')).toBeOnTheScreen();
  await fireEvent.press(screen.getByText('Trip'));
  expect(screen.getByText('No expenses yet.')).toBeOnTheScreen();

  await fireEvent.press(screen.getByText('Add an expense'));
  await fireEvent.changeText(screen.getByTestId('description'), 'Pizza');
  await fireEvent.changeText(screen.getByTestId('amount'), '10');
  expect(screen.getByTestId('part-m1')).toHaveTextContent('3.34 CAD');
  expect(screen.getByTestId('part-m2')).toHaveTextContent('3.33 CAD');
  expect(screen.getByTestId('part-m3')).toHaveTextContent('3.33 CAD');

  await fireEvent.press(screen.getByText('Shares'));
  expect(screen.getByTestId('problem')).toBeOnTheScreen();
  await fireEvent.changeText(screen.getByTestId('weight-m1'), '2');
  await fireEvent.changeText(screen.getByTestId('weight-m2'), '1');
  await fireEvent.changeText(screen.getByTestId('weight-m3'), '1');
  expect(screen.getByTestId('part-m1')).toHaveTextContent('5.00 CAD');
  expect(screen.getByTestId('part-m2')).toHaveTextContent('2.50 CAD');

  await fireEvent.press(screen.getByTestId('save'));
  expect(await screen.findByText('Pizza')).toBeOnTheScreen();
  expect(screen.getByText('10.00 CAD')).toBeOnTheScreen();

  await fireEvent.press(screen.getByText('Balances'));
  expect(screen.getByText('+5.00')).toBeOnTheScreen();
  expect(screen.getAllByText('-2.50')).toHaveLength(2);
  expect(screen.getByText('Ben pays Ana')).toBeOnTheScreen();
  expect(screen.getByText('Cy pays Ana')).toBeOnTheScreen();
});

test('the home screen with no groups', async () => {
  const library = await Library.load(new FakeServer().client(), new MemoryStore());
  await render(<SplitkenApp library={library} />);
  expect(screen.getByText(/No groups yet/)).toBeOnTheScreen();
  expect(screen.getByText('New group')).toBeOnTheScreen();
  expect(screen.getByText('Join')).toBeOnTheScreen();
});

test('the app loads its groups from storage on start', async () => {
  const server = new FakeServer();
  const store = new MemoryStore();
  const first = await Library.load(server.client(), store);
  await first.create('Cabin', 'USD', ['Ana', 'Ben']);
  await render(<App store={store} api={server.client()} />);
  expect(await screen.findByText('Cabin')).toBeOnTheScreen();
  expect(screen.getByText('2 members, USD')).toBeOnTheScreen();
});
