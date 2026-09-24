import { useState } from 'react';
import {
  Stack, Group, Text, Button, NumberInput, Switch, Alert, Table, Badge, TextInput, Select, ScrollArea, Pagination, Modal, Paper, Loader, Center, ActionIcon, Tooltip, SimpleGrid,
} from '@mantine/core';
import { useQuery, useMutation, useQueryClient, keepPreviousData } from '@tanstack/react-query';
import { useDebouncedValue } from '@mantine/hooks';
import { notifications } from '@mantine/notifications';
import { modals } from '@mantine/modals';
import { IconRefresh, IconEdit, IconAlertTriangle, IconStar, IconStarFilled } from '@tabler/icons-react';
import {
  listNameComTlds, syncNameComTlds, recomputeNameComTlds, ackNameComTlds, updateNameComTld, saveNameComSettings, NameComTldRow, NameComSettingsData,
} from '../api/namecom';

const errMsg = (e: any): string =>
  e?.response?.data?.message || (e?.response?.data?.errors ? Object.values(e.response.data.errors).flat().join(' ') : null) || e?.message || 'Something went wrong';
const usd = (v: number | null) => (v === null || v === undefined ? '-' : `$${Number(v).toFixed(2)}`);
const tzs = (v: number | null) => (v === null || v === undefined ? '-' : Number(v).toLocaleString('en-US', { maximumFractionDigits: 0 }));

export default function NameComPricingPanel() {
  const qc = useQueryClient();
  const [search, setSearch] = useState('');
  const [debounced] = useDebouncedValue(search, 300);
  const [filter, setFilter] = useState<string | null>(null);
  const [page, setPage] = useState(1);
  const [editing, setEditing] = useState<NameComTldRow | null>(null);

  const { data, isFetching, isLoading } = useQuery({
    queryKey: ['namecom-tlds', debounced, filter, page],
    queryFn: () => listNameComTlds({ search: debounced || undefined, filter: filter || undefined, page }),
    placeholderData: keepPreviousData,
  });
  const list = data?.data;
  const rows = list?.data ?? [];
  const refresh = () => qc.invalidateQueries({ queryKey: ['namecom-tlds'] });

  const sync = useMutation({
    mutationFn: syncNameComTlds,
    onSuccess: (r) => { notifications.show({ color: 'green', message: r.data.message }); refresh(); },
    onError: (e) => notifications.show({ color: 'red', message: errMsg(e) }),
  });
  const recompute = useMutation({
    mutationFn: recomputeNameComTlds,
    onSuccess: (r) => { notifications.show({ color: 'green', message: r.data.message }); refresh(); },
    onError: (e) => notifications.show({ color: 'red', message: errMsg(e) }),
  });
  const ack = useMutation({
    mutationFn: () => ackNameComTlds(),
    onSuccess: (r) => { notifications.show({ color: 'green', message: r.data.message }); refresh(); },
  });
  const star = useMutation({
    mutationFn: (v: { tld: string; is_popular: boolean }) => updateNameComTld(v.tld, { is_popular: v.is_popular }),
    onSuccess: refresh,
    onError: (e) => notifications.show({ color: 'red', message: errMsg(e) }),
  });
  const toggle = useMutation({
    mutationFn: (v: { tld: string; is_active: boolean }) => updateNameComTld(v.tld, { is_active: v.is_active }),
    onSuccess: refresh,
    onError: (e) => notifications.show({ color: 'red', message: errMsg(e) }),
  });

  return (
    <Stack>
      <SettingsCard settings={list?.settings} onSaved={refresh} onRecompute={() => recompute.mutate()} recomputing={recompute.isPending} />

      <Group justify="space-between" wrap="wrap">
        <Group gap="xs">
          <Button leftSection={<IconRefresh size={16} />} loading={sync.isPending}
            onClick={() => modals.openConfirmModal({
              title: 'Sync TLDs & prices from Name.com',
              children: <Text size="sm">Reads the full TLD list and your USD prices from Name.com (read-only, a few paced requests). New TLDs are added <b>disabled</b>; old manual placeholders such as .com/.net/.org become Name.com rows (also disabled until you switch them on). Your price overrides and enabled/disabled choices are kept; TLDs whose USD cost changed are flagged.</Text>,
              labels: { confirm: 'Sync now', cancel: 'Cancel' },
              onConfirm: () => sync.mutate(),
            })}>
            Sync TLDs &amp; prices from Name.com
          </Button>
          {(list?.counts.changed ?? 0) > 0 && <Button variant="light" color="orange" onClick={() => ack.mutate()}>Clear {list?.counts.changed} change flag(s)</Button>}
        </Group>
        {list && <Text size="sm" c="dimmed">{list.counts.total} TLDs - {list.counts.enabled} on sale - {list.counts.changed} cost changed - {list.counts.overridden} overridden</Text>}
      </Group>

      <Group grow align="flex-end">
        <TextInput label="Search TLD" placeholder="com, io, shop..." value={search} onChange={(e) => { setSearch(e.currentTarget.value); setPage(1); }} />
        <Select label="Show" clearable placeholder="All" value={filter} onChange={(v) => { setFilter(v); setPage(1); }}
          data={[{ value: 'enabled', label: 'On sale' }, { value: 'disabled', label: 'Not on sale' }, { value: 'changed', label: 'USD cost changed' }, { value: 'overridden', label: 'Manual price' }]} />
      </Group>

      {isLoading ? <Center py="md"><Loader size="sm" /></Center> : rows.length === 0 ? (
        <Text size="sm" c="dimmed">No Name.com TLDs yet. Connect Name.com, then press "Sync TLDs &amp; prices".</Text>
      ) : (
        <ScrollArea>
          <Table striped withTableBorder miw={900} opacity={isFetching ? 0.6 : 1}>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>TLD</Table.Th>
                <Table.Th>USD reg / renew / transfer</Table.Th>
                <Table.Th>Selling TZS: register</Table.Th>
                <Table.Th>renew</Table.Th>
                <Table.Th>transfer</Table.Th>
                <Table.Th>Flags</Table.Th>
                <Table.Th>On sale</Table.Th>
                <Table.Th />
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {rows.map((r) => (
                <Table.Tr key={r.tld}>
                  <Table.Td fw={600}>
                    <Group gap={4} wrap="nowrap">
                      <Tooltip label={r.is_popular ? 'Popular: shown first in customer search. Click to remove.' : 'Mark as popular (shown first in search when on sale)'}>
                        <ActionIcon variant="subtle" color="yellow" disabled={star.isPending} aria-label={`Popular .${r.tld}`}
                          onClick={() => star.mutate({ tld: r.tld, is_popular: !r.is_popular })}>
                          {r.is_popular ? <IconStarFilled size={16} /> : <IconStar size={16} />}
                        </ActionIcon>
                      </Tooltip>
                      .{r.tld}
                    </Group>
                  </Table.Td>
                  <Table.Td>{usd(r.usd_register)} / {usd(r.usd_renew)} / {usd(r.usd_transfer)}</Table.Td>
                  <Table.Td>{tzs(r.register_price)}</Table.Td>
                  <Table.Td>{tzs(r.renew_price)}</Table.Td>
                  <Table.Td>{tzs(r.transfer_price)}</Table.Td>
                  <Table.Td>
                    <Group gap={4} wrap="nowrap">
                      {r.usd_changed && (
                        <Tooltip label={r.usd_prev ? `Was ${usd(r.usd_prev.register)} / ${usd(r.usd_prev.renew)} / ${usd(r.usd_prev.transfer)}` : 'USD cost changed'}>
                          <Badge color="orange" variant="light" leftSection={<IconAlertTriangle size={11} />}>cost changed</Badge>
                        </Tooltip>
                      )}
                      {r.price_overridden && <Badge color="grape" variant="light">manual</Badge>}
                      {r.usd_register === null && <Badge color="gray" variant="light">no registration</Badge>}
                    </Group>
                  </Table.Td>
                  <Table.Td>
                    <Switch checked={r.is_active} disabled={toggle.isPending} aria-label={`Sell .${r.tld}`}
                      onChange={(e) => toggle.mutate({ tld: r.tld, is_active: e.currentTarget.checked })} />
                  </Table.Td>
                  <Table.Td><ActionIcon variant="light" onClick={() => setEditing(r)} aria-label="Edit price"><IconEdit size={15} /></ActionIcon></Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        </ScrollArea>
      )}
      {list && list.meta.last_page > 1 && <Pagination value={page} onChange={setPage} total={list.meta.last_page} size="sm" />}
      {editing && <EditModal row={editing} onClose={() => setEditing(null)} onSaved={() => { setEditing(null); refresh(); }} />}
    </Stack>
  );
}

function SettingsCard({ settings, onSaved, onRecompute, recomputing }: { settings?: NameComSettingsData; onSaved: () => void; onRecompute: () => void; recomputing: boolean }) {
  const [draft, setDraft] = useState<Partial<NameComSettingsData>>({});
  const v = { ...(settings ?? { usd_rate: 3000, fixed_markup: 10000, auto_register: false, auto_cap_usd: 50, auto_daily_limit: 10 }), ...draft } as NameComSettingsData;
  const set = (k: keyof NameComSettingsData, val: any) => setDraft((d) => ({ ...d, [k]: val }));
  const save = useMutation({
    mutationFn: () => saveNameComSettings(v),
    onSuccess: (r) => { notifications.show({ color: 'green', message: r.data.message }); setDraft({}); onSaved(); },
    onError: (e) => notifications.show({ color: 'red', message: errMsg(e) }),
  });
  const example = Math.round(10 * v.usd_rate) + Math.round(v.fixed_markup);
  return (
    <Paper withBorder p="md" radius="md">
      <Stack gap="sm">
        <Text fw={600}>Pricing rule &amp; registration</Text>
        <Text size="xs" c="dimmed">Selling price (TZS) = ROUND(USD cost x rate) + fixed markup, applied separately to register, renew and transfer. Example: a $10.00 TLD sells at {tzs(example)} TZS.</Text>
        <SimpleGrid cols={{ base: 1, sm: 2 }}>
          <NumberInput label="USD rate (TZS per 1 USD)" min={1} value={v.usd_rate} onChange={(x) => set('usd_rate', Number(x) || 0)} thousandSeparator="," />
          <NumberInput label="Fixed markup per domain (TZS)" min={0} value={v.fixed_markup} onChange={(x) => set('fixed_markup', Number(x) || 0)} thousandSeparator="," />
        </SimpleGrid>
        <Switch checked={v.auto_register} onChange={(e) => set('auto_register', e.currentTarget.checked)} color="red"
          label="Auto-register at Name.com after payment" description="OFF (recommended): paid orders wait in the registration queue for a staff member to confirm. ON: paid orders are bought automatically at Name.com (real money) within the limits below; any failure falls back to the queue." />
        {v.auto_register && (
          <SimpleGrid cols={{ base: 1, sm: 2 }}>
            <NumberInput label="Max cost per domain (USD)" min={0} value={v.auto_cap_usd} onChange={(x) => set('auto_cap_usd', Number(x) || 0)} />
            <NumberInput label="Max auto-registrations per day" min={0} value={v.auto_daily_limit} onChange={(x) => set('auto_daily_limit', Number(x) || 0)} />
          </SimpleGrid>
        )}
        <Group>
          <Button loading={save.isPending} disabled={Object.keys(draft).length === 0} onClick={() => save.mutate()}>Save settings</Button>
          <Button variant="light" loading={recomputing} onClick={onRecompute}>Apply rate to all TLDs (keeps manual prices)</Button>
        </Group>
      </Stack>
    </Paper>
  );
}

function EditModal({ row, onClose, onSaved }: { row: NameComTldRow; onClose: () => void; onSaved: () => void }) {
  const [reg, setReg] = useState<number>(row.register_price);
  const [ren, setRen] = useState<number>(row.renew_price);
  const [tr, setTr] = useState<number>(row.transfer_price);
  const [error, setError] = useState<string | null>(null);
  const save = useMutation({
    mutationFn: () => updateNameComTld(row.tld, { register_price: reg, renew_price: ren, transfer_price: tr }),
    onSuccess: (r) => { notifications.show({ color: 'green', message: r.data.message }); onSaved(); },
    onError: (e) => setError(errMsg(e)),
  });
  const reset = useMutation({
    mutationFn: () => updateNameComTld(row.tld, { reset_override: true }),
    onSuccess: () => { notifications.show({ color: 'green', message: 'Back to the automatic price.' }); onSaved(); },
    onError: (e) => setError(errMsg(e)),
  });
  return (
    <Modal opened onClose={onClose} title={`Selling price for .${row.tld}`} centered zIndex={400}>
      <Stack>
        {error && <Alert color="red">{error}</Alert>}
        <Text size="sm" c="dimmed">Name.com cost: {usd(row.usd_register)} register, {usd(row.usd_renew)} renew, {usd(row.usd_transfer)} transfer. Setting a price here keeps it fixed - syncing will not change it.</Text>
        <NumberInput label="Register (TZS per year)" min={0} value={reg} onChange={(x) => setReg(Number(x) || 0)} thousandSeparator="," />
        <NumberInput label="Renew (TZS per year)" min={0} value={ren} onChange={(x) => setRen(Number(x) || 0)} thousandSeparator="," />
        <NumberInput label="Transfer (TZS)" min={0} value={tr} onChange={(x) => setTr(Number(x) || 0)} thousandSeparator="," />
        <Group justify="space-between">
          {row.price_overridden ? <Button variant="subtle" loading={reset.isPending} onClick={() => reset.mutate()}>Reset to automatic</Button> : <span />}
          <Button loading={save.isPending} onClick={() => { setError(null); save.mutate(); }}>Save price</Button>
        </Group>
      </Stack>
    </Modal>
  );
}
