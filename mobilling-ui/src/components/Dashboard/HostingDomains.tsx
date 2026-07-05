import { Card, SimpleGrid, Group, Text, ThemeIcon, Table, Badge, Anchor, Box } from '@mantine/core';
import {
  IconServer, IconPlayerPause, IconWorldWww, IconClockExclamation,
  IconWallet, IconTicket, IconRepeat, IconRepeatOff,
} from '@tabler/icons-react';
import { useNavigate } from 'react-router-dom';
import type { HostingDomainsSummary } from '../../api/dashboard';

function Stat({ icon, color, label, value, hint, onClick }: {
  icon: React.ReactNode; color: string; label: string;
  value: number | string; hint?: string; onClick?: () => void;
}) {
  return (
    <Card withBorder padding="sm" radius="md"
      style={{ cursor: onClick ? 'pointer' : undefined }} onClick={onClick}>
      <Group gap="sm" wrap="nowrap">
        <ThemeIcon variant="light" color={color} size={40} radius="md">{icon}</ThemeIcon>
        <div style={{ minWidth: 0 }}>
          <Text size="xl" fw={700} lh={1.15} truncate>{value}</Text>
          <Text size="xs" c="dimmed" truncate>{label}</Text>
          {hint && <Text size="xs" c={color} truncate>{hint}</Text>}
        </div>
      </Group>
    </Card>
  );
}

export default function HostingDomains({ data }: { data: HostingDomainsSummary }) {
  const navigate = useNavigate();
  const credit = data.registrar_credit_total;

  return (
    <Box>
      <Text fw={600} mb="xs">Hosting & Domains</Text>
      <SimpleGrid cols={{ base: 2, sm: 3, lg: 6 }} spacing="sm" mb="md">
        <Stat icon={<IconServer size={20} />} color="teal" label="Active Hosting"
          value={data.hosting.active} hint={`${data.hosting.total} total`}
          onClick={() => navigate('/hosting')} />
        <Stat icon={<IconPlayerPause size={20} />} color="orange" label="Suspended"
          value={data.hosting.suspended} onClick={() => navigate('/hosting')} />
        <Stat icon={<IconWorldWww size={20} />} color="blue" label="Active Domains"
          value={data.domains.active} hint={`${data.domains.total} total`}
          onClick={() => navigate('/domains')} />
        <Stat icon={<IconClockExclamation size={20} />} color="red" label="Expiring ≤ 45d"
          value={data.domains.expiring_soon} onClick={() => navigate('/domains')} />
        <Stat icon={<IconWallet size={20} />} color="grape" label="Registrar Credit"
          value={credit == null ? '—' : `${credit.toLocaleString()}`}
          hint={credit == null ? undefined : 'TZS'} onClick={() => navigate('/domains')} />
        <Stat icon={<IconTicket size={20} />} color="indigo" label="Open Tickets"
          value={data.open_tickets} onClick={() => navigate('/tickets')} />
      </SimpleGrid>

      {data.expiring_domains.length > 0 && (
        <Card withBorder padding="md" radius="md">
          <Group justify="space-between" mb="xs">
            <Text fw={600} size="sm">Domains Expiring Soon</Text>
            <Anchor size="xs" onClick={() => navigate('/domains')}>View all</Anchor>
          </Group>
          <Table.ScrollContainer minWidth={480}>
            <Table verticalSpacing={6}>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Domain</Table.Th>
                  <Table.Th>Client</Table.Th>
                  <Table.Th>Expires</Table.Th>
                  <Table.Th>Auto-renew</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {data.expiring_domains.map((d) => (
                  <Table.Tr key={d.id} style={{ cursor: 'pointer' }}
                    onClick={() => navigate(`/domains/${d.id}`)}>
                    <Table.Td fw={500}>{d.name}</Table.Td>
                    <Table.Td>{d.client_name ?? '—'}</Table.Td>
                    <Table.Td>
                      <Badge size="sm" variant="light"
                        color={d.days_left <= 7 ? 'red' : d.days_left <= 30 ? 'orange' : 'yellow'}>
                        {d.days_left <= 0 ? 'expired' : `${d.days_left}d`}
                      </Badge>
                    </Table.Td>
                    <Table.Td>
                      {d.auto_renew
                        ? <Badge size="sm" color="teal" variant="light" leftSection={<IconRepeat size={11} />}>On</Badge>
                        : <Badge size="sm" color="gray" variant="light" leftSection={<IconRepeatOff size={11} />}>Off</Badge>}
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        </Card>
      )}
    </Box>
  );
}
