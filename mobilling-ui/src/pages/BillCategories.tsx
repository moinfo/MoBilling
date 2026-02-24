import { useState } from 'react';
import { Title, Group, Button, Modal, LoadingOverlay } from '@mantine/core';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconPlus } from '@tabler/icons-react';
import {
  getBillCategories,
  createBillCategory,
  updateBillCategory,
  deleteBillCategory,
  BillCategory,
  BillCategoryFormData,
} from '../api/billCategories';
import BillCategoryTree from '../components/Statutory/BillCategoryTree';
import BillCategoryForm from '../components/Statutory/BillCategoryForm';

export default function BillCategories() {
  const queryClient = useQueryClient();
  const [formOpen, setFormOpen] = useState(false);
  const [editing, setEditing] = useState<BillCategory | null>(null);
  const [parentIdForNew, setParentIdForNew] = useState<string | null>(null);

  const { data, isLoading } = useQuery({
    queryKey: ['bill-categories'],
    queryFn: getBillCategories,
  });

  const categories: BillCategory[] = data?.data?.data || [];

  const createMutation = useMutation({
    mutationFn: (values: BillCategoryFormData) => createBillCategory(values),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['bill-categories'] });
      closeForm();
      notifications.show({ title: 'Success', message: 'Category created', color: 'green' });
    },
    onError: () => notifications.show({ title: 'Error', message: 'Failed to create category', color: 'red' }),
  });

  const updateMutation = useMutation({
    mutationFn: (values: BillCategoryFormData) => updateBillCategory(editing!.id, values),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['bill-categories'] });
      closeForm();
      notifications.show({ title: 'Success', message: 'Category updated', color: 'green' });
    },
    onError: () => notifications.show({ title: 'Error', message: 'Failed to update category', color: 'red' }),
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => deleteBillCategory(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['bill-categories'] });
      notifications.show({ title: 'Success', message: 'Category deleted', color: 'green' });
    },
    onError: (err: any) => {
      const msg = err.response?.data?.message || 'Failed to delete category';
      notifications.show({ title: 'Error', message: msg, color: 'red' });
    },
  });

  const closeForm = () => {
    setFormOpen(false);
    setEditing(null);
    setParentIdForNew(null);
  };

  const openNewCategory = () => {
    setEditing(null);
    setParentIdForNew(null);
    setFormOpen(true);
  };

  const openNewSubcategory = (parentId: string) => {
    setEditing(null);
    setParentIdForNew(parentId);
    setFormOpen(true);
  };

  const openEdit = (category: BillCategory) => {
    setEditing(category);
    setParentIdForNew(null);
    setFormOpen(true);
  };

  const handleDelete = (category: BillCategory) => {
    modals.openConfirmModal({
      title: 'Delete Category',
      children: `Delete "${category.name}"${category.children?.length ? ` and its ${category.children.length} subcategories` : ''}?`,
      labels: { confirm: 'Delete', cancel: 'Cancel' },
      confirmProps: { color: 'red' },
      onConfirm: () => deleteMutation.mutate(category.id),
    });
  };

  const handleSubmit = (values: BillCategoryFormData) => {
    if (editing) {
      updateMutation.mutate(values);
    } else {
      createMutation.mutate({ ...values, parent_id: parentIdForNew });
    }
  };

  const isSubcategory = editing ? !!editing.parent_id : !!parentIdForNew;
  const modalTitle = editing
    ? `Edit ${isSubcategory ? 'Subcategory' : 'Category'}`
    : `New ${isSubcategory ? 'Subcategory' : 'Category'}`;

  return (
    <>
      <Group justify="space-between" mb="md">
        <Title order={2}>Bill Categories</Title>
        <Button leftSection={<IconPlus size={16} />} onClick={openNewCategory}>
          Add Category
        </Button>
      </Group>

      <div style={{ position: 'relative' }}>
        <LoadingOverlay visible={isLoading} />
        <BillCategoryTree
          categories={categories}
          onAddSubcategory={openNewSubcategory}
          onEdit={openEdit}
          onDelete={handleDelete}
        />
      </div>

      <Modal opened={formOpen} onClose={closeForm} title={modalTitle}>
        <BillCategoryForm
          initialValues={editing ? {
            name: editing.name,
            billing_cycle: editing.billing_cycle,
            is_active: editing.is_active,
          } : undefined}
          isSubcategory={isSubcategory}
          onSubmit={handleSubmit}
          loading={createMutation.isPending || updateMutation.isPending}
        />
      </Modal>
    </>
  );
}
