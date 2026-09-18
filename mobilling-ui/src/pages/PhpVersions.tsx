import { useMemo, useState } from 'react';
import {
  Stack, Paper, Title, Text, Group, Table, Select, Center, Loader, Alert, Badge,
} from '@mantine/core';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { IconBrandPhp, IconAlertTriangle } from '@tabler/icons-react';
import { discoverHostingAccounts, getPhpVersions, updatePhpVersion, DiscoveredAccount, PhpVhostRow } from '../api/hosting';
import { usePermissions } from '../hooks/usePermissions';

/** "ea-php83" -> "PHP 8.3", "alt-php74" -> "PHP 7.4 (CloudLinux)" */
export function phpVersionLabel(raw: string): string {
  const m = raw.match(/^(ea|alt)-php(\d)(\d)$/);
  if (!m) return raw;
  const [, stack, major, minor] = m;
  return `PHP ${major}.${minor}${stack === 'alt' ? ' (CloudLinux)' : ''}`;
}

export default function PhpVersions() {
  const { can } = usePermissions();
  const canManage = can('hosting.change_package');
  const qc = useQueryClient();
  const [selected, setSelected] = useState<string | null>(null);

  const { data: accountsData, isLoading: accountsLoading } = useQuery({
    queryKey: ['discover-hosting', undefined, 'all'],
    queryFn: () => discoverHostingAccounts({}),
    staleTime: 60_000,
  });
  const accounts: DiscoveredAccount[] = accountsData?.data?.data ?? [];

  const options = useMemo(() => accounts
    .slice()
    .sort((a, b) => (a.domain ?? '').localeCompare(b.domain ?? ''))
    .map((a) => ({
      value: `${a.server_id}|${a.cpanel_username}`,
      label: `${a.domain ?? a.cpanel_username}${a.client ? ` — ${a.client.name}` : ''}`,
    })), [accounts]);

  const [serverId, cpanelUsername] = selected ? selected.split('|') : [null, null];

  const { data: phpData, isLoading: phpLoading, isError } = useQuery({
    queryKey: ['php-versions', serverId, cpanelUsername],
    queryFn: () => getPhpVersions({ server_id: serverId!, cpanel_username: cpanelUsername! }),
    enabled: !!serverId && !!cpanelUsername,
  });
  const vhosts = phpData?.data?.data ?? [];
  const installed = phpData?.data?.installed ?? [];

  const versionOptions = useMemo(() => installed
    .slice()
    .sort()
    .reverse()
    .map((v) => ({ value: v, label: phpVersionLabel(v) })), [installed]);

  const mutation = useMutation({
    mutationFn: (vars: { vhost: string; version: string }) =>
      updatePhpVersion({ server_id: serverId!, cpanel_username: cpanelUsername!, ...vars }),
    onSuccess: (_res, vars) => {
      qc.invalidateQueries({ queryKey: ['php-versions', serverId, cpanelUsername] });
      notifications.show({ title: 'Updated', message: `${vars.vhost} is now on ${phpVersionLabel(vars.version)}.`, color: 'green' });
    },
    onError: (e: any) => notifications.show({ title: 'Error', message: e?.response?.data?.message ?? 'Failed to change the PHP version.', color: 'red' }),
  });

  const confirmChange = (row: PhpVhostRow, newVersion: string) => modals.openConfirmModal({
    title: 'Change PHP version',
    children: (
      <Text size="sm">
        Change <Text span fw={600}>{row.vhost}</Text> from {phpVersionLabel(row.version ?? '')} to{' '}
        <Text span fw={600}>{phpVersionLabel(newVersion)}</Text>? If the site's code isn't compatible
        with this version, it may break until changed back.
      </Text>
    ),
    labels: { confirm: 'Change it', cancel: 'Cancel' },
    confirmProps: { color: 'orange' },
    onConfirm: () => mutation.mutate({ vhost: row.vhost!, version: newVersion }),
  });

  return (
    <Stack gap="md">
      <Title order={3}>
        <Group gap="xs"><IconBrandPhp size={22} /> PHP Version</Group>
      </Title>

      <Text size="sm" c="dimmed">
        Pick a hosting account to see and change the PHP version for its domains and subdomains,
        without needing to log into cPanel.
      </Text>

      <Paper withBorder p="sm" radius="sm">
        <Select
          label="Hosting account" placeholder="Search domain or client…" searchable clearable
          data={options} value={selected} onChange={setSelected}
          disabled={accountsLoading}
          rightSection={accountsLoading ? <Loader size="xs" /> : undefined}
          maw={500}
        />
      </Paper>

      {selected && (
        <Paper withBorder radius="sm">
          {phpLoading ? (
            <Center py="xl"><Loader /></Center>
          ) : isError ? (
            <Alert color="red" variant="light" icon={<IconAlertTriangle size={16} />} m="sm">
              Could not load PHP versions for {cpanelUsername}.
            </Alert>
          ) : vhosts.length === 0 ? (
            <Center py="xl"><Text c="dimmed">No domains found for {cpanelUsername}.</Text></Center>
          ) : (
            <Table.ScrollContainer minWidth={600}>
              <Table striped highlightOnHover verticalSpacing="xs">
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th>Domain</Table.Th>
                    <Table.Th>Current Version</Table.Th>
                    {canManage && <Table.Th w={220}>Change to</Table.Th>}
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {vhosts.map((v) => (
                    <Table.Tr key={v.vhost}>
                      <Table.Td>
                        {v.vhost}
                        {v.main_domain && <Badge ml={6} size="xs" variant="light" color="blue">Main</Badge>}
                      </Table.Td>
                      <Table.Td fz="sm">{v.version ? phpVersionLabel(v.version) : '—'}</Table.Td>
                      {canManage && (
                        <Table.Td>
                          <Select
                            size="xs" data={versionOptions} value={v.version}
                            disabled={mutation.isPending}
                            onChange={(val) => val && val !== v.version && confirmChange(v, val)}
                          />
                        </Table.Td>
                      )}
                    </Table.Tr>
                  ))}
                </Table.Tbody>
              </Table>
            </Table.ScrollContainer>
          )}
        </Paper>
      )}
    </Stack>
  );
}
