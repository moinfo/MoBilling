import {
  Title, Text, SimpleGrid, Paper, Group, Badge, Table, Loader, Center,
  ThemeIcon, Stack,
} from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import {
  IconBuilding, IconUsers, IconMessage, IconCoin, IconClock, IconWallet,
} from '@tabler/icons-react';
import { getAdminDashboard, AdminDashboard } from '../../api/admin';

const statusColors: Record<string, string> = {
  pending: 'yellow',
  completed: 'green',
  failed: 'red',
};

export default function Dashboard() {
  const { data, isLoading } = useQuery({
    queryKey: ['admin-dashboard'],
    queryFn: getAdminDashboard,
  });

  const stats: AdminDashboard | undefined = data?.data;

  if (isLoading) {
    return <Center py="xl"><Loader /></Center>;
  }

  return (
    <>
      <Title order={2} mb="md">Dashboard</Title>
      <Text c="dimmed" mb="lg">Overview of tenants, users, and SMS activity.</Text>

      <SimpleGrid cols={{ base: 1, sm: 2, lg: 5 }} mb="xl">
        <StatCard
          icon={<IconWallet size={22} />}
          color="green"
          label="Master SMS Balance"
          value={stats?.master_sms_balance != null ? stats.master_sms_balance.toLocaleString() : '—'}
          description="Reseller account"
        />
        <StatCard
          icon={<IconBuilding size={22} />}
          color="blue"
          label="Tenants"
          value={`${stats?.active_tenants ?? 0} / ${stats?.total_tenants ?? 0}`}
          description="Active / Total"
        />
        <StatCard
          icon={<IconUsers size={22} />}
          color="violet"
          label="Total Users"
          value={String(stats?.total_users ?? 0)}
          description="Across all tenants"
        />
        <StatCard
          icon={<IconMessage size={22} />}
          color="teal"
          label="SMS Sold"
          value={(stats?.total_sms_sold ?? 0).toLocaleString()}
          description={`${stats?.sms_enabled_tenants ?? 0} SMS-enabled tenants`}
        />
        <StatCard
          icon={<IconCoin size={22} />}
          color="orange"
          label="SMS Revenue (TZS)"
          value={(stats?.total_sms_revenue ?? 0).toLocaleString()}
          description={`${stats?.pending_purchases ?? 0} pending`}
        />
      </SimpleGrid>

      <Paper withBorder p="lg">
        <Group mb="md">
          <IconClock size={20} />
          <Text fw={600}>Recent SMS Purchases</Text>
        </Group>

        <Table.ScrollContainer minWidth={600}>
          <Table striped highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Tenant</Table.Th>
                <Table.Th>User</Table.Th>
                <Table.Th>Quantity</Table.Th>
                <Table.Th>Amount (TZS)</Table.Th>
                <Table.Th>Status</Table.Th>
                <Table.Th>Date</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {stats?.recent_purchases?.map((p) => (
                <Table.Tr key={p.id}>
                  <Table.Td fw={500}>{p.tenant_name || '—'}</Table.Td>
                  <Table.Td>{p.user_name || '—'}</Table.Td>
                  <Table.Td>{p.sms_quantity.toLocaleString()}</Table.Td>
                  <Table.Td>{Number(p.total_amount).toLocaleString()}</Table.Td>
                  <Table.Td>
                    <Badge color={statusColors[p.status] || 'gray'} variant="light">
                      {p.status}
                    </Badge>
                  </Table.Td>
                  <Table.Td>{p.created_at}</Table.Td>
                </Table.Tr>
              ))}
              {(!stats?.recent_purchases || stats.recent_purchases.length === 0) && (
                <Table.Tr>
                  <Table.Td colSpan={6}>
                    <Text ta="center" c="dimmed" py="md">No purchases yet</Text>
                  </Table.Td>
                </Table.Tr>
              )}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      </Paper>
    </>
  );
}

function StatCard({ icon, color, label, value, description }: {
  icon: React.ReactNode;
  color: string;
  label: string;
  value: string;
  description: string;
}) {
  return (
    <Paper withBorder p="md">
      <Group>
        <ThemeIcon size="lg" radius="md" variant="light" color={color}>
          {icon}
        </ThemeIcon>
        <Stack gap={0}>
          <Text size="xs" c="dimmed" tt="uppercase" fw={600}>{label}</Text>
          <Text size="xl" fw={700}>{value}</Text>
          <Text size="xs" c="dimmed">{description}</Text>
        </Stack>
      </Group>
    </Paper>
  );
}
