import { Table, ActionIcon, Group, Text, Badge } from '@mantine/core';
import { IconEdit, IconUserCheck, IconUserOff } from '@tabler/icons-react';
import { TenantUser } from '../../api/users';

interface Props {
  users: TenantUser[];
  isAdmin: boolean;
  currentUserId: string;
  onEdit: (user: TenantUser) => void;
  onToggleActive: (user: TenantUser) => void;
}

export default function UserTable({ users, isAdmin, currentUserId, onEdit, onToggleActive }: Props) {
  if (users.length === 0) {
    return <Text c="dimmed" ta="center" py="xl">No team members found</Text>;
  }

  return (
    <Table striped highlightOnHover>
      <Table.Thead>
        <Table.Tr>
          <Table.Th>Name</Table.Th>
          <Table.Th>Email</Table.Th>
          <Table.Th>Phone</Table.Th>
          <Table.Th>Role</Table.Th>
          <Table.Th>Status</Table.Th>
          {isAdmin && <Table.Th w={100}>Actions</Table.Th>}
        </Table.Tr>
      </Table.Thead>
      <Table.Tbody>
        {users.map((user) => (
          <Table.Tr key={user.id}>
            <Table.Td>{user.name}</Table.Td>
            <Table.Td>{user.email}</Table.Td>
            <Table.Td>{user.phone || '—'}</Table.Td>
            <Table.Td>
              <Badge color={user.role === 'admin' ? 'blue' : 'gray'} variant="light">
                {user.role}
              </Badge>
            </Table.Td>
            <Table.Td>
              <Badge color={user.is_active ? 'green' : 'red'} variant="light">
                {user.is_active ? 'Active' : 'Inactive'}
              </Badge>
            </Table.Td>
            {isAdmin && (
              <Table.Td>
                <Group gap="xs">
                  <ActionIcon variant="light" onClick={() => onEdit(user)}>
                    <IconEdit size={16} />
                  </ActionIcon>
                  {user.id !== currentUserId && (
                    <ActionIcon
                      variant="light"
                      color={user.is_active ? 'red' : 'green'}
                      onClick={() => onToggleActive(user)}
                    >
                      {user.is_active ? <IconUserOff size={16} /> : <IconUserCheck size={16} />}
                    </ActionIcon>
                  )}
                </Group>
              </Table.Td>
            )}
          </Table.Tr>
        ))}
      </Table.Tbody>
    </Table>
  );
}
