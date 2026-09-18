import { useEffect, useState } from 'react';
import {
  Stack, Paper, Title, Text, Group, Table, Select, Center, Loader, Badge,
} from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import { IconPackage } from '@tabler/icons-react';
import { getServers, getServerPackagesDetailed } from '../api/hosting';

const limit = (v: number | null, unit: string) => (v === null ? <Badge size="sm" variant="light" color="teal">Unlimited</Badge> : `${v} ${unit}`);

/**
 * WHM's own packages (listpkgs), with their real resource limits — the
 * reference the Product/Service form's "cPanel Package" field draws from,
 * but never browsable on its own before. No new backend needed:
 * ServerController::packagesDetailed() and its WhmService plumbing already
 * existed, just never had a dedicated page.
 */
export default function HostingPackages() {
  const [serverId, setServerId] = useState<string | null>(null);

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

  return (
    <Stack gap="md">
      <Title order={3}>
        <Group gap="xs"><IconPackage size={22} /> Hosting Packages</Group>
      </Title>

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
          <Table.ScrollContainer minWidth={900}>
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
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        )}
      </Paper>
    </Stack>
  );
}
