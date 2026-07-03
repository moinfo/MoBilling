import { useState } from 'react';
import {
  Stack, Paper, Title, Table, Badge, LoadingOverlay, Button, Text, Group, Code,
} from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { useQuery } from '@tanstack/react-query';
import { IconExternalLink, IconWorld } from '@tabler/icons-react';
import { getPortalHosting, portalHostingSso, PortalHostingAccount } from '../../api/portal';
import { useAuth } from '../../context/AuthContext';

const fmtDate = (d: string | null) =>
  d ? new Date(d).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' }) : '-';

const statusColor: Record<string, string> = {
  pending: 'blue', active: 'green', suspended: 'orange', failed: 'red',
};

export default function PortalHosting() {
  const { user } = useAuth();
  const [openingId, setOpeningId] = useState<string | null>(null);
  const isPortalAdmin = (user as any)?.role === 'admin';

  const { data, isLoading } = useQuery({
    queryKey: ['portal-hosting'],
    queryFn: getPortalHosting,
  });
  const accounts: PortalHostingAccount[] = data?.data?.data ?? [];

  const openCpanel = async (id: string) => {
    setOpeningId(id);
    try {
      const res = await portalHostingSso(id);
      window.open(res.data.url, '_blank', 'noopener');
    } catch (e: any) {
      notifications.show({
        title: 'cPanel login failed',
        message: e?.response?.data?.message ?? 'Could not open cPanel. Please try again later.',
        color: 'red',
      });
    } finally {
      setOpeningId(null);
    }
  };

  return (
    <Stack>
      <Group gap="xs">
        <IconWorld size={22} />
        <Title order={3}>My Hosting</Title>
      </Group>

      <Paper withBorder radius="md" pos="relative">
        <LoadingOverlay visible={isLoading} />
        {!isLoading && accounts.length === 0 ? (
          <Text c="dimmed" size="sm" p="lg">You have no hosting accounts.</Text>
        ) : (
          <Table.ScrollContainer minWidth={640}>
            <Table highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Domain</Table.Th>
                  <Table.Th>Username</Table.Th>
                  <Table.Th>Package</Table.Th>
                  <Table.Th>Disk</Table.Th>
                  <Table.Th>Renews</Table.Th>
                  <Table.Th>Status</Table.Th>
                  <Table.Th></Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {accounts.map((a) => (
                  <Table.Tr key={a.id}>
                    <Table.Td fw={500}>{a.domain}</Table.Td>
                    <Table.Td><Code>{a.cpanel_username}</Code></Table.Td>
                    <Table.Td>{a.package ?? '—'}</Table.Td>
                    <Table.Td>
                      <Text size="xs" c="dimmed">
                        {a.disk_used ? `${a.disk_used} / ${a.disk_limit ?? '∞'}` : '—'}
                      </Text>
                    </Table.Td>
                    <Table.Td><Text size="sm">{fmtDate(a.expires_at)}</Text></Table.Td>
                    <Table.Td>
                      <Badge size="sm" color={statusColor[a.status] ?? 'gray'} variant="light">
                        {a.status}
                      </Badge>
                    </Table.Td>
                    <Table.Td>
                      {isPortalAdmin && a.status === 'active' && (
                        <Button size="xs" variant="light"
                          leftSection={<IconExternalLink size={13} />}
                          loading={openingId === a.id}
                          onClick={() => openCpanel(a.id)}>
                          Login to cPanel
                        </Button>
                      )}
                      {a.status === 'suspended' && (
                        <Text size="xs" c="orange">Suspended — please settle any unpaid invoices.</Text>
                      )}
                    </Table.Td>
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
