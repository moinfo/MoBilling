import { useState } from 'react';
import {
  Title, Group, Button, TextInput, Modal, Table, Text, Badge, Pagination,
  Stack, NumberInput, Select, ActionIcon,
} from '@mantine/core';
import { DateInput } from '@mantine/dates';
import { useForm } from '@mantine/form';
import { useDebouncedValue } from '@mantine/hooks';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconPlus, IconSearch, IconEdit, IconTrash } from '@tabler/icons-react';
import {
  getClientSubscriptions, createClientSubscription, updateClientSubscription,
  deleteClientSubscription, ClientSubscription, ClientSubscriptionFormData,
} from '../api/clientSubscriptions';
import { getClients, Client } from '../api/clients';
import { getProductServices, ProductService } from '../api/productServices';
import { formatCurrency } from '../utils/formatCurrency';
import { formatDate } from '../utils/formatDate';

const cycleLabels: Record<string, string> = {
  monthly: 'Monthly',
  quarterly: 'Quarterly',
  half_yearly: 'Semi-Annual',
  yearly: 'Annually',
};

const statusColors: Record<string, string> = {
  pending: 'blue',
  active: 'green',
  cancelled: 'red',
  suspended: 'yellow',
};

export default function ClientSubscriptions() {
  const queryClient = useQueryClient();
  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 300);
  const [page, setPage] = useState(1);
  const [modalOpen, setModalOpen] = useState(false);
  const [editing, setEditing] = useState<ClientSubscription | null>(null);

  const { data } = useQuery({
    queryKey: ['client-subscriptions', debouncedSearch, page],
    queryFn: () => getClientSubscriptions({ search: debouncedSearch || undefined, page }),
  });

  const items: ClientSubscription[] = data?.data?.data || [];
  const meta = data?.data?.meta;

  // Load clients and products for the form dropdowns
  const { data: clientsData } = useQuery({
    queryKey: ['clients-all'],
    queryFn: () => getClients({ per_page: 200 }),
  });
  const clients: Client[] = clientsData?.data?.data || [];

  const { data: productsData } = useQuery({
    queryKey: ['products-recurring'],
    queryFn: () => getProductServices({ per_page: 200, active_only: true }),
  });
  const products: ProductService[] = (productsData?.data?.data || []).filter(
    (p: ProductService) => p.billing_cycle && p.billing_cycle !== 'once'
  );

  const createMutation = useMutation({
    mutationFn: (values: ClientSubscriptionFormData) => createClientSubscription(values),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['client-subscriptions'] });
      setModalOpen(false);
      notifications.show({ title: 'Success', message: 'Subscription created', color: 'green' });
    },
    onError: () => notifications.show({ title: 'Error', message: 'Failed to create subscription', color: 'red' }),
  });

  const updateMutation = useMutation({
    mutationFn: (values: ClientSubscriptionFormData) => updateClientSubscription(editing!.id, values),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['client-subscriptions'] });
      setModalOpen(false);
      setEditing(null);
      notifications.show({ title: 'Success', message: 'Subscription updated', color: 'green' });
    },
    onError: () => notifications.show({ title: 'Error', message: 'Failed to update subscription', color: 'red' }),
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => deleteClientSubscription(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['client-subscriptions'] });
      notifications.show({ title: 'Success', message: 'Subscription deleted', color: 'green' });
    },
  });

  const handleEdit = (sub: ClientSubscription) => {
    setEditing(sub);
    setModalOpen(true);
  };

  const handleDelete = (sub: ClientSubscription) => {
    modals.openConfirmModal({
      title: 'Delete Subscription',
      children: `Are you sure you want to delete this subscription${sub.label ? ` for "${sub.label}"` : ''}?`,
      labels: { confirm: 'Delete', cancel: 'Cancel' },
      confirmProps: { color: 'red' },
      onConfirm: () => deleteMutation.mutate(sub.id),
    });
  };

  const handleSubmit = (values: ClientSubscriptionFormData) => {
    if (editing) {
      updateMutation.mutate(values);
    } else {
      createMutation.mutate(values);
    }
  };

  return (
    <>
      <Group justify="space-between" mb="md" wrap="wrap">
        <Title order={2}>Client Subscriptions</Title>
        <Button leftSection={<IconPlus size={16} />} onClick={() => { setEditing(null); setModalOpen(true); }}>
          Add Subscription
        </Button>
      </Group>

      <TextInput
        placeholder="Search by label, client, or product..."
        leftSection={<IconSearch size={16} />}
        value={search}
        onChange={(e) => { setSearch(e.currentTarget.value); setPage(1); }}
        mb="md"
        maw={350}
      />

      {items.length === 0 ? (
        <Text c="dimmed" ta="center" py="xl">
          No subscriptions yet. Add a subscription to track what each client is subscribed to (e.g., domains, hosting).
        </Text>
      ) : (
        <Table.ScrollContainer minWidth={900}>
          <Table striped highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Client</Table.Th>
                <Table.Th>Product / Service</Table.Th>
                <Table.Th>Label</Table.Th>
                <Table.Th>Cycle</Table.Th>
                <Table.Th>Qty</Table.Th>
                <Table.Th>Price</Table.Th>
                <Table.Th>Start Date</Table.Th>
                <Table.Th>Status</Table.Th>
                <Table.Th w={90}>Actions</Table.Th>
              </Table.Tr>
            </Table.Thead>
          <Table.Tbody>
            {items.map((sub) => (
              <Table.Tr key={sub.id}>
                <Table.Td>
                  <Text fw={500} size="sm">{sub.client_name}</Text>
                </Table.Td>
                <Table.Td>{sub.product_service_name}</Table.Td>
                <Table.Td>
                  {sub.label ? (
                    <Text size="sm" fw={500}>{sub.label}</Text>
                  ) : (
                    <Text size="sm" c="dimmed">—</Text>
                  )}
                </Table.Td>
                <Table.Td>
                  <Badge variant="light" size="sm">
                    {cycleLabels[sub.billing_cycle || ''] || sub.billing_cycle || '—'}
                  </Badge>
                </Table.Td>
                <Table.Td>{sub.quantity}</Table.Td>
                <Table.Td>{sub.price ? formatCurrency(sub.price) : '—'}</Table.Td>
                <Table.Td>{formatDate(sub.start_date)}</Table.Td>
                <Table.Td>
                  <Badge color={statusColors[sub.status] || 'gray'} size="sm">
                    {sub.status}
                  </Badge>
                </Table.Td>
                <Table.Td>
                  <Group gap={4}>
                    <ActionIcon variant="light" onClick={() => handleEdit(sub)}>
                      <IconEdit size={16} />
                    </ActionIcon>
                    <ActionIcon variant="light" color="red" onClick={() => handleDelete(sub)}>
                      <IconTrash size={16} />
                    </ActionIcon>
                  </Group>
                </Table.Td>
              </Table.Tr>
            ))}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      )}

      {meta && meta.last_page > 1 && (
        <Group justify="center" mt="md">
          <Pagination total={meta.last_page} value={page} onChange={setPage} />
        </Group>
      )}

      <Modal
        opened={modalOpen}
        onClose={() => { setModalOpen(false); setEditing(null); }}
        title={editing ? 'Edit Subscription' : 'New Subscription'}
        size="md"
      >
        <SubscriptionForm
          clients={clients}
          products={products}
          initialValues={editing ? {
            client_id: editing.client_id,
            product_service_id: editing.product_service_id,
            label: editing.label || '',
            quantity: editing.quantity,
            start_date: editing.start_date,
            status: editing.status,
          } : undefined}
          onSubmit={handleSubmit}
          loading={createMutation.isPending || updateMutation.isPending}
          isEditing={!!editing}
        />
      </Modal>
    </>
  );
}

function SubscriptionForm({
  clients,
  products,
  initialValues,
  onSubmit,
  loading,
  isEditing,
}: {
  clients: Client[];
  products: ProductService[];
  initialValues?: ClientSubscriptionFormData;
  onSubmit: (values: ClientSubscriptionFormData) => void;
  loading?: boolean;
  isEditing: boolean;
}) {
  const form = useForm<ClientSubscriptionFormData>({
    initialValues: initialValues || {
      client_id: '',
      product_service_id: '',
      label: '',
      quantity: 1,
      start_date: new Date().toISOString().split('T')[0],
      status: 'pending',
    },
    validate: {
      client_id: (v) => (v ? null : 'Client is required'),
      product_service_id: (v) => (v ? null : 'Product is required'),
      start_date: (v) => (v ? null : 'Start date is required'),
    },
  });

  const clientOptions = clients.map((c) => ({ value: c.id, label: c.name }));
  const productOptions = products.map((p) => ({
    value: p.id,
    label: `${p.name} — ${cycleLabels[p.billing_cycle || ''] || p.billing_cycle}`,
  }));

  const handleFormSubmit = (values: ClientSubscriptionFormData) => {
    onSubmit({
      ...values,
      start_date: typeof values.start_date === 'string'
        ? values.start_date
        : (values.start_date as unknown as Date).toISOString().split('T')[0],
    });
  };

  return (
    <form onSubmit={form.onSubmit(handleFormSubmit)}>
      <Stack>
        <Select
          label="Client"
          placeholder="Select client"
          data={clientOptions}
          searchable
          required
          {...form.getInputProps('client_id')}
        />
        <Select
          label="Product / Service"
          placeholder="Select recurring product"
          data={productOptions}
          searchable
          required
          {...form.getInputProps('product_service_id')}
        />
        <TextInput
          label="Label"
          placeholder="e.g., example.co.ke, Server #2"
          description="Identifies this specific instance of the product for the client"
          {...form.getInputProps('label')}
        />
        <NumberInput
          label="Quantity"
          min={1}
          {...form.getInputProps('quantity')}
        />
        <DateInput
          label="Start Date"
          placeholder="When does billing start?"
          required
          value={form.values.start_date ? new Date(form.values.start_date) : null}
          onChange={(date) => form.setFieldValue('start_date', date ? date.toISOString().split('T')[0] : '')}
          error={form.errors.start_date}
        />
        <Select
          label="Status"
          description={!isEditing ? 'Active = no invoice created. Pending = invoice will be sent to client.' : undefined}
          data={isEditing
            ? [
                { value: 'pending', label: 'Pending Payment' },
                { value: 'active', label: 'Active' },
                { value: 'suspended', label: 'Suspended' },
                { value: 'cancelled', label: 'Cancelled' },
              ]
            : [
                { value: 'pending', label: 'Pending Payment' },
                { value: 'active', label: 'Active' },
              ]
          }
          {...form.getInputProps('status')}
        />
        <Group justify="flex-end">
          <Button type="submit" loading={loading}>
            {isEditing ? 'Update Subscription' : 'Create Subscription'}
          </Button>
        </Group>
      </Stack>
    </form>
  );
}
