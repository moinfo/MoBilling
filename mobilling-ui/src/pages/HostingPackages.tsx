import { useEffect, useState } from 'react';
import {
  Stack, Paper, Title, Text, Group, Table, Select, Center, Loader, Badge,
  Button, ActionIcon, Tooltip, Modal, NumberInput, TextInput, Alert,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { IconPackage, IconPlus, IconEdit, IconTrash, IconInfoCircle } from '@tabler/icons-react';
import {
  getServers, getServerPackagesDetailed, createServerPackage, updateServerPackage, deleteServerPackage,
  ServerPackageDetails,
} from '../api/hosting';
import { usePermissions } from '../hooks/usePermissions';

const limit = (v: number | null, unit: string) => (v === null ? <Badge size="sm" variant="light" color="teal">Unlimited</Badge> : `${v} ${unit}`);

const LIMIT_FIELDS: { key: keyof FormValues; label: string; unit: string }[] = [
  { key: 'quota_mb', label: 'Disk Quota', unit: 'MB' },
  { key: 'bandwidth_mb', label: 'Bandwidth', unit: 'MB' },
  { key: 'databases', label: 'Databases', unit: '' },
  { key: 'email_accounts', label: 'Email Accounts', unit: '' },
  { key: 'subdomains', label: 'Subdomains', unit: '' },
  { key: 'ftp_accounts', label: 'FTP Accounts', unit: '' },
  { key: 'addon_domains', label: 'Addon Domains', unit: '' },
  { key: 'parked_domains', label: 'Parked Domains', unit: '' },
];

interface FormValues {
  name: string;
  quota_mb: number | '';
  bandwidth_mb: number | '';
  databases: number | '';
  email_accounts: number | '';
  subdomains: number | '';
  ftp_accounts: number | '';
  addon_domains: number | '';
  parked_domains: number | '';
}

const emptyForm: FormValues = {
  name: '', quota_mb: '', bandwidth_mb: '', databases: '', email_accounts: '',
  subdomains: '', ftp_accounts: '', addon_domains: '', parked_domains: '',
};

/**
 * WHM's own packages (listpkgs/addpkg/editpkg/killpkg), with their real
 * resource limits — the reference the Product/Service form's "cPanel
 * Package" field draws from. Reading was already wired elsewhere; create/
 * edit/delete are new, verified live against disposable test packages
 * before shipping (create→edit→delete, cleaned up each time).
 */
export default function HostingPackages() {
  const { can } = usePermissions();
  const canManage = can('hosting.settings');
  const qc = useQueryClient();
  const [serverId, setServerId] = useState<string | null>(null);
  const [formOpen, setFormOpen] = useState(false);
  const [editing, setEditing] = useState<ServerPackageDetails | null>(null);

  const { data: serversData, isLoading: serversLoading } = useQuery({ queryKey: ['servers-for-discover'], queryFn: getServers });
  const servers = serversData?.data?.data ?? [];

  useEffect(() => {
    if (!serverId && servers.length > 0) setServerId(servers[0].id);
  }, [servers, serverId]);

  const { data, isLoading } = useQuery({
    queryKey: ['server-packages-detailed', serverId],
    queryFn: () => getServerPackagesDetailed(serverId!),
    enabled: !!serverId,
  });
  const packages = data?.data?.data ?? [];

  const invalidate = () => qc.invalidateQueries({ queryKey: ['server-packages-detailed', serverId] });

  const form = useForm<FormValues>({ initialValues: emptyForm });

  const openCreate = () => { setEditing(null); form.setValues(emptyForm); setFormOpen(true); };
  const openEdit = (p: ServerPackageDetails) => {
    setEditing(p);
    form.setValues({
      name: p.name,
      quota_mb: p.quota_mb ?? 0,
      bandwidth_mb: p.bandwidth_mb ?? 0,
      databases: p.databases ?? 0,
      email_accounts: p.email_accounts ?? 0,
      subdomains: p.subdomains ?? 0,
      ftp_accounts: p.ftp_accounts ?? 0,
      addon_domains: p.addon_domains ?? 0,
      parked_domains: p.parked_domains ?? 0,
    });
    setFormOpen(true);
  };
  const closeForm = () => { setFormOpen(false); setEditing(null); form.reset(); };

  const toLimits = (v: FormValues) => Object.fromEntries(
    LIMIT_FIELDS.map((f) => [f.key, v[f.key] === '' ? null : Number(v[f.key])])
  );

  const createMutation = useMutation({
    mutationFn: (v: FormValues) => createServerPackage(serverId!, { name: v.name, ...toLimits(v) }),
    onSuccess: (res) => {
      invalidate();
      notifications.show({ title: 'Created', message: `Package created as "${res.data.data.name}" (WHM prefixes it with your reseller username).`, color: 'green' });
      closeForm();
    },
    onError: (e: any) => notifications.show({ title: 'Error', message: e?.response?.data?.message ?? 'Failed to create.', color: 'red' }),
  });

  const updateMutation = useMutation({
    mutationFn: (v: FormValues) => updateServerPackage(serverId!, editing!.name, toLimits(v)),
    onSuccess: () => {
      invalidate();
      notifications.show({ title: 'Updated', message: 'Package updated.', color: 'green' });
      closeForm();
    },
    onError: (e: any) => notifications.show({ title: 'Error', message: e?.response?.data?.message ?? 'Failed to update.', color: 'red' }),
  });

  const deleteMutation = useMutation({
    mutationFn: (name: string) => deleteServerPackage(serverId!, name),
    onSuccess: () => {
      invalidate();
      notifications.show({ title: 'Deleted', message: 'Package deleted.', color: 'gray' });
    },
    onError: (e: any) => notifications.show({ title: 'Error', message: e?.response?.data?.message ?? 'Failed to delete — WHM refuses while any account still uses it.', color: 'red' }),
  });

  const handleDelete = (p: ServerPackageDetails) => modals.openConfirmModal({
    title: 'Delete Package',
    children: <Text size="sm">Delete package <Text span fw={600}>{p.name}</Text>? WHM refuses if any hosting account still uses it.</Text>,
    labels: { confirm: 'Delete', cancel: 'Cancel' },
    confirmProps: { color: 'red' },
    onConfirm: () => deleteMutation.mutate(p.name),
  });

  return (
    <Stack gap="md">
      <Group justify="space-between">
        <Title order={3}>
          <Group gap="xs"><IconPackage size={22} /> Hosting Packages</Group>
        </Title>
        {canManage && (
          <Button leftSection={<IconPlus size={16} />} onClick={openCreate} disabled={!serverId}>
            Add Package
          </Button>
        )}
      </Group>

      <Text size="sm" c="dimmed">
        Every WHM package on the server, with its real resource limits — the same catalog the
        Product/Service form's "cPanel Package" field picks from.
      </Text>

      <Paper withBorder p="sm" radius="sm">
        <Select
          label="Server" data={servers.map((s) => ({ value: s.id, label: s.name }))}
          value={serverId} onChange={setServerId} disabled={serversLoading} maw={300}
        />
      </Paper>

      <Paper withBorder radius="sm">
        {isLoading ? (
          <Center py="xl"><Loader /></Center>
        ) : packages.length === 0 ? (
          <Center py="xl"><Text c="dimmed">No packages found.</Text></Center>
        ) : (
          <Table.ScrollContainer minWidth={canManage ? 1000 : 900}>
            <Table striped highlightOnHover verticalSpacing="xs">
              <Table.Thead>
                <Table.Tr>
                  <Table.Th w={48}>#</Table.Th>
                  <Table.Th>Package</Table.Th>
                  <Table.Th>Disk Quota</Table.Th>
                  <Table.Th>Bandwidth</Table.Th>
                  <Table.Th>Databases</Table.Th>
                  <Table.Th>Email Accounts</Table.Th>
                  <Table.Th>Subdomains</Table.Th>
                  <Table.Th>FTP Accounts</Table.Th>
                  <Table.Th>Addon Domains</Table.Th>
                  <Table.Th>Parked Domains</Table.Th>
                  {canManage && <Table.Th w={80}>Actions</Table.Th>}
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {packages.map((p, i) => (
                  <Table.Tr key={p.name}>
                    <Table.Td c="dimmed">{i + 1}</Table.Td>
                    <Table.Td fw={500}>{p.name}</Table.Td>
                    <Table.Td>{limit(p.quota_mb, 'MB')}</Table.Td>
                    <Table.Td>{limit(p.bandwidth_mb, 'MB')}</Table.Td>
                    <Table.Td>{limit(p.databases, '')}</Table.Td>
                    <Table.Td>{limit(p.email_accounts, '')}</Table.Td>
                    <Table.Td>{limit(p.subdomains, '')}</Table.Td>
                    <Table.Td>{limit(p.ftp_accounts, '')}</Table.Td>
                    <Table.Td>{limit(p.addon_domains, '')}</Table.Td>
                    <Table.Td>{limit(p.parked_domains, '')}</Table.Td>
                    {canManage && (
                      <Table.Td>
                        <Group gap={4} wrap="nowrap">
                          <Tooltip label="Edit">
                            <ActionIcon variant="light" size="sm" onClick={() => openEdit(p)}>
                              <IconEdit size={14} />
                            </ActionIcon>
                          </Tooltip>
                          <Tooltip label="Delete">
                            <ActionIcon variant="light" color="red" size="sm" onClick={() => handleDelete(p)}>
                              <IconTrash size={14} />
                            </ActionIcon>
                          </Tooltip>
                        </Group>
                      </Table.Td>
                    )}
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        )}
      </Paper>

      <Modal opened={formOpen} onClose={closeForm} title={editing ? `Edit ${editing.name}` : 'Add Package'} size="md">
        <form onSubmit={form.onSubmit((v) => (editing ? updateMutation : createMutation).mutate(v))}>
          <Stack>
            {!editing && (
              <>
                <TextInput label="Package Name" required placeholder="e.g. business_hosting"
                  description="Letters, numbers, underscore only. WHM will prefix it with your reseller username."
                  {...form.getInputProps('name')} />
                <Alert color="blue" variant="light" icon={<IconInfoCircle size={16} />}>
                  Leave a limit blank to let WHM use its own default for that one.
                </Alert>
              </>
            )}
            {editing && (
              <Alert color="yellow" variant="light" icon={<IconInfoCircle size={16} />}>
                Every field is sent on save (WHM doesn't support setting a limit back to "unlimited"
                through an edit) — enter a real number for each.
              </Alert>
            )}
            <Group grow>
              {LIMIT_FIELDS.slice(0, 2).map((f) => (
                <NumberInput key={f.key} label={`${f.label}${f.unit ? ` (${f.unit})` : ''}`} min={0}
                  required={!!editing} {...form.getInputProps(f.key)} />
              ))}
            </Group>
            <Group grow>
              {LIMIT_FIELDS.slice(2, 4).map((f) => (
                <NumberInput key={f.key} label={f.label} min={0} required={!!editing} {...form.getInputProps(f.key)} />
              ))}
            </Group>
            <Group grow>
              {LIMIT_FIELDS.slice(4, 6).map((f) => (
                <NumberInput key={f.key} label={f.label} min={0} required={!!editing} {...form.getInputProps(f.key)} />
              ))}
            </Group>
            <Group grow>
              {LIMIT_FIELDS.slice(6, 8).map((f) => (
                <NumberInput key={f.key} label={f.label} min={0} required={!!editing} {...form.getInputProps(f.key)} />
              ))}
            </Group>
            <Group justify="flex-end">
              <Button variant="default" onClick={closeForm}>Cancel</Button>
              <Button type="submit" loading={createMutation.isPending || updateMutation.isPending}>
                {editing ? 'Save' : 'Create'}
              </Button>
            </Group>
          </Stack>
        </form>
      </Modal>
    </Stack>
  );
}
