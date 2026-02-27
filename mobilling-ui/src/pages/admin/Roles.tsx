import { useState, useEffect } from 'react';
import {
  Title, Paper, Badge, Text, Loader, Center, Group, Button, Card,
  SimpleGrid, Anchor, ThemeIcon, RingProgress, Checkbox, Stack,
} from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  IconShieldCheck, IconArrowLeft, IconCrown, IconUserShield,
  IconUser, IconLock, IconChevronRight,
} from '@tabler/icons-react';
import {
  getRoleTemplates, getRoleTemplate, updateRoleTemplate,
  type RoleTemplate, type RoleTemplateDetail,
} from '../../api/permissions';
import type { Permission, GroupedPermissions } from '../../api/roles';

const roleConfig: Record<string, { icon: typeof IconCrown; color: string; gradient: { from: string; to: string } }> = {
  super_admin: {
    icon: IconCrown,
    color: 'yellow',
    gradient: { from: 'yellow.6', to: 'orange.5' },
  },
  admin: {
    icon: IconUserShield,
    color: 'violet',
    gradient: { from: 'violet.6', to: 'indigo.5' },
  },
  user: {
    icon: IconUser,
    color: 'blue',
    gradient: { from: 'blue.6', to: 'cyan.5' },
  },
};

export default function RolesAdmin() {
  const [selectedType, setSelectedType] = useState<string | null>(null);

  if (selectedType) {
    return <RoleDetail type={selectedType} onBack={() => setSelectedType(null)} />;
  }

  return <RoleList onSelect={setSelectedType} />;
}

function RoleList({ onSelect }: { onSelect: (type: string) => void }) {
  const { data, isLoading } = useQuery({
    queryKey: ['admin-role-templates'],
    queryFn: getRoleTemplates,
  });

  const roles: RoleTemplate[] = data?.data?.data || [];

  if (isLoading) {
    return <Center py="xl"><Loader /></Center>;
  }

  return (
    <>
      <Group mb="xs" gap="xs">
        <IconShieldCheck size={28} />
        <Title order={2}>Global Roles</Title>
      </Group>
      <Text c="dimmed" mb="lg" size="sm">
        Configure default permissions for each role type. Changes apply to all tenants.
      </Text>

      <SimpleGrid cols={{ base: 1, sm: 3 }}>
        {roles.map((role) => {
          const config = roleConfig[role.type] || roleConfig.user;
          const Icon = config.icon;
          const pct = role.total_permissions > 0
            ? Math.round((role.permissions_count / role.total_permissions) * 100)
            : 0;

          return (
            <Card
              key={role.type}
              withBorder
              padding="lg"
              style={{
                cursor: role.editable ? 'pointer' : 'default',
                transition: 'transform 120ms ease, box-shadow 120ms ease',
              }}
              onMouseEnter={(e) => {
                if (role.editable) {
                  e.currentTarget.style.transform = 'translateY(-2px)';
                  e.currentTarget.style.boxShadow = 'var(--mantine-shadow-md)';
                }
              }}
              onMouseLeave={(e) => {
                e.currentTarget.style.transform = '';
                e.currentTarget.style.boxShadow = '';
              }}
              onClick={() => role.editable && onSelect(role.type)}
            >
              <Group justify="space-between" mb="md">
                <ThemeIcon
                  size={48}
                  radius="md"
                  variant="light"
                  color={config.color}
                >
                  <Icon size={26} />
                </ThemeIcon>
                {!role.editable && (
                  <Badge
                    leftSection={<IconLock size={12} />}
                    color="gray"
                    variant="light"
                    size="sm"
                  >
                    Read-only
                  </Badge>
                )}
                {role.editable && (
                  <IconChevronRight size={18} color="var(--mantine-color-dimmed)" />
                )}
              </Group>

              <Text fw={700} size="lg" mb={4}>{role.label}</Text>
              <Text size="xs" c="dimmed" mb="md" lineClamp={2}>
                {role.description}
              </Text>

              <Group justify="space-between" align="flex-end">
                <div>
                  <Text size="xs" c="dimmed" mb={2}>Permissions</Text>
                  <Group gap={4} align="baseline">
                    <Text fw={700} size="xl" lh={1}>{role.permissions_count}</Text>
                    <Text size="sm" c="dimmed" lh={1}>/ {role.total_permissions}</Text>
                  </Group>
                </div>
                <RingProgress
                  size={52}
                  thickness={5}
                  roundCaps
                  sections={[{ value: pct, color: config.color }]}
                  label={
                    <Text size="xs" ta="center" fw={600} lh={1}>{pct}%</Text>
                  }
                />
              </Group>

              {role.tenants_count !== null && (
                <Text size="xs" c="dimmed" mt="sm">
                  Applied to {role.tenants_count} tenant{role.tenants_count !== 1 ? 's' : ''}
                </Text>
              )}
            </Card>
          );
        })}
      </SimpleGrid>
    </>
  );
}

function RoleDetail({ type, onBack }: { type: string; onBack: () => void }) {
  const queryClient = useQueryClient();
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [initialized, setInitialized] = useState(false);

  const config = roleConfig[type] || roleConfig.user;
  const Icon = config.icon;

  const { data, isLoading } = useQuery({
    queryKey: ['admin-role-template', type],
    queryFn: () => getRoleTemplate(type),
  });

  const detail: RoleTemplateDetail | undefined = data?.data?.data;

  useEffect(() => {
    if (detail && !initialized) {
      setSelected(new Set(detail.enabled_ids));
      setInitialized(true);
    }
  }, [detail, initialized]);

  const saveMutation = useMutation({
    mutationFn: () => updateRoleTemplate(type, Array.from(selected)),
    onSuccess: (res) => {
      queryClient.invalidateQueries({ queryKey: ['admin-role-template', type] });
      queryClient.invalidateQueries({ queryKey: ['admin-role-templates'] });
      notifications.show({ title: 'Success', message: res.data.message, color: 'green' });
    },
    onError: (err: any) => {
      notifications.show({
        title: 'Error',
        message: err?.response?.data?.message || 'Failed to update role',
        color: 'red',
      });
    },
  });

  const togglePerm = (id: string) => {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const toggleAll = (perms: Permission[]) => {
    const ids = perms.map((p) => p.id);
    const allOn = ids.every((id) => selected.has(id));
    setSelected((prev) => {
      const next = new Set(prev);
      ids.forEach((id) => (allOn ? next.delete(id) : next.add(id)));
      return next;
    });
  };

  const selectAll = () => {
    if (!detail) return;
    const all = Object.values(detail.grouped_permissions).flatMap((g) =>
      Object.values(g).flat()
    );
    setSelected(new Set(all.map((p: Permission) => p.id)));
  };

  const deselectAll = () => setSelected(new Set());

  if (isLoading || !detail) {
    return <Center py="xl"><Loader /></Center>;
  }

  const grouped: GroupedPermissions = detail.grouped_permissions;
  const totalPerms = Object.values(grouped).flatMap((g) => Object.values(g).flat()).length;
  const roleLabel = type === 'admin' ? 'Tenant Admin' : 'Tenant User';

  const categoryLabels: Record<string, string> = {
    menu: 'Menu Access',
    crud: 'Data Operations',
    settings: 'Settings',
    reports: 'Reports',
  };

  return (
    <>
      <Group mb="md">
        <Anchor c="dimmed" onClick={onBack} style={{ cursor: 'pointer' }}>
          <Group gap={4}>
            <IconArrowLeft size={16} />
            <Text size="sm">Back to Roles</Text>
          </Group>
        </Anchor>
      </Group>

      <Group mb="lg" gap="md">
        <ThemeIcon size={44} radius="md" variant="light" color={config.color}>
          <Icon size={24} />
        </ThemeIcon>
        <div>
          <Title order={2} lh={1.2}>{roleLabel}</Title>
          <Text size="sm" c="dimmed">
            {selected.size} of {totalPerms} permissions enabled across all tenants
          </Text>
        </div>
      </Group>

      <Paper p="md" withBorder mb="md">
        <Group justify="space-between">
          <Group gap="xs">
            <Button variant="light" size="xs" onClick={selectAll}>Select All</Button>
            <Button variant="light" size="xs" color="gray" onClick={deselectAll}>Deselect All</Button>
          </Group>
          <Button loading={saveMutation.isPending} onClick={() => saveMutation.mutate()}>
            Save to All Tenants
          </Button>
        </Group>
      </Paper>

      <Stack gap="md">
        {Object.entries(grouped).map(([category, groups]) => {
          const catPerms = Object.values(groups).flat();
          const catEnabled = catPerms.filter((p) => selected.has(p.id)).length;

          return (
            <Paper key={category} withBorder p="md">
              <Group justify="space-between" mb="sm">
                <Text fw={700} size="sm" tt="uppercase" c="dimmed">
                  {categoryLabels[category] || category}
                </Text>
                <Badge variant="light" size="sm">
                  {catEnabled} / {catPerms.length}
                </Badge>
              </Group>

              <Stack gap="xs">
                {Object.entries(groups).map(([groupName, perms]: [string, Permission[]]) => {
                  const ids = perms.map((p) => p.id);
                  const allOn = ids.every((id) => selected.has(id));
                  const someOn = ids.some((id) => selected.has(id));

                  return (
                    <Paper key={groupName} p="xs" bg="var(--mantine-color-default-hover)" radius="sm">
                      <Group gap="xs" mb={6}>
                        <Checkbox
                          size="sm"
                          checked={allOn}
                          indeterminate={someOn && !allOn}
                          onChange={() => toggleAll(perms)}
                          label={
                            <Group gap={6}>
                              <Text fw={500} size="sm">{groupName}</Text>
                              <Badge size="xs" variant="light" color={allOn ? 'green' : someOn ? 'yellow' : 'gray'}>
                                {ids.filter((id) => selected.has(id)).length}/{ids.length}
                              </Badge>
                            </Group>
                          }
                        />
                      </Group>
                      <Group gap={6} ml={30}>
                        {perms.map((perm) => (
                          <Badge
                            key={perm.id}
                            variant={selected.has(perm.id) ? 'filled' : 'outline'}
                            color={selected.has(perm.id) ? config.color : 'gray'}
                            style={{ cursor: 'pointer' }}
                            onClick={() => togglePerm(perm.id)}
                            size="sm"
                          >
                            {perm.label}
                          </Badge>
                        ))}
                      </Group>
                    </Paper>
                  );
                })}
              </Stack>
            </Paper>
          );
        })}
      </Stack>
    </>
  );
}
