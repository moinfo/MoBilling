import { Card, Text, Group, Badge, Stack, RingProgress, Center } from '@mantine/core';
import type { SubscriptionStats as Stats } from '../../api/dashboard';

interface Props {
  data: Stats;
}

export default function SubscriptionStats({ data }: Props) {
  const total = data.active + data.pending + data.cancelled;
  const activePercent = total > 0 ? Math.round((data.active / total) * 100) : 0;

  return (
    <Card withBorder padding="lg" radius="md" h="100%">
      <Text fw={600} mb="md">Subscriptions</Text>
      {total === 0 ? (
        <Center h={200}><Text c="dimmed" size="sm">No subscriptions yet</Text></Center>
      ) : (
        <Stack align="center" gap="lg" mt="md">
          <RingProgress
            size={140}
            thickness={14}
            roundCaps
            label={
              <Center>
                <div style={{ textAlign: 'center' }}>
                  <Text fw={700} size="xl">{total}</Text>
                  <Text c="dimmed" size="xs">Total</Text>
                </div>
              </Center>
            }
            sections={[
              { value: total > 0 ? (data.active / total) * 100 : 0, color: 'green' },
              { value: total > 0 ? (data.pending / total) * 100 : 0, color: 'yellow' },
              { value: total > 0 ? (data.cancelled / total) * 100 : 0, color: 'red' },
            ]}
          />
          <Group gap="md">
            <Badge color="green" variant="light" size="lg">{data.active} Active</Badge>
            <Badge color="yellow" variant="light" size="lg">{data.pending} Pending</Badge>
            <Badge color="red" variant="light" size="lg">{data.cancelled} Cancelled</Badge>
          </Group>
        </Stack>
      )}
    </Card>
  );
}
