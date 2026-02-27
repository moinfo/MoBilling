import { useState, useEffect } from 'react';
import {
  Title, Paper, Table, Badge, Text, Loader, Center, Group, Button, Select, Switch,
} from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconShieldLock } from '@tabler/icons-react';
import { getTenants, type Tenant } from '../../api/admin';
import {
  getAllPermissions, getPermissionTenants, updatePermissionTenants,
  type PermissionTenant,
} from '../../api/permissions';
import type { Permission, GroupedPermissions } from '../../api/roles';

function flattenPermissions(grouped: GroupedPermissions): Permission[] {
  return Object.values(grouped).flatMap((g) => Object.values(g).flat());
}


export default function PermissionsAdmin() {
  const queryClient = useQueryClient();
  const [selectedGroup, setSelectedGroup] = useState<string | null>(null);
  const [selectedPermId, setSelectedPermId] = useState<string | null>(null);
  const [enabledTenantIds, setEnabledTenantIds] = useState<Set<string>>(new Set());
  const [dirty, setDirty] = useState(false);

  // Fetch all permissions for dropdowns
  const { data: permsData, isLoading: permsLoading } = useQuery({
    queryKey: ['admin-all-permissions'],
    queryFn: () => getAllPermissions(),
  });

  // Fetch tenants for the overview table
  const { data: tenantsData, isLoading: tenantsLoading } = useQuery({
    queryKey: ['admin-tenants-permissions'],
    queryFn: () => getTenants({ per_page: 100 }),
  });

  const grouped: GroupedPermissions = permsData?.data?.data || {};
  const allPermissions = flattenPermissions(grouped);
  const totalPermissions = allPermissions.length;
  const tenants: Tenant[] = tenantsData?.data?.data || [];

  // Build group options from grouped permissions (e.g. "Clients", "Invoices")
  const groupOptions = [...new Set(allPermissions.map((p) => p.group_name))].sort()
    .map((g) => ({ value: g, label: g }));

  // Build permission options filtered by selected group
  const permissionOptions = allPermissions
    .filter((p) => !selectedGroup || p.group_name === selectedGroup)
    .map((p) => ({ value: p.id, label: p.label }));

  // Fetch tenants for the selected permission
  const { data: permTenantsData, isLoading: permTenantsLoading } = useQuery({
    queryKey: ['admin-permission-tenants', selectedPermId],
    queryFn: () => getPermissionTenants(selectedPermId!),
    enabled: !!selectedPermId,
  });

  // Sync local state when server data arrives
  useEffect(() => {
    if (permTenantsData?.data?.data) {
      const enabled = permTenantsData.data.data
        .filter((t: PermissionTenant) => t.enabled)
        .map((t: PermissionTenant) => t.id);
      setEnabledTenantIds(new Set(enabled));
      setDirty(false);
    }
  }, [permTenantsData]);

  const saveMutation = useMutation({
    mutationFn: () => updatePermissionTenants(selectedPermId!, Array.from(enabledTenantIds)),
    onSuccess: (res) => {
      queryClient.invalidateQueries({ queryKey: ['admin-permission-tenants', selectedPermId] });
      queryClient.invalidateQueries({ queryKey: ['admin-tenants-permissions'] });
      notifications.show({ title: 'Success', message: res.data.message, color: 'green' });
      setDirty(false);
    },
    onError: (err: any) => {
      notifications.show({
        title: 'Error',
        message: err?.response?.data?.message || 'Failed to update',
        color: 'red',
      });
    },
  });

  const toggle = (tenantId: string) => {
    setEnabledTenantIds((prev) => {
      const next = new Set(prev);
      if (next.has(tenantId)) next.delete(tenantId);
      else next.add(tenantId);
      return next;
    });
    setDirty(true);
  };

  const enableAll = () => {
    const permTenants: PermissionTenant[] = permTenantsData?.data?.data || [];
    setEnabledTenantIds(new Set(permTenants.map((t) => t.id)));
    setDirty(true);
  };

  const disableAll = () => {
    setEnabledTenantIds(new Set());
    setDirty(true);
  };

  if (permsLoading || tenantsLoading) {
    return <Center py="xl"><Loader /></Center>;
  }

  return (
    <>
      <Group mb="lg" gap="xs">
        <IconShieldLock size={28} />
        <Title order={2}>Permissions Overview</Title>
      </Group>

      {/* Overview table */}
      <Paper withBorder mb="xl">
        <Table.ScrollContainer minWidth={500}>
          <Table striped highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Tenant</Table.Th>
                <Table.Th>Enabled Permissions</Table.Th>
                <Table.Th>Status</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {tenants.map((tenant) => {
                const count = tenant.allowed_permissions_count ?? 0;
                const color = count === 0 ? 'gray' : count === totalPermissions ? 'green' : 'blue';
                return (
                  <Table.Tr key={tenant.id}>
                    <Table.Td>
                      <Text fw={500}>{tenant.name}</Text>
                      <Text size="xs" c="dimmed">{tenant.email}</Text>
                    </Table.Td>
                    <Table.Td>
                      <Badge color={color} variant="light" size="lg">
                        {count} / {totalPermissions}
                      </Badge>
                    </Table.Td>
                    <Table.Td>
                      <Badge color={tenant.is_active ? 'green' : 'red'} variant="light">
                        {tenant.is_active ? 'Active' : 'Inactive'}
                      </Badge>
                    </Table.Td>
                  </Table.Tr>
                );
              })}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      </Paper>

      {/* Permission-centric control */}
      <Title order={3} mb="md">Manage Permission Across Tenants</Title>

      <Group mb="md">
        <Select
          placeholder="Filter by group"
          data={groupOptions}
          value={selectedGroup}
          onChange={(val) => {
            setSelectedGroup(val);
            setSelectedPermId(null);
          }}
          clearable
          searchable
          style={{ width: 220 }}
        />
        <Select
          placeholder="Select permission"
          data={permissionOptions}
          value={selectedPermId}
          onChange={setSelectedPermId}
          searchable
          style={{ width: 280 }}
          disabled={permissionOptions.length === 0}
        />
      </Group>

      {selectedPermId && (
        <Paper withBorder>
          {permTenantsLoading ? (
            <Center py="xl"><Loader /></Center>
          ) : (
            <>
              <Group justify="space-between" p="md">
                <Text fw={500}>
                  {enabledTenantIds.size} / {permTenantsData?.data?.data?.length || 0} tenants enabled
                </Text>
                <Group gap="xs">
                  <Button variant="light" size="xs" onClick={enableAll}>Enable All</Button>
                  <Button variant="light" size="xs" color="gray" onClick={disableAll}>Disable All</Button>
                  <Button
                    size="sm"
                    disabled={!dirty}
                    loading={saveMutation.isPending}
                    onClick={() => saveMutation.mutate()}
                  >
                    Save
                  </Button>
                </Group>
              </Group>
              <Table striped highlightOnHover>
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th>Tenant</Table.Th>
                    <Table.Th>Status</Table.Th>
                    <Table.Th style={{ width: 100 }}>Enabled</Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {(permTenantsData?.data?.data || []).map((tenant: PermissionTenant) => (
                    <Table.Tr key={tenant.id}>
                      <Table.Td>
                        <Text fw={500}>{tenant.name}</Text>
                        <Text size="xs" c="dimmed">{tenant.email}</Text>
                      </Table.Td>
                      <Table.Td>
                        <Badge color={tenant.is_active ? 'green' : 'red'} variant="light" size="sm">
                          {tenant.is_active ? 'Active' : 'Inactive'}
                        </Badge>
                      </Table.Td>
                      <Table.Td>
                        <Switch
                          checked={enabledTenantIds.has(tenant.id)}
                          onChange={() => toggle(tenant.id)}
                        />
                      </Table.Td>
                    </Table.Tr>
                  ))}
                </Table.Tbody>
              </Table>
            </>
          )}
        </Paper>
      )}
    </>
  );
}
