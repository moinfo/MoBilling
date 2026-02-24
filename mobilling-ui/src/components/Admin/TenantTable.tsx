import { Table, ActionIcon, Group, Text, Badge, Tooltip } from '@mantine/core';
import { IconEdit, IconPlayerPlay, IconPlayerPause, IconUsers, IconEye } from '@tabler/icons-react';
import { useNavigate } from 'react-router-dom';
import { Tenant } from '../../api/admin';

interface Props {
  tenants: Tenant[];
  onEdit: (tenant: Tenant) => void;
  onToggleActive: (tenant: Tenant) => void;
  onImpersonate?: (tenant: Tenant) => void;
}

export default function TenantTable({ tenants, onEdit, onToggleActive, onImpersonate }: Props) {
  const navigate = useNavigate();

  if (tenants.length === 0) {
    return <Text c="dimmed" ta="center" py="xl">No tenants found</Text>;
  }

  return (
    <Table striped highlightOnHover>
      <Table.Thead>
        <Table.Tr>
          <Table.Th>Company Name</Table.Th>
          <Table.Th>Email</Table.Th>
          <Table.Th>Currency</Table.Th>
          <Table.Th>Users</Table.Th>
          <Table.Th>Status</Table.Th>
          <Table.Th w={160}>Actions</Table.Th>
        </Table.Tr>
      </Table.Thead>
      <Table.Tbody>
        {tenants.map((tenant) => (
          <Table.Tr key={tenant.id}>
            <Table.Td>{tenant.name}</Table.Td>
            <Table.Td>{tenant.email}</Table.Td>
            <Table.Td>{tenant.currency}</Table.Td>
            <Table.Td>{tenant.users_count}</Table.Td>
            <Table.Td>
              <Badge color={tenant.is_active ? 'green' : 'red'} variant="light">
                {tenant.is_active ? 'Active' : 'Inactive'}
              </Badge>
            </Table.Td>
            <Table.Td>
              <Group gap="xs" wrap="nowrap">
                {onImpersonate && tenant.is_active && (
                  <Tooltip label="View as tenant">
                    <ActionIcon variant="light" color="teal" onClick={() => onImpersonate(tenant)}>
                      <IconEye size={16} />
                    </ActionIcon>
                  </Tooltip>
                )}
                <ActionIcon variant="light" color="blue" onClick={() => navigate(`/admin/tenants/${tenant.id}/users`)}>
                  <IconUsers size={16} />
                </ActionIcon>
                <ActionIcon variant="light" onClick={() => onEdit(tenant)}>
                  <IconEdit size={16} />
                </ActionIcon>
                <ActionIcon
                  variant="light"
                  color={tenant.is_active ? 'orange' : 'green'}
                  onClick={() => onToggleActive(tenant)}
                >
                  {tenant.is_active ? <IconPlayerPause size={16} /> : <IconPlayerPlay size={16} />}
                </ActionIcon>
              </Group>
            </Table.Td>
          </Table.Tr>
        ))}
      </Table.Tbody>
    </Table>
  );
}
