import type { ReactNode } from 'react';
import { Pressable, StyleSheet, Text, TextInput, type TextInputProps, View } from 'react-native';

export const colors = {
  accent: '#00796b',
  owed: '#2e7d32',
  owes: '#c62828',
  line: '#d0d7d6',
  muted: '#5f6b6a',
};

export function Button({
  label,
  onPress,
  disabled,
  testID,
  quiet,
}: {
  label: string;
  onPress: () => void;
  disabled?: boolean;
  testID?: string;
  quiet?: boolean;
}) {
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityState={{ disabled: !!disabled }}
      testID={testID}
      disabled={disabled}
      onPress={onPress}
      style={[styles.button, quiet && styles.quiet, disabled && styles.disabled]}
    >
      <Text style={[styles.buttonText, quiet && styles.quietText]}>{label}</Text>
    </Pressable>
  );
}

export function Field(props: TextInputProps & { label: string }) {
  return (
    <View style={styles.field}>
      <Text style={styles.label}>{props.label}</Text>
      <TextInput accessibilityLabel={props.label} style={styles.input} {...props} />
    </View>
  );
}

export function Row({
  children,
  onPress,
  onLongPress,
}: {
  children: ReactNode;
  onPress?: () => void;
  onLongPress?: () => void;
}) {
  return (
    <Pressable onPress={onPress} onLongPress={onLongPress} style={styles.row}>
      {children}
    </Pressable>
  );
}

export const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: '#fff' },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    padding: 16,
    borderBottomWidth: 1,
    borderColor: colors.line,
  },
  title: { fontSize: 20, fontWeight: '600', flex: 1 },
  button: {
    backgroundColor: colors.accent,
    paddingHorizontal: 14,
    paddingVertical: 10,
    borderRadius: 8,
  },
  buttonText: { color: '#fff', fontWeight: '600' },
  quiet: { backgroundColor: 'transparent' },
  quietText: { color: colors.accent },
  disabled: { opacity: 0.4 },
  field: { marginBottom: 12 },
  label: { color: colors.muted, marginBottom: 4 },
  input: { borderWidth: 1, borderColor: colors.line, borderRadius: 8, padding: 10, fontSize: 16 },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderBottomWidth: 1,
    borderColor: colors.line,
    gap: 8,
  },
  grow: { flex: 1 },
  muted: { color: colors.muted },
  banner: {
    backgroundColor: '#fff3e0',
    padding: 12,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  empty: { padding: 32, textAlign: 'center', color: colors.muted },
  tabs: { flexDirection: 'row', borderBottomWidth: 1, borderColor: colors.line },
  tab: { flex: 1, padding: 12, alignItems: 'center' },
  tabOn: { borderBottomWidth: 3, borderColor: colors.accent },
  chip: {
    borderWidth: 1,
    borderColor: colors.line,
    borderRadius: 16,
    paddingHorizontal: 12,
    paddingVertical: 6,
  },
  chipOn: { backgroundColor: colors.accent, borderColor: colors.accent },
  weight: { width: 90, borderWidth: 1, borderColor: colors.line, borderRadius: 8, padding: 8 },
});
