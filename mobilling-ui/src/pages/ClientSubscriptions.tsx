import { useState, useEffect } from 'react';
import {
  Title, Group, Button, TextInput, Modal, Table, Text, Badge, Pagination,
  Stack, NumberInput, Select, ActionIcon, Tooltip, Loader, Center,
} from '@mantine/core';
import { DateInput } from '@mantine/dates';
import { useForm } from '@mantine/form';
import { useDebouncedValue } from '@mantine/hooks';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconPlus, IconSearch, IconEdit, IconTrash, IconArrowUp, IconArrowDown, IconArrowsSort, IconFileInvoice, IconCalendarEvent } from '@tabler/icons-react';
import {
  getClientSubscriptions, createClientSubscription, createBulkSubscription, updateClientSubscription,
  deleteClientSubscription, generateInvoiceFromSubscription, updateExpireDate, ClientSubscription, ClientSubscriptionFormData,
  BulkSubscriptionFormData, BulkSubscriptionItem,
} from '../api/clientSubscriptions';
import { getClients, Client } from '../api/clients';
import { getProductServices, ProductService } from '../api/productServices';
import { formatCurrency } from '../utils/formatCurrency';
import { formatDate } from '../utils/formatDate';
import { usePermissions } from '../hooks/usePermissions';

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
  const { can } = usePermissions();
  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 300);
  const [page, setPage] = useState(1);
  const [sortBy, setSortBy] = useState<string | undefined>(undefined);
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('desc');
  const [modalOpen, setModalOpen] = useState(false);
  const [editing, setEditing] = useState<ClientSubscription | null>(null);
  const [renewSub, setRenewSub] = useState<ClientSubscription | null>(null);

  const toggleSort = (column: string) => {
    if (sortBy === column) {
      setSortDir((prev) => (prev === 'asc' ? 'desc' : 'asc'));
    } else {
      setSortBy(column);
      setSortDir('asc');
    }
    setPage(1);
  };

  const { data, isLoading } = useQuery({
    queryKey: ['client-subscriptions', debouncedSearch, page, sortBy, sortDir],
    queryFn: () => getClientSubscriptions({ search: debouncedSearch || undefined, page, sort_by: sortBy, sort_dir: sortDir }),
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
    mutationFn: (values: BulkSubscriptionFormData) => createBulkSubscription(values),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['client-subscriptions'] });
      setModalOpen(false);
      notifications.show({ title: 'Success', message: 'Subscriptions created', color: 'green' });
    },
    onError: () => notifications.show({ title: 'Error', message: 'Failed to create subscriptions', color: 'red' }),
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

  const invoiceMutation = useMutation({
    mutationFn: (id: string) => generateInvoiceFromSubscription(id),
    onSuccess: (res) => {
      queryClient.invalidateQueries({ queryKey: ['documents'] });
      notifications.show({
        title: 'Invoice Created',
        message: res.data.message,
        color: 'green',
      });
    },
    onError: (err: any) => notifications.show({
      title: 'Error',
      message: err.response?.data?.message || 'Failed to generate invoice',
      color: 'red',
    }),
  });

  const renewMutation = useMutation({
    mutationFn: ({ id, expire_date }: { id: string; expire_date: string }) => updateExpireDate(id, expire_date),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['client-subscriptions'] });
      setRenewSub(null);
      notifications.show({ title: 'Success', message: 'Expire date updated', color: 'green' });
    },
    onError: () => notifications.show({ title: 'Error', message: 'Failed to update expire date', color: 'red' }),
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

  const handleCreateSubmit = (values: BulkSubscriptionFormData) => {
    createMutation.mutate(values);
  };

  const handleEditSubmit = (values: ClientSubscriptionFormData) => {
    updateMutation.mutate(values);
  };

  return (
    <>
      <Group justify="space-between" mb="md" wrap="wrap">
        <Title order={2}>Client Subscriptions</Title>
        {can('client_subscriptions.create') && (
          <Button leftSection={<IconPlus size={16} />} onClick={() => { setEditing(null); setModalOpen(true); }}>
            Add Subscription
          </Button>
        )}
      </Group>

      <TextInput
        placeholder="Search by label, client, or product..."
        leftSection={<IconSearch size={16} />}
        value={search}
        onChange={(e) => { setSearch(e.currentTarget.value); setPage(1); }}
        mb="md"
        maw={350}
      />

      {isLoading ? (
        <Center py="xl"><Loader /></Center>
      ) : items.length === 0 ? (
        <Text c="dimmed" ta="center" py="xl">
          No subscriptions yet. Add a subscription to track what each client is subscribed to (e.g., domains, hosting).
        </Text>
      ) : (
        <Table.ScrollContainer minWidth={900}>
          <Table striped highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th w={50}>#</Table.Th>
                <Table.Th>Client</Table.Th>
                <Table.Th>Product / Service</Table.Th>
                <Table.Th>Label</Table.Th>
                <Table.Th>Cycle</Table.Th>
                <Table.Th>Qty</Table.Th>
                <Table.Th>Price</Table.Th>
                <SortableHeader column="start_date" label="Start Date" sortBy={sortBy} sortDir={sortDir} onSort={toggleSort} />
                <Table.Th>Expire Date</Table.Th>
                <SortableHeader column="status" label="Status" sortBy={sortBy} sortDir={sortDir} onSort={toggleSort} />
                <Table.Th w={120}>Actions</Table.Th>
              </Table.Tr>
            </Table.Thead>
          <Table.Tbody>
            {items.map((sub, index) => (
              <Table.Tr key={sub.id}>
                <Table.Td><Text size="sm" c="dimmed">{((meta?.current_page ?? 1) - 1) * (meta?.per_page ?? 20) + index + 1}</Text></Table.Td>
                <Table.Td>
                  <Text fw={500} size="sm" tt="uppercase">{sub.client_name}</Text>
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
                  {sub.expire_date ? (
                    <Text size="sm" c={new Date(sub.expire_date) < new Date() ? 'red' : undefined}>
                      {formatDate(sub.expire_date)}
                    </Text>
                  ) : (
                    <Text size="sm" c="dimmed">—</Text>
                  )}
                </Table.Td>
                <Table.Td>
                  <Badge color={statusColors[sub.status] || 'gray'} size="sm">
                    {sub.status}
                  </Badge>
                </Table.Td>
                <Table.Td>
                  <Group gap={4} wrap="nowrap">
                    {can('documents.create') && (
                      <Tooltip label="Create Invoice">
                        <ActionIcon
                          variant="light"
                          color="green"
                          onClick={() => invoiceMutation.mutate(sub.id)}
                          loading={invoiceMutation.isPending}
                        >
                          <IconFileInvoice size={16} />
                        </ActionIcon>
                      </Tooltip>
                    )}
                    {can('client_subscriptions.renew') && (
                      <Tooltip label="Update Expire Date">
                        <ActionIcon variant="light" color="cyan" onClick={() => setRenewSub(sub)}>
                          <IconCalendarEvent size={16} />
                        </ActionIcon>
                      </Tooltip>
                    )}
                    {can('client_subscriptions.update') && (
                      <ActionIcon variant="light" onClick={() => handleEdit(sub)}>
                        <IconEdit size={16} />
                      </ActionIcon>
                    )}
                    {can('client_subscriptions.delete') && (
                      <ActionIcon variant="light" color="red" onClick={() => handleDelete(sub)}>
                        <IconTrash size={16} />
                      </ActionIcon>
                    )}
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
        title={editing ? 'Edit Subscription' : 'New Subscriptions'}
        size={editing ? 'md' : 'lg'}
      >
        {editing ? (
          <SubscriptionEditForm
            clients={clients}
            products={products}
            initialValues={{
              client_id: editing.client_id,
              product_service_id: editing.product_service_id,
              label: editing.label || '',
              quantity: editing.quantity,
              start_date: editing.start_date,
              status: editing.status,
            }}
            onSubmit={handleEditSubmit}
            loading={updateMutation.isPending}
          />
        ) : (
          <BulkSubscriptionForm
            clients={clients}
            products={products}
            onSubmit={handleCreateSubmit}
            loading={createMutation.isPending}
          />
        )}
      </Modal>

      <RenewModal
        subscription={renewSub}
        onClose={() => setRenewSub(null)}
        onSubmit={(expireDate) => {
          if (renewSub) renewMutation.mutate({ id: renewSub.id, expire_date: expireDate });
        }}
        loading={renewMutation.isPending}
      />
    </>
  );
}

function RenewModal({ subscription, onClose, onSubmit, loading }: {
  subscription: ClientSubscription | null;
  onClose: () => void;
  onSubmit: (expireDate: string) => void;
  loading?: boolean;
}) {
  const [date, setDate] = useState<Date | null>(null);

  const currentExpire = subscription?.expire_date ? new Date(subscription.expire_date) : null;

  // Auto-fill next expire date based on current expire + billing cycle
  const suggestedDate = (() => {
    const base = currentExpire || (subscription?.start_date ? new Date(subscription.start_date) : null);
    if (!base || !subscription?.billing_cycle) return null;
    const d = new Date(base);
    switch (subscription.billing_cycle) {
      case 'monthly': d.setMonth(d.getMonth() + 1); break;
      case 'quarterly': d.setMonth(d.getMonth() + 3); break;
      case 'half_yearly': d.setMonth(d.getMonth() + 6); break;
      case 'yearly': d.setFullYear(d.getFullYear() + 1); break;
    }
    return d;
  })();

  // Set suggested date when subscription changes
  const subId = subscription?.id;
  useEffect(() => { setDate(suggestedDate); }, [subId]); // eslint-disable-line react-hooks/exhaustive-deps

  return (
    <Modal opened={!!subscription} onClose={onClose} title="Update Expire Date" size="sm">
      <Stack>
        <Text size="sm">
          <Text span fw={600}>{subscription?.product_service_name}</Text>
          {subscription?.label && <Text span> — {subscription.label}</Text>}
        </Text>
        {currentExpire && (
          <Text size="sm" c="dimmed">
            Current expire date: <Text span fw={500} c={currentExpire < new Date() ? 'red' : undefined}>{currentExpire.toLocaleDateString()}</Text>
          </Text>
        )}
        <DateInput
          key={subId}
          label="New Expire Date"
          placeholder="Select new expire date"
          required
          value={date}
          onChange={setDate}
        />
        <Group justify="flex-end">
          <Button variant="default" onClick={onClose}>Cancel</Button>
          <Button
            color="cyan"
            loading={loading}
            disabled={!date}
            onClick={() => {
              if (date) onSubmit(date.toISOString().split('T')[0]);
            }}
          >
            Update Expire Date
          </Button>
        </Group>
      </Stack>
    </Modal>
  );
}

function SortableHeader({ column, label, sortBy, sortDir, onSort }: {
  column: string;
  label: string;
  sortBy: string | undefined;
  sortDir: 'asc' | 'desc';
  onSort: (column: string) => void;
}) {
  const icon = sortBy !== column
    ? <IconArrowsSort size={14} style={{ opacity: 0.4 }} />
    : sortDir === 'asc'
      ? <IconArrowUp size={14} />
      : <IconArrowDown size={14} />;

  return (
    <Table.Th style={{ cursor: 'pointer', userSelect: 'none' }} onClick={() => onSort(column)}>
      <Group gap={4} wrap="nowrap">
        {label}
        {icon}
      </Group>
    </Table.Th>
  );
}

function SubscriptionEditForm({
  clients,
  products,
  initialValues,
  onSubmit,
  loading,
}: {
  clients: Client[];
  products: ProductService[];
  initialValues: ClientSubscriptionFormData;
  onSubmit: (values: ClientSubscriptionFormData) => void;
  loading?: boolean;
}) {
  const form = useForm<ClientSubscriptionFormData>({
    initialValues,
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
        <Select label="Client" placeholder="Select client" data={clientOptions} searchable required {...form.getInputProps('client_id')} />
        <Select label="Product / Service" placeholder="Select recurring product" data={productOptions} searchable required {...form.getInputProps('product_service_id')} />
        <TextInput label="Label" placeholder="e.g., example.co.ke, Server #2" {...form.getInputProps('label')} />
        <NumberInput label="Quantity" min={1} {...form.getInputProps('quantity')} />
        <DateInput
          label="Start Date" placeholder="When does billing start?" required
          value={form.values.start_date ? new Date(form.values.start_date) : null}
          onChange={(date: any) => form.setFieldValue('start_date', date ? new Date(date).toISOString().split('T')[0] : '')}
          error={form.errors.start_date}
        />
        <Select
          label="Status"
          data={[
            { value: 'pending', label: 'Pending Payment' },
            { value: 'active', label: 'Active' },
            { value: 'suspended', label: 'Suspended' },
            { value: 'cancelled', label: 'Cancelled' },
          ]}
          {...form.getInputProps('status')}
        />
        <Group justify="flex-end">
          <Button type="submit" loading={loading}>Update Subscription</Button>
        </Group>
      </Stack>
    </form>
  );
}

interface BulkFormValues {
  client_id: string;
  start_date: string;
  status: string;
  items: BulkSubscriptionItem[];
}

function BulkSubscriptionForm({
  clients,
  products,
  onSubmit,
  loading,
}: {
  clients: Client[];
  products: ProductService[];
  onSubmit: (values: BulkSubscriptionFormData) => void;
  loading?: boolean;
}) {
  const form = useForm<BulkFormValues>({
    initialValues: {
      client_id: '',
      start_date: new Date().toISOString().split('T')[0],
      status: 'pending',
      items: [{ product_service_id: '', label: '', quantity: 1 }],
    },
    validate: {
      client_id: (v) => (v ? null : 'Client is required'),
      start_date: (v) => (v ? null : 'Start date is required'),
      items: {
        product_service_id: (v) => (v ? null : 'Product is required'),
      },
    },
  });

  const clientOptions = clients.map((c) => ({ value: c.id, label: c.name }));
  const productOptions = products.map((p) => ({
    value: p.id,
    label: `${p.name} — ${cycleLabels[p.billing_cycle || ''] || p.billing_cycle}`,
  }));

  const addItem = () => {
    form.insertListItem('items', { product_service_id: '', label: '', quantity: 1 });
  };

  const removeItem = (index: number) => {
    form.removeListItem('items', index);
  };

  const handleFormSubmit = (values: BulkFormValues) => {
    onSubmit({
      ...values,
      start_date: typeof values.start_date === 'string'
        ? values.start_date
        : (values.start_date as unknown as Date).toISOString().split('T')[0],
    });
  };

  // Calculate total price preview
  const totalPreview = form.values.items.reduce((sum, item) => {
    const product = products.find((p) => p.id === item.product_service_id);
    if (!product) return sum;
    return sum + (item.quantity || 1) * parseFloat(product.price || '0');
  }, 0);

  return (
    <form onSubmit={form.onSubmit(handleFormSubmit)}>
      <Stack>
        <Select label="Client" placeholder="Select client" data={clientOptions} searchable required {...form.getInputProps('client_id')} />

        <DateInput
          label="Start Date" placeholder="When does billing start?" required
          value={form.values.start_date ? new Date(form.values.start_date) : null}
          onChange={(date: any) => form.setFieldValue('start_date', date ? new Date(date).toISOString().split('T')[0] : '')}
          error={form.errors.start_date}
        />

        <Select
          label="Status"
          description="Active = no invoice created. Pending = invoice will be sent to client."
          data={[
            { value: 'pending', label: 'Pending Payment' },
            { value: 'active', label: 'Active' },
          ]}
          {...form.getInputProps('status')}
        />

        <Text fw={600} size="sm" mt="xs">Products / Services</Text>

        {form.values.items.map((_, index) => (
          <Group key={index} align="flex-start" gap="xs" wrap="nowrap">
            <Select
              placeholder="Select product"
              data={productOptions}
              searchable
              required
              style={{ flex: 3 }}
              {...form.getInputProps(`items.${index}.product_service_id`)}
            />
            <TextInput
              placeholder="Label (optional)"
              style={{ flex: 2 }}
              {...form.getInputProps(`items.${index}.label`)}
            />
            <NumberInput
              placeholder="Qty"
              min={1}
              style={{ width: 70 }}
              {...form.getInputProps(`items.${index}.quantity`)}
            />
            {form.values.items.length > 1 && (
              <ActionIcon variant="light" color="red" mt={4} onClick={() => removeItem(index)}>
                <IconTrash size={16} />
              </ActionIcon>
            )}
          </Group>
        ))}

        <Button variant="light" leftSection={<IconPlus size={14} />} onClick={addItem} size="xs">
          Add Product
        </Button>

        {totalPreview > 0 && (
          <Text size="sm" c="dimmed" ta="right">
            Subtotal: {formatCurrency(totalPreview)}
          </Text>
        )}

        <Group justify="flex-end">
          <Button type="submit" loading={loading}>
            Create {form.values.items.length > 1 ? `${form.values.items.length} Subscriptions` : 'Subscription'}
          </Button>
        </Group>
      </Stack>
    </form>
  );
}
