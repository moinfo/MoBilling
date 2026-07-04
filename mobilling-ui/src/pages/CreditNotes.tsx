import { useEffect, useState } from 'react';
import {
  Title, Group, Button, TextInput, Pagination, Drawer, Table, Badge, Card, Stack, Text,
  Divider, Checkbox, LoadingOverlay, Select,
} from '@mantine/core';
import { useDisclosure } from '@mantine/hooks';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconPlus, IconSearch, IconFileDownload, IconTrash, IconCheck } from '@tabler/icons-react';
import { useSearchParams } from 'react-router-dom';
import dayjs from 'dayjs';
import {
  getCreditNotes, getCreditNote, createCreditNote, issueCreditNote, deleteCreditNote,
  downloadCreditNotePdf, creditNoteItemsFromInvoice, CreditNoteItemInput,
} from '../api/creditNotes';
import { getDocument, Document } from '../api/documents';
import { getClients, Client } from '../api/clients';
import { getProductServices, ProductService } from '../api/productServices';
import DocumentForm from '../components/Billing/DocumentForm';
import { usePermissions } from '../hooks/usePermissions';
import { formatCurrency } from '../utils/formatCurrency';
import { formatDate } from '../utils/formatDate';

const statusColor: Record<string, string> = { draft: 'gray', sent: 'grape' };
const statusLabel: Record<string, string> = { draft: 'Draft', sent: 'Issued' };

export default function CreditNotes() {
  const queryClient = useQueryClient();
  const { can } = usePermissions();
  const [searchParams, setSearchParams] = useSearchParams();
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(1);
  const [formOpen, { open: openForm, close: closeForm }] = useDisclosure(false);
  const [viewId, setViewId] = useState<string | null>(null);

  // Prefill state when creating from an invoice.
  const [sourceInvoice, setSourceInvoice] = useState<Document | null>(null);
  const [prefillItems, setPrefillItems] = useState<CreditNoteItemInput[] | null>(null);
  const [selectedClient, setSelectedClient] = useState<string>('');
  const [cancelSource, setCancelSource] = useState(false);

  const { data, isLoading } = useQuery({
    queryKey: ['credit-notes', search, page],
    queryFn: () => getCreditNotes({ search: search || undefined, page }),
  });
  const { data: clientsData } = useQuery({ queryKey: ['clients-all'], queryFn: () => getClients({ per_page: 1000 }) });
  const { data: psData } = useQuery({ queryKey: ['product-services-all'], queryFn: () => getProductServices({ per_page: 1000, active_only: true }) });

  const creditNotes: Document[] = data?.data?.data || [];
  const meta = data?.data?.meta;
  const clients: Client[] = clientsData?.data?.data || [];
  const productServices: ProductService[] = psData?.data?.data || [];

  // ?from=<invoiceId> — open the form prefilled from an invoice ("Credit this invoice").
  useEffect(() => {
    const from = searchParams.get('from');
    const preview = searchParams.get('preview');
    if (from) {
      getDocument(from).then((res) => {
        const inv = res.data.data;
        setSourceInvoice(inv);
        setSelectedClient(inv.client_id);
        setPrefillItems(creditNoteItemsFromInvoice(inv));
        openForm();
      }).catch(() => notifications.show({ title: 'Error', message: 'Could not load the invoice.', color: 'red' }));
      searchParams.delete('from');
      setSearchParams(searchParams, { replace: true });
    } else if (preview) {
      setViewId(preview);
      searchParams.delete('preview');
      setSearchParams(searchParams, { replace: true });
    }
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  const { data: detailData } = useQuery({
    queryKey: ['credit-note', viewId],
    queryFn: () => getCreditNote(viewId!),
    enabled: !!viewId,
  });
  const detail = detailData?.data?.data;

  const resetForm = () => {
    setSourceInvoice(null);
    setPrefillItems(null);
    setSelectedClient('');
    setCancelSource(false);
  };

  const createMutation = useMutation({
    mutationFn: (payload: Parameters<typeof createCreditNote>[0]) => createCreditNote(payload),
    onSuccess: (res) => {
      queryClient.invalidateQueries({ queryKey: ['credit-notes'] });
      closeForm();
      resetForm();
      notifications.show({ title: 'Created', message: `Credit note ${res.data.data.document_number} created as draft.`, color: 'green' });
      setViewId(res.data.data.id);
    },
    onError: (err: any) => notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed to create credit note', color: 'red' }),
  });

  const issueMutation = useMutation({
    mutationFn: ({ id, cancel }: { id: string; cancel: boolean }) => issueCreditNote(id, cancel),
    onSuccess: (res) => {
      queryClient.invalidateQueries({ queryKey: ['credit-notes'] });
      queryClient.invalidateQueries({ queryKey: ['credit-note', viewId] });
      notifications.show({ title: 'Issued', message: res.data.message, color: 'green' });
    },
    onError: (err: any) => notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed to issue credit note', color: 'red' }),
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => deleteCreditNote(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['credit-notes'] });
      setViewId(null);
      notifications.show({ title: 'Deleted', message: 'Credit note deleted.', color: 'green' });
    },
    onError: (err: any) => notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed to delete', color: 'red' }),
  });

  const handleFormSubmit = (values: any) => {
    createMutation.mutate({
      client_id: values.client_id,
      date: values.date,
      notes: values.notes || undefined,
      items: values.items,
      source_invoice_id: sourceInvoice?.id ?? null,
      cancel_source_invoice: sourceInvoice ? cancelSource : false,
    });
  };

  const handleIssue = (cn: Document) => {
    const hasSource = !!cn.parent_id;
    modals.openConfirmModal({
      title: 'Issue Credit Note',
      children: (
        <Stack gap="xs">
          <Text size="sm">
            Issue {cn.document_number}? This credits {formatCurrency(cn.total)} to the client's account balance. This cannot be undone.
          </Text>
          {hasSource && (
            <Checkbox
              label="Also cancel the source invoice (only if it has no payments)"
              checked={cancelSource}
              onChange={(e) => setCancelSource(e.currentTarget.checked)}
            />
          )}
        </Stack>
      ),
      labels: { confirm: 'Issue & Credit', cancel: 'Cancel' },
      confirmProps: { color: 'grape' },
      onConfirm: () => issueMutation.mutate({ id: cn.id, cancel: hasSource ? cancelSource : false }),
    });
  };

  const handleDownload = async (cn: Document) => {
    try {
      const res = await downloadCreditNotePdf(cn.id);
      const url = window.URL.createObjectURL(new Blob([res.data]));
      const link = window.document.createElement('a');
      link.href = url;
      link.download = `${cn.document_number}.pdf`;
      link.click();
      window.URL.revokeObjectURL(url);
    } catch {
      notifications.show({ title: 'Error', message: 'PDF download failed', color: 'red' });
    }
  };

  return (
    <>
      <Group justify="space-between" mb="md">
        <Title order={2}>Credit Notes</Title>
        {can('documents.create') && (
          <Button leftSection={<IconPlus size={16} />} onClick={() => { resetForm(); openForm(); }}>
            New Credit Note
          </Button>
        )}
      </Group>

      <Group mb="md">
        <TextInput
          placeholder="Search by number or client..."
          leftSection={<IconSearch size={16} />}
          value={search}
          onChange={(e) => { setSearch(e.currentTarget.value); setPage(1); }}
          w={320}
        />
      </Group>

      <Card withBorder pos="relative">
        <LoadingOverlay visible={isLoading} />
        <Table striped highlightOnHover>
          <Table.Thead>
            <Table.Tr>
              <Table.Th>Number</Table.Th>
              <Table.Th>Client</Table.Th>
              <Table.Th>Date</Table.Th>
              <Table.Th ta="right">Total</Table.Th>
              <Table.Th>Status</Table.Th>
              <Table.Th></Table.Th>
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {creditNotes.map((cn) => (
              <Table.Tr key={cn.id} style={{ cursor: 'pointer' }} onClick={() => setViewId(cn.id)}>
                <Table.Td fw={600}>{cn.document_number}</Table.Td>
                <Table.Td>{cn.client?.name}</Table.Td>
                <Table.Td>{formatDate(cn.date)}</Table.Td>
                <Table.Td ta="right">{formatCurrency(cn.total)}</Table.Td>
                <Table.Td>
                  <Badge color={statusColor[cn.status] || 'gray'} variant="light">{statusLabel[cn.status] || cn.status}</Badge>
                </Table.Td>
                <Table.Td onClick={(e) => e.stopPropagation()}>
                  <Button variant="subtle" size="compact-xs" leftSection={<IconFileDownload size={14} />} onClick={() => handleDownload(cn)}>
                    PDF
                  </Button>
                </Table.Td>
              </Table.Tr>
            ))}
            {creditNotes.length === 0 && !isLoading && (
              <Table.Tr><Table.Td colSpan={6} ta="center" c="dimmed">No credit notes found</Table.Td></Table.Tr>
            )}
          </Table.Tbody>
        </Table>
        {meta && meta.last_page > 1 && (
          <Group justify="center" mt="md">
            <Pagination total={meta.last_page} value={page} onChange={setPage} />
          </Group>
        )}
      </Card>

      {/* Create form drawer */}
      <Drawer opened={formOpen} onClose={() => { closeForm(); resetForm(); }}
        title={sourceInvoice ? `Credit Note from ${sourceInvoice.document_number}` : 'New Credit Note'}
        size={900} position="right">
        <Stack>
          {sourceInvoice && (
            <Card withBorder p="sm">
              <Text size="sm">Crediting invoice <Text span fw={600}>{sourceInvoice.document_number}</Text> for {sourceInvoice.client?.name}.</Text>
              <Checkbox mt="xs" label="Cancel the source invoice when this credit note is issued (only if it has no payments)"
                checked={cancelSource} onChange={(e) => setCancelSource(e.currentTarget.checked)} />
            </Card>
          )}
          {!sourceInvoice && (
            <Select
              label="Client" placeholder="Select client" searchable required
              data={clients.map((c) => ({ value: c.id, label: c.name }))}
              value={selectedClient}
              onChange={(v) => setSelectedClient(v || '')}
            />
          )}
          {(sourceInvoice || selectedClient) && (
            <DocumentForm
              key={sourceInvoice?.id || selectedClient || 'new-cn'}
              clients={clients}
              productServices={productServices}
              type="invoice"
              onSubmit={handleFormSubmit}
              loading={createMutation.isPending}
              initialValues={{
                client_id: sourceInvoice?.client_id || selectedClient,
                date: dayjs().format('YYYY-MM-DD'),
                due_date: null,
                notes: '',
                items: (prefillItems || []).map((it) => ({ ...it })),
              }}
            />
          )}
        </Stack>
      </Drawer>

      {/* View drawer */}
      <Drawer opened={!!viewId} onClose={() => setViewId(null)} title="Credit Note" size="lg" position="right">
        {detail && (
          <Stack>
            <Group justify="space-between">
              <div>
                <Text size="xl" fw={700}>{detail.document_number}</Text>
                <Text c="dimmed" size="sm">Credit Note — {detail.client?.name}</Text>
              </div>
              <Badge color={statusColor[detail.status] || 'gray'} size="lg">{statusLabel[detail.status] || detail.status}</Badge>
            </Group>
            <Text size="sm" c="dimmed">Date: {formatDate(detail.date)}</Text>
            {detail.parent_id && (
              <Text size="sm" c="dimmed">Linked to source invoice.</Text>
            )}
            <Divider />
            <Table>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Description</Table.Th>
                  <Table.Th ta="right">Qty</Table.Th>
                  <Table.Th ta="right">Price</Table.Th>
                  <Table.Th ta="right">Total</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {detail.items?.map((it, i) => (
                  <Table.Tr key={i}>
                    <Table.Td>{it.description}</Table.Td>
                    <Table.Td ta="right">{it.quantity}</Table.Td>
                    <Table.Td ta="right">{formatCurrency(it.price)}</Table.Td>
                    <Table.Td ta="right">{formatCurrency(it.total || 0)}</Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
            <Group justify="flex-end">
              <Text size="lg" fw={700}>Credit Total: {formatCurrency(detail.total)}</Text>
            </Group>
            {detail.notes && <Text size="sm" c="dimmed">Notes: {detail.notes}</Text>}
            <Divider />
            <Group>
              <Button variant="light" leftSection={<IconFileDownload size={16} />} onClick={() => handleDownload(detail)}>
                Download PDF
              </Button>
              {detail.status === 'draft' && can('documents.update') && (
                <Button color="grape" leftSection={<IconCheck size={16} />}
                  loading={issueMutation.isPending}
                  onClick={() => handleIssue(detail)}>
                  Issue & Credit Client
                </Button>
              )}
              {detail.status === 'draft' && can('documents.delete') && (
                <Button variant="light" color="red" leftSection={<IconTrash size={16} />}
                  loading={deleteMutation.isPending}
                  onClick={() => modals.openConfirmModal({
                    title: 'Delete Credit Note',
                    children: `Delete ${detail.document_number}?`,
                    labels: { confirm: 'Delete', cancel: 'Cancel' },
                    confirmProps: { color: 'red' },
                    onConfirm: () => deleteMutation.mutate(detail.id),
                  })}>
                  Delete
                </Button>
              )}
            </Group>
          </Stack>
        )}
      </Drawer>
    </>
  );
}
