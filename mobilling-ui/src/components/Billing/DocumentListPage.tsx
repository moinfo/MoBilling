import { useState, useEffect } from 'react';
import {
  Title, Group, Button, TextInput, Pagination, Drawer,
  SegmentedControl, Modal, Stack, Text, Radio,
} from '@mantine/core';
import { DateInput } from '@mantine/dates';
import { useDisclosure, useDebouncedValue } from '@mantine/hooks';
import dayjs from 'dayjs';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconPlus, IconSearch, IconBell, IconMail, IconMessage, IconSend, IconFileSymlink } from '@tabler/icons-react';
import { useSearchParams } from 'react-router-dom';
import { getDocuments, getDocument, createDocument, updateDocument, deleteDocument, cancelDocument, uncancelDocument, remindUnpaid, mergeInvoices, submitForApproval, approveDocument, rejectDocument, updateDocumentDueDate, returnDocumentToDraft, Document, DocumentFormData } from '../../api/documents';
import { getClients, Client } from '../../api/clients';
import { getProductServices, ProductService } from '../../api/productServices';
import DocumentTable from './DocumentTable';
import DocumentForm from './DocumentForm';
import DocumentView from './DocumentView';
import { usePermissions } from '../../hooks/usePermissions';
import { formatCurrency } from '../../utils/formatCurrency';
import { formatDate } from '../../utils/formatDate';

interface Props {
  type: 'quotation' | 'proforma' | 'invoice';
  title: string;
}

export default function DocumentListPage({ type, title }: Props) {
  const queryClient = useQueryClient();
  const { can } = usePermissions();
  const canChangeDateRange = can('documents.date_range');
  const monthStart = dayjs().startOf('month').format('YYYY-MM-DD');
  const monthEnd = dayjs().endOf('month').format('YYYY-MM-DD');
  const [searchParams, setSearchParams] = useSearchParams();
  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 300);
  const [page, setPage] = useState(1);
  const [dateFrom, setDateFrom] = useState<string>(monthStart);
  const [dateTo, setDateTo] = useState<string>(monthEnd);
  const [statusFilter, setStatusFilter] = useState('all');
  const [formOpen, setFormOpen] = useState(false);
  const [editDoc, setEditDoc] = useState<Document | null>(null);
  const [viewDoc, setViewDoc] = useState<Document | null>(null);
  const [dueDateDoc, setDueDateDoc] = useState<Document | null>(null);
  const [newDueDate, setNewDueDate] = useState<Date | null>(null);

  // Auto-open preview from URL query param (?preview=documentId)
  useEffect(() => {
    const previewId = searchParams.get('preview');
    if (previewId) {
      getDocument(previewId).then((res) => setViewDoc(res.data.data)).catch(() => {});
      searchParams.delete('preview');
      setSearchParams(searchParams, { replace: true });
    }
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  // Selection state for merge
  const [selectedIds, setSelectedIds] = useState<string[]>([]);

  // Remind modal state
  const [remindOpened, { open: openRemind, close: closeRemind }] = useDisclosure(false);
  const [remindIds, setRemindIds] = useState<string[]>([]);
  const [remindChannel, setRemindChannel] = useState<'email' | 'sms' | 'whatsapp' | 'both'>('email');
  const [remindLabel, setRemindLabel] = useState('');

  const isInvoice = type === 'invoice';

  // Map filter to API status param
  const statusParam = statusFilter === 'all' ? undefined
    : statusFilter === 'unpaid' ? 'sent' // sent = unpaid invoices
    : statusFilter; // 'paid', 'overdue', 'draft'

  const { data: docsData, isLoading } = useQuery({
    queryKey: ['documents', type, debouncedSearch, page, statusParam, dateFrom, dateTo],
    queryFn: () => getDocuments({
      type,
      search: debouncedSearch || undefined,
      page,
      status: statusParam,
      date_from: dateFrom || undefined,
      date_to: dateTo || undefined,
    }),
  });

  const { data: clientsData } = useQuery({
    queryKey: ['clients-all'],
    queryFn: () => getClients({ per_page: 1000 }),
  });

  const { data: psData } = useQuery({
    queryKey: ['product-services-all'],
    queryFn: () => getProductServices({ per_page: 1000, active_only: true }),
  });

  const documents = docsData?.data?.data || [];
  const meta = docsData?.data?.meta;
  const clients: Client[] = clientsData?.data?.data || [];
  const productServices: ProductService[] = psData?.data?.data || [];

  // Unpaid invoices for "Remind All"
  const unpaidDocs = documents.filter((d: Document) => d.status !== 'paid' && d.status !== 'draft');

  const createMutation = useMutation({
    mutationFn: (values: DocumentFormData) => createDocument(values),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['documents'] });
      setFormOpen(false);
      notifications.show({ title: 'Success', message: `${title.slice(0, -1)} created`, color: 'green' });
    },
    onError: () => notifications.show({ title: 'Error', message: 'Failed to create', color: 'red' }),
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, values }: { id: string; values: DocumentFormData }) => updateDocument(id, values),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['documents'] });
      setFormOpen(false);
      setEditDoc(null);
      notifications.show({ title: 'Success', message: `${title.slice(0, -1)} updated`, color: 'green' });
    },
    onError: () => notifications.show({ title: 'Error', message: 'Failed to update', color: 'red' }),
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => deleteDocument(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['documents'] });
      notifications.show({ title: 'Success', message: 'Document deleted', color: 'green' });
    },
  });

  const cancelMutation = useMutation({
    mutationFn: (id: string) => cancelDocument(id),
    onSuccess: (res) => {
      queryClient.invalidateQueries({ queryKey: ['documents'] });
      notifications.show({ title: 'Cancelled', message: res.data.message, color: 'green' });
    },
    onError: (err: any) => notifications.show({
      title: 'Error',
      message: err.response?.data?.message || 'Failed to cancel',
      color: 'red',
    }),
  });

  const uncancelMutation = useMutation({
    mutationFn: (id: string) => uncancelDocument(id),
    onSuccess: (res) => {
      queryClient.invalidateQueries({ queryKey: ['documents'] });
      notifications.show({ title: 'Restored', message: res.data.message, color: 'green' });
    },
    onError: (err: any) => notifications.show({
      title: 'Error',
      message: err.response?.data?.message || 'Failed to restore',
      color: 'red',
    }),
  });

  const remindMutation = useMutation({
    mutationFn: ({ ids, channel }: { ids: string[]; channel: 'email' | 'sms' | 'whatsapp' | 'both' }) =>
      remindUnpaid(ids, channel),
    onSuccess: (res) => {
      closeRemind();
      notifications.show({ title: 'Reminders Sent', message: res.data.message, color: 'green' });
    },
    onError: () => notifications.show({ title: 'Error', message: 'Failed to send reminders', color: 'red' }),
  });

  const mergeMutation = useMutation({
    mutationFn: (ids: string[]) => mergeInvoices(ids),
    onSuccess: (res) => {
      queryClient.invalidateQueries({ queryKey: ['documents'] });
      setSelectedIds([]);
      notifications.show({ title: 'Merged', message: res.data.message, color: 'green' });
    },
    onError: (err: any) => notifications.show({
      title: 'Error',
      message: err.response?.data?.message || 'Failed to merge invoices',
      color: 'red',
    }),
  });

  const submitApprovalMutation = useMutation({
    mutationFn: (id: string) => submitForApproval(id),
    onSuccess: (res) => {
      queryClient.invalidateQueries({ queryKey: ['documents'] });
      notifications.show({ title: 'Submitted', message: res.data.message, color: 'violet' });
    },
    onError: (err: any) => notifications.show({
      title: 'Error',
      message: err.response?.data?.message || 'Failed to submit for approval',
      color: 'red',
    }),
  });

  const approveMutation = useMutation({
    mutationFn: (id: string) => approveDocument(id),
    onSuccess: (res) => {
      queryClient.invalidateQueries({ queryKey: ['documents'] });
      notifications.show({ title: 'Approved', message: res.data.message, color: 'green' });
    },
    onError: (err: any) => notifications.show({
      title: 'Error',
      message: err.response?.data?.message || 'Failed to approve',
      color: 'red',
    }),
  });

  const rejectMutation = useMutation({
    mutationFn: (id: string) => rejectDocument(id),
    onSuccess: (res) => {
      queryClient.invalidateQueries({ queryKey: ['documents'] });
      notifications.show({ title: 'Rejected', message: res.data.message, color: 'orange' });
    },
    onError: (err: any) => notifications.show({
      title: 'Error',
      message: err.response?.data?.message || 'Failed to reject',
      color: 'red',
    }),
  });

  const dueDateMutation = useMutation({
    mutationFn: ({ id, due_date }: { id: string; due_date: string }) => updateDocumentDueDate(id, due_date),
    onSuccess: (res) => {
      queryClient.invalidateQueries({ queryKey: ['documents'] });
      setDueDateDoc(null);
      notifications.show({ title: 'Updated', message: res.data.message, color: 'green' });
    },
    onError: (err: any) => notifications.show({
      title: 'Error',
      message: err.response?.data?.message || 'Failed to update due date',
      color: 'red',
    }),
  });

  const handleExtendDueDate = (doc: Document) => {
    setDueDateDoc(doc);
    setNewDueDate(doc.due_date ? new Date(doc.due_date) : null);
  };

  const returnToDraftMutation = useMutation({
    mutationFn: (id: string) => returnDocumentToDraft(id),
    onSuccess: (res) => {
      queryClient.invalidateQueries({ queryKey: ['documents'] });
      notifications.show({ title: 'Returned', message: res.data.message, color: 'green' });
    },
    onError: (err: any) => notifications.show({
      title: 'Error',
      message: err.response?.data?.message || 'Failed to return to draft',
      color: 'red',
    }),
  });

  const handleReturnToDraft = (doc: Document) => {
    modals.openConfirmModal({
      title: 'Return to Draft',
      children: `Return ${doc.document_number} to draft? You will be able to edit it before resending.`,
      labels: { confirm: 'Return to Draft', cancel: 'Cancel' },
      confirmProps: { color: 'orange' },
      onConfirm: () => returnToDraftMutation.mutate(doc.id),
    });
  };

  const handleSubmitForApproval = (doc: Document) => {
    modals.openConfirmModal({
      title: 'Submit for Approval',
      children: `Submit ${doc.document_number} for approval? Once approved, it will be sent to the client.`,
      labels: { confirm: 'Submit', cancel: 'Cancel' },
      confirmProps: { color: 'violet' },
      onConfirm: () => submitApprovalMutation.mutate(doc.id),
    });
  };

  const handleApprove = (doc: Document) => {
    modals.openConfirmModal({
      title: 'Approve & Send',
      children: `Approve ${doc.document_number}? This will send it to ${doc.client?.name || 'the client'}.`,
      labels: { confirm: 'Approve & Send', cancel: 'Cancel' },
      confirmProps: { color: 'green' },
      onConfirm: () => approveMutation.mutate(doc.id),
    });
  };

  const handleReject = (doc: Document) => {
    modals.openConfirmModal({
      title: 'Return to Draft',
      children: `Return ${doc.document_number} to draft? You can edit and resubmit it.`,
      labels: { confirm: 'Return to Draft', cancel: 'Cancel' },
      confirmProps: { color: 'orange' },
      onConfirm: () => rejectMutation.mutate(doc.id),
    });
  };

  const handleView = async (doc: Document) => {
    const res = await getDocument(doc.id);
    setViewDoc(res.data.data);
  };

  const handleEdit = async (doc: Document) => {
    const res = await getDocument(doc.id);
    const full = res.data.data;
    setEditDoc(full);
    setFormOpen(true);
  };

  const handleDelete = (doc: Document) => {
    modals.openConfirmModal({
      title: 'Delete Document',
      children: `Delete ${doc.document_number}?`,
      labels: { confirm: 'Delete', cancel: 'Cancel' },
      confirmProps: { color: 'red' },
      onConfirm: () => deleteMutation.mutate(doc.id),
    });
  };

  const handleCancel = (doc: Document) => {
    modals.openConfirmModal({
      title: 'Cancel Invoice',
      children: `Cancel ${doc.document_number}? This will mark it as cancelled and stop all reminders.`,
      labels: { confirm: 'Cancel Invoice', cancel: 'Keep' },
      confirmProps: { color: 'red' },
      onConfirm: () => cancelMutation.mutate(doc.id),
    });
  };

  const handleUncancel = (doc: Document) => {
    modals.openConfirmModal({
      title: 'Restore Invoice',
      children: `Restore ${doc.document_number}? This will reactivate the invoice and resume reminders.`,
      labels: { confirm: 'Restore', cancel: 'Keep Cancelled' },
      confirmProps: { color: 'green' },
      onConfirm: () => uncancelMutation.mutate(doc.id),
    });
  };

  const handleRefresh = async () => {
    if (viewDoc) {
      const res = await getDocument(viewDoc.id);
      setViewDoc(res.data.data);
    }
    queryClient.invalidateQueries({ queryKey: ['documents'] });
  };

  const handleMerge = () => {
    const selectedDocs = documents.filter((d: Document) => selectedIds.includes(d.id));
    const clientIds = [...new Set(selectedDocs.map((d: Document) => d.client_id))];
    if (clientIds.length > 1) {
      notifications.show({ title: 'Error', message: 'All selected invoices must belong to the same client.', color: 'red' });
      return;
    }
    const clientName = selectedDocs[0]?.client?.name || 'the client';
    const totalAmount = selectedDocs.reduce((sum: number, d: Document) => sum + parseFloat(d.total), 0);
    modals.openConfirmModal({
      title: 'Merge Invoices',
      children: `Merge ${selectedDocs.length} invoices for ${clientName} into one combined invoice (${formatCurrency(totalAmount)})? The original invoices will be cancelled.`,
      labels: { confirm: 'Merge', cancel: 'Cancel' },
      confirmProps: { color: 'blue' },
      onConfirm: () => mergeMutation.mutate(selectedIds),
    });
  };

  const openRemindSingle = (doc: Document) => {
    setRemindIds([doc.id]);
    setRemindLabel(doc.document_number);
    setRemindChannel('email');
    openRemind();
  };

  const openRemindAll = () => {
    setRemindIds(unpaidDocs.map((d: Document) => d.id));
    setRemindLabel(`${unpaidDocs.length} unpaid invoice(s)`);
    setRemindChannel('email');
    openRemind();
  };

  return (
    <>
      <Group justify="space-between" mb="md">
        <Title order={2}>{title}</Title>
        {can('documents.create') && (
          <Button leftSection={<IconPlus size={16} />} onClick={() => setFormOpen(true)}>
            New {title.slice(0, -1)}
          </Button>
        )}
      </Group>

      <Group mb="md" justify="space-between" wrap="wrap">
        <Group gap="sm" wrap="wrap">
          <TextInput
            placeholder="Search by number or client..."
            leftSection={<IconSearch size={16} />}
            value={search}
            onChange={(e) => { setSearch(e.currentTarget.value); setPage(1); }}
            w={300}
          />
          <DateInput
            label="From"
            value={dateFrom ? new Date(dateFrom) : null}
            onChange={(v) => { setDateFrom(v ? dayjs(v).format('YYYY-MM-DD') : monthStart); setPage(1); }}
            disabled={!canChangeDateRange}
            maw={160}
            size="sm"
          />
          <DateInput
            label="To"
            value={dateTo ? new Date(dateTo) : null}
            onChange={(v) => { setDateTo(v ? dayjs(v).format('YYYY-MM-DD') : monthEnd); setPage(1); }}
            disabled={!canChangeDateRange}
            maw={160}
            size="sm"
          />
          {isInvoice && (
            <SegmentedControl
              size="sm"
              value={statusFilter}
              onChange={(v) => { setStatusFilter(v); setPage(1); }}
              data={[
                { label: 'All', value: 'all' },
                { label: 'Draft', value: 'draft' },
                { label: 'Pending', value: 'pending_approval' },
                { label: 'Unpaid', value: 'unpaid' },
                { label: 'Paid', value: 'paid' },
                { label: 'Overdue', value: 'overdue' },
                { label: 'Cancelled', value: 'cancelled' },
              ]}
            />
          )}
        </Group>
        <Group gap="sm">
          {isInvoice && selectedIds.length >= 2 && (
            <Button
              variant="light"
              color="blue"
              leftSection={<IconFileSymlink size={16} />}
              onClick={handleMerge}
              loading={mergeMutation.isPending}
            >
              Merge Selected ({selectedIds.length})
            </Button>
          )}
          {isInvoice && statusFilter === 'unpaid' && unpaidDocs.length > 0 && (
            <Button
              variant="light"
              color="orange"
              leftSection={<IconBell size={16} />}
              onClick={openRemindAll}
            >
              Remind All ({unpaidDocs.length})
            </Button>
          )}
        </Group>
      </Group>

      <DocumentTable
        documents={documents}
        onView={handleView}
        onEdit={handleEdit}
        onDelete={handleDelete}
        onRemind={isInvoice ? openRemindSingle : undefined}
        onCancel={isInvoice ? handleCancel : undefined}
        onUncancel={isInvoice ? handleUncancel : undefined}
        onSubmitForApproval={handleSubmitForApproval}
        onApprove={handleApprove}
        onReject={handleReject}
        onExtendDueDate={isInvoice ? handleExtendDueDate : undefined}
        onReturnToDraft={isInvoice ? handleReturnToDraft : undefined}
        startIndex={meta ? (meta.current_page - 1) * meta.per_page + 1 : 1}
        loading={isLoading}
        selectable={isInvoice}
        selectedIds={selectedIds}
        onSelectionChange={setSelectedIds}
      />

      {meta && meta.last_page > 1 && (
        <Group justify="center" mt="md">
          <Pagination total={meta.last_page} value={page} onChange={setPage} />
        </Group>
      )}

      {/* Create/Edit form drawer */}
      <Drawer
        opened={formOpen}
        onClose={() => { setFormOpen(false); setEditDoc(null); }}
        title={editDoc ? `Edit ${editDoc.document_number}` : `New ${title.slice(0, -1)}`}
        size={900}
        position="right"
      >
        <DocumentForm
          key={editDoc?.id || 'new'}
          clients={clients}
          productServices={productServices}
          type={type}
          onSubmit={(values) => {
            if (editDoc) {
              updateMutation.mutate({ id: editDoc.id, values });
            } else {
              createMutation.mutate(values);
            }
          }}
          loading={editDoc ? updateMutation.isPending : createMutation.isPending}
          initialValues={editDoc ? {
            client_id: editDoc.client_id,
            date: editDoc.date,
            due_date: editDoc.due_date || null,
            notes: editDoc.notes || '',
            items: editDoc.items.map((item) => ({
              product_service_id: item.product_service_id || '',
              item_type: item.item_type,
              description: item.description,
              quantity: item.quantity,
              price: item.price,
              discount_type: item.discount_type,
              discount_value: item.discount_value,
              tax_percent: item.tax_percent,
              unit: item.unit || '',
            })),
          } : undefined}
        />
      </Drawer>

      {/* View drawer */}
      <Drawer
        opened={!!viewDoc}
        onClose={() => setViewDoc(null)}
        title="Document Details"
        size="xl"
        position="right"
      >
        {viewDoc && (
          <DocumentView
            document={viewDoc}
            onRefresh={handleRefresh}
            onClose={() => setViewDoc(null)}
          />
        )}
      </Drawer>

      {/* Extend Due Date Modal */}
      <Modal opened={!!dueDateDoc} onClose={() => setDueDateDoc(null)} title="Extend Due Date" size="sm">
        <Stack gap="md">
          <Text size="sm">
            <Text span fw={600}>{dueDateDoc?.document_number}</Text> — {dueDateDoc?.client?.name}
          </Text>
          {dueDateDoc?.due_date && (
            <Text size="sm" c="dimmed">
              Current due date: <Text span fw={500}>{formatDate(dueDateDoc.due_date)}</Text>
            </Text>
          )}
          <DateInput
            label="New Due Date"
            placeholder="Select new due date"
            required
            value={newDueDate}
            onChange={(v) => setNewDueDate(v ? new Date(v) : null)}
          />
          <Group justify="flex-end">
            <Button variant="default" onClick={() => setDueDateDoc(null)}>Cancel</Button>
            <Button
              color="cyan"
              loading={dueDateMutation.isPending}
              disabled={!newDueDate}
              onClick={() => {
                if (dueDateDoc && newDueDate) {
                  dueDateMutation.mutate({
                    id: dueDateDoc.id,
                    due_date: dayjs(newDueDate).format('YYYY-MM-DD'),
                  });
                }
              }}
            >
              Update Due Date
            </Button>
          </Group>
        </Stack>
      </Modal>

      {/* Remind Modal */}
      <Modal opened={remindOpened} onClose={closeRemind} title="Send Payment Reminder" size="sm">
        <Stack gap="md">
          <Text size="sm">
            Send reminder for <Text span fw={600}>{remindLabel}</Text>
          </Text>

          <Radio.Group
            label="Send via"
            value={remindChannel}
            onChange={(v) => setRemindChannel(v as 'email' | 'sms' | 'whatsapp' | 'both')}
          >
            <Stack gap="xs" mt="xs">
              <Radio value="email" label="Email" icon={({ ...rest }) => <IconMail size={14} {...rest} />} />
              <Radio value="sms" label="SMS" icon={({ ...rest }) => <IconMessage size={14} {...rest} />} />
              <Radio value="whatsapp" label="WhatsApp" icon={({ ...rest }) => <IconSend size={14} {...rest} />} />
              <Radio value="both" label="Both (Email + SMS)" icon={({ ...rest }) => <IconSend size={14} {...rest} />} />
            </Stack>
          </Radio.Group>

          <Group justify="flex-end">
            <Button variant="default" onClick={closeRemind}>Cancel</Button>
            <Button
              color="orange"
              leftSection={<IconBell size={16} />}
              loading={remindMutation.isPending}
              onClick={() => remindMutation.mutate({ ids: remindIds, channel: remindChannel })}
            >
              Send Reminder
            </Button>
          </Group>
        </Stack>
      </Modal>
    </>
  );
}
