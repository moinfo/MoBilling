import { Stack, Paper, Title, Table, Badge, Button, Text, Loader, Center, Alert } from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import { useNavigate } from 'react-router-dom';
import { getPortalLinodeServers } from '../../api/portal';

export default function PortalServers() {
  const navigate = useNavigate();
  const { data, isLoading } = useQuery({ queryKey: ['portal-linode-servers'], queryFn: getPortalLinodeServers });
  const rows = data?.data?.data ?? [];
  return (
    <Stack>
      <Title order={2}>My Servers</Title>
      {isLoading ? <Center h={160}><Loader /></Center> : rows.length === 0 ? (
        <Alert>You have no servers yet. Your Linode server will appear here once it is linked to your subscription.</Alert>
      ) : (
        <Paper withBorder p="md">
          <Table.ScrollContainer minWidth={520}>
            <Table striped>
              <Table.Thead><Table.Tr><Table.Th>Server</Table.Th><Table.Th>IP</Table.Th><Table.Th>Region</Table.Th><Table.Th>Status</Table.Th><Table.Th /></Table.Tr></Table.Thead>
              <Table.Tbody>
                {rows.map((s) => (
                  <Table.Tr key={s.id}>
                    <Table.Td><Text fw={600}>{s.name}</Text></Table.Td>
                    <Table.Td>{s.ip ?? '-'}</Table.Td>
                    <Table.Td>{s.region ?? '-'}</Table.Td>
                    <Table.Td><Badge variant="light" color={s.status === 'running' ? 'green' : 'gray'}>{s.status ?? '-'}</Badge></Table.Td>
                    <Table.Td><Button size="compact-sm" variant="light" onClick={() => navigate(`/portal/servers/${s.id}`)}>Manage</Button></Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        </Paper>
      )}
    </Stack>
  );
}
