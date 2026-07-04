import { useState } from 'react';
import {
  Title, Group, Button, TextInput, Modal, Table, Badge, ActionIcon,
  Textarea, NumberInput, Select, Switch, MultiSelect, Stack, Text,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconPlus, IconPencil, IconTrash } from '@tabler/icons-react';
import {
  getProductAddons, createProductAddon, updateProductAddon,
  deleteProductAddon, ProductAddon, ProductAddonFormData,
} from '../api/productAddons';
import { getProductServices } from '../api/productServices';

const cycleOptions = [
  { value: 'once', label: 'One-time' },
  { value: 'monthly', label: 'Monthly' },
  { value: 'quarterly', label: 'Quarterly' },
  { value: 'half_yearly', label: 'Semi-Annually' },
  { value: 'yearly', label: 'Annually' },
];

const cycleLabel = Object.fromEntries(cycleOptions.map((c) => [c.value, c.label]));

export default function ProductAddons() {
  const qc = useQueryClient();
  const [modalOpen, setModalOpen] = useState(false);
  const [editing, setEditing] = useState<ProductAddon | null>(null);

  const { data } = useQuery({ queryKey: ['product-addons'], queryFn: () => getProductAddons() });
  const addons = data?.data?.data ?? [];

  const { data: productsData } = useQuery({
    queryKey: ['product-addons-products'],
    queryFn: () => getProductServices({ type: 'product', per_page: 200 }),
  });
  const productOptions = (productsData?.data?.data ?? []).map((p: any) => ({ value: p.id, label: p.name }));

  const form = useForm<ProductAddonFormData>({
    initialValues: {
      name: '', description: '', price: 0, billing_cycle: 'monthly',
      tax_percent: 0, is_active: true, product_service_ids: [],
    },
    validate: {
      name: (v) => (v.trim() ? null : 'Name is required'),
      billing_cycle: (v) => (v ? null : 'Billing cycle is required'),
    },
  });

  const openCreate = () => {
    setEditing(null);
    form.setValues({ name: '', description: '', price: 0, billing_cycle: 'monthly', tax_percent: 0, is_active: true, product_service_ids: [] });
    setModalOpen(true);
  };

  const openEdit = (a: ProductAddon) => {
    setEditing(a);
    form.setValues({
      name: a.name, description: a.description ?? '', price: Number(a.price),
      billing_cycle: a.billing_cycle, tax_percent: Number(a.tax_percent),
      is_active: a.is_active, product_service_ids: a.product_service_ids ?? [],
    });
    setModalOpen(true);
  };

  const saveMutation = useMutation({
    mutationFn: (values: ProductAddonFormData) =>
      editing ? updateProductAddon(editing.id, values) : createProductAddon(values),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['product-addons'] });
      setModalOpen(false);
      setEditing(null);
      notifications.show({ title: 'Success', message: editing ? 'Add-on updated' : 'Add-on created', color: 'green' });
    },
    onError: (e: any) => notifications.show({ message: e?.response?.data?.message ?? 'Save failed', color: 'red' }),
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => deleteProductAddon(id),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['product-addons'] });
      notifications.show({ title: 'Deleted', message: 'Add-on deleted', color: 'green' });
    },
  });

  const confirmDelete = (a: ProductAddon) =>
    modals.openConfirmModal({
      title: 'Delete Add-on',
      children: `Delete "${a.name}"? Existing services already using it keep their attached copy.`,
      labels: { confirm: 'Delete', cancel: 'Cancel' },
      confirmProps: { color: 'red' },
      onConfirm: () => deleteMutation.mutate(a.id),
    });

  return (
    <>
      <Group justify="space-between" mb="md" wrap="wrap">
        <Title order={2}>Product Add-ons</Title>
        <Button leftSection={<IconPlus size={16} />} onClick={openCreate}>Add New</Button>
      </Group>

      <Text c="dimmed" size="sm" mb="md">
        Paid upsell extras (Dedicated IP, Extra Storage, Daily Backups, SSL…) that clients can add to a product at order time.
        They are billed on the order invoice and on every recurring renewal.
      </Text>

      <Table.ScrollContainer minWidth={700}>
        <Table striped highlightOnHover>
          <Table.Thead>
            <Table.Tr>
              <Table.Th>Name</Table.Th>
              <Table.Th>Price</Table.Th>
              <Table.Th>Cycle</Table.Th>
              <Table.Th>Tax %</Table.Th>
              <Table.Th>Offered on</Table.Th>
              <Table.Th>Status</Table.Th>
              <Table.Th />
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {addons.length === 0 && (
              <Table.Tr><Table.Td colSpan={7}><Text c="dimmed" ta="center" py="md">No add-ons yet.</Text></Table.Td></Table.Tr>
            )}
            {addons.map((a) => (
              <Table.Tr key={a.id}>
                <Table.Td>{a.name}</Table.Td>
                <Table.Td>{Number(a.price).toLocaleString(undefined, { minimumFractionDigits: 2 })}</Table.Td>
                <Table.Td>{cycleLabel[a.billing_cycle] ?? a.billing_cycle}</Table.Td>
                <Table.Td>{Number(a.tax_percent)}%</Table.Td>
                <Table.Td>
                  {a.products.length ? (
                    <Group gap={4}>{a.products.map((p) => <Badge key={p.id} variant="light" size="sm">{p.name}</Badge>)}</Group>
                  ) : <Text c="dimmed" size="sm">—</Text>}
                </Table.Td>
                <Table.Td>
                  <Badge color={a.is_active ? 'green' : 'gray'} variant="light">{a.is_active ? 'Active' : 'Inactive'}</Badge>
                </Table.Td>
                <Table.Td>
                  <Group gap={4} justify="flex-end" wrap="nowrap">
                    <ActionIcon variant="subtle" onClick={() => openEdit(a)}><IconPencil size={16} /></ActionIcon>
                    <ActionIcon variant="subtle" color="red" onClick={() => confirmDelete(a)}><IconTrash size={16} /></ActionIcon>
                  </Group>
                </Table.Td>
              </Table.Tr>
            ))}
          </Table.Tbody>
        </Table>
      </Table.ScrollContainer>

      <Modal opened={modalOpen} onClose={() => { setModalOpen(false); setEditing(null); }}
        title={editing ? 'Edit Add-on' : 'New Add-on'} size="lg">
        <form onSubmit={form.onSubmit((v) => saveMutation.mutate(v))}>
          <Stack gap="sm">
            <TextInput label="Name" required {...form.getInputProps('name')} />
            <Textarea label="Description" autosize minRows={2} {...form.getInputProps('description')} />
            <Group grow>
              <NumberInput label="Price" min={0} decimalScale={2} {...form.getInputProps('price')} />
              <Select label="Billing cycle" data={cycleOptions} {...form.getInputProps('billing_cycle')} />
              <NumberInput label="Tax %" min={0} max={100} decimalScale={2} {...form.getInputProps('tax_percent')} />
            </Group>
            <MultiSelect label="Offered on products" placeholder="Select products that can add this"
              data={productOptions} searchable clearable {...form.getInputProps('product_service_ids')} />
            <Switch label="Active" {...form.getInputProps('is_active', { type: 'checkbox' })} />
            <Group justify="flex-end" mt="sm">
              <Button variant="default" onClick={() => { setModalOpen(false); setEditing(null); }}>Cancel</Button>
              <Button type="submit" loading={saveMutation.isPending}>{editing ? 'Save' : 'Create'}</Button>
            </Group>
          </Stack>
        </form>
      </Modal>
    </>
  );
}
