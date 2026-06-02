import { useState } from 'react';
import {
  Title, Card, Group, Text, Stack, Button, Modal, NumberInput, TextInput, Textarea,
  Select, Tabs, Table, Badge, ActionIcon, Tooltip, Alert, FileButton, Box,
} from '@mantine/core';
import { DateInput } from '@mantine/dates';
import { useForm } from '@mantine/form';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  IconCash, IconArrowsExchange, IconChecklist, IconFileDownload, IconUpload,
  IconCheck, IconAlertTriangle, IconEye,
} from '@tabler/icons-react';
import dayjs from 'dayjs';
import {
  getPettyCash, createPettyCashTransaction, createPettyCashReconciliation,
  downloadPettyCashTransactionVoucher, uploadPettyCashTransactionVoucher,
  PettyCashHistoryItem, PettyCashHistoryKind,
} from '../api/pettyCash';
import { formatCurrency } from '../utils/formatCurrency';
import { formatDate } from '../utils/formatDate';
import { usePermissions } from '../hooks/usePermissions';

const kindLabel: Record<PettyCashHistoryKind, string> = {
  top_up: 'Top-Up',
  return: 'Return',
  adjustment_in: 'Adjustment +',
  adjustment_out: 'Adjustment −',
  expense: 'Expense',
};

const kindColor: Record<PettyCashHistoryKind, string> = {
  top_up: 'green',
  return: 'orange',
  adjustment_in: 'teal',
  adjustment_out: 'red',
  expense: 'gray',
};

// + adds to balance (top_up, adjustment_in); − subtracts (return, adjustment_out, expense)
const isInflow = (k: PettyCashHistoryKind) => k === 'top_up' || k === 'adjustment_in';

export default function PettyCash() {
  const queryClient = useQueryClient();
  const { can } = usePermissions();
  const canTopUp = can('petty_cash.topup');
  const canReconcile = can('petty_cash.reconcile');

  const [topUpOpen, setTopUpOpen] = useState(false);
  const [reconcileOpen, setReconcileOpen] = useState(false);
  const [uploadingFor, setUploadingFor] = useState<string | null>(null);

  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['petty-cash'],
    queryFn: async () => (await getPettyCash()).data,
    retry: 1,
  });

  const balance = parseFloat(data?.balance ?? '0') || 0;                              // verified
  const committedBalance = parseFloat(data?.committed_balance ?? '0') || 0;            // physical
  const pendingCount = data?.pending_vouchers?.count ?? 0;
  const pendingTotal = parseFloat(data?.pending_vouchers?.total ?? '0') || 0;
  const history = data?.history ?? [];
  const reconciliations = data?.reconciliations ?? [];

  // ----- Top-Up form -----
  const topUpForm = useForm({
    initialValues: {
      type: 'top_up' as 'top_up' | 'return',
      amount: 0,
      transaction_date: new Date(),
      notes: '',
      given_by_name: '',
      received_by_name: '',
    },
    validate: {
      amount: (v) => (v > 0 ? null : 'Amount must be greater than zero'),
    },
  });

  const topUpMutation = useMutation({
    mutationFn: (values: typeof topUpForm.values) =>
      createPettyCashTransaction({
        type: values.type,
        amount: values.amount,
        transaction_date: dayjs(values.transaction_date).format('YYYY-MM-DD'),
        notes: values.notes || undefined,
        given_by_name: values.given_by_name || undefined,
        received_by_name: values.received_by_name || undefined,
      }),
    onSuccess: (res) => {
      notifications.show({ title: 'Recorded', message: res.data.message, color: 'green' });
      queryClient.invalidateQueries({ queryKey: ['petty-cash'] });
      setTopUpOpen(false);
      topUpForm.reset();
    },
    onError: (err: any) => notifications.show({
      title: 'Error',
      message: err.response?.data?.message || 'Failed to record transaction',
      color: 'red',
    }),
  });

  // ----- Reconcile form -----
  const reconcileForm = useForm({
    initialValues: {
      counted_balance: 0,
      reconciled_at: new Date(),
      resolution: 'accepted' as 'accepted' | 'investigating',
      notes: '',
    },
  });
  // Reconciliation compares the physical count against the COMMITTED balance
  // (what should be in the till including pending-voucher expenses), not the
  // verified one — the user is counting cash, not paperwork.
  const difference = (reconcileForm.values.counted_balance || 0) - committedBalance;

  const reconcileMutation = useMutation({
    mutationFn: (values: typeof reconcileForm.values) =>
      createPettyCashReconciliation({
        counted_balance: values.counted_balance,
        reconciled_at: dayjs(values.reconciled_at).toISOString(),
        resolution: values.resolution,
        notes: values.notes || undefined,
      }),
    onSuccess: (res) => {
      notifications.show({ title: 'Reconciliation recorded', message: res.data.message, color: 'green' });
      queryClient.invalidateQueries({ queryKey: ['petty-cash'] });
      setReconcileOpen(false);
      reconcileForm.reset();
    },
    onError: (err: any) => notifications.show({
      title: 'Error',
      message: err.response?.data?.message || 'Failed to reconcile',
      color: 'red',
    }),
  });

  // ----- Voucher actions -----
  const handleDownloadVoucher = async (item: PettyCashHistoryItem) => {
    if (item.kind === 'expense') {
      notifications.show({ title: 'Expense voucher', message: 'Open the Expenses page to download an expense voucher.', color: 'blue' });
      return;
    }
    try {
      const res = await downloadPettyCashTransactionVoucher(item.id);
      const url = window.URL.createObjectURL(new Blob([res.data], { type: 'application/pdf' }));
      const link = window.document.createElement('a');
      link.href = url;
      link.download = `voucher-${item.id.slice(0, 8)}.pdf`;
      link.click();
      window.URL.revokeObjectURL(url);
    } catch (err: any) {
      let msg = 'Failed to download voucher';
      try {
        const d = err?.response?.data;
        if (d instanceof Blob) msg = JSON.parse(await d.text())?.message || msg;
        else if (d?.message) msg = d.message;
      } catch { /* keep default */ }
      notifications.show({ title: 'Error', message: msg, color: 'red' });
    }
  };

  const handleUploadVoucher = async (item: PettyCashHistoryItem, file: File | null) => {
    if (!file) return;
    setUploadingFor(item.id);
    try {
      await uploadPettyCashTransactionVoucher(item.id, file);
      notifications.show({ title: 'Uploaded', message: 'Signed voucher attached.', color: 'green' });
      queryClient.invalidateQueries({ queryKey: ['petty-cash'] });
    } catch (err: any) {
      notifications.show({
        title: 'Error',
        message: err.response?.data?.message || 'Failed to upload voucher',
        color: 'red',
      });
    } finally {
      setUploadingFor(null);
    }
  };

  return (
    <Stack>
      {isError && (
        <Alert color="red" title="Could not load petty cash">
          {(error as any)?.response?.data?.message || 'Please try refreshing the page.'}
        </Alert>
      )}
      <Group justify="space-between">
        <Title order={2}>Petty Cash</Title>
        <Group>
          {canTopUp && (
            <Button leftSection={<IconArrowsExchange size={16} />} onClick={() => setTopUpOpen(true)}>
              Top Up / Return
            </Button>
          )}
          {canReconcile && (
            <Button variant="light" leftSection={<IconChecklist size={16} />}
              onClick={() => {
                // Pre-fill with the committed (physical) balance — that's
                // what the user is counting against, not the verified one.
                reconcileForm.setFieldValue('counted_balance', committedBalance);
                setReconcileOpen(true);
              }}>
              Reconcile
            </Button>
          )}
        </Group>
      </Group>

      <Card withBorder padding="lg">
        <Group justify="space-between" align="flex-start">
          <Stack gap={4}>
            <Text size="sm" c="dimmed" tt="uppercase">Verified Balance</Text>
            <Group gap="xs" align="baseline">
              <IconCash size={28} />
              <Text fw={700} size="32px">{formatCurrency(balance)}</Text>
            </Group>
            <Text size="xs" c="dimmed">
              {data?.account.name} · opening balance {formatCurrency(parseFloat(data?.account?.opening_balance ?? '0') || 0)}
            </Text>
            {pendingCount > 0 && (
              <Text size="xs" c="dimmed">
                Cash physically left (committed): <Text span fw={600}>{formatCurrency(committedBalance)}</Text>
              </Text>
            )}
          </Stack>
        </Group>
      </Card>

      {pendingCount > 0 && (
        <Alert color="yellow" icon={<IconAlertTriangle size={16} />} title={`${pendingCount} expense${pendingCount === 1 ? '' : 's'} awaiting signed voucher`}>
          {formatCurrency(pendingTotal)} of petty cash has been spent but the signed vouchers haven't been uploaded yet, so they aren't reducing the verified balance. Open the Expenses page to attach the signed PDFs.
        </Alert>
      )}

      <Tabs defaultValue="history">
        <Tabs.List>
          <Tabs.Tab value="history">Activity</Tabs.Tab>
          <Tabs.Tab value="reconciliations">Reconciliations</Tabs.Tab>
        </Tabs.List>

        <Tabs.Panel value="history" pt="md">
          {isLoading ? <Text c="dimmed">Loading…</Text> : history.length === 0 ? (
            <Alert>No activity yet. Record a top-up to get started.</Alert>
          ) : (
            <Table verticalSpacing="xs" striped highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Date</Table.Th>
                  <Table.Th>Kind</Table.Th>
                  <Table.Th>Description</Table.Th>
                  <Table.Th>Given / Received</Table.Th>
                  <Table.Th style={{ textAlign: 'right' }}>Amount</Table.Th>
                  <Table.Th>Voucher</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {history.map((item) => (
                  <Table.Tr key={`${item.kind}-${item.id}`}>
                    <Table.Td>{formatDate(item.date)}</Table.Td>
                    <Table.Td>
                      <Badge color={kindColor[item.kind]} variant="light">{kindLabel[item.kind]}</Badge>
                    </Table.Td>
                    <Table.Td>
                      <Text size="sm">{item.description}</Text>
                      {item.category && <Text size="xs" c="dimmed">{item.category} · {item.sub_category}</Text>}
                      {item.reference && <Text size="xs" c="dimmed">Ref: {item.reference}</Text>}
                    </Table.Td>
                    <Table.Td>
                      {item.kind === 'expense' ? (
                        <Stack gap={2}>
                          {item.voucher_attached ? (
                            <Badge color="green" variant="light" leftSection={<IconCheck size={12} />}>Verified</Badge>
                          ) : (
                            <Tooltip label="Signed voucher not yet attached — open the Expenses page to upload it. Until then this expense does not reduce the verified balance.">
                              <Badge color="yellow" variant="light" leftSection={<IconAlertTriangle size={12} />}>Pending voucher</Badge>
                            </Tooltip>
                          )}
                        </Stack>
                      ) : (
                        <Stack gap={0}>
                          <Text size="xs">Given: {item.given_by_name || '—'}</Text>
                          <Text size="xs">Received: {item.received_by_name || '—'}</Text>
                        </Stack>
                      )}
                    </Table.Td>
                    <Table.Td style={{ textAlign: 'right' }}>
                      <Text fw={600} c={isInflow(item.kind) ? 'green' : 'red'}>
                        {isInflow(item.kind) ? '+' : '−'}{formatCurrency(item.amount)}
                      </Text>
                    </Table.Td>
                    <Table.Td>
                      <Group gap="xs">
                        {/* Download BLANK voucher template — only for transactions
                            (top-up/return/adjustment). Expense vouchers download
                            from the Expenses page. */}
                        {item.kind !== 'expense' && (
                          <Tooltip label="Download blank voucher PDF (for printing)">
                            <ActionIcon variant="light" color="blue" onClick={() => handleDownloadVoucher(item)}>
                              <IconFileDownload size={16} />
                            </ActionIcon>
                          </Tooltip>
                        )}
                        {/* VIEW already-signed voucher — works for both expenses
                            and transactions whenever a scan is attached. */}
                        {item.voucher_attachment_url && (
                          <Tooltip label="View signed voucher">
                            <ActionIcon
                              component="a"
                              variant="light"
                              color="green"
                              href={item.voucher_attachment_url}
                              target="_blank"
                            >
                              <IconEye size={16} />
                            </ActionIcon>
                          </Tooltip>
                        )}
                        {/* Upload/Replace for transaction rows only — expense
                            voucher uploads happen on the Expenses page. */}
                        {item.kind !== 'expense' && canTopUp && (
                          <FileButton onChange={(f) => handleUploadVoucher(item, f)} accept="application/pdf,image/*">
                            {(props) => (
                              <Tooltip label={item.voucher_attachment_url ? 'Replace signed voucher' : 'Upload signed voucher'}>
                                <ActionIcon variant="light" color="violet" loading={uploadingFor === item.id} {...props}>
                                  <IconUpload size={16} />
                                </ActionIcon>
                              </Tooltip>
                            )}
                          </FileButton>
                        )}
                      </Group>
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          )}
        </Tabs.Panel>

        <Tabs.Panel value="reconciliations" pt="md">
          {reconciliations.length === 0 ? (
            <Alert>No reconciliations yet. Use the Reconcile button to record a cash count.</Alert>
          ) : (
            <Table verticalSpacing="xs" striped>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Date</Table.Th>
                  <Table.Th style={{ textAlign: 'right' }}>Ledger</Table.Th>
                  <Table.Th style={{ textAlign: 'right' }}>Counted</Table.Th>
                  <Table.Th style={{ textAlign: 'right' }}>Diff</Table.Th>
                  <Table.Th>Resolution</Table.Th>
                  <Table.Th>By</Table.Th>
                  <Table.Th>Notes</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {reconciliations.map((r) => {
                  const diff = parseFloat(r.difference);
                  return (
                    <Table.Tr key={r.id}>
                      <Table.Td>{dayjs(r.reconciled_at).format('DD MMM YYYY')}</Table.Td>
                      <Table.Td style={{ textAlign: 'right' }}>{formatCurrency(parseFloat(r.ledger_balance))}</Table.Td>
                      <Table.Td style={{ textAlign: 'right' }}>{formatCurrency(parseFloat(r.counted_balance))}</Table.Td>
                      <Table.Td style={{ textAlign: 'right' }}>
                        <Text c={diff === 0 ? 'dimmed' : diff > 0 ? 'green' : 'red'} fw={600}>
                          {diff > 0 ? '+' : ''}{formatCurrency(diff)}
                        </Text>
                      </Table.Td>
                      <Table.Td>
                        <Badge color={r.resolution === 'accepted' ? 'green' : 'orange'}
                          leftSection={r.resolution === 'accepted' ? <IconCheck size={12} /> : <IconAlertTriangle size={12} />}>
                          {r.resolution}
                        </Badge>
                      </Table.Td>
                      <Table.Td>{r.created_by?.name || '—'}</Table.Td>
                      <Table.Td>
                        <Text size="xs" c="dimmed">{r.notes || '—'}</Text>
                      </Table.Td>
                    </Table.Tr>
                  );
                })}
              </Table.Tbody>
            </Table>
          )}
        </Tabs.Panel>
      </Tabs>

      {/* Top-Up / Return Modal */}
      <Modal opened={topUpOpen} onClose={() => setTopUpOpen(false)} title="Record Petty Cash Transaction" size="lg">
        <form onSubmit={topUpForm.onSubmit((v) => topUpMutation.mutate(v))}>
          <Stack>
            <Select
              label="Type" required
              data={[
                { value: 'top_up', label: 'Top-Up (money in)' },
                { value: 'return', label: 'Return (cash returned to source)' },
              ]}
              {...topUpForm.getInputProps('type')}
            />
            <Group grow>
              <NumberInput label="Amount" required min={0.01} decimalScale={2} {...topUpForm.getInputProps('amount')} />
              <DateInput label="Date" required {...topUpForm.getInputProps('transaction_date')} />
            </Group>
            <Group grow>
              <TextInput label="Given by" placeholder="Name of giver" {...topUpForm.getInputProps('given_by_name')} />
              <TextInput label="Received by" placeholder="Name of receiver / custodian" {...topUpForm.getInputProps('received_by_name')} />
            </Group>
            <Textarea label="Notes" {...topUpForm.getInputProps('notes')} />
            <Box>
              <Text size="xs" c="dimmed">
                After saving, download the voucher PDF, print it, get it signed by both parties, then upload the scanned copy back here.
              </Text>
            </Box>
            <Group justify="flex-end">
              <Button variant="default" onClick={() => setTopUpOpen(false)}>Cancel</Button>
              <Button type="submit" loading={topUpMutation.isPending}>Record</Button>
            </Group>
          </Stack>
        </form>
      </Modal>

      {/* Reconcile Modal */}
      <Modal opened={reconcileOpen} onClose={() => setReconcileOpen(false)} title="Reconcile Petty Cash" size="lg">
        <form onSubmit={reconcileForm.onSubmit((v) => reconcileMutation.mutate(v))}>
          <Stack>
            <Card withBorder padding="sm">
              <Group justify="space-between">
                <Text size="sm" c="dimmed">Expected cash in till (committed)</Text>
                <Text fw={600}>{formatCurrency(committedBalance)}</Text>
              </Group>
              {pendingCount > 0 && (
                <Text size="xs" c="dimmed" mt={4}>
                  Includes {pendingCount} pending-voucher expense{pendingCount === 1 ? '' : 's'} totalling {formatCurrency(pendingTotal)} — the cash has already left the till, just awaiting paperwork.
                </Text>
              )}
            </Card>
            <NumberInput
              label="Counted (physical) balance" required min={0} decimalScale={2}
              {...reconcileForm.getInputProps('counted_balance')}
            />
            <Card withBorder padding="sm" bg={difference === 0 ? undefined : difference > 0 ? 'green.0' : 'red.0'}>
              <Group justify="space-between">
                <Text size="sm" c="dimmed">Difference (counted − ledger)</Text>
                <Text fw={700} c={difference === 0 ? 'dimmed' : difference > 0 ? 'green' : 'red'}>
                  {difference > 0 ? '+' : ''}{formatCurrency(difference)}
                </Text>
              </Group>
              {difference !== 0 && (
                <Text size="xs" c="dimmed" mt="xs">
                  {difference > 0 ? 'Extra cash on hand — system will record an adjustment gain.' : 'Cash short — system will record an adjustment loss.'}
                </Text>
              )}
            </Card>
            <Select
              label="Resolution" required
              data={[
                { value: 'accepted', label: 'Accept difference — auto-create adjustment' },
                { value: 'investigating', label: 'Investigate — leave balance untouched for now' },
              ]}
              {...reconcileForm.getInputProps('resolution')}
            />
            <DateInput label="Reconciled at" {...reconcileForm.getInputProps('reconciled_at')} />
            <Textarea label="Notes" {...reconcileForm.getInputProps('notes')} />
            <Group justify="flex-end">
              <Button variant="default" onClick={() => setReconcileOpen(false)}>Cancel</Button>
              <Button type="submit" loading={reconcileMutation.isPending}>Save Reconciliation</Button>
            </Group>
          </Stack>
        </form>
      </Modal>
    </Stack>
  );
}
