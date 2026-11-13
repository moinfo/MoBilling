import { Box, Text, SimpleGrid, Card, Group, ThemeIcon } from '@mantine/core';
import { IconRouter, IconTicket, IconCash, IconUsers, IconClockDollar } from '@tabler/icons-react';
import { useQuery } from '@tanstack/react-query';
import { getWifiDashboardSummary } from '../../api/wifiEarnings';
import { usePermissions } from '../../hooks/usePermissions';
import { formatCurrency } from '../../utils/formatCurrency';
import classes from './Dashboard.module.css';

/**
 * A wifi-hotspot-only tenant has none of the dashboard.* permissions every
 * other widget on this page needs — without this, their dashboard is just
 * blank. Self-service, fetched independently of GET /dashboard-summary
 * (same pattern as MyMonth/MyPayroll), gated on wifi_purchases.read.
 */
export default function WifiHotspotSummary() {
  const { can } = usePermissions();
  const { data } = useQuery({
    queryKey: ['wifi-dashboard-summary'],
    queryFn: getWifiDashboardSummary,
    enabled: can('wifi_purchases.read'),
  });
  const s = data?.data?.data;

  if (!can('wifi_purchases.read') || !s) return null;

  const cards = [
    { title: 'Active Routers', value: String(s.active_routers), icon: IconRouter, color: 'orange' },
    { title: 'Vouchers Sold', value: String(s.vouchers_sold), icon: IconTicket, color: 'blue' },
    { title: 'Total Revenue', value: formatCurrency(s.total_revenue), icon: IconCash, color: 'green' },
    { title: 'Unique Customers', value: String(s.unique_customers), icon: IconUsers, color: 'teal' },
    ...(s.owed > 0 ? [{ title: 'Owed to You (unsettled)', value: formatCurrency(s.owed), icon: IconClockDollar, color: 'red' }] : []),
  ];

  return (
    <Box>
      <div className={classes.sectionLabel} style={{ marginBottom: 12 }}>
        <Text fw={700} size="sm" tt="uppercase" c="dimmed" style={{ letterSpacing: 0.5 }}>
          WiFi Hotspot
        </Text>
      </div>
      <SimpleGrid cols={{ base: 2, sm: 3, lg: 5 }} spacing="md">
        {cards.map((card) => (
          <Card key={card.title} withBorder padding="md" radius="md" shadow="xs"
            className={classes.statCard}
            style={{ ['--stat-accent' as string]: `var(--mantine-color-${card.color}-6)` }}>
            <Group justify="space-between" wrap="nowrap" gap="sm" align="flex-start">
              <div style={{ minWidth: 0 }}>
                <Text size="xs" c="dimmed" tt="uppercase" fw={700} truncate>{card.title}</Text>
                <Text fw={800} mt={6} lh={1.1} truncate style={{ fontSize: 'clamp(1.2rem, 2.2vw, 1.55rem)' }}>
                  {card.value}
                </Text>
              </div>
              <ThemeIcon variant="light" color={card.color} size={44} radius="md" style={{ flexShrink: 0 }}>
                <card.icon size={23} />
              </ThemeIcon>
            </Group>
          </Card>
        ))}
      </SimpleGrid>
    </Box>
  );
}
