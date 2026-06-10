import { Card, Text, Group, Stack, Divider, Box, ThemeIcon, Progress, Badge } from '@mantine/core';
import { IconDatabase } from '@tabler/icons-react';
import { formatCurrency } from '../../utils/formatCurrency';
import type { SystemRecordsBreakdown as Breakdown } from '../../api/dashboard';

export default function SystemRecordsBreakdown({
  data,
  periodLabel,
}: {
  data: Breakdown;
  periodLabel: string;
}) {
  const hasData = data.systems.length > 0;

  return (
    <Card withBorder padding="lg" radius="md">
      {/* Header */}
      <Group justify="space-between" align="flex-start" mb="lg">
        <Group gap="sm">
          <ThemeIcon size="xl" variant="light" color="blue" radius="md">
            <IconDatabase size={22} />
          </ThemeIcon>
          <Box>
            <Text fw={700} size="md">System Records</Text>
            <Text size="xs" c="dimmed" tt="uppercase" fw={500} style={{ letterSpacing: 0.5 }}>
              {periodLabel}
            </Text>
          </Box>
        </Group>
        <Box ta="right">
          <Text size="xs" c="dimmed" tt="uppercase" fw={700} style={{ letterSpacing: 0.8 }}>
            Total
          </Text>
          <Text fw={800} size="22px" c="blue.7" lh={1.2}>
            {formatCurrency(data.total)}
          </Text>
        </Box>
      </Group>

      <Divider mb="lg" />

      {/* Content */}
      {!hasData ? (
        <Box ta="center" py="xl">
          <ThemeIcon size="xl" variant="light" color="gray" radius="xl" mb="sm">
            <IconDatabase size={22} />
          </ThemeIcon>
          <Text c="dimmed" size="sm">No system records recorded this month.</Text>
        </Box>
      ) : (
        <Stack gap="md">
          {data.systems.map((sys) => {
            const systemPct = data.total > 0 ? (sys.subtotal / data.total) * 100 : 0;
            return (
              <Box key={sys.name}>
                {/* System headline row */}
                <Group justify="space-between" mb={6} wrap="nowrap">
                  <Group gap={8} wrap="nowrap" style={{ minWidth: 0 }}>
                    <Badge variant="filled" color="blue" size="md" radius="sm">
                      {sys.name}
                    </Badge>
                    <Text size="xs" c="dimmed" fw={600}>
                      {systemPct.toFixed(1)}%
                    </Text>
                  </Group>
                  <Text fw={700} size="md" style={{ whiteSpace: 'nowrap' }}>
                    {formatCurrency(sys.subtotal)}
                  </Text>
                </Group>

                {/* Proportion bar — instant visual share-of-total */}
                <Progress value={systemPct} size="xs" color="blue" radius="xl" mb="xs" />

                {/* Property breakdown — indented with a left guide line for clear hierarchy */}
                <Stack gap={2} pl="sm" mt={4}
                  style={{ borderLeft: '2px solid var(--mantine-color-gray-2)' }}
                >
                  {sys.properties.map((prop) => {
                    const propPct = sys.subtotal > 0 ? (prop.total / sys.subtotal) * 100 : 0;
                    return (
                      <Group key={prop.name} justify="space-between" pl="sm" py={2} wrap="nowrap">
                        <Group gap={6} wrap="nowrap" style={{ minWidth: 0 }}>
                          <Text size="sm" c="gray.7" fw={500} truncate>
                            {prop.name}
                          </Text>
                          <Text size="xs" c="dimmed">·</Text>
                          <Text size="xs" c="dimmed">{propPct.toFixed(0)}%</Text>
                        </Group>
                        <Text size="sm" c="gray.8" fw={500} style={{ whiteSpace: 'nowrap' }}>
                          {formatCurrency(prop.total)}
                        </Text>
                      </Group>
                    );
                  })}
                </Stack>
              </Box>
            );
          })}
        </Stack>
      )}
    </Card>
  );
}
