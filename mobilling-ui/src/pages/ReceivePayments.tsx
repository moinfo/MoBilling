import {
  Title, Table, Text, Group, Pagination, Badge, TextInput, Stack, NumberInput, Select, Textarea, Button, Loader, Center,
  Paper, Checkbox, Switch, Modal, Alert, FileInput, Collapse, ActionIcon, Tooltip, ScrollArea, Box, SimpleGrid,
} from '@mantine/core';
import { DateInput } from '@mantine/dates';
import { useDebouncedValue, useMediaQuery } from '@mantine/hooks';
import { notifications } from '@mantine/notifications';
import { modals } from '@mantine/modals';
import { useEffect, useMemo, useRef, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { IconSearch, IconCash, IconClipboardText, IconArrowBackUp, IconPaperclip } from '@tabler/icons-react';
import dayjs from 'dayjs';
import {
  getReceiveOptions, getUnpaidInvoices, getRecentRecorded, parsePaymentMessage, recordOfflinePayment, undoRecordedPayment,
  UnpaidInvoice, RecordResult, ParsedMessage,
} from '../api/receivePayments';
import { usePermissions } from '../hooks/usePermissions';
import { formatCurrency } from '../utils/formatCurrency';
import { formatDate } from '../utils/formatDate';

const STATUS_COLOR: Record<string, string> = { sent: 'blue', overdue: 'red', partial: 'orange' };
const HINT_KEY = 'receivePayments.defaultMethod';

function newKey(): string {
  try { return crypto.randomUUID(); } catch { return `k${Date.now()}${Math.random().toString(36).slice(2)}`; }
}
function readHint(): string | null { try { return localStorage.getItem(HINT_KEY); } catch { return null; } }
function saveHint(v: string | null) { try { v ? localStorage.setItem(HINT_KEY, v) : localStorage.removeItem(HINT_KEY); } catch { /* ignore */ } }

/** Oldest-due-first allocation preview — mirrors the server. */
function allocate(invoices: UnpaidInvoice[], amount: number) {
  const sorted = [...invoices].sort((a, b) => (a.due_date || '9999').localeCompare(b.due_date || '9999') || (a.date || '').localeCompare(b.date || ''));
  let left = Math.round(amount * 100) / 100;
  const rows = sorted.map((inv) => {
    const take = Math.max(0, Math.min(left, inv.balance_due));
    left = Math.round((left - take) * 100) / 100;
    return { inv, take, after: Math.round((inv.balance_due - take) * 100) / 100 };
  }).filter((r) => r.take > 0);
  return { rows, excess: left };
}

interface Prefill { amount?: number; reference?: string }

function RecordModal({ invoices, prefill, defaultMethod, onClose, onDone }: {
  invoices: UnpaidInvoice[]; prefill: Prefill; defaultMethod: string | null; onClose: () => void; onDone: (r: RecordResult) => void;
}) {
  const isMobile = useMediaQuery('(max-width: 48em)');
  const { data: opts } = useQuery({ queryKey: ['receive-options'], queryFn: () => getReceiveOptions().then((r) => r.data) });
  const methods = opts?.methods ?? [];
  const totalBalance = invoices.reduce((s, i) => s + i.balance_due, 0);
  const [amount, setAmount] = useState<number | string>(prefill.amount ?? totalBalance);
  const [method, setMethod] = useState<string | null>(null);
  const [date, setDate] = useState<Date | null>(new Date());
  const [reference, setReference] = useState(prefill.reference ?? '');
  const [notes, setNotes] = useState('');
  const [proof, setProof] = useState<File | null>(null);
  const [sendReceipt, setSendReceipt] = useState(true);
  const [allowExcess, setAllowExcess] = useState(false);
  const [confirmDifferent, setConfirmDifferent] = useState(false);
  const [warning, setWarning] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const key = useRef(newKey());

  useEffect(() => {
    if (!method && methods.length) {
      setMethod(methods.find((m) => m.value === defaultMethod)?.value ?? methods[0].value);
    }
  }, [methods, method, defaultMethod]);

  const chosen = methods.find((m) => m.value === method);
  const amt = typeof amount === 'number' ? amount : parseFloat(String(amount)) || 0;
  const { rows, excess } = useMemo(() => allocate(invoices, amt), [invoices, amt]);
  const single = invoices.length === 1;

  const mutation = useMutation({
    mutationFn: () => {
      const fd = new FormData();
      invoices.forEach((i) => fd.append('invoice_ids[]', i.id));
      fd.append('amount', String(amt));
      fd.append('payment_method', method || '');
      fd.append('payment_date', dayjs(date || new Date()).format('YYYY-MM-DD'));
      if (reference.trim()) fd.append('reference', reference.trim());
      if (notes.trim()) fd.append('notes', notes.trim());
      if (proof) fd.append('proof', proof);
      fd.append('send_receipt', sendReceipt ? '1' : '0');
      fd.append('allow_excess', allowExcess ? '1' : '0');
      fd.append('confirm_different', confirmDifferent ? '1' : '0');
      fd.append('idempotency_key', key.current);
      return recordOfflinePayment(fd).then((r) => r.data);
    },
    onSuccess: onDone,
    onError: (e: any) => {
      const d = e?.response?.data;
      if (e?.response?.status === 409 && (d?.code === 'duplicate_reference' || d?.code === 'recent_same_amount')) {
        setWarning(d.message); setError(null);
      } else {
        setError(d?.message || 'Failed to record payment'); setWarning(null);
      }
    },
  });

  const refMissing = !!chosen?.reference_required && !reference.trim();
  const tooMuch = excess > 0 && !allowExcess;
  const canSubmit = amt > 0 && !!method && !refMissing && !tooMuch && !!date && (!warning || confirmDifferent);

  return (
    <Modal opened onClose={onClose} fullScreen={!!isMobile} size="lg" title={single ? `Record payment — ${invoices[0].document_number}` : `Record one payment for ${invoices.length} invoices`}>
      <Stack gap="sm">
        <Text size="sm" c="dimmed">
          {invoices[0].client?.name} · balance due <b>{formatCurrency(totalBalance)}</b>
        </Text>
        {error && <Alert color="red" variant="light">{error}</Alert>}
        {warning && (
          <Alert color="yellow" variant="light" title="Possible duplicate">
            {warning}
            <Checkbox mt="xs" checked={confirmDifferent} onChange={(e) => setConfirmDifferent(e.currentTarget.checked)} label="I confirm this is a different payment" />
          </Alert>
        )}
        <NumberInput label="Amount received" value={amount} onChange={setAmount} min={0} decimalScale={2} thousandSeparator="," inputMode="decimal" data-autofocus
          description={single ? 'Defaults to the full balance; lower it for a partial payment.' : 'Split oldest-due-first across the selected invoices.'} />
        {excess > 0 && (
          <Checkbox checked={allowExcess} onChange={(e) => setAllowExcess(e.currentTarget.checked)}
            label={`Record excess ${formatCurrency(excess)} as client credit`} color="orange" />
        )}
        {!single && rows.length > 0 && (
          <Paper withBorder p="xs">
            <Text size="xs" fw={600} mb={4}>Allocation preview</Text>
            {rows.map((r) => (
              <Group key={r.inv.id} justify="space-between" wrap="nowrap">
                <Text size="xs">{r.inv.document_number}</Text>
                <Text size="xs">{formatCurrency(r.take)} → balance {formatCurrency(r.after)}</Text>
              </Group>
            ))}
            {excess > 0 && <Text size="xs" c="orange">Excess: {formatCurrency(excess)}</Text>}
          </Paper>
        )}
        <Select label="Payment method" data={methods.map((m) => ({ value: m.value, label: m.label }))} value={method} onChange={setMethod} allowDeselect={false} />
        <TextInput label={chosen?.reference_required ? 'Reference / transaction ID (required)' : 'Reference'} placeholder="M-Pesa / Tigo / Airtel code or bank slip ref"
          value={reference} onChange={(e) => { setReference(e.currentTarget.value); setWarning(null); setConfirmDifferent(false); }}
          error={refMissing ? 'Required for this method' : undefined} />
        <DateInput label="Payment date" value={date} onChange={(v) => setDate(v ? new Date(v) : null)} maxDate={new Date()} valueFormat="DD MMM YYYY" />
        <Textarea label="Notes" value={notes} onChange={(e) => setNotes(e.currentTarget.value)} autosize minRows={1} maxRows={3} />
        <FileInput label="Proof (image or PDF, max 5 MB)" value={proof} onChange={setProof} accept="image/jpeg,image/png,image/webp,application/pdf" clearable leftSection={<IconPaperclip size={14} />} />
        <Checkbox checked={sendReceipt} onChange={(e) => setSendReceipt(e.currentTarget.checked)} label="Send receipt to client" />
        <Group justify="flex-end" mt="sm">
          <Button variant="default" onClick={onClose}>Cancel</Button>
          <Button color="green" leftSection={<IconCash size={16} />} loading={mutation.isPending} disabled={!canSubmit} onClick={() => mutation.mutate()}>
            Record {formatCurrency(amt)}
          </Button>
        </Group>
      </Stack>
    </Modal>
  );
}

export default function ReceivePayments() {
  const queryClient = useQueryClient();
  const { can } = usePermissions();
  const canRecord = can('payments_in.create');
  const [page, setPage] = useState(1);
  const [search, setSearch] = useState('');
  const [debounced] = useDebouncedValue(search, 300);
  const [overdueOnly, setOverdueOnly] = useState(false);
  const [dueFrom, setDueFrom] = useState<Date | null>(null);
  const [dueTo, setDueTo] = useState<Date | null>(null);
  const [amountFilter, setAmountFilter] = useState<string>('');
  const [defaultMethod, setDefaultMethod] = useState<string | null>(readHint());
  const [selected, setSelected] = useState<UnpaidInvoice[]>([]);
  const [modal, setModal] = useState<{ invoices: UnpaidInvoice[]; prefill: Prefill } | null>(null);
  const [pasteOpen, setPasteOpen] = useState(false);
  const [pasteText, setPasteText] = useState('');
  const [parsed, setParsed] = useState<ParsedMessage | null>(null);

  const { data: opts } = useQuery({ queryKey: ['receive-options'], queryFn: () => getReceiveOptions().then((r) => r.data) });

  const params = {
    page, per_page: 20, search: debounced || undefined, overdue: overdueOnly ? 1 : undefined,
    date_from: dueFrom ? dayjs(dueFrom).format('YYYY-MM-DD') : undefined,
    date_to: dueTo ? dayjs(dueTo).format('YYYY-MM-DD') : undefined,
    amount: amountFilter || undefined,
  };
  const { data, isLoading } = useQuery({ queryKey: ['receive-invoices', params], queryFn: () => getUnpaidInvoices(params).then((r) => r.data) });
  const rows: UnpaidInvoice[] = data?.data ?? [];

  const { data: recent } = useQuery({ queryKey: ['receive-recent'], queryFn: () => getRecentRecorded().then((r) => r.data.data) });

  const parseMutation = useMutation({
    mutationFn: () => parsePaymentMessage(pasteText).then((r) => r.data),
    onSuccess: (r) => {
      setParsed(r);
      setPage(1);
      // narrow the list by what we understood (never records anything)
      if (r.parsed.phone) setSearch(r.parsed.phone);
      else if (r.parsed.name) setSearch(r.parsed.name);
      else if (r.parsed.invoice_number) setSearch(r.parsed.invoice_number);
      setAmountFilter(r.parsed.amount && !r.parsed.phone && !r.parsed.name ? String(r.parsed.amount) : '');
    },
    onError: () => notifications.show({ color: 'red', message: 'Could not read that message' }),
  });

  const undoMutation = useMutation({
    mutationFn: (id: string) => undoRecordedPayment(id),
    onSuccess: () => {
      notifications.show({ color: 'green', message: 'Payment undone' });
      refresh();
    },
    onError: (e: any) => notifications.show({ color: 'red', message: e?.response?.data?.message || 'Could not undo' }),
  });

  const refresh = () => {
    queryClient.invalidateQueries({ queryKey: ['receive-invoices'] });
    queryClient.invalidateQueries({ queryKey: ['receive-recent'] });
    queryClient.invalidateQueries({ queryKey: ['payments-in'] });
    queryClient.invalidateQueries({ queryKey: ['documents'] });
  };

  const onDone = (r: RecordResult) => {
    setModal(null); setSelected([]);
    const msg = r.invoices.map((i) => `${i.document_number}: ${i.status === 'paid' ? 'PAID' : `partial, balance ${formatCurrency(i.balance_after)}`}`).join(' · ');
    notifications.show({ color: 'green', title: r.replayed ? 'Already recorded' : 'Payment recorded', message: msg + (r.excess_credit > 0 ? ` · credit ${formatCurrency(r.excess_credit)}` : ''), autoClose: 8000 });
    refresh();
  };

  const toggle = (inv: UnpaidInvoice) => setSelected((s) => (s.some((x) => x.id === inv.id) ? s.filter((x) => x.id !== inv.id) : [...s, inv]));
  const selClient = selected[0]?.client?.id;

  const methodData = (opts?.methods ?? []).map((m) => ({ value: m.value, label: m.label }));

  return (
    <Stack gap="md">
      <Group justify="space-between">
        <Title order={2}>Receive payments</Title>
        <Button variant="light" leftSection={<IconClipboardText size={16} />} onClick={() => setPasteOpen((o) => !o)}>Paste payment message</Button>
      </Group>

      <Collapse in={pasteOpen}>
        <Paper withBorder p="sm">
          <Stack gap="xs">
            <Textarea placeholder="Paste the M-Pesa / Tigo Pesa / Airtel Money / HaloPesa SMS or bank credit alert" value={pasteText} onChange={(e) => setPasteText(e.currentTarget.value)} autosize minRows={2} maxRows={6} />
            <Group>
              <Button size="xs" loading={parseMutation.isPending} disabled={!pasteText.trim()} onClick={() => parseMutation.mutate()}>Read message</Button>
              <Text size="xs" c="dimmed">Nothing is recorded until you confirm in the payment form.</Text>
            </Group>
            {parsed && (
              <Stack gap={4}>
                <Group gap="xs">
                  <Badge variant="light">Amount: {parsed.parsed.amount ? formatCurrency(parsed.parsed.amount) : '—'}</Badge>
                  <Badge variant="light">Ref: {parsed.parsed.reference ?? '—'}</Badge>
                  <Badge variant="light">Phone: {parsed.parsed.phone ?? '—'}</Badge>
                  <Badge variant="light">Sender: {parsed.parsed.name ?? '—'}</Badge>
                </Group>
                {parsed.suggestions.length === 0 ? <Text size="sm" c="dimmed">No matching unpaid invoice found — search manually below.</Text> : (
                  <>
                    <Text size="sm" fw={600}>Possible invoices</Text>
                    {parsed.suggestions.map((s) => (
                      <Group key={s.id} justify="space-between" wrap="nowrap">
                        <Text size="sm">{s.document_number} — {s.client_name} — {formatCurrency(s.balance_due)}</Text>
                        {canRecord && (
                          <Button size="compact-xs" onClick={() => {
                            const inv = rows.find((r) => r.id === s.id);
                            setModal({
                              invoices: [inv ?? ({ id: s.id, document_number: s.document_number, status: 'sent', date: null, due_date: null, is_overdue: false, total: s.balance_due, paid_amount: 0, balance_due: s.balance_due, client: { id: '', name: s.client_name ?? '', phone: null, credit_balance: 0 } } as UnpaidInvoice)],
                              prefill: { amount: parsed.parsed.amount ?? undefined, reference: parsed.parsed.reference ?? undefined },
                            });
                          }}>Use</Button>
                        )}
                      </Group>
                    ))}
                  </>
                )}
              </Stack>
            )}
          </Stack>
        </Paper>
      </Collapse>

      <Paper withBorder p="sm">
        <SimpleGrid cols={{ base: 1, sm: 2, md: 5 }} spacing="xs">
          <TextInput placeholder="Client, invoice no, phone or amount" leftSection={<IconSearch size={14} />} value={search} onChange={(e) => { setSearch(e.currentTarget.value); setPage(1); }} />
          <DateInput placeholder="Due from" value={dueFrom} onChange={(v) => { setDueFrom(v ? new Date(v) : null); setPage(1); }} clearable valueFormat="DD MMM YYYY" />
          <DateInput placeholder="Due to" value={dueTo} onChange={(v) => { setDueTo(v ? new Date(v) : null); setPage(1); }} clearable valueFormat="DD MMM YYYY" />
          <Select placeholder="Default method" data={methodData} value={defaultMethod} onChange={(v) => { setDefaultMethod(v); saveHint(v); }} clearable />
          <Switch label="Overdue only" checked={overdueOnly} onChange={(e) => { setOverdueOnly(e.currentTarget.checked); setPage(1); }} mt={6} />
        </SimpleGrid>
      </Paper>

      {selected.length > 0 && canRecord && (
        <Paper withBorder p="xs" bg="var(--mantine-color-blue-light)">
          <Group justify="space-between">
            <Text size="sm">{selected.length} invoice(s) selected for {selected[0].client?.name} · balance {formatCurrency(selected.reduce((s, i) => s + i.balance_due, 0))}</Text>
            <Group gap="xs">
              <Button size="xs" variant="default" onClick={() => setSelected([])}>Clear</Button>
              <Button size="xs" onClick={() => setModal({ invoices: selected, prefill: {} })}>Record one payment</Button>
            </Group>
          </Group>
        </Paper>
      )}

      <Paper withBorder>
        <ScrollArea>
          <Table striped highlightOnHover miw={860}>
            <Table.Thead>
              <Table.Tr>
                {canRecord && <Table.Th w={36} />}
                <Table.Th>Invoice</Table.Th><Table.Th>Client</Table.Th><Table.Th>Issued</Table.Th><Table.Th>Due</Table.Th>
                <Table.Th ta="right">Total</Table.Th><Table.Th ta="right">Paid</Table.Th><Table.Th ta="right">Balance</Table.Th><Table.Th>Status</Table.Th><Table.Th />
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {isLoading ? (
                <Table.Tr><Table.Td colSpan={10}><Center p="md"><Loader size="sm" /></Center></Table.Td></Table.Tr>
              ) : rows.length === 0 ? (
                <Table.Tr><Table.Td colSpan={10}><Text ta="center" c="dimmed" p="md">No unpaid invoices found</Text></Table.Td></Table.Tr>
              ) : rows.map((inv) => (
                <Table.Tr key={inv.id}>
                  {canRecord && (
                    <Table.Td>
                      <Checkbox checked={selected.some((s) => s.id === inv.id)} disabled={!!selClient && selClient !== inv.client?.id} onChange={() => toggle(inv)} aria-label="Select invoice" />
                    </Table.Td>
                  )}
                  <Table.Td><Text size="sm" fw={500}>{inv.document_number}</Text></Table.Td>
                  <Table.Td><Text size="sm">{inv.client?.name}</Text><Text size="xs" c="dimmed">{inv.client?.phone}</Text></Table.Td>
                  <Table.Td>{inv.date ? formatDate(inv.date) : '—'}</Table.Td>
                  <Table.Td><Text size="sm" c={inv.is_overdue ? 'red' : undefined}>{inv.due_date ? formatDate(inv.due_date) : '—'}</Text></Table.Td>
                  <Table.Td ta="right">{formatCurrency(inv.total)}</Table.Td>
                  <Table.Td ta="right">{formatCurrency(inv.paid_amount)}</Table.Td>
                  <Table.Td ta="right"><b>{formatCurrency(inv.balance_due)}</b></Table.Td>
                  <Table.Td><Badge color={STATUS_COLOR[inv.status] ?? 'gray'} variant="light">{inv.is_overdue && inv.status !== 'overdue' ? 'overdue' : inv.status}</Badge></Table.Td>
                  <Table.Td>
                    {canRecord && <Button size="compact-sm" leftSection={<IconCash size={14} />} onClick={() => setModal({ invoices: [inv], prefill: {} })}>Record payment</Button>}
                  </Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        </ScrollArea>
      </Paper>
      {data?.last_page > 1 && <Group justify="center"><Pagination value={page} onChange={setPage} total={data.last_page} /></Group>}

      <Box>
        <Title order={4} mb="xs">Recorded today (by you, last 24h)</Title>
        <Paper withBorder>
          <ScrollArea>
            <Table miw={640}>
              <Table.Tbody>
                {(recent ?? []).length === 0 ? (
                  <Table.Tr><Table.Td><Text size="sm" c="dimmed">Nothing recorded yet</Text></Table.Td></Table.Tr>
                ) : (recent ?? []).map((p) => (
                  <Table.Tr key={p.id}>
                    <Table.Td>{dayjs(p.created_at).format('HH:mm')}</Table.Td>
                    <Table.Td>{p.document_number}<Text size="xs" c="dimmed">{p.client_name}</Text></Table.Td>
                    <Table.Td>{formatCurrency(p.amount)}</Table.Td>
                    <Table.Td><Text size="sm">{p.payment_method}</Text><Text size="xs" c="dimmed">{p.reference}</Text></Table.Td>
                    <Table.Td>
                      {p.undoable && (
                        <Tooltip label={`Undo (within ${opts?.undo_minutes ?? 15} minutes)`}>
                          <ActionIcon variant="light" color="red" onClick={() => modals.openConfirmModal({
                            title: 'Undo this payment?', children: <Text size="sm">{formatCurrency(p.amount)} on {p.document_number} will be removed and the invoice status recalculated.</Text>,
                            labels: { confirm: 'Undo payment', cancel: 'Keep' }, confirmProps: { color: 'red' }, onConfirm: () => undoMutation.mutate(p.id),
                          })}><IconArrowBackUp size={16} /></ActionIcon>
                        </Tooltip>
                      )}
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </ScrollArea>
        </Paper>
      </Box>

      {modal && <RecordModal invoices={modal.invoices} prefill={modal.prefill} defaultMethod={defaultMethod} onClose={() => setModal(null)} onDone={onDone} />}
    </Stack>
  );
}
