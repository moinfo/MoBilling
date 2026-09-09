import { useState } from 'react';
import {
  Title, Text, Paper, Stack, Group, Table, Badge, Button, Select, Modal, TextInput, Textarea,
  SimpleGrid, Pagination,
} from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconCash, IconCheck } from '@tabler/icons-react';
import {
  getWifiSettlements, getWifiSettlementsSummary, settleWifiVoucherPurchase, WifiSettlementRow,
} from '../../api/admin';
import { formatCurrency } from '../../utils/formatCurrency';
import { formatDate } from '../../utils/formatDate';

const METHOD_OPTIONS = [
  { value: 'mpesa', label: 'M-Pesa / Mobile Money' },
  { value: 'bank', label: 'Bank Transfer' },
  { value: 'cash', label: 'Cash' },
  { value: 'pesapal', label: 'Pesapal' },
  { value: 'other', label: 'Other' },
];

export default function WifiSettlements() {
  const queryClient = useQueryClient();
  const [page, setPage] = useState(1);
  const [filterTenant, setFilterTenant] = useState<string | null>(null);
  const [filterSettled, setFilterSettled] = useState<string | null>('false');
  const [settling, setSettling] = useState<WifiSettlementRow | null>(null);
  const [method, setMethod] = useState<string | null>('mpesa');
  const [reference, setReference] = useState('');
  const [notes, setNotes] = useState('');

  const { data: summaryData } = useQuery({
    queryKey: ['wifi-settlements-summary'],
    queryFn: getWifiSettlementsSummary,
  });
  const summary = summaryData?.data?.data ?? [];

  const { data } = useQuery({
    queryKey: ['wifi-settlements', page, filterTenant, filterSettled],
    queryFn: () => getWifiSettlements({
      page,
      tenant_id: filterTenant || undefined,
      settled: filterSettled === null ? undefined : filterSettled === 'true',
    }),
  });
  const items: WifiSettlementRow[] = data?.data?.data || [];
  const meta = data?.data?.meta;

  const tenantOptions = summary.map((s) => ({ value: s.tenant_id, label: s.tenant_name }));

  const settleMutation = useMutation({
    mutationFn: () => settleWifiVoucherPurchase(settling!.id, { method: method!, reference: reference || undefined, notes: notes || undefined }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['wifi-settlements'] });
      queryClient.invalidateQueries({ queryKey: ['wifi-settlements-summary'] });
      notifications.show({ title: 'Settled', message: 'Marked as paid.', color: 'green' });
      closeSettle();
    },
    onError: (err: any) => notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed to settle', color: 'red' }),
  });

  const openSettle = (row: WifiSettlementRow) => {
    setSettling(row);
    setMethod('mpesa');
    setReference('');
    setNotes('');
  };
  const closeSettle = () => setSettling(null);

  return (
    <Stack gap="lg">
      <div>
        <Title order={2} mb={4}>WiFi Settlements</Title>
        <Text c="dimmed">Money MoBilling collected on behalf of hotspot owners (platform-collected routers) — pay them out by hand, then mark it settled here.</Text>
      </div>

      {summary.length > 0 && (
        <SimpleGrid cols={{ base: 1, sm: 2, md: 3 }}>
          {summary.map((s) => (
            <Paper key={s.tenant_id} withBorder p="md" radius="md">
              <Text size="sm" c="dimmed">{s.tenant_name}</Text>
              <Text size="xl" fw={800} c="orange">{formatCurrency(s.total_owed)}</Text>
              <Text size="xs" c="dimmed">{s.count} unsettled voucher{s.count === 1 ? '' : 's'}</Text>
            </Paper>
          ))}
        </SimpleGrid>
      )}

      <Group wrap="wrap">
        <Select placeholder="All tenants" data={tenantOptions} clearable searchable
          value={filterTenant} onChange={(v) => { setFilterTenant(v); setPage(1); }} maw={220} />
        <Select placeholder="All" data={[{ value: 'false', label: 'Unsettled' }, { value: 'true', label: 'Settled' }]}
          clearable value={filterSettled} onChange={(v) => { setFilterSettled(v); setPage(1); }} maw={160} />
      </Group>

      {items.length === 0 ? (
        <Text c="dimmed" ta="center" py="xl">No platform-collected voucher sales yet</Text>
      ) : (
        <Table.ScrollContainer minWidth={900}>
          <Table striped highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Date</Table.Th>
                <Table.Th>Tenant</Table.Th>
                <Table.Th>Phone</Table.Th>
                <Table.Th style={{ textAlign: 'right' }}>Amount</Table.Th>
                <Table.Th style={{ textAlign: 'right' }}>Commission</Table.Th>
                <Table.Th style={{ textAlign: 'right' }}>Owed</Table.Th>
                <Table.Th>Status</Table.Th>
                <Table.Th w={120}>Action</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {items.map((r) => (
                <Table.Tr key={r.id}>
                  <Table.Td>{r.completed_at ? formatDate(r.completed_at) : '—'}</Table.Td>
                  <Table.Td>{r.tenant_name}</Table.Td>
                  <Table.Td>{r.customer_phone}</Table.Td>
                  <Table.Td style={{ textAlign: 'right' }}>{formatCurrency(r.amount)}</Table.Td>
                  <Table.Td style={{ textAlign: 'right' }} c="dimmed">−{formatCurrency(r.commission_amount)}</Table.Td>
                  <Table.Td style={{ textAlign: 'right' }} fw={600}>{formatCurrency(r.net_amount)}</Table.Td>
                  <Table.Td>
                    {r.settled_at ? (
                      <Badge size="sm" variant="light" color="green" leftSection={<IconCheck size={10} />}>Settled</Badge>
                    ) : (
                      <Badge size="sm" variant="light" color="orange">Owed</Badge>
                    )}
                  </Table.Td>
                  <Table.Td>
                    {!r.settled_at && (
                      <Button size="compact-xs" variant="light" color="green" leftSection={<IconCash size={13} />}
                        onClick={() => openSettle(r)}>
                        Mark Paid
                      </Button>
                    )}
                  </Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      )}

      {meta && meta.last_page > 1 && (
        <Group justify="center">
          <Pagination total={meta.last_page} value={page} onChange={setPage} />
        </Group>
      )}

      <Modal opened={!!settling} onClose={closeSettle} title="Mark as Settled" size="md">
        {settling && (
          <Stack>
            <Text size="sm">
              Confirm you have paid <b>{settling.tenant_name}</b> <b>{formatCurrency(settling.net_amount)}</b> outside
              the app (mobile money, bank transfer, or cash), then record it here.
            </Text>
            <Select label="Method" required data={METHOD_OPTIONS} value={method} onChange={setMethod} />
            <TextInput label="Reference (optional)" placeholder="e.g. M-Pesa transaction code"
              value={reference} onChange={(e) => setReference(e.currentTarget.value)} />
            <Textarea label="Notes (optional)" value={notes} onChange={(e) => setNotes(e.currentTarget.value)} />
            <Group justify="flex-end">
              <Button variant="default" onClick={closeSettle}>Cancel</Button>
              <Button color="green" loading={settleMutation.isPending} onClick={() => settleMutation.mutate()}>
                Confirm Settlement
              </Button>
            </Group>
          </Stack>
        )}
      </Modal>
    </Stack>
  );
}
