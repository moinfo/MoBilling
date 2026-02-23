import { Table, Badge, ActionIcon, Group, Switch, Text } from '@mantine/core';
import { IconEdit, IconTrash } from '@tabler/icons-react';
import { ProductService } from '../../api/productServices';
import { formatCurrency } from '../../utils/formatCurrency';

interface Props {
  items: ProductService[];
  onEdit: (item: ProductService) => void;
  onDelete: (item: ProductService) => void;
}

export default function ProductServiceTable({ items, onEdit, onDelete }: Props) {
  if (items.length === 0) {
    return <Text c="dimmed" ta="center" py="xl">No products or services found</Text>;
  }

  return (
    <Table striped highlightOnHover>
      <Table.Thead>
        <Table.Tr>
          <Table.Th>Type</Table.Th>
          <Table.Th>Code</Table.Th>
          <Table.Th>Name</Table.Th>
          <Table.Th>Price</Table.Th>
          <Table.Th>Tax %</Table.Th>
          <Table.Th>Unit</Table.Th>
          <Table.Th>Active</Table.Th>
          <Table.Th w={100}>Actions</Table.Th>
        </Table.Tr>
      </Table.Thead>
      <Table.Tbody>
        {items.map((item) => (
          <Table.Tr key={item.id}>
            <Table.Td>
              <Badge color={item.type === 'product' ? 'blue' : 'green'} size="sm">
                {item.type}
              </Badge>
            </Table.Td>
            <Table.Td>{item.code || '—'}</Table.Td>
            <Table.Td>{item.name}</Table.Td>
            <Table.Td>{formatCurrency(item.price)}</Table.Td>
            <Table.Td>{item.tax_percent}%</Table.Td>
            <Table.Td>{item.unit}</Table.Td>
            <Table.Td><Switch checked={item.is_active} readOnly size="xs" /></Table.Td>
            <Table.Td>
              <Group gap="xs">
                <ActionIcon variant="light" onClick={() => onEdit(item)}>
                  <IconEdit size={16} />
                </ActionIcon>
                <ActionIcon variant="light" color="red" onClick={() => onDelete(item)}>
                  <IconTrash size={16} />
                </ActionIcon>
              </Group>
            </Table.Td>
          </Table.Tr>
        ))}
      </Table.Tbody>
    </Table>
  );
}
