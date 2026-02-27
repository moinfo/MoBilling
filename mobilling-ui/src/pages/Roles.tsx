import { useState } from 'react';
import {
  Title, Group, Button, Table, Badge, ActionIcon, Modal, TextInput,
  Stack, Text, Alert, Paper, SimpleGrid, Checkbox, Switch, Divider,
  Card, ThemeIcon, Anchor, Box, useComputedColorScheme, alpha,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  IconPlus, IconEdit, IconTrash, IconInfoCircle, IconArrowLeft,
  IconShieldLock, IconMenu2, IconDatabase, IconSettings, IconChartBar,
} from '@tabler/icons-react';
import {
  getRoles, createRole, updateRole, deleteRole, getAvailablePermissions,
  Role, RoleFormData, GroupedPermissions, Permission,
} from '../api/roles';

type View = { mode: 'list' } | { mode: 'create' } | { mode: 'edit'; role: Role };

const categoryMeta: Record<string, { label: string; icon: typeof IconMenu2; color: string }> = {
  menu: { label: 'Menu Access', icon: IconMenu2, color: 'blue' },
  crud: { label: 'Data Operations', icon: IconDatabase, color: 'teal' },
  settings: { label: 'Settings', icon: IconSettings, color: 'orange' },
  reports: { label: 'Reports', icon: IconChartBar, color: 'violet' },
};

export default function Roles() {
  const queryClient = useQueryClient();
  const [view, setView] = useState<View>({ mode: 'list' });
  const [deleteTarget, setDeleteTarget] = useState<Role | null>(null);

  const { data: rolesData } = useQuery({
    queryKey: ['roles'],
    queryFn: () => getRoles(),
  });

  const { data: permsData } = useQuery({
    queryKey: ['available-permissions'],
    queryFn: () => getAvailablePermissions(),
  });

  const roles: Role[] = rolesData?.data?.data || [];
  const groupedPermissions: GroupedPermissions = permsData?.data?.data || {};

  const deleteMutation = useMutation({
    mutationFn: (id: string) => deleteRole(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['roles'] });
      setDeleteTarget(null);
      notifications.show({ title: 'Success', message: 'Role deleted', color: 'green' });
    },
    onError: (err: any) => {
      notifications.show({
        title: 'Error',
        message: err?.response?.data?.message || 'Failed to delete role',
        color: 'red',
      });
    },
  });

  const goBack = () => setView({ mode: 'list' });

  // ─── List View ───
  if (view.mode === 'list') {
    return (
      <>
        <Group justify="space-between" mb="md">
          <Group gap="xs">
            <ThemeIcon variant="light" size="lg" radius="md">
              <IconShieldLock size={20} />
            </ThemeIcon>
            <Title order={2}>Roles & Permissions</Title>
          </Group>
          <Button leftSection={<IconPlus size={16} />} onClick={() => setView({ mode: 'create' })}>
            Create Role
          </Button>
        </Group>

        {roles.length === 0 ? (
          <Paper p="xl" withBorder>
            <Text c="dimmed" ta="center">No roles found. Create one to get started.</Text>
          </Paper>
        ) : (
          <Paper withBorder radius="md">
            <Table.ScrollContainer minWidth={500}>
              <Table striped highlightOnHover verticalSpacing="sm">
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th>Role</Table.Th>
                    <Table.Th>Permissions</Table.Th>
                    <Table.Th>Users</Table.Th>
                    <Table.Th w={100}>Actions</Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {roles.map((role) => (
                    <Table.Tr key={role.id} style={{ cursor: 'pointer' }} onClick={() => setView({ mode: 'edit', role })}>
                      <Table.Td>
                        <Group gap="xs">
                          <Text fw={500}>{role.label}</Text>
                          {role.is_system && <Badge size="xs" variant="light">System</Badge>}
                        </Group>
                        <Text size="xs" c="dimmed">{role.name}</Text>
                      </Table.Td>
                      <Table.Td>
                        <Badge variant="light" color="gray">{role.permissions.length}</Badge>
                      </Table.Td>
                      <Table.Td>
                        <Badge variant="light" color={role.users_count > 0 ? 'blue' : 'gray'}>
                          {role.users_count}
                        </Badge>
                      </Table.Td>
                      <Table.Td>
                        <Group gap="xs" onClick={(e) => e.stopPropagation()}>
                          <ActionIcon variant="light" onClick={() => setView({ mode: 'edit', role })}>
                            <IconEdit size={16} />
                          </ActionIcon>
                          {!role.is_system && (
                            <ActionIcon variant="light" color="red" onClick={() => setDeleteTarget(role)}>
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
          </Paper>
        )}

        {/* Delete Confirmation */}
        <Modal opened={!!deleteTarget} onClose={() => setDeleteTarget(null)} title="Delete Role" size="sm">
          <Stack>
            <Text>Are you sure you want to delete the role <strong>{deleteTarget?.label}</strong>?</Text>
            {deleteTarget && deleteTarget.users_count > 0 && (
              <Alert icon={<IconInfoCircle size={16} />} color="red">
                This role has {deleteTarget.users_count} user(s). Reassign them first.
              </Alert>
            )}
            <Group justify="flex-end">
              <Button variant="default" onClick={() => setDeleteTarget(null)}>Cancel</Button>
              <Button
                color="red"
                loading={deleteMutation.isPending}
                disabled={!!deleteTarget && deleteTarget.users_count > 0}
                onClick={() => deleteTarget && deleteMutation.mutate(deleteTarget.id)}
              >
                Delete
              </Button>
            </Group>
          </Stack>
        </Modal>
      </>
    );
  }

  // ─── Create / Edit View ───
  const editing = view.mode === 'edit' ? view.role : null;

  return (
    <>
      <Anchor
        component="button"
        size="sm"
        mb="xs"
        onClick={goBack}
        style={{ display: 'inline-flex', alignItems: 'center', gap: 4 }}
      >
        <IconArrowLeft size={14} /> Back to Roles
      </Anchor>

      <Group gap="xs" mb="lg">
        <ThemeIcon variant="light" size="lg" radius="md">
          <IconShieldLock size={20} />
        </ThemeIcon>
        <Title order={2}>{editing ? `Edit Role: ${editing.label}` : 'Create New Role'}</Title>
      </Group>

      <RoleFormPage
        editing={editing}
        groupedPermissions={groupedPermissions}
        onClose={goBack}
      />
    </>
  );
}

// ─── Full-page Role Form ───

function RoleFormPage({
  editing,
  groupedPermissions,
  onClose,
}: {
  editing: Role | null;
  groupedPermissions: GroupedPermissions;
  onClose: () => void;
}) {
  const queryClient = useQueryClient();
  const isDark = useComputedColorScheme('light') === 'dark';

  const form = useForm<RoleFormData>({
    initialValues: {
      name: editing?.name || '',
      label: editing?.label || '',
      permissions: editing?.permissions?.map((p) => p.id) || [],
    },
    validate: {
      label: (v) => (v.length > 0 ? null : 'Label is required'),
      name: (v) => {
        if (!editing && !v) return 'Name is required';
        if (!editing && !/^[a-z0-9_]+$/.test(v || '')) return 'Only lowercase letters, numbers, underscores';
        return null;
      },
      permissions: (v) => (v.length > 0 ? null : 'Select at least one permission'),
    },
  });

  const createMutation = useMutation({
    mutationFn: (data: RoleFormData) => createRole(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['roles'] });
      onClose();
      notifications.show({ title: 'Success', message: 'Role created', color: 'green' });
    },
    onError: (err: any) => {
      notifications.show({
        title: 'Error',
        message: err?.response?.data?.message || 'Failed to create role',
        color: 'red',
      });
    },
  });

  const updateMutation = useMutation({
    mutationFn: (data: RoleFormData) => updateRole(editing!.id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['roles'] });
      onClose();
      notifications.show({ title: 'Success', message: 'Role updated', color: 'green' });
    },
    onError: (err: any) => {
      notifications.show({
        title: 'Error',
        message: err?.response?.data?.message || 'Failed to update role',
        color: 'red',
      });
    },
  });

  const handleSubmit = (values: RoleFormData) => {
    if (editing) updateMutation.mutate(values);
    else createMutation.mutate(values);
  };

  const getGroupPermIds = (perms: Permission[]): string[] => perms.map((p) => p.id);

  const toggleGroup = (perms: Permission[]) => {
    const ids = getGroupPermIds(perms);
    const allSelected = ids.every((id) => form.values.permissions.includes(id));
    if (allSelected) {
      form.setFieldValue('permissions', form.values.permissions.filter((id) => !ids.includes(id)));
    } else {
      form.setFieldValue('permissions', Array.from(new Set([...form.values.permissions, ...ids])));
    }
  };

  const toggleCategory = (groups: Record<string, Permission[]>) => {
    const allIds = Object.values(groups).flat().map((p) => p.id);
    const allSelected = allIds.every((id) => form.values.permissions.includes(id));
    if (allSelected) {
      form.setFieldValue('permissions', form.values.permissions.filter((id) => !allIds.includes(id)));
    } else {
      form.setFieldValue('permissions', Array.from(new Set([...form.values.permissions, ...allIds])));
    }
  };

  const totalPerms = Object.values(groupedPermissions).flatMap((g) => Object.values(g).flat()).length;
  const selectedCount = form.values.permissions.length;

  return (
    <form onSubmit={form.onSubmit(handleSubmit)}>
      {/* Role details card */}
      <Paper withBorder p="md" radius="md" mb="lg">
        <Group grow>
          {!editing && (
            <TextInput
              label="Slug"
              placeholder="e.g. accountant"
              description="Lowercase, no spaces (used internally)"
              required
              {...form.getInputProps('name')}
            />
          )}
          <TextInput
            label="Display Name"
            placeholder="e.g. Accountant"
            required
            {...form.getInputProps('label')}
          />
        </Group>
      </Paper>

      {/* Permissions header */}
      <Group justify="space-between" mb="md">
        <Group gap="xs">
          <Text fw={600} size="lg">Permissions</Text>
          <Badge variant="light" size="lg">
            {selectedCount} / {totalPerms}
          </Badge>
        </Group>
        {form.errors.permissions && (
          <Text c="red" size="sm">{form.errors.permissions}</Text>
        )}
      </Group>

      {/* Permission category cards */}
      <Stack gap="lg" mb="xl">
        {Object.entries(groupedPermissions).map(([category, groups]) => {
          const meta = categoryMeta[category] || { label: category, icon: IconShieldLock, color: 'gray' };
          const Icon = meta.icon;
          const allCategoryIds = Object.values(groups).flat().map((p: Permission) => p.id);
          const selectedInCategory = allCategoryIds.filter((id) => form.values.permissions.includes(id)).length;
          const allCategorySelected = selectedInCategory === allCategoryIds.length;


          return (
            <Card key={category} withBorder radius="md" padding={0}>
              {/* Category header */}
              <Group
                justify="space-between"
                p="md"
                style={(theme) => ({
                  backgroundColor: alpha(theme.colors[meta.color][isDark ? 8 : 0], isDark ? 0.15 : 1),
                  borderBottom: `1px solid ${alpha(theme.colors[meta.color][isDark ? 6 : 2], isDark ? 0.3 : 1)}`,
                })}
              >
                <Group gap="sm">
                  <ThemeIcon variant="light" color={meta.color} size="md" radius="md">
                    <Icon size={16} />
                  </ThemeIcon>
                  <Text fw={600}>{meta.label}</Text>
                  <Badge variant="light" color={meta.color} size="sm">
                    {selectedInCategory}/{allCategoryIds.length}
                  </Badge>
                </Group>
                <Switch
                  label="All"
                  size="xs"
                  checked={allCategorySelected}
                  onChange={() => toggleCategory(groups)}
                  styles={{ label: { cursor: 'pointer' } }}
                />
              </Group>

              {/* Permission groups */}
              <Box p="md">
                <SimpleGrid cols={{ base: 1, sm: 2 }} spacing="lg">
                  {Object.entries(groups).map(([groupName, perms]: [string, Permission[]]) => {
                    const groupIds = getGroupPermIds(perms);
                    const allSelected = groupIds.every((id) => form.values.permissions.includes(id));
                    const someSelected = groupIds.some((id) => form.values.permissions.includes(id));

                    return (
                      <Box key={groupName}>
                        <Checkbox
                          label={<Text fw={600} size="sm">{groupName}</Text>}
                          checked={allSelected}
                          indeterminate={someSelected && !allSelected}
                          onChange={() => toggleGroup(perms)}
                          mb="xs"
                        />
                        <Divider mb="xs" />
                        <Stack gap={6} ml="lg">
                          {perms.map((perm) => (
                            <Checkbox
                              key={perm.id}
                              label={perm.label}
                              size="sm"
                              checked={form.values.permissions.includes(perm.id)}
                              onChange={(e) => {
                                if (e.currentTarget.checked) {
                                  form.setFieldValue('permissions', [...form.values.permissions, perm.id]);
                                } else {
                                  form.setFieldValue('permissions', form.values.permissions.filter((id) => id !== perm.id));
                                }
                              }}
                            />
                          ))}
                        </Stack>
                      </Box>
                    );
                  })}
                </SimpleGrid>
              </Box>
            </Card>
          );
        })}
      </Stack>

      {/* Action buttons */}
      <Paper withBorder p="md" radius="md" pos="sticky" bottom={0} bg={isDark ? 'dark.7' : 'white'} style={{ zIndex: 10 }}>
        <Group justify="flex-end">
          <Button variant="default" onClick={onClose}>Cancel</Button>
          <Button type="submit" loading={createMutation.isPending || updateMutation.isPending}>
            {editing ? 'Update Role' : 'Create Role'}
          </Button>
        </Group>
      </Paper>
    </form>
  );
}
