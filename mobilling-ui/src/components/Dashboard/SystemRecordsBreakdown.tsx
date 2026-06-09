import { Card, Text, Group, Stack, Divider, Badge, Box } from '@mantine/core';
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
    <Card withBorder padding="lg">
      <Group justify="space-between" align="flex-start" mb="md">
        <Group gap="xs">
          <IconDatabase size={20} />
          <Box>
            <Text fw={600}>System Records</Text>
            <Text size="xs" c="dimmed">{periodLabel}</Text>
          </Box>
        </Group>
        <Box ta="right">
          <Text size="xs" c="dimmed" tt="uppercase" fw={600} style={{ letterSpacing: 0.5 }}>
            Total
          </Text>
          <Text fw={700} size="xl" c="blue.7">
            {formatCurrency(data.total)}
          </Text>
        </Box>
      </Group>

      <Divider mb="md" />

      {!hasData ? (
        <Text c="dimmed" size="sm">No system records recorded this month.</Text>
      ) : (
        <Stack gap="md">
          {data.systems.map((sys) => (
            <Box key={sys.name}>
              <Group justify="space-between" mb={6}>
                <Badge variant="light" color="blue" size="md">{sys.name}</Badge>
                <Text fw={700} size="sm">{formatCurrency(sys.subtotal)}</Text>
              </Group>
              <Stack gap={4} pl="md">
                {sys.properties.map((prop) => (
                  <Group key={prop.name} justify="space-between">
                    <Text size="sm" c="dimmed">{prop.name}</Text>
                    <Text size="sm" fw={500}>{formatCurrency(prop.total)}</Text>
                  </Group>
                ))}
              </Stack>
            </Box>
          ))}
        </Stack>
      )}
    </Card>
  );
}
