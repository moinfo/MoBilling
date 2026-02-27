import { useState } from 'react';
import {
  Title, Group, Button, TextInput, Pagination, Drawer,
  SegmentedControl, Modal, Stack, Text, Radio,
} from '@mantine/core';
import { useDisclosure, useDebouncedValue } from '@mantine/hooks';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconPlus, IconSearch, IconBell, IconMail, IconMessage, IconSend } from '@tabler/icons-react';
import { getDocuments, getDocument, createDocument, deleteDocument, remindUnpaid, Document, DocumentFormData } from '../../api/documents';
import { getClients, Client } from '../../api/clients';
import { getProductServices, ProductService } from '../../api/productServices';
import DocumentTable from './DocumentTable';
import DocumentForm from './DocumentForm';
import DocumentView from './DocumentView';

interface Props {
  type: 'quotation' | 'proforma' | 'invoice';
  title: string;
}

export default function DocumentListPage({ type, title }: Props) {
  const queryClient = useQueryClient();
  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 300);
  const [page, setPage] = useState(1);
  const [statusFilter, setStatusFilter] = useState('all');
  const [formOpen, setFormOpen] = useState(false);
  const [viewDoc, setViewDoc] = useState<Document | null>(null);

  // Remind modal state
  const [remindOpened, { open: openRemind, close: closeRemind }] = useDisclosure(false);
  const [remindIds, setRemindIds] = useState<string[]>([]);
  const [remindChannel, setRemindChannel] = useState<'email' | 'sms' | 'both'>('email');
  const [remindLabel, setRemindLabel] = useState('');

  const isInvoice = type === 'invoice';

  // Map filter to API status param
  const statusParam = statusFilter === 'all' ? undefined
    : statusFilter === 'unpaid' ? 'sent' // sent = unpaid invoices
    : statusFilter; // 'paid', 'overdue', 'draft'

  const { data: docsData } = useQuery({
    queryKey: ['documents', type, debouncedSearch, page, statusParam],
    queryFn: () => getDocuments({ type, search: debouncedSearch || undefined, page, status: statusParam }),
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

  const deleteMutation = useMutation({
    mutationFn: (id: string) => deleteDocument(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['documents'] });
      notifications.show({ title: 'Success', message: 'Document deleted', color: 'green' });
    },
  });

  const remindMutation = useMutation({
    mutationFn: ({ ids, channel }: { ids: string[]; channel: 'email' | 'sms' | 'both' }) =>
      remindUnpaid(ids, channel),
    onSuccess: (res) => {
      closeRemind();
      notifications.show({ title: 'Reminders Sent', message: res.data.message, color: 'green' });
    },
    onError: () => notifications.show({ title: 'Error', message: 'Failed to send reminders', color: 'red' }),
  });

  const handleView = async (doc: Document) => {
    const res = await getDocument(doc.id);
    setViewDoc(res.data.data);
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

  const handleRefresh = async () => {
    if (viewDoc) {
      const res = await getDocument(viewDoc.id);
      setViewDoc(res.data.data);
    }
    queryClient.invalidateQueries({ queryKey: ['documents'] });
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
        <Button leftSection={<IconPlus size={16} />} onClick={() => setFormOpen(true)}>
          New {title.slice(0, -1)}
        </Button>
      </Group>

      <Group mb="md" justify="space-between" wrap="wrap">
        <Group gap="sm">
          <TextInput
            placeholder="Search by number or client..."
            leftSection={<IconSearch size={16} />}
            value={search}
            onChange={(e) => { setSearch(e.currentTarget.value); setPage(1); }}
            w={300}
          />
          {isInvoice && (
            <SegmentedControl
              size="sm"
              value={statusFilter}
              onChange={(v) => { setStatusFilter(v); setPage(1); }}
              data={[
                { label: 'All', value: 'all' },
                { label: 'Unpaid', value: 'unpaid' },
                { label: 'Paid', value: 'paid' },
                { label: 'Overdue', value: 'overdue' },
                { label: 'Draft', value: 'draft' },
              ]}
            />
          )}
        </Group>
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

      <DocumentTable
        documents={documents}
        onView={handleView}
        onEdit={() => {}}
        onDelete={handleDelete}
        onRemind={isInvoice ? openRemindSingle : undefined}
      />

      {meta && meta.last_page > 1 && (
        <Group justify="center" mt="md">
          <Pagination total={meta.last_page} value={page} onChange={setPage} />
        </Group>
      )}

      {/* Create form drawer */}
      <Drawer
        opened={formOpen}
        onClose={() => setFormOpen(false)}
        title={`New ${title.slice(0, -1)}`}
        size={900}
        position="right"
      >
        <DocumentForm
          clients={clients}
          productServices={productServices}
          type={type}
          onSubmit={(values) => createMutation.mutate(values)}
          loading={createMutation.isPending}
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

      {/* Remind Modal */}
      <Modal opened={remindOpened} onClose={closeRemind} title="Send Payment Reminder" size="sm">
        <Stack gap="md">
          <Text size="sm">
            Send reminder for <Text span fw={600}>{remindLabel}</Text>
          </Text>

          <Radio.Group
            label="Send via"
            value={remindChannel}
            onChange={(v) => setRemindChannel(v as 'email' | 'sms' | 'both')}
          >
            <Stack gap="xs" mt="xs">
              <Radio value="email" label="Email" icon={({ ...rest }) => <IconMail size={14} {...rest} />} />
              <Radio value="sms" label="SMS" icon={({ ...rest }) => <IconMessage size={14} {...rest} />} />
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
