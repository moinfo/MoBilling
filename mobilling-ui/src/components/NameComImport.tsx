import { useMemo, useState } from 'react';
import { Modal, Stack, Group, Text, Button, Alert, Badge, Table, Select, ScrollArea, Loader, Center } from '@mantine/core';
import { useQuery, useMutation, useQueryClient, keepPreviousData } from '@tanstack/react-query';
import { useDebouncedValue, useMediaQuery } from '@mantine/hooks';
import { notifications } from '@mantine/notifications';
import { IconDownload, IconLink } from '@tabler/icons-react';
import {
  listNameComAccountOptions, importNameComDomains, linkNameComDomainTo, bulkLinkMatched, NameComImportRow, BulkLinkResult,
} from '../api/namecomAccounts';
import { getClients } from '../api/clients';

const errMsg = (e: any): string =>
  e?.response?.data?.message
  || (e?.response?.data?.errors ? Object.values(e.response.data.errors).flat().join(' ') : null)
  || e?.message || 'Something went wrong';

// Server-side client search (never loads every client).
function useClientOptions(search: string) {
  const [debounced] = useDebouncedValue(search, 300);
  const { data } = useQuery({
    queryKey: ['namecom-client-options', debounced],
    queryFn: () => getClients({ per_page: 50, status: 'all', search: debounced || undefined } as any),
    placeholderData: keepPreviousData,
    staleTime: 30_000,
  });
  const rows: any[] = data?.data?.data ?? [];
  return rows.map((c) => ({ value: String(c.id), label: c.email ? `${c.name} (${c.email})` : c.name }));
}

export default function NameComImport() {
  const qc = useQueryClient();
  const { data: opts } = useQuery({ queryKey: ['namecom-account-options'], queryFn: listNameComAccountOptions });
  const accounts = opts?.data?.data ?? [];
  const [accountId, setAccountId] = useState<string>('all');
  const [enabled, setEnabled] = useState(false);
  const { data, isFetching, error, refetch } = useQuery({
    queryKey: ['namecom-domains', accountId],
    queryFn: () => importNameComDomains(accountId),
    enabled,
    staleTime: 0,
    gcTime: 0,
    retry: false,
  });
  const rows: NameComImportRow[] = data?.data?.data ?? [];
  const errors = data?.data?.errors ?? [];
  const [linking, setLinking] = useState<NameComImportRow | null>(null);
  const [bulkOpen, setBulkOpen] = useState(false);

  const matched = useMemo(() => rows.filter((r) => r.in_mobilling && !r.linked && !r.fred_managed && r.client_id), [rows]);
  const isNew = (r: NameComImportRow) => !r.in_mobilling;
  const showAccount = accountId === 'all' && accounts.length > 1;
  const selectData = [{ value: 'all', label: accounts.length > 1 ? 'All accounts' : 'My account' }, ...accounts.filter(() => accounts.length > 1).map((a) => ({ value: a.id, label: `${a.label} (${a.username})` }))];

  const done = () => { qc.invalidateQueries({ queryKey: ['domains'] }); qc.invalidateQueries({ queryKey: ['domain-stats'] }); refetch(); };

  return (
    <Stack>
      <Text size="sm" c="dimmed">
        Reads the domains in a Name.com account (read-only) and lets you link each one to a client. Domains registered by another
        Name.com user only appear when that user&apos;s account is added under Connection.
      </Text>
      {accounts.length === 0 && <Alert color="orange" variant="light">No Name.com account is connected yet. Add one under Connection.</Alert>}
      <Group align="flex-end" wrap="wrap">
        {accounts.length > 1 && <Select label="Load from" data={selectData} value={accountId} allowDeselect={false}
          onChange={(v) => { setAccountId(v || 'all'); setEnabled(false); }} w={{ base: '100%', sm: 320 }} />}
        <Button leftSection={<IconDownload size={16} />} loading={isFetching} disabled={accounts.length === 0} onClick={() => (enabled ? refetch() : setEnabled(true))}>
          {enabled ? 'Reload list' : 'Load domains from Name.com'}
        </Button>
        {matched.length > 0 && (
          <Button variant="light" color="yellow" leftSection={<IconLink size={16} />} onClick={() => setBulkOpen(true)}>
            Link matched domains ({matched.length})
          </Button>
        )}
      </Group>
      {error && <Alert color="red">{errMsg(error)}</Alert>}
      {errors.map((e) => <Alert key={e.account_id} color="orange" variant="light" title={`Could not read "${e.account_label}"`}>{e.message}</Alert>)}
      {enabled && !isFetching && !error && rows.length === 0 && <Text size="sm" c="dimmed">No domains found.</Text>}
      {rows.length > 0 && (
        <>
          <Group gap="xs">
            <Badge variant="light">{rows.length} in Name.com</Badge>
            <Badge color="green" variant="light">{rows.filter((r) => r.linked).length} linked</Badge>
            <Badge color="yellow" variant="light">{matched.length} in MoBilling, not linked</Badge>
            <Badge color="gray" variant="light">{rows.filter(isNew).length} new</Badge>
          </Group>
          <ScrollArea>
            <Table striped withTableBorder miw={showAccount ? 760 : 640}>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Domain</Table.Th>
                  {showAccount && <Table.Th>Account</Table.Th>}
                  <Table.Th>Expires</Table.Th><Table.Th>Client</Table.Th><Table.Th>Status</Table.Th><Table.Th />
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {rows.map((r) => (
                  <Table.Tr key={r.name}>
                    <Table.Td>{r.name}</Table.Td>
                    {showAccount && <Table.Td>{r.account_label}</Table.Td>}
                    <Table.Td>{r.expires_at ?? '-'}</Table.Td>
                    <Table.Td>{r.client_name ?? '-'}</Table.Td>
                    <Table.Td>
                      {r.linked ? <Badge color="green" variant="light">Linked{r.linked_account_label && accounts.length > 1 ? ` (${r.linked_account_label})` : ''}</Badge>
                        : r.fred_managed ? <Badge color="gray" variant="light">.tz registry</Badge>
                        : r.in_mobilling ? <Badge color="yellow" variant="light">In MoBilling - not linked</Badge>
                        : <Badge color="gray" variant="light">New</Badge>}
                    </Table.Td>
                    <Table.Td>
                      {!r.fred_managed && (
                        <Button size="compact-xs" variant="light" onClick={() => setLinking(r)}>
                          {r.linked ? 'Change client' : r.in_mobilling ? 'Link / upgrade' : 'Link to client'}
                        </Button>
                      )}
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </ScrollArea>
        </>
      )}
      {linking && <LinkModal row={linking} showAccount={accounts.length > 1} onClose={() => setLinking(null)} onDone={() => { setLinking(null); done(); }} />}
      {bulkOpen && <BulkLinkModal rows={matched} newCount={rows.filter(isNew).length} onClose={() => setBulkOpen(false)} onDone={() => { setBulkOpen(false); done(); }} />}
    </Stack>
  );
}

function LinkModal({ row, showAccount, onClose, onDone }: { row: NameComImportRow; showAccount: boolean; onClose: () => void; onDone: () => void }) {
  const qc = useQueryClient();
  const [search, setSearch] = useState('');
  const found = useClientOptions(search);
  const [clientId, setClientId] = useState<string | null>(row.client_id);
  const [pickedLabel, setPickedLabel] = useState<string | null>(row.client_name);
  const options = clientId && !found.some((o) => o.value === clientId) && pickedLabel ? [{ value: clientId, label: pickedLabel }, ...found] : found;
  const [error, setError] = useState<string | null>(null);
  const m = useMutation({
    mutationFn: () => linkNameComDomainTo(row.name, clientId!, row.account_id),
    onSuccess: (r) => {
      notifications.show({ color: 'green', message: r.data.message });
      qc.invalidateQueries({ queryKey: ['domains'] });
      qc.invalidateQueries({ queryKey: ['domain-stats'] });
      onDone();
    },
    onError: (e) => setError(errMsg(e)),
  });
  return (
    <Modal opened onClose={onClose} title={`Link ${row.name}`} zIndex={400}>
      <Stack>
        {error && <Alert color="red">{error}</Alert>}
        <Text size="sm" c="dimmed">
          The domain is recorded under this client with its expiry date from Name.com, and its nameservers can then be
          changed from MoBilling (staff and the client portal).
        </Text>
        {showAccount && <Text size="sm">Managed through Name.com account: <b>{row.account_label}</b></Text>}
        <Select label="Client" data={options} value={clientId}
          onChange={(v) => { setClientId(v); setPickedLabel(options.find((o) => o.value === v)?.label ?? null); }}
          searchValue={search} onSearchChange={setSearch} filter={({ options }) => options}
          nothingFoundMessage="No client found" searchable clearable placeholder="Search name, email or phone" />
        <Button disabled={!clientId} loading={m.isPending} onClick={() => { setError(null); m.mutate(); }}>Link domain</Button>
      </Stack>
    </Modal>
  );
}

const CHUNK = 25;

/** Preview (server-verified, no changes) then explicit confirm. The client comes from the MoBilling row, not from this page. */
function BulkLinkModal({ rows, newCount, onClose, onDone }: { rows: NameComImportRow[]; newCount: number; onClose: () => void; onDone: () => void }) {
  const mobile = useMediaQuery('(max-width: 48em)');
  const items = rows.map((r) => ({ domain_name: r.name, account_id: r.account_id }));
  const byName = new Map(rows.map((r) => [r.name, r]));
  const preview = useQuery({
    queryKey: ['namecom-bulk-preview', items.map((i) => i.domain_name).join(',')],
    queryFn: async () => {
      const out: BulkLinkResult[] = [];
      for (let i = 0; i < items.length; i += 50) out.push(...(await bulkLinkMatched(items.slice(i, i + 50), false)).data.data);
      return out;
    },
    gcTime: 0, staleTime: 0, retry: false,
  });
  const [results, setResults] = useState<BulkLinkResult[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const ready = (preview.data ?? []).filter((p) => p.status === 'ready');

  const run = useMutation({
    mutationFn: async () => {
      const out: BulkLinkResult[] = [];
      const todo = ready.map((p) => ({ domain_name: p.name, account_id: byName.get(p.name)!.account_id }));
      for (let i = 0; i < todo.length; i += CHUNK) out.push(...(await bulkLinkMatched(todo.slice(i, i + CHUNK), true)).data.data);
      return out;
    },
    onSuccess: (out) => {
      setResults(out);
      notifications.show({ color: 'green', message: `${out.filter((o) => o.status === 'linked').length} domain(s) linked.` });
    },
    onError: (e) => setError(errMsg(e)),
  });

  return (
    <Modal opened onClose={results ? onDone : onClose} title="Link matched domains" size="lg" fullScreen={!!mobile} zIndex={400}>
      <Stack>
        {error && <Alert color="red">{error}</Alert>}
        {!results && (
          <>
            <Text size="sm" c="dimmed">
              These domains already exist in MoBilling and also exist in Name.com. Linking attaches each one to the Name.com account shown,
              keeps the client already on the MoBilling record, and lets nameservers be managed from MoBilling. Nothing changes until you confirm.
            </Text>
            {preview.isLoading && <Center py="md"><Loader size="sm" /></Center>}
            {preview.error && <Alert color="red">{errMsg(preview.error)}</Alert>}
            {preview.data && (
              <ScrollArea.Autosize mah={360}>
                <Table striped withTableBorder miw={520}>
                  <Table.Thead><Table.Tr><Table.Th>Domain</Table.Th><Table.Th>MoBilling client</Table.Th><Table.Th>Name.com account</Table.Th><Table.Th>Result</Table.Th></Table.Tr></Table.Thead>
                  <Table.Tbody>
                    {preview.data.map((p) => (
                      <Table.Tr key={p.name}>
                        <Table.Td>{p.name}</Table.Td>
                        <Table.Td>{p.client_name ?? byName.get(p.name)?.client_name ?? '-'}</Table.Td>
                        <Table.Td>{byName.get(p.name)?.account_label ?? '-'}</Table.Td>
                        <Table.Td>{p.status === 'ready' ? <Badge color="green" variant="light">Will link</Badge>
                          : p.status === 'new' ? <Badge color="gray" variant="light">New - no client match</Badge>
                          : <Badge color="gray" variant="light">{p.message ?? 'Skipped'}</Badge>}</Table.Td>
                      </Table.Tr>
                    ))}
                  </Table.Tbody>
                </Table>
              </ScrollArea.Autosize>
            )}
            {newCount > 0 && <Text size="xs" c="dimmed">{newCount} other domain(s) in Name.com have no MoBilling record (New). They are not touched here - use &quot;Link to client&quot; on each.</Text>}
            <Group justify="flex-end">
              <Button variant="default" onClick={onClose}>Cancel</Button>
              <Button disabled={ready.length === 0} loading={run.isPending} onClick={() => { setError(null); run.mutate(); }}>
                Confirm: link {ready.length} domain{ready.length === 1 ? '' : 's'}
              </Button>
            </Group>
          </>
        )}
        {results && (
          <>
            <Text size="sm" fw={600}>{results.filter((r) => r.status === 'linked').length} linked, {results.filter((r) => r.status === 'failed').length} failed.</Text>
            {results.filter((r) => r.status === 'failed').map((r) => <Alert key={r.name} color="red" variant="light">{r.name}: {r.message}</Alert>)}
            <Group justify="flex-end"><Button onClick={onDone}>Done</Button></Group>
          </>
        )}
      </Stack>
    </Modal>
  );
}
