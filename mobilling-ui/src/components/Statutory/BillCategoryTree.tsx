import { Card, Group, Text, Badge, ActionIcon, Table, Button, Stack } from '@mantine/core';
import { IconEdit, IconTrash, IconPlus } from '@tabler/icons-react';
import { BillCategory } from '../../api/billCategories';

const cycleLabels: Record<string, string> = {
  once: 'Once',
  monthly: 'Monthly',
  quarterly: 'Quarterly',
  half_yearly: 'Semi-Annual',
  yearly: 'Annually',
};

interface Props {
  categories: BillCategory[];
  onAddSubcategory: (parentId: string) => void;
  onEdit: (category: BillCategory) => void;
  onDelete: (category: BillCategory) => void;
}

export default function BillCategoryTree({ categories, onAddSubcategory, onEdit, onDelete }: Props) {
  if (categories.length === 0) {
    return <Text c="dimmed" ta="center" py="xl">No categories yet. Create your first category above.</Text>;
  }

  return (
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
                onClick={() => onAddSubcategory(cat.id)}
              >
                Add Subcategory
              </Button>
              <ActionIcon variant="light" onClick={() => onEdit(cat)}>
                <IconEdit size={16} />
              </ActionIcon>
              <ActionIcon variant="light" color="red" onClick={() => onDelete(cat)}>
                <IconTrash size={16} />
              </ActionIcon>
            </Group>
          </Group>

          {cat.children && cat.children.length > 0 ? (
            <Table striped highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Subcategory</Table.Th>
                  <Table.Th>Billing Cycle</Table.Th>
                  <Table.Th>Status</Table.Th>
                  <Table.Th w={100}>Actions</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {cat.children.map((sub) => (
                  <Table.Tr key={sub.id}>
                    <Table.Td>{sub.name}</Table.Td>
                    <Table.Td>
                      {sub.billing_cycle ? cycleLabels[sub.billing_cycle] || sub.billing_cycle : '—'}
                    </Table.Td>
                    <Table.Td>
                      <Badge color={sub.is_active ? 'green' : 'gray'} size="sm">
                        {sub.is_active ? 'Active' : 'Inactive'}
                      </Badge>
                    </Table.Td>
                    <Table.Td>
                      <Group gap="xs">
                        <ActionIcon variant="light" size="sm" onClick={() => onEdit(sub)}>
                          <IconEdit size={14} />
                        </ActionIcon>
                        <ActionIcon variant="light" color="red" size="sm" onClick={() => onDelete(sub)}>
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
  );
}
