import { useState } from 'react';
import { Title, Group, Button, TextInput, Modal, Pagination } from '@mantine/core';
import { useDebouncedValue } from '@mantine/hooks';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconPlus, IconSearch, IconDownload, IconAddressBook } from '@tabler/icons-react';
import { getClients, createClient, updateClient, deleteClient, Client, ClientFormData } from '../api/clients';
import ClientTable from '../components/Billing/ClientTable';
import ClientForm from '../components/Billing/ClientForm';
import { usePermissions } from '../hooks/usePermissions';

export default function Clients() {
  const queryClient = useQueryClient();
  const { can } = usePermissions();
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

  const handleExportCsv = async () => {
    try {
      const res = await getClients({ per_page: 10000 });
      const allClients: Client[] = res.data?.data || [];
      const csvRows = [
        ['Name', 'Email', 'Phone'].join(','),
        ...allClients.map((c) =>
          [`"${(c.name || '').replace(/"/g, '""')}"`, `"${c.email || ''}"`, `"${c.phone || ''}"`].join(',')
        ),
      ];
      const blob = new Blob([csvRows.join('\n')], { type: 'text/csv' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `clients-${new Date().toISOString().slice(0, 10)}.csv`;
      a.click();
      URL.revokeObjectURL(url);
    } catch {
      notifications.show({ title: 'Error', message: 'Failed to export clients', color: 'red' });
    }
  };

  const handleExportVcf = async () => {
    try {
      const res = await getClients({ per_page: 10000 });
      const allClients: Client[] = res.data?.data || [];
      const vcards = allClients.map((c) => {
        const nameParts = (c.name || '').trim().split(/\s+/);
        const lastName = nameParts.length > 1 ? nameParts.pop() : '';
        const firstName = nameParts.join(' ');
        const lines = [
          'BEGIN:VCARD',
          'VERSION:3.0',
          `FN:${c.name || ''}`,
          `N:${lastName};${firstName};;;`,
        ];
        if (c.email) lines.push(`EMAIL:${c.email}`);
        if (c.phone) lines.push(`TEL;TYPE=CELL:${c.phone}`);
        if (c.address) lines.push(`ADR;TYPE=WORK:;;${c.address};;;;`);
        lines.push('END:VCARD');
        return lines.join('\r\n');
      });
      const blob = new Blob([vcards.join('\r\n')], { type: 'text/vcard' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `clients-${new Date().toISOString().slice(0, 10)}.vcf`;
      a.click();
      URL.revokeObjectURL(url);
    } catch {
      notifications.show({ title: 'Error', message: 'Failed to export contacts', color: 'red' });
    }
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
        <Group gap="xs">
          <Button variant="light" leftSection={<IconDownload size={16} />} onClick={handleExportCsv}>
            Export CSV
          </Button>
          <Button variant="light" leftSection={<IconAddressBook size={16} />} onClick={handleExportVcf}>
            Export VCF
          </Button>
          {can('clients.create') && (
            <Button leftSection={<IconPlus size={16} />} onClick={() => { setEditing(null); setModalOpen(true); }}>
              Add Client
            </Button>
          )}
        </Group>
      </Group>

      <TextInput
        placeholder="Search clients..."
        leftSection={<IconSearch size={16} />}
        value={search}
        onChange={(e) => { setSearch(e.currentTarget.value); setPage(1); }}
        mb="md"
        maw={300}
      />

      <ClientTable clients={clients} onEdit={handleEdit} onDelete={handleDelete} startIndex={meta ? (meta.current_page - 1) * meta.per_page + 1 : 1} loading={isLoading} />

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
