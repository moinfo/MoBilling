import { useState } from 'react';
import { Title, Group, Button, Modal, LoadingOverlay, Card, Text, Badge, ActionIcon, Table, Stack, TextInput, Switch } from '@mantine/core';
import { useForm } from '@mantine/form';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconPlus, IconEdit, IconTrash } from '@tabler/icons-react';
import {
  getExpenseCategories,
  createExpenseCategory,
  updateExpenseCategory,
  deleteExpenseCategory,
  ExpenseCategory,
  SubExpenseCategory,
  ExpenseCategoryFormData,
} from '../api/expenseCategories';

export default function ExpenseCategories() {
  const queryClient = useQueryClient();
  const [formOpen, setFormOpen] = useState(false);
  const [editing, setEditing] = useState<(ExpenseCategory | SubExpenseCategory) | null>(null);
  const [parentIdForNew, setParentIdForNew] = useState<string | null>(null);

  const { data, isLoading } = useQuery({
    queryKey: ['expense-categories'],
    queryFn: getExpenseCategories,
  });

  const categories: ExpenseCategory[] = data?.data?.data || [];

  const createMutation = useMutation({
    mutationFn: (values: ExpenseCategoryFormData) => createExpenseCategory(values),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['expense-categories'] });
      closeForm();
      notifications.show({ title: 'Success', message: 'Category created', color: 'green' });
    },
    onError: () => notifications.show({ title: 'Error', message: 'Failed to create category', color: 'red' }),
  });

  const updateMutation = useMutation({
    mutationFn: (values: ExpenseCategoryFormData) => updateExpenseCategory(editing!.id, values),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['expense-categories'] });
      closeForm();
      notifications.show({ title: 'Success', message: 'Category updated', color: 'green' });
    },
    onError: () => notifications.show({ title: 'Error', message: 'Failed to update category', color: 'red' }),
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => deleteExpenseCategory(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['expense-categories'] });
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

  const openEdit = (item: ExpenseCategory | SubExpenseCategory) => {
    setEditing(item);
    setParentIdForNew(null);
    setFormOpen(true);
  };

  const handleDelete = (item: ExpenseCategory | SubExpenseCategory, isSubcategory: boolean) => {
    const label = isSubcategory ? 'subcategory' : 'category';
    const extra = !isSubcategory && 'sub_categories' in item && item.sub_categories?.length
      ? ` and its ${item.sub_categories.length} subcategories`
      : '';
    modals.openConfirmModal({
      title: `Delete ${label}`,
      children: `Delete "${item.name}"${extra}?`,
      labels: { confirm: 'Delete', cancel: 'Cancel' },
      confirmProps: { color: 'red' },
      onConfirm: () => deleteMutation.mutate(item.id),
    });
  };

  const handleSubmit = (values: ExpenseCategoryFormData) => {
    if (editing) {
      updateMutation.mutate(values);
    } else {
      createMutation.mutate({ ...values, expense_category_id: parentIdForNew });
    }
  };

  const isSubcategory = editing ? 'expense_category_id' in editing : !!parentIdForNew;
  const modalTitle = editing
    ? `Edit ${isSubcategory ? 'Subcategory' : 'Category'}`
    : `New ${isSubcategory ? 'Subcategory' : 'Category'}`;

  return (
    <>
      <Group justify="space-between" mb="md">
        <Title order={2}>Expense Categories</Title>
        <Button leftSection={<IconPlus size={16} />} onClick={openNewCategory}>
          Add Category
        </Button>
      </Group>

      <div style={{ position: 'relative' }}>
        <LoadingOverlay visible={isLoading} />
        {categories.length === 0 ? (
          <Text c="dimmed" ta="center" py="xl">No categories yet. Create your first category above.</Text>
        ) : (
          <Stack gap="md">
            {categories.map((cat) => (
              <Card key={cat.id} withBorder shadow="xs" padding="md">
                <Group justify="space-between" mb="sm">
                  <Group gap="sm">
                    <Text fw={600} size="lg">{cat.name}</Text>
                    {!cat.is_active && <Badge color="gray" size="sm">Inactive</Badge>}
                  </Group>
                  <Group gap="xs">
                    <Button
                      variant="light"
                      size="compact-sm"
                      leftSection={<IconPlus size={14} />}
                      onClick={() => openNewSubcategory(cat.id)}
                    >
                      Add Subcategory
                    </Button>
                    <ActionIcon variant="light" onClick={() => openEdit(cat)}>
                      <IconEdit size={16} />
                    </ActionIcon>
                    <ActionIcon variant="light" color="red" onClick={() => handleDelete(cat, false)}>
                      <IconTrash size={16} />
                    </ActionIcon>
                  </Group>
                </Group>

                {cat.sub_categories && cat.sub_categories.length > 0 ? (
                  <Table striped highlightOnHover>
                    <Table.Thead>
                      <Table.Tr>
                        <Table.Th>Subcategory</Table.Th>
                        <Table.Th>Status</Table.Th>
                        <Table.Th w={100}>Actions</Table.Th>
                      </Table.Tr>
                    </Table.Thead>
                    <Table.Tbody>
                      {cat.sub_categories.map((sub) => (
                        <Table.Tr key={sub.id}>
                          <Table.Td>{sub.name}</Table.Td>
                          <Table.Td>
                            <Badge color={sub.is_active ? 'green' : 'gray'} size="sm">
                              {sub.is_active ? 'Active' : 'Inactive'}
                            </Badge>
                          </Table.Td>
                          <Table.Td>
                            <Group gap="xs">
                              <ActionIcon variant="light" size="sm" onClick={() => openEdit(sub)}>
                                <IconEdit size={14} />
                              </ActionIcon>
                              <ActionIcon variant="light" color="red" size="sm" onClick={() => handleDelete(sub, true)}>
                                <IconTrash size={14} />
                              </ActionIcon>
                            </Group>
                          </Table.Td>
                        </Table.Tr>
                      ))}
                    </Table.Tbody>
                  </Table>
                ) : (
                  <Text c="dimmed" size="sm" fs="italic">No subcategories yet</Text>
                )}
              </Card>
            ))}
          </Stack>
        )}
      </div>

      <Modal opened={formOpen} onClose={closeForm} title={modalTitle}>
        <CategoryForm
          initialValues={editing ? { name: editing.name, is_active: editing.is_active } : undefined}
          onSubmit={handleSubmit}
          loading={createMutation.isPending || updateMutation.isPending}
        />
      </Modal>
    </>
  );
}

function CategoryForm({ initialValues, onSubmit, loading }: {
  initialValues?: { name: string; is_active: boolean };
  onSubmit: (values: ExpenseCategoryFormData) => void;
  loading?: boolean;
}) {
  const form = useForm({
    initialValues: {
      name: initialValues?.name || '',
      is_active: initialValues?.is_active ?? true,
    },
  });

  return (
    <form onSubmit={form.onSubmit((values) => onSubmit(values))}>
      <Stack>
        <TextInput label="Name" required {...form.getInputProps('name')} />
        <Switch label="Active" {...form.getInputProps('is_active', { type: 'checkbox' })} />
        <Group justify="flex-end">
          <Button type="submit" loading={loading}>
            {initialValues ? 'Update' : 'Create'}
          </Button>
        </Group>
      </Stack>
    </form>
  );
}
