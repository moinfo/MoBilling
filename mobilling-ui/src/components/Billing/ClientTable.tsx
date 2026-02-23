import { Table, ActionIcon, Group, Text } from '@mantine/core';
import { IconEdit, IconTrash } from '@tabler/icons-react';
import { Client } from '../../api/clients';

interface Props {
  clients: Client[];
  onEdit: (client: Client) => void;
  onDelete: (client: Client) => void;
}

export default function ClientTable({ clients, onEdit, onDelete }: Props) {
  if (clients.length === 0) {
    return <Text c="dimmed" ta="center" py="xl">No clients found</Text>;
  }

  return (
    <Table striped highlightOnHover>
      <Table.Thead>
        <Table.Tr>
          <Table.Th>Name</Table.Th>
          <Table.Th>Email</Table.Th>
          <Table.Th>Phone</Table.Th>
          <Table.Th>Tax ID</Table.Th>
          <Table.Th w={100}>Actions</Table.Th>
        </Table.Tr>
      </Table.Thead>
      <Table.Tbody>
        {clients.map((client) => (
          <Table.Tr key={client.id}>
            <Table.Td>{client.name}</Table.Td>
            <Table.Td>{client.email || '—'}</Table.Td>
            <Table.Td>{client.phone || '—'}</Table.Td>
            <Table.Td>{client.tax_id || '—'}</Table.Td>
            <Table.Td>
              <Group gap="xs">
                <ActionIcon variant="light" onClick={() => onEdit(client)}>
                  <IconEdit size={16} />
                </ActionIcon>
                <ActionIcon variant="light" color="red" onClick={() => onDelete(client)}>
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
