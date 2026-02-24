import { useState } from 'react';
import { Title, Group, Button, TextInput, Pagination, Drawer } from '@mantine/core';
import { useDebouncedValue } from '@mantine/hooks';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconPlus, IconSearch } from '@tabler/icons-react';
import { getDocuments, getDocument, createDocument, deleteDocument, Document, DocumentFormData } from '../../api/documents';
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
  const [formOpen, setFormOpen] = useState(false);
  const [viewDoc, setViewDoc] = useState<Document | null>(null);

  const { data: docsData } = useQuery({
    queryKey: ['documents', type, debouncedSearch, page],
    queryFn: () => getDocuments({ type, search: debouncedSearch || undefined, page }),
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

  return (
    <>
      <Group justify="space-between" mb="md">
        <Title order={2}>{title}</Title>
        <Button leftSection={<IconPlus size={16} />} onClick={() => setFormOpen(true)}>
          New {title.slice(0, -1)}
        </Button>
      </Group>

      <TextInput
        placeholder="Search by number or client..."
        leftSection={<IconSearch size={16} />}
        value={search}
        onChange={(e) => { setSearch(e.currentTarget.value); setPage(1); }}
        mb="md"
        w={300}
      />

      <DocumentTable
        documents={documents}
        onView={handleView}
        onEdit={() => {}}
        onDelete={handleDelete}
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
    </>
  );
}
