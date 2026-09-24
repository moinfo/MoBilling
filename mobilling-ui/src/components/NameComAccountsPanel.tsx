import { useState } from 'react';
import { Modal, Stack, Group, Text, TextInput, PasswordInput, Checkbox, Button, Alert, Badge, Loader, Center, Code, Paper } from '@mantine/core';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useMediaQuery } from '@mantine/hooks';
import { notifications } from '@mantine/notifications';
import { IconPlus } from '@tabler/icons-react';
import {
  listNameComAccounts, createNameComAccount, updateNameComAccount, deleteNameComAccountById, testNameComAccountById, NameComAccountRow,
} from '../api/namecomAccounts';

const errMsg = (e: any): string =>
  e?.response?.data?.message
  || (e?.response?.data?.errors ? Object.values(e.response.data.errors).flat().join(' ') : null)
  || e?.message || 'Something went wrong';

/** Connection tab: several Name.com API logins (e.g. the owner and a second user). Tokens are write-only. */
export default function NameComAccountsPanel() {
  const qc = useQueryClient();
  const { data, isLoading } = useQuery({ queryKey: ['namecom-accounts'], queryFn: listNameComAccounts });
  const accounts = data?.data?.data ?? [];
  const [editing, setEditing] = useState<NameComAccountRow | 'new' | null>(null);
  const refresh = () => { qc.invalidateQueries({ queryKey: ['namecom-accounts'] }); qc.invalidateQueries({ queryKey: ['namecom-account-options'] }); };

  const test = useMutation({
    mutationFn: (id: string) => testNameComAccountById(id),
    onSuccess: (r) => { notifications.show({ color: 'green', message: r.data.message }); refresh(); },
    onError: (e) => { notifications.show({ color: 'red', message: errMsg(e) }); refresh(); },
  });
  const makeDefault = useMutation({
    mutationFn: (id: string) => updateNameComAccount(id, { is_default: true }),
    onSuccess: (r) => { notifications.show({ color: 'green', message: `"${r.data.data.label}" is now the default account.` }); refresh(); },
    onError: (e) => notifications.show({ color: 'red', message: errMsg(e) }),
  });
  const remove = useMutation({
    mutationFn: async (a: NameComAccountRow) => {
      const msg = a.linked_domains > 0
        ? `${a.linked_domains} linked domain(s) use "${a.label}". If you remove it their nameservers fall back to the default account and may stop working. Remove anyway?`
        : `Remove "${a.label}" from MoBilling? Nothing is changed at Name.com.`;
      if (!window.confirm(msg)) return null;
      return deleteNameComAccountById(a.id, a.linked_domains > 0);
    },
    onSuccess: (r) => { if (r) { notifications.show({ color: 'green', message: r.data.message }); refresh(); } },
    onError: (e) => notifications.show({ color: 'red', message: errMsg(e) }),
  });

  if (isLoading) return <Center py="md"><Loader size="sm" /></Center>;

  return (
    <Stack>
      <Text size="sm" c="dimmed">
        Add one API login for every Name.com username that owns domains (for example the owner and a second user you gave access).
        MoBilling reads each account with its own token, and remembers which account every linked domain belongs to.
        Renewals, transfers and deletions are never done through the API.
      </Text>
      <Alert color="blue" variant="light" title="Why one entry per username?">
        Name.com only lists the domains owned by the account whose token is used. Domains registered by another
        Name.com user are not visible with your token, so add that user&apos;s own API token as a second account here.
        Create the token at Name.com (Account &gt; Settings &gt; API Token Management) while signed in as that user, with two-step verification (2FA) off.
      </Alert>

      {accounts.length === 0 && <Text size="sm" c="dimmed">No Name.com account connected yet.</Text>}
      {accounts.map((a) => (
        <Paper key={a.id} withBorder p="sm" radius="md">
          <Group justify="space-between" wrap="wrap" align="flex-start">
            <div style={{ minWidth: 0 }}>
              <Group gap="xs" wrap="wrap">
                <Text fw={600}>{a.label}</Text>
                {a.is_default && <Badge variant="light">Default</Badge>}
                <Badge color={a.status === 'active' ? 'green' : 'red'} variant="light">{a.status}</Badge>
                {a.is_sandbox && <Badge color="orange" variant="light">sandbox</Badge>}
              </Group>
              <Text size="sm">Name.com username: <b>{a.username}</b></Text>
              <Text size="xs" c="dimmed">Token <Code>{a.token_hint}</Code>
                {a.last_verified_at ? ` - verified ${new Date(a.last_verified_at).toLocaleString()}` : ''} - {a.linked_domains} linked domain{a.linked_domains === 1 ? '' : 's'}</Text>
              {a.status_message && <Text size="xs" c="red">{a.status_message}</Text>}
            </div>
            <Group gap="xs" wrap="wrap">
              <Button size="xs" variant="light" loading={test.isPending && test.variables === a.id} onClick={() => test.mutate(a.id)}>Test</Button>
              <Button size="xs" variant="light" onClick={() => setEditing(a)}>Edit / rotate token</Button>
              {!a.is_default && <Button size="xs" variant="subtle" loading={makeDefault.isPending && makeDefault.variables === a.id} onClick={() => makeDefault.mutate(a.id)}>Make default</Button>}
              <Button size="xs" variant="subtle" color="red" onClick={() => remove.mutate(a)}>Remove</Button>
            </Group>
          </Group>
        </Paper>
      ))}
      <Text size="xs" c="dimmed">
        The default account is used for TLD price sync, availability checks and new registrations (staff can pick another account when confirming a registration).
      </Text>
      <Group>
        <Button leftSection={<IconPlus size={16} />} onClick={() => setEditing('new')}>Add Name.com account</Button>
      </Group>
      {editing && <AccountForm account={editing === 'new' ? null : editing} isFirst={accounts.length === 0} onClose={() => setEditing(null)} onDone={() => { setEditing(null); refresh(); }} />}
    </Stack>
  );
}

function AccountForm({ account, isFirst, onClose, onDone }: { account: NameComAccountRow | null; isFirst: boolean; onClose: () => void; onDone: () => void }) {
  const mobile = useMediaQuery('(max-width: 48em)');
  const [label, setLabel] = useState(account?.label ?? '');
  const [username, setUsername] = useState(account?.username ?? '');
  const [token, setToken] = useState('');
  const [sandbox, setSandbox] = useState(account?.is_sandbox ?? false);
  const [asDefault, setAsDefault] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const save = useMutation({
    mutationFn: () => account
      ? updateNameComAccount(account.id, { label: label.trim(), username: username.trim(), token: token.trim() || undefined, is_sandbox: sandbox, is_default: asDefault || undefined })
      : createNameComAccount({ label: label.trim(), username: username.trim(), token: token.trim(), is_sandbox: sandbox, is_default: asDefault || undefined }),
    onSuccess: (r) => { notifications.show({ color: 'green', message: r.data.message }); onDone(); },
    onError: (e) => setError(errMsg(e)),
  });

  return (
    <Modal opened onClose={onClose} title={account ? `Edit "${account.label}"` : 'Add Name.com account'} fullScreen={!!mobile} zIndex={400}>
      <Stack>
        {error && <Alert color="red">{error}</Alert>}
        <TextInput label="Label" description="A name for you, e.g. Owner account or Second user" value={label} onChange={(e) => setLabel(e.currentTarget.value)} maxLength={60} />
        <TextInput label="Name.com username" value={username} onChange={(e) => setUsername(e.currentTarget.value)} placeholder="The Name.com login that owns the domains" />
        <PasswordInput label={account ? 'New API token (leave empty to keep the current one)' : 'API token'} value={token}
          onChange={(e) => setToken(e.currentTarget.value)} autoComplete="off" description="Write-only: stored encrypted and never shown again." />
        <Checkbox label="Use the Name.com sandbox (testing only)" checked={sandbox} onChange={(e) => setSandbox(e.currentTarget.checked)} />
        {!isFirst && !account?.is_default && <Checkbox label="Make this the default account" checked={asDefault} onChange={(e) => setAsDefault(e.currentTarget.checked)} />}
        <Text size="xs" c="dimmed">The credentials are checked with a read-only call to Name.com before they are saved.</Text>
        <Group justify="flex-end">
          <Button variant="default" onClick={onClose}>Cancel</Button>
          <Button loading={save.isPending} disabled={label.trim().length < 2 || !username.trim() || (!account && !token.trim())} onClick={() => { setError(null); save.mutate(); }}>
            {account ? 'Save' : 'Verify and add'}
          </Button>
        </Group>
      </Stack>
    </Modal>
  );
}
