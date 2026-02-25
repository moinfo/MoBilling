import { Table, ActionIcon, Group, Text, Badge, Tooltip } from '@mantine/core';
import { IconEdit, IconPlayerPlay, IconPlayerPause, IconUsers, IconEye, IconId } from '@tabler/icons-react';
import { useNavigate } from 'react-router-dom';
import { Tenant } from '../../api/admin';

const subscriptionStatusColors: Record<string, string> = {
  trial: 'blue',
  subscribed: 'green',
  expired: 'red',
  deactivated: 'gray',
};

interface Props {
  tenants: Tenant[];
  onEdit: (tenant: Tenant) => void;
  onToggleActive: (tenant: Tenant) => void;
  onImpersonate?: (tenant: Tenant) => void;
}

function formatExpiry(tenant: Tenant): string {
  if (!tenant.expires_at) return '—';
  const date = new Date(tenant.expires_at);
  const formatted = date.toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' });
  const days = tenant.days_remaining ?? 0;
  if (days <= 0) return formatted;
  return `${formatted} (${days}d)`;
}

function expiryColor(tenant: Tenant): string {
  const days = tenant.days_remaining ?? 0;
  if (days <= 0) return 'red';
  if (days <= 7) return 'orange';
  return 'dimmed';
}

export default function TenantTable({ tenants, onEdit, onToggleActive, onImpersonate }: Props) {
  const navigate = useNavigate();

  if (tenants.length === 0) {
    return <Text c="dimmed" ta="center" py="xl">No tenants found</Text>;
  }

  return (
    <Table.ScrollContainer minWidth={800}>
      <Table striped highlightOnHover>
        <Table.Thead>
          <Table.Tr>
            <Table.Th>Company Name</Table.Th>
            <Table.Th>Email</Table.Th>
            <Table.Th>Currency</Table.Th>
            <Table.Th>Users</Table.Th>
            <Table.Th>Subscription</Table.Th>
            <Table.Th>Expires</Table.Th>
            <Table.Th>Status</Table.Th>
            <Table.Th w={190}>Actions</Table.Th>
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
              {tenant.subscription_status && (
                <Badge color={subscriptionStatusColors[tenant.subscription_status] || 'gray'} variant="light">
                  {tenant.subscription_status === 'trial' ? 'Trial' :
                   tenant.subscription_status === 'subscribed' ? 'Subscribed' :
                   tenant.subscription_status === 'expired' ? 'Expired' : 'Deactivated'}
                </Badge>
              )}
            </Table.Td>
            <Table.Td>
              <Text size="sm" c={expiryColor(tenant)}>
                {formatExpiry(tenant)}
              </Text>
            </Table.Td>
            <Table.Td>
              <Badge color={tenant.is_active ? 'green' : 'red'} variant="light">
                {tenant.is_active ? 'Active' : 'Inactive'}
              </Badge>
            </Table.Td>
            <Table.Td>
              <Group gap="xs" wrap="nowrap">
                <Tooltip label="Tenant profile">
                  <ActionIcon variant="light" color="violet" onClick={() => navigate(`/admin/tenants/${tenant.id}`)}>
                    <IconId size={16} />
                  </ActionIcon>
                </Tooltip>
                {onImpersonate && tenant.is_active && (
                  <Tooltip label="View as tenant">
                    <ActionIcon variant="light" color="teal" onClick={() => onImpersonate(tenant)}>
                      <IconEye size={16} />
                    </ActionIcon>
                  </Tooltip>
                )}
                <Tooltip label="Manage users">
                  <ActionIcon variant="light" color="blue" onClick={() => navigate(`/admin/tenants/${tenant.id}/users`)}>
                    <IconUsers size={16} />
                  </ActionIcon>
                </Tooltip>
                <Tooltip label="Edit tenant">
                  <ActionIcon variant="light" onClick={() => onEdit(tenant)}>
                    <IconEdit size={16} />
                  </ActionIcon>
                </Tooltip>
                <Tooltip label={tenant.is_active ? 'Deactivate' : 'Activate'}>
                  <ActionIcon
                    variant="light"
                    color={tenant.is_active ? 'orange' : 'green'}
                    onClick={() => onToggleActive(tenant)}
                  >
                    {tenant.is_active ? <IconPlayerPause size={16} /> : <IconPlayerPlay size={16} />}
                  </ActionIcon>
                </Tooltip>
              </Group>
            </Table.Td>
          </Table.Tr>
        ))}
      </Table.Tbody>
      </Table>
    </Table.ScrollContainer>
  );
}
