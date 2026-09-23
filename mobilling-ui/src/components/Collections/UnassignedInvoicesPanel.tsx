import { useState } from 'react';
import {
  Paper, Group, Stack, Text, Badge, Table, Button, TextInput, NumberInput, Select, Checkbox,
  Pagination, Loader, Center, SimpleGrid, Anchor, Alert, Modal, Textarea,
} from '@mantine/core';
import { useDebouncedValue } from '@mantine/hooks';
import { useNavigate } from 'react-router-dom';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { getUnassignedInvoices, UnassignedInvoice } from '../../api/followups';
import { bulkApproveForCollection, BulkApproveResult } from '../../api/documents';
import { usePermissions } from '../../hooks/usePermissions';
import { formatCurrency } from '../../utils/formatCurrency';
import { formatDate } from '../../utils/formatDate';
import AssignFollowupModal from './AssignFollowupModal';
import ApproveCollectionModal from './ApproveCollectionModal';
import CollectionReviewBadge from './CollectionReviewBadge';

interface Props {
  onOpenInvoice: (documentId: string) => void;
}

/** Unpaid invoices nobody is working yet (Hazijapangiwa): approve, then assign to staff, singly or in bulk. */
export default function UnassignedInvoicesPanel({ onOpenInvoice }: Props) {
  const qc = useQueryClient();
  const navigate = useNavigate();
  const { can } = usePermissions();
  const canApprove = can('documents.approve_collection');

  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 400);
  const [minBalance, setMinBalance] = useState<number | string>('');
  const [minDays, setMinDays] = useState<number | string>('');
  const [review, setReview] = useState<string>('all');
  const [page, setPage] = useState(1);
  const [selected, setSelected] = useState<Record<string, UnassignedInvoice>>({});
  const [assignOne, setAssignOne] = useState<UnassignedInvoice | null>(null);
  const [approveOne, setApproveOne] = useState<UnassignedInvoice | null>(null);
  const [assignBulk, setAssignBulk] = useState(false);
  const [bulkApproveOpen, setBulkApproveOpen] = useState(false);
  const [bulkApproveNotes, setBulkApproveNotes] = useState('');
  const [bulkApproving, setBulkApproving] = useState(false);
  const [approveResult, setApproveResult] = useState<BulkApproveResult | null>(null);

  const params: Record<string, string> = { page: String(page), per_page: '25', review };
  if (debouncedSearch.trim()) params.search = debouncedSearch.trim();
  if (minBalance !== '') params.min_balance = String(minBalance);
  if (minDays !== '') params.min_days_overdue = String(minDays);

  const { data, isLoading, isError } = useQuery({
    queryKey: ['unassigned-invoices', params],
    queryFn: () => getUnassignedInvoices(params),
  });
  const res = data?.data;
  const rows = res?.data ?? [];
  const selectedList = Object.values(selected);
  const selectedApproved = selectedList.filter((r) => r.collection_reviewed_at);
  const selectedUnreviewed = selectedList.filter((r) => !r.collection_reviewed_at);

  const refresh = () => {
    setSelected({});
    qc.invalidateQueries({ queryKey: ['unassigned-invoices'] });
    qc.invalidateQueries({ queryKey: ['followup-dashboard'] });
    qc.invalidateQueries({ queryKey: ['followups'] });
    qc.invalidateQueries({ queryKey: ['my-followups'] });
  };

  const toggle = (r: UnassignedInvoice) =>
    setSelected((s) => {
      const n = { ...s };
      if (n[r.id]) delete n[r.id]; else n[r.id] = r;
      return n;
    });
  const allOnPage = rows.length > 0 && rows.every((r) => selected[r.id]);
  const togglePage = () =>
    setSelected((s) => {
      const n = { ...s };
      if (allOnPage) rows.forEach((r) => delete n[r.id]); else rows.forEach((r) => { n[r.id] = r; });
      return n;
    });

  const submitBulkApprove = async () => {
    setBulkApproving(true);
    try {
      const r = await bulkApproveForCollection(selectedUnreviewed.map((x) => x.id), bulkApproveNotes.trim());
      notifications.show({ title: 'Approved', message: r.data.message, color: 'green' });
      setBulkApproveOpen(false);
      setBulkApproveNotes('');
      if (r.data.skipped.length) setApproveResult(r.data);
      refresh();
    } catch (err: any) {
      notifications.show({ title: 'Error', message: err?.response?.data?.message ?? 'Bulk approve failed.', color: 'red' });
    } finally {
      setBulkApproving(false);
    }
  };

  const resetPage = <T,>(fn: (v: T) => void) => (v: T) => { fn(v); setPage(1); setSelected({}); };

  return (
    <Stack gap="md">
      <SimpleGrid cols={{ base: 1, xs: 3 }}>
        <Paper withBorder p="md" radius="md">
          <Text size="xs" c="dimmed" tt="uppercase" fw={600}>Unassigned invoices (Hazijapangiwa)</Text>
          <Text size="xl" fw={700}>{res?.summary.total ?? 0}</Text>
        </Paper>
        <Paper withBorder p="md" radius="md">
          <Text size="xs" c="dimmed" tt="uppercase" fw={600}>Total balance</Text>
          <Text size="xl" fw={700} c="red">{formatCurrency(res?.summary.total_balance ?? 0)}</Text>
        </Paper>
        <Paper withBorder p="md" radius="md">
          <Text size="xs" c="dimmed" tt="uppercase" fw={600}>Not yet reviewed</Text>
          <Text size="xl" fw={700}>{res?.summary.not_reviewed ?? 0}</Text>
        </Paper>
      </SimpleGrid>

      <Paper withBorder p="md" radius="md">
        <Group gap="sm" mb="sm" align="flex-end" wrap="wrap">
          <TextInput size="xs" label="Search" placeholder="Client or invoice no." w={200}
            value={search} onChange={(e) => { setSearch(e.currentTarget.value); setPage(1); setSelected({}); }} />
          <NumberInput size="xs" label="Min balance" w={130} min={0} hideControls thousandSeparator=","
            value={minBalance} onChange={resetPage(setMinBalance)} />
          <NumberInput size="xs" label="Min days overdue" w={140} min={0} hideControls
            value={minDays} onChange={resetPage(setMinDays)} />
          <Select size="xs" label="Review" w={150} allowDeselect={false} value={review}
            onChange={(v) => resetPage(setReview)(v || 'all')}
            data={[
              { value: 'all', label: 'All' },
              { value: 'approved', label: 'Approved' },
              { value: 'not_reviewed', label: 'Not reviewed' },
            ]} />
        </Group>

        {selectedList.length > 0 && (
          <Group gap="sm" mb="sm">
            <Text size="sm" fw={500}>{selectedList.length} selected</Text>
            {canApprove && selectedUnreviewed.length > 0 && (
              <Button size="xs" color="green" variant="light" onClick={() => setBulkApproveOpen(true)}>
                Approve {selectedUnreviewed.length}
              </Button>
            )}
            <Button size="xs" disabled={selectedApproved.length === 0} onClick={() => setAssignBulk(true)}>
              Assign {selectedApproved.length} approved
            </Button>
            {selectedUnreviewed.length > 0 && (
              <Text size="xs" c="dimmed">{selectedUnreviewed.length} not reviewed will be left out of assignment.</Text>
            )}
            <Button size="xs" variant="subtle" color="gray" onClick={() => setSelected({})}>Clear</Button>
          </Group>
        )}

        {approveResult && (
          <Alert color="orange" title={approveResult.message} withCloseButton onClose={() => setApproveResult(null)} mb="sm">
            {approveResult.skipped.map((s) => (
              <Text key={s.document_id} size="sm"><b>{s.document_number ?? s.document_id}</b>: {s.reason}</Text>
            ))}
          </Alert>
        )}

        {isLoading ? (
          <Center py="md"><Loader size="sm" /></Center>
        ) : isError ? (
          <Text c="red" size="sm">Failed to load unassigned invoices.</Text>
        ) : rows.length === 0 ? (
          <Text c="dimmed" size="sm">Every unpaid invoice matching these filters is already assigned.</Text>
        ) : (
          <>
            <Table.ScrollContainer minWidth={950}>
              <Table striped highlightOnHover>
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th w={30}><Checkbox size="xs" checked={allOnPage} onChange={togglePage} aria-label="Select all" /></Table.Th>
                    <Table.Th>Client</Table.Th>
                    <Table.Th>Invoice</Table.Th>
                    <Table.Th>Balance</Table.Th>
                    <Table.Th>Due</Table.Th>
                    <Table.Th>Calls</Table.Th>
                    <Table.Th>Review</Table.Th>
                    <Table.Th>Action</Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {rows.map((r) => (
                    <Table.Tr key={r.id}>
                      <Table.Td><Checkbox size="xs" checked={!!selected[r.id]} onChange={() => toggle(r)} /></Table.Td>
                      <Table.Td>
                        <Anchor size="sm" fw={500} onClick={() => navigate(`/clients/${r.client_id}`)} style={{ textTransform: 'uppercase' }}>
                          {r.client_name}
                        </Anchor>
                        <Text size="xs" c="dimmed">{r.client_phone || '—'}</Text>
                      </Table.Td>
                      <Table.Td>
                        <Anchor size="sm" onClick={() => onOpenInvoice(r.id)}>{r.document_number}</Anchor>
                        <Group gap={4}>
                          <Badge size="xs" variant="light" color={r.status === 'partial' ? 'yellow' : 'red'}>{r.status}</Badge>
                          {r.escalated && <Badge size="xs" color="orange">escalated</Badge>}
                        </Group>
                      </Table.Td>
                      <Table.Td>
                        <Text size="sm" fw={600} c="red">{formatCurrency(r.balance_due)}</Text>
                        {r.paid > 0 && <Text size="xs" c="dimmed">of {formatCurrency(r.total)}</Text>}
                      </Table.Td>
                      <Table.Td>
                        <Text size="sm">{r.due_date ? formatDate(r.due_date) : '—'}</Text>
                        {r.days_overdue > 0 && <Text size="xs" c="red">{r.days_overdue} days overdue</Text>}
                      </Table.Td>
                      <Table.Td>
                        <Badge color={r.call_count >= 3 ? 'red' : 'gray'} variant="light" size="sm">{r.call_count}/3</Badge>
                      </Table.Td>
                      <Table.Td>
                        <CollectionReviewBadge reviewedAt={r.collection_reviewed_at} reviewedByName={r.collection_reviewed_by_name} />
                      </Table.Td>
                      <Table.Td>
                        <Group gap="xs" wrap="nowrap">
                          {canApprove && !r.collection_reviewed_at && (
                            <Button size="compact-xs" color="green" variant="light" onClick={() => setApproveOne(r)}>Approve</Button>
                          )}
                          <Button size="compact-xs" onClick={() => setAssignOne(r)}
                            disabled={!r.collection_reviewed_at && !canApprove}>
                            Assign
                          </Button>
                        </Group>
                      </Table.Td>
                    </Table.Tr>
                  ))}
                </Table.Tbody>
              </Table>
            </Table.ScrollContainer>
            {(res?.last_page ?? 1) > 1 && (
              <Group justify="center" mt="md">
                <Pagination value={page} onChange={setPage} total={res!.last_page} size="sm" />
              </Group>
            )}
          </>
        )}
      </Paper>

      {assignOne && (
        <AssignFollowupModal
          opened
          onClose={() => setAssignOne(null)}
          documentId={assignOne.id}
          documentNumber={assignOne.document_number}
          clientName={assignOne.client_name}
          balance={assignOne.balance_due}
          onDone={refresh}
        />
      )}
      {approveOne && (
        <ApproveCollectionModal
          opened
          onClose={() => setApproveOne(null)}
          documentId={approveOne.id}
          documentNumber={approveOne.document_number}
          onApproved={refresh}
        />
      )}
      {assignBulk && (
        <AssignFollowupModal
          opened
          onClose={() => setAssignBulk(false)}
          documentId=""
          documentNumber=""
          bulkDocuments={selectedApproved.map((r) => ({ id: r.id, number: r.document_number }))}
          onDone={refresh}
        />
      )}
      <Modal opened={bulkApproveOpen} onClose={() => setBulkApproveOpen(false)}
        title={`Approve ${selectedUnreviewed.length} invoices for collection`} centered>
        <Stack>
          <Text size="sm" c="dimmed">
            Confirm these debts are genuine and collectible. (Thibitisha madeni haya ni halali.)
          </Text>
          <Textarea label="Review notes (optional)" minRows={3} maxLength={2000}
            value={bulkApproveNotes} onChange={(e) => setBulkApproveNotes(e.currentTarget.value)} />
          <Group justify="flex-end">
            <Button variant="default" onClick={() => setBulkApproveOpen(false)}>Cancel</Button>
            <Button color="green" loading={bulkApproving} onClick={submitBulkApprove}>Approve</Button>
          </Group>
        </Stack>
      </Modal>
    </Stack>
  );
}
