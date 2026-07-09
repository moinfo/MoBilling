import { Card, SimpleGrid, Group, Text, ThemeIcon, Table, Badge, Anchor, Box } from '@mantine/core';
import {
  IconServer, IconPlayerPause, IconWorldWww, IconClockExclamation,
  IconWallet, IconTicket, IconRepeat, IconRepeatOff,
} from '@tabler/icons-react';
import { useNavigate } from 'react-router-dom';
import type { HostingDomainsSummary } from '../../api/dashboard';
import { usePermissions } from '../../hooks/usePermissions';
import classes from './Dashboard.module.css';

function Stat({ icon, color, label, value, hint, onClick }: {
  icon: React.ReactNode; color: string; label: string;
  value: number | string; hint?: string; onClick?: () => void;
}) {
  return (
    <Card withBorder padding="sm" radius="md" shadow="xs" className={classes.statCard}
      style={{ cursor: onClick ? 'pointer' : undefined, ['--stat-accent' as string]: `var(--mantine-color-${color}-6)` }}
      onClick={onClick}>
      <Group gap="sm" wrap="nowrap">
        <ThemeIcon variant="light" color={color} size={42} radius="md">{icon}</ThemeIcon>
        <div style={{ minWidth: 0 }}>
          <Text size="xl" fw={800} lh={1.15} truncate>{value}</Text>
          <Text size="xs" c="dimmed" truncate>{label}</Text>
          {hint && <Text size="xs" c={color} truncate>{hint}</Text>}
        </div>
      </Group>
    </Card>
  );
}

export default function HostingDomains({ data }: { data: HostingDomainsSummary }) {
  const navigate = useNavigate();
  const { can } = usePermissions();
  const credit = data.registrar_credit_total;
  const expiring = data.expiring_domains ?? [];
  // Only link a card through to its page if the viewer can actually open it
  // (the summary can be granted without the full menu permission).
  const go = (perm: string, path: string) => (can(perm) ? () => navigate(path) : undefined);
  const canDomainsPage = can('menu.domains');

  return (
    <Box>
      <div className={classes.sectionLabel} style={{ marginBottom: 12 }}>
        <Text fw={700} size="sm" tt="uppercase" c="dimmed" style={{ letterSpacing: 0.5 }}>Hosting &amp; Domains</Text>
      </div>
      <SimpleGrid cols={{ base: 2, sm: 3, lg: 6 }} spacing="sm" mb="md">
        {data.can.hosting && data.hosting && (
          <>
            <Stat icon={<IconServer size={20} />} color="teal" label="Active Hosting"
              value={data.hosting.active} hint={`${data.hosting.total} total`}
              onClick={go('menu.hosting', '/hosting')} />
            <Stat icon={<IconPlayerPause size={20} />} color="orange" label="Suspended"
              value={data.hosting.suspended} onClick={go('menu.hosting', '/hosting')} />
          </>
        )}
        {data.can.domains && data.domains && (
          <>
            <Stat icon={<IconWorldWww size={20} />} color="blue" label="Active Domains"
              value={data.domains.active} hint={`${data.domains.total} total`}
              onClick={go('menu.domains', '/domains')} />
            <Stat icon={<IconClockExclamation size={20} />} color="red" label="Expiring ≤ 45d"
              value={data.domains.expiring_soon} onClick={go('menu.domains', '/domains')} />
            <Stat icon={<IconWallet size={20} />} color="grape" label="Registrar Credit"
              value={credit == null ? '—' : `${credit.toLocaleString()}`}
              hint={credit == null ? undefined : 'TZS'} onClick={go('menu.domains', '/domains')} />
          </>
        )}
        {data.can.tickets && data.open_tickets != null && (
          <Stat icon={<IconTicket size={20} />} color="indigo" label="Open Tickets"
            value={data.open_tickets} onClick={go('menu.tickets', '/tickets')} />
        )}
      </SimpleGrid>

      {data.can.domains && expiring.length > 0 && (
        <Card withBorder padding="md" radius="md">
          <Group justify="space-between" mb="xs">
            <Text fw={600} size="sm">Domains Expiring Soon</Text>
            {canDomainsPage && <Anchor size="xs" onClick={() => navigate('/domains')}>View all</Anchor>}
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
                {expiring.map((d) => (
                  <Table.Tr key={d.id} style={{ cursor: canDomainsPage ? 'pointer' : 'default' }}
                    onClick={canDomainsPage ? () => navigate(`/domains/${d.id}`) : undefined}>
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
