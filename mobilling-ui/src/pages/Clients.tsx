import { useState } from 'react';
import { Title, Group, Button, TextInput, Modal, Pagination } from '@mantine/core';
import { useDebouncedValue } from '@mantine/hooks';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconPlus, IconSearch } from '@tabler/icons-react';
import { getClients, createClient, updateClient, deleteClient, Client, ClientFormData } from '../api/clients';
import ClientTable from '../components/Billing/ClientTable';
import ClientForm from '../components/Billing/ClientForm';

export default function Clients() {
  const queryClient = useQueryClient();
  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 300);
  const [page, setPage] = useState(1);
  const [modalOpen, setModalOpen] = useState(false);
  const [editing, setEditing] = useState<Client | null>(null);

  const { data, isLoading } = useQuery({
    queryKey: ['clients', debouncedSearch, page],
    queryFn: () => getClients({ search: debouncedSearch || undefined, page }),
  });

  const clients = data?.data?.data || [];
  const meta = data?.data?.meta;

  const createMutation = useMutation({
    mutationFn: (values: ClientFormData) => createClient(values),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['clients'] });
      setModalOpen(false);
      notifications.show({ title: 'Success', message: 'Client created', color: 'green' });
    },
    onError: () => notifications.show({ title: 'Error', message: 'Failed to create client', color: 'red' }),
  });

  const updateMutation = useMutation({
    mutationFn: (values: ClientFormData) => updateClient(editing!.id, values),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['clients'] });
      setModalOpen(false);
      setEditing(null);
      notifications.show({ title: 'Success', message: 'Client updated', color: 'green' });
    },
    onError: () => notifications.show({ title: 'Error', message: 'Failed to update client', color: 'red' }),
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => deleteClient(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['clients'] });
      notifications.show({ title: 'Success', message: 'Client deleted', color: 'green' });
    },
  });

  const handleEdit = (client: Client) => {
    setEditing(client);
    setModalOpen(true);
  };

  const handleDelete = (client: Client) => {
    modals.openConfirmModal({
      title: 'Delete Client',
      children: `Are you sure you want to delete "${client.name}"?`,
      labels: { confirm: 'Delete', cancel: 'Cancel' },
      confirmProps: { color: 'red' },
      onConfirm: () => deleteMutation.mutate(client.id),
    });
  };

  const handleSubmit = (values: ClientFormData) => {
    if (editing) {
      updateMutation.mutate(values);
    } else {
      createMutation.mutate(values);
    }
  };

  return (
    <>
      <Group justify="space-between" mb="md" wrap="wrap">
        <Title order={2}>Clients</Title>
        <Button leftSection={<IconPlus size={16} />} onClick={() => { setEditing(null); setModalOpen(true); }}>
          Add Client
        </Button>
      </Group>

      <TextInput
        placeholder="Search clients..."
        leftSection={<IconSearch size={16} />}
        value={search}
        onChange={(e) => { setSearch(e.currentTarget.value); setPage(1); }}
        mb="md"
        maw={300}
      />

      <ClientTable clients={clients} onEdit={handleEdit} onDelete={handleDelete} />

      {meta && meta.last_page > 1 && (
        <Group justify="center" mt="md">
          <Pagination total={meta.last_page} value={page} onChange={setPage} />
        </Group>
      )}

      <Modal
        opened={modalOpen}
        onClose={() => { setModalOpen(false); setEditing(null); }}
        title={editing ? 'Edit Client' : 'New Client'}
        size="md"
      >
        <ClientForm
          initialValues={editing ? {
            name: editing.name,
            email: editing.email || '',
            phone: editing.phone || '',
            address: editing.address || '',
            tax_id: editing.tax_id || '',
          } : undefined}
          onSubmit={handleSubmit}
          loading={createMutation.isPending || updateMutation.isPending}
        />
      </Modal>
    </>
  );
}
