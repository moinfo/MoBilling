import { Table, ActionIcon, Group, Text, Anchor, Badge, Loader, Center } from '@mantine/core';
import { IconEdit, IconTrash, IconEye } from '@tabler/icons-react';
import { useNavigate } from 'react-router-dom';
import { Client } from '../../api/clients';
import { formatCurrency } from '../../utils/formatCurrency';
import { usePermissions } from '../../hooks/usePermissions';

interface Props {
  clients: Client[];
  onEdit: (client: Client) => void;
  onDelete: (client: Client) => void;
  startIndex?: number;
  loading?: boolean;
}

export default function ClientTable({ clients, onEdit, onDelete, startIndex = 1, loading }: Props) {
  const navigate = useNavigate();
  const { can } = usePermissions();

  if (loading) {
    return <Center py="xl"><Loader /></Center>;
  }
  if (clients.length === 0) {
    return <Text c="dimmed" ta="center" py="xl">No clients found</Text>;
  }

  return (
    <Table.ScrollContainer minWidth={750}>
      <Table striped highlightOnHover>
        <Table.Thead>
          <Table.Tr>
            <Table.Th w={50}>#</Table.Th>
            <Table.Th>Name</Table.Th>
            <Table.Th>Email</Table.Th>
            <Table.Th>Phone</Table.Th>
            <Table.Th ta="center">Subscriptions</Table.Th>
            {can('client_profile.subscription_value') && <Table.Th ta="right">Sub. Amount</Table.Th>}
            <Table.Th w={120}>Actions</Table.Th>
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {clients.map((client, index) => (
            <Table.Tr key={client.id}>
              <Table.Td>
                <Text size="sm" c="dimmed">{startIndex + index}</Text>
              </Table.Td>
              <Table.Td>
                <Anchor size="sm" fw={500} onClick={() => navigate(`/clients/${client.id}`)} style={{ textTransform: 'uppercase' }}>
                  {client.name}
                </Anchor>
              </Table.Td>
              <Table.Td>{client.email || '—'}</Table.Td>
              <Table.Td>{client.phone || '—'}</Table.Td>
              <Table.Td ta="center">
                {client.active_subscriptions_count ? (
                  <Badge variant="light" color="green" size="sm">{client.active_subscriptions_count}</Badge>
                ) : (
                  <Text size="sm" c="dimmed">0</Text>
                )}
              </Table.Td>
              {can('client_profile.subscription_value') && (
                <Table.Td ta="right">
                  {client.subscription_total ? (
                    <Text size="sm" fw={500}>{formatCurrency(client.subscription_total)}</Text>
                  ) : (
                    <Text size="sm" c="dimmed">—</Text>
                  )}
                </Table.Td>
              )}
              <Table.Td>
                <Group gap="xs" wrap="nowrap">
                  <ActionIcon variant="light" color="gray" onClick={() => navigate(`/clients/${client.id}`)}>
                    <IconEye size={16} />
                  </ActionIcon>
                  {can('clients.update') && (
                    <ActionIcon variant="light" onClick={() => onEdit(client)}>
                      <IconEdit size={16} />
                    </ActionIcon>
                  )}
                  {can('clients.delete') && (
                    <ActionIcon variant="light" color="red" onClick={() => onDelete(client)}>
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
  );
}
