import { Table, ActionIcon, Group, Text, Anchor } from '@mantine/core';
import { IconEdit, IconTrash, IconEye } from '@tabler/icons-react';
import { useNavigate } from 'react-router-dom';
import { Client } from '../../api/clients';

interface Props {
  clients: Client[];
  onEdit: (client: Client) => void;
  onDelete: (client: Client) => void;
}

export default function ClientTable({ clients, onEdit, onDelete }: Props) {
  const navigate = useNavigate();

  if (clients.length === 0) {
    return <Text c="dimmed" ta="center" py="xl">No clients found</Text>;
  }

  return (
    <Table.ScrollContainer minWidth={550}>
      <Table striped highlightOnHover>
        <Table.Thead>
          <Table.Tr>
            <Table.Th>Name</Table.Th>
            <Table.Th>Email</Table.Th>
            <Table.Th>Phone</Table.Th>
            <Table.Th>Tax ID</Table.Th>
            <Table.Th w={120}>Actions</Table.Th>
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {clients.map((client) => (
            <Table.Tr key={client.id}>
              <Table.Td>
                <Anchor size="sm" fw={500} onClick={() => navigate(`/clients/${client.id}`)}>
                  {client.name}
                </Anchor>
              </Table.Td>
              <Table.Td>{client.email || '—'}</Table.Td>
              <Table.Td>{client.phone || '—'}</Table.Td>
              <Table.Td>{client.tax_id || '—'}</Table.Td>
              <Table.Td>
                <Group gap="xs">
                  <ActionIcon variant="light" color="gray" onClick={() => navigate(`/clients/${client.id}`)}>
                    <IconEye size={16} />
                  </ActionIcon>
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
    </Table.ScrollContainer>
  );
}
