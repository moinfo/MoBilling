import { useState } from 'react';
import {
  Stack, SimpleGrid, Paper, Text, Badge, LoadingOverlay, Group, Title, Button,
  TextInput, Divider, NavLink, Grid, Tooltip,
} from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import {
  IconServer, IconWorldWww, IconTicket, IconReceipt, IconUser, IconPencil,
  IconShoppingCart, IconLogout, IconExternalLink, IconRefresh, IconBox,
  IconMessageCircle, IconPlus, IconUsers, IconFileInvoice, IconCash,
  IconAlertTriangle, IconClock,
} from '@tabler/icons-react';
import { useNavigate } from 'react-router-dom';
import { getPortalDashboard, portalHostingSso } from '../../api/portal';
import { useAuth } from '../../context/AuthContext';

const fmt = (n: number) => n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });

const serviceStatusColor: Record<string, string> = {
  active: 'green', pending: 'blue', suspended: 'gray', cancelled: 'red',
};

export default function PortalDashboard() {
  const { user, logout } = useAuth();
  const navigate = useNavigate();
  const [domainQuery, setDomainQuery] = useState('');
  const [ssoLoading, setSsoLoading] = useState<string | null>(null);

  const { data, isLoading } = useQuery({
    queryKey: ['portal-dashboard'],
    queryFn: () => getPortalDashboard(),
  });
  const d: any = data?.data;

  const openCpanel = async (hostingAccountId: string) => {
    setSsoLoading(hostingAccountId);
    try {
      const res = await portalHostingSso(hostingAccountId);
      window.open(res.data.url, '_blank', 'noopener');
    } catch (e: any) {
      notifications.show({ message: e?.response?.data?.message ?? 'Could not open cPanel.', color: 'red' });
    } finally {
      setSsoLoading(null);
    }
  };

  const searchDomain = (action: 'register' | 'transfer') => {
    const name = domainQuery.trim().toLowerCase();
    navigate(`/portal/domains${name ? `?order=${action}&name=${encodeURIComponent(name)}` : `?order=${action}`}`);
  };

  const handleLogout = async () => {
    await logout();
    navigate('/login');
  };

  return (
    <Stack gap="lg" pos="relative">
      <LoadingOverlay visible={isLoading} />
      <Title order={3}>Welcome, {user?.name}</Title>

      {d && (
        <>
          {/* 1 ── Stats row */}
          <SimpleGrid cols={{ base: 2, md: 4 }}>
            <StatTile label="Services" value={d.services_count ?? 0} color="blue"
              icon={<IconServer size={40} />} onClick={() => navigate('/portal/subscriptions')} />
            <StatTile label="Domains" value={d.domains_count ?? 0} color="green"
              icon={<IconWorldWww size={40} />} onClick={() => navigate('/portal/domains')} />
            <StatTile label="Tickets" value={d.tickets_count ?? 0} color="red"
              icon={<IconTicket size={40} />} />
            <StatTile label="Invoices" value={d.unpaid_invoices_count ?? 0} color="orange"
              icon={<IconReceipt size={40} />} onClick={() => navigate('/portal/invoices')} />
          </SimpleGrid>

          <Grid gutter="lg">
            {/* ── Main column ── */}
            <Grid.Col span={{ base: 12, md: 8 }}>
              <Stack gap="lg">
                {/* 5 ── Active Products/Services */}
                <Paper withBorder radius="md" p="lg">
                  <Group justify="space-between" mb="sm">
                    <Group gap="xs"><IconBox size={18} /><Text fw={700}>Your Active Products/Services</Text></Group>
                    <Button size="xs" color="orange" variant="light"
                      onClick={() => navigate('/portal/subscriptions')}>
                      My Services
                    </Button>
                  </Group>
                  <Divider mb="xs" />
                  {(d.recent_services ?? []).length === 0 ? (
                    <Text c="dimmed" size="sm" py="md" ta="center">No services yet.</Text>
                  ) : (
                    <Stack gap={0}>
                      {d.recent_services.map((s: any, i: number) => (
                        <Group key={s.id} justify="space-between" wrap="nowrap" py="sm"
                          style={{ borderBottom: i < d.recent_services.length - 1 ? '1px solid var(--mantine-color-default-border)' : undefined }}>
                          <Group gap="sm" wrap="nowrap" style={{ minWidth: 0 }}>
                            <Badge size="sm" color={serviceStatusColor[s.status] ?? 'gray'} variant="filled" radius="xl">
                              {s.status}
                            </Badge>
                            <div style={{ minWidth: 0 }}>
                              <Text size="sm" fw={600} truncate>{s.product}</Text>
                              {s.label && <Text size="xs" c="dimmed" truncate>{s.label}</Text>}
                            </div>
                          </Group>
                          <Group gap="xs" wrap="nowrap">
                            {s.hosting_account_id && (
                              <Button size="xs" variant="filled" color="blue"
                                leftSection={<IconExternalLink size={12} />}
                                loading={ssoLoading === s.hosting_account_id}
                                onClick={() => openCpanel(s.hosting_account_id)}>
                                Log in to cPanel
                              </Button>
                            )}
                            <Button size="xs" variant="default"
                              onClick={() => navigate('/portal/subscriptions')}>
                              View Details
                            </Button>
                          </Group>
                        </Group>
                      ))}
                    </Stack>
                  )}
                  <Group justify="flex-end" mt="xs">
                    <Text size="xs" c="blue" style={{ cursor: 'pointer' }}
                      onClick={() => navigate('/portal/subscriptions')}>View More…</Text>
                  </Group>
                </Paper>

                {/* 6 ── Domains expiring soon */}
                {(d.expiring_domains_count ?? 0) > 0 && (
                  <Paper withBorder radius="md" p="lg">
                    <Group justify="space-between" mb="xs">
                      <Group gap="xs"><IconWorldWww size={18} /><Text fw={700}>Domains Expiring Soon</Text></Group>
                      <Button size="xs" color="dark" radius="xl" leftSection={<IconRefresh size={13} />}
                        onClick={() => navigate('/portal/domains')}>
                        Renew Now
                      </Button>
                    </Group>
                    <Text size="sm" c="dimmed">
                      You have {d.expiring_domains_count} domain(s) expiring within the next 45 days.
                      Renew them today for peace of mind.
                    </Text>
                  </Paper>
                )}

                {/* 7 ── Register a new domain */}
                <Paper withBorder radius="md" p="lg">
                  <Group gap="xs" mb="sm"><IconWorldWww size={18} /><Text fw={700}>Register a New Domain</Text></Group>
                  <Group gap={0} wrap="nowrap">
                    <TextInput
                      placeholder="yourdomain.co.tz"
                      value={domainQuery}
                      onChange={(e) => setDomainQuery(e.currentTarget.value)}
                      style={{ flex: 1 }}
                      styles={{ input: { borderTopRightRadius: 0, borderBottomRightRadius: 0 } }}
                      onKeyDown={(e) => e.key === 'Enter' && searchDomain('register')}
                    />
                    <Button color="green" radius={0} onClick={() => searchDomain('register')}>Register</Button>
                    <Button variant="default" style={{ borderTopLeftRadius: 0, borderBottomLeftRadius: 0 }}
                      onClick={() => searchDomain('transfer')}>Transfer</Button>
                  </Group>
                </Paper>

                {/* Money summary */}
                <SimpleGrid cols={{ base: 2, md: 4 }}>
                  <MiniStat label="Total Invoiced" value={fmt(d.total_invoiced)} icon={<IconFileInvoice size={20} />} color="blue" />
                  <MiniStat label="Total Paid" value={fmt(d.total_paid)} icon={<IconCash size={20} />} color="green" />
                  <MiniStat label="Balance" value={fmt(d.total_balance)} icon={<IconAlertTriangle size={20} />} color="orange" />
                  <MiniStat label="Overdue" value={String(d.overdue_count)} icon={<IconClock size={20} />} color="red" />
                </SimpleGrid>
              </Stack>
            </Grid.Col>

            {/* ── Side column ── */}
            <Grid.Col span={{ base: 12, md: 4 }}>
              <Stack gap="lg">
                {/* 2 ── Your Info */}
                <Paper withBorder radius="md" p="lg">
                  <Group gap="xs" mb="sm"><IconUser size={18} /><Text fw={700}>Your Info</Text></Group>
                  <Text fw={700} size="sm">{d.client_info?.company ?? '—'}</Text>
                  <Text size="sm" fs="italic" c="dimmed">{d.client_info?.contact}</Text>
                  {d.client_info?.address && <Text size="sm" c="dimmed" mt={4}>{d.client_info.address}</Text>}
                  {d.client_info?.email && <Text size="xs" c="dimmed" mt={2}>{d.client_info.email}</Text>}
                  <Button fullWidth color="green" mt="md" leftSection={<IconPencil size={14} />}
                    onClick={() => navigate('/portal/profile')}>
                    Update
                  </Button>
                </Paper>

                {/* 3 ── Contacts */}
                <Paper withBorder radius="md" p="lg">
                  <Group gap="xs" mb="sm"><IconUsers size={18} /><Text fw={700}>Contacts</Text></Group>
                  {(d.contacts ?? []).length === 0 ? (
                    <Text size="sm" c="dimmed" ta="center" py="xs">No Contacts Found</Text>
                  ) : (
                    <Stack gap={4}>
                      {d.contacts.map((c: any) => (
                        <Group key={c.id} justify="space-between">
                          <div>
                            <Text size="sm" fw={500}>{c.name}</Text>
                            <Text size="xs" c="dimmed">{c.email}</Text>
                          </div>
                          <Badge size="xs" variant="light">{c.role}</Badge>
                        </Group>
                      ))}
                    </Stack>
                  )}
                  <Button fullWidth variant="outline" mt="md" leftSection={<IconPlus size={14} />}
                    onClick={() => navigate('/portal/users')}>
                    New Contact…
                  </Button>
                </Paper>

                {/* 4 ── Shortcuts */}
                <Paper withBorder radius="md" p="xs">
                  <Text fw={700} px="md" pt="sm" pb="xs">Shortcuts</Text>
                  <NavLink label="Order New Services" leftSection={<IconShoppingCart size={16} />}
                    onClick={() => navigate('/portal/products-services')} />
                  <NavLink label="Register a New Domain" leftSection={<IconWorldWww size={16} />}
                    onClick={() => navigate('/portal/domains?order=register')} />
                  <NavLink label="Logout" leftSection={<IconLogout size={16} />} onClick={handleLogout} />
                </Paper>

                {/* 8 ── Recent Support Tickets */}
                <Paper withBorder radius="md" p="lg">
                  <Group justify="space-between" mb="sm">
                    <Group gap="xs"><IconMessageCircle size={18} /><Text fw={700}>Recent Support Tickets</Text></Group>
                    <Tooltip label="Ticketing is coming soon — contact us by email or phone for now">
                      <Button size="xs" variant="light" leftSection={<IconPlus size={12} />} disabled>
                        Open New Ticket
                      </Button>
                    </Tooltip>
                  </Group>
                  {(d.recent_tickets ?? []).length === 0 && (
                    <Text size="sm" c="dimmed" ta="center" py="xs">No Recent Tickets Found</Text>
                  )}
                </Paper>
              </Stack>
            </Grid.Col>
          </Grid>
        </>
      )}
    </Stack>
  );
}

/* Stats tile: big colored number, uppercase label, large faded icon right, colored bottom border */
function StatTile({ label, value, icon, color, onClick }: {
  label: string; value: number; icon: React.ReactNode; color: string; onClick?: () => void;
}) {
  return (
    <Paper withBorder radius="md" p="lg" onClick={onClick}
      style={{ cursor: onClick ? 'pointer' : undefined, borderBottom: `3px solid var(--mantine-color-${color}-6)` }}>
      <Group justify="space-between" align="center" wrap="nowrap">
        <div>
          <Text fz={28} fw={800} c={`${color}.6`} lh={1.2}>{value}</Text>
          <Text size="xs" c="dimmed" tt="uppercase" fw={600} mt={4}>{label}</Text>
        </div>
        <Text c="gray.3" style={{ display: 'flex' }}>{icon}</Text>
      </Group>
    </Paper>
  );
}

function MiniStat({ label, value, icon, color }: {
  label: string; value: string; icon: React.ReactNode; color: string;
}) {
  return (
    <Paper withBorder radius="md" p="md">
      <Group gap="xs" wrap="nowrap">
        <Text c={color} style={{ display: 'flex' }}>{icon}</Text>
        <div style={{ minWidth: 0 }}>
          <Text size="sm" fw={700} truncate>{value}</Text>
          <Text size="xs" c="dimmed">{label}</Text>
        </div>
      </Group>
    </Paper>
  );
}
