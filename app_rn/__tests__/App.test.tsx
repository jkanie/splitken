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

  // The same weights read as exact amounts, then as percentages, say what is left to assign.
  await fireEvent.press(screen.getByText('Exact'));
  expect(screen.getByTestId('problem')).toHaveTextContent(
    'The exact parts add up to 4.00, not 10.00: 6.00 is left to assign.',
  );
  await fireEvent.press(screen.getByText('%'));
  expect(screen.getByTestId('problem')).toHaveTextContent(
    'The percentages add up to 4%, not 100%: 96% is left to assign.',
  );
  await fireEvent.press(screen.getByText('Shares'));
  expect(screen.queryByTestId('problem')).toBeNull();

  await fireEvent.press(screen.getByTestId('save'));
  expect(await screen.findByText('Pizza')).toBeOnTheScreen();
  expect(screen.getByText('10.00 CAD')).toBeOnTheScreen();
  expect(screen.getByText('Ana paid, split 3 ways by shares')).toBeOnTheScreen();

  await fireEvent.press(screen.getByText('Balances'));
  expect(screen.getByText('+5.00')).toBeOnTheScreen();
  expect(screen.getAllByText('-2.50')).toHaveLength(2);
  // What each member paid and owes, which the balance is the difference of.
  expect(screen.getByText('Spent 10.00 CAD')).toBeOnTheScreen();
  expect(screen.getByText('Paid 10.00, share 5.00')).toBeOnTheScreen();
  expect(screen.getAllByText('Paid 0.00, share 2.50')).toHaveLength(2);
  expect(screen.getByText('Ben pays Ana')).toBeOnTheScreen();
  expect(screen.getByText('Cy pays Ana')).toBeOnTheScreen();

  await fireEvent.press(screen.getByText('Members'));
  expect(screen.getByText('Paid for 1 expense')).toBeOnTheScreen();
  expect(screen.getAllByText('No expenses paid yet')).toHaveLength(2);
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
