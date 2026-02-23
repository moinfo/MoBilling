import { useState } from 'react';
import { Title, Group, Button, TextInput, Modal, Tabs, Pagination } from '@mantine/core';
import { useDebouncedValue } from '@mantine/hooks';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconPlus, IconSearch } from '@tabler/icons-react';
import {
  getProductServices, createProductService, updateProductService,
  deleteProductService, ProductService, ProductServiceFormData,
} from '../api/productServices';
import ProductServiceTable from '../components/Billing/ProductServiceTable';
import ProductServiceForm from '../components/Billing/ProductServiceForm';

export default function ProductServices() {
  const queryClient = useQueryClient();
  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 300);
  const [typeFilter, setTypeFilter] = useState<string | null>('all');
  const [page, setPage] = useState(1);
  const [modalOpen, setModalOpen] = useState(false);
  const [editing, setEditing] = useState<ProductService | null>(null);

  const typeParam = typeFilter === 'all' ? undefined : typeFilter ?? undefined;

  const { data } = useQuery({
    queryKey: ['product-services', debouncedSearch, typeParam, page],
    queryFn: () => getProductServices({ search: debouncedSearch || undefined, type: typeParam, page }),
  });

  const items = data?.data?.data || [];
  const meta = data?.data?.meta;

  const createMutation = useMutation({
    mutationFn: (values: ProductServiceFormData) => createProductService(values),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['product-services'] });
      setModalOpen(false);
      notifications.show({ title: 'Success', message: 'Item created', color: 'green' });
    },
    onError: () => notifications.show({ title: 'Error', message: 'Failed to create', color: 'red' }),
  });

  const updateMutation = useMutation({
    mutationFn: (values: ProductServiceFormData) => updateProductService(editing!.id, values),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['product-services'] });
      setModalOpen(false);
      setEditing(null);
      notifications.show({ title: 'Success', message: 'Item updated', color: 'green' });
    },
    onError: () => notifications.show({ title: 'Error', message: 'Failed to update', color: 'red' }),
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => deleteProductService(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['product-services'] });
      notifications.show({ title: 'Success', message: 'Item deleted', color: 'green' });
    },
  });

  const handleEdit = (item: ProductService) => {
    setEditing(item);
    setModalOpen(true);
  };

  const handleDelete = (item: ProductService) => {
    modals.openConfirmModal({
      title: 'Delete Item',
      children: `Are you sure you want to delete "${item.name}"?`,
      labels: { confirm: 'Delete', cancel: 'Cancel' },
      confirmProps: { color: 'red' },
      onConfirm: () => deleteMutation.mutate(item.id),
    });
  };

  const handleSubmit = (values: ProductServiceFormData) => {
    if (editing) {
      updateMutation.mutate(values);
    } else {
      createMutation.mutate(values);
    }
  };

  return (
    <>
      <Group justify="space-between" mb="md">
        <Title order={2}>Products & Services</Title>
        <Button leftSection={<IconPlus size={16} />} onClick={() => { setEditing(null); setModalOpen(true); }}>
          Add New
        </Button>
      </Group>

      <Group mb="md">
        <TextInput
          placeholder="Search..."
          leftSection={<IconSearch size={16} />}
          value={search}
          onChange={(e) => { setSearch(e.currentTarget.value); setPage(1); }}
          w={300}
        />
        <Tabs value={typeFilter} onChange={(v) => { setTypeFilter(v); setPage(1); }}>
          <Tabs.List>
            <Tabs.Tab value="all">All</Tabs.Tab>
            <Tabs.Tab value="product">Products</Tabs.Tab>
            <Tabs.Tab value="service">Services</Tabs.Tab>
          </Tabs.List>
        </Tabs>
      </Group>

      <ProductServiceTable items={items} onEdit={handleEdit} onDelete={handleDelete} />

      {meta && meta.last_page > 1 && (
        <Group justify="center" mt="md">
          <Pagination total={meta.last_page} value={page} onChange={setPage} />
        </Group>
      )}

      <Modal
        opened={modalOpen}
        onClose={() => { setModalOpen(false); setEditing(null); }}
        title={editing ? 'Edit Item' : 'New Product / Service'}
        size="lg"
      >
        <ProductServiceForm
          initialValues={editing ? {
            type: editing.type,
            name: editing.name,
            code: editing.code || '',
            description: editing.description || '',
            price: parseFloat(editing.price),
            tax_percent: parseFloat(editing.tax_percent),
            unit: editing.unit,
            category: editing.category || '',
            is_active: editing.is_active,
          } : undefined}
          onSubmit={handleSubmit}
          loading={createMutation.isPending || updateMutation.isPending}
        />
      </Modal>
    </>
  );
}
