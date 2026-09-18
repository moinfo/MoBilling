import { useEffect, useState } from 'react';
import {
  Stack, Paper, Title, Text, Group, Select, Center, Loader, SimpleGrid, Badge,
} from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import { IconServer2, IconTag, IconWorldWww } from '@tabler/icons-react';
import { getServers, getServerHealth } from '../api/hosting';
import StatCard from '../components/Reports/StatCard';

// Rough visual cue only — WHM doesn't report core count here, so this
// isn't "load per core", just a coarse flag for "worth a look".
const loadColor = (v: number | null) => {
  if (v === null) return 'gray';
  if (v >= 8) return 'red';
  if (v >= 2) return 'yellow';
  return 'teal';
};

/**
 * Server vitals — hostname, WHM version, load average — pulled live on
 * demand (not cached), since these are meant to reflect right now, not a
 * nightly snapshot like SSL Expiry.
 */
export default function ServerHealth() {
  const [serverId, setServerId] = useState<string | null>(null);

  const { data: serversData, isLoading: serversLoading } = useQuery({ queryKey: ['servers-for-discover'], queryFn: getServers });
  const servers = serversData?.data?.data ?? [];

  useEffect(() => {
    if (!serverId && servers.length > 0) setServerId(servers[0].id);
  }, [servers, serverId]);

  const { data, isLoading, isError } = useQuery({
    queryKey: ['server-health', serverId],
    queryFn: () => getServerHealth(serverId!),
    enabled: !!serverId,
    staleTime: 30_000,
  });
  const health = data?.data?.data;

  return (
    <Stack gap="md">
      <Title order={3}>
        <Group gap="xs"><IconServer2 size={22} /> Server Health</Group>
      </Title>

      <Text size="sm" c="dimmed">
        Live server vitals from WHM — hostname, version, and load average. Not core-count-aware, so
        treat the load colors as a rough flag, not a hard threshold.
      </Text>

      <Paper withBorder p="sm" radius="sm">
        <Select
          label="Server" data={servers.map((s) => ({ value: s.id, label: s.name }))}
          value={serverId} onChange={setServerId} disabled={serversLoading} maw={300}
        />
      </Paper>

      {isLoading ? (
        <Center py="xl"><Loader /></Center>
      ) : isError || !health ? (
        <Center py="xl"><Text c="dimmed">Could not load server health.</Text></Center>
      ) : (
        <SimpleGrid cols={{ base: 1, sm: 2, md: 3 }}>
          <StatCard label="Hostname" value={health.hostname ?? '—'} icon={<IconWorldWww size={20} />} color="blue" />
          <StatCard label="WHM Version" value={health.whm_version ?? '—'} icon={<IconTag size={20} />} color="grape" />
          <Paper withBorder p="md" radius="md">
            <Text size="xs" c="dimmed" tt="uppercase" fw={700} mb={8}>Load Average</Text>
            <Group gap="xs">
              <Group gap={4}>
                <Text size="xs" c="dimmed">1m</Text>
                <Badge size="lg" variant="light" color={loadColor(health.load_avg.one)}>{health.load_avg.one ?? '—'}</Badge>
              </Group>
              <Group gap={4}>
                <Text size="xs" c="dimmed">5m</Text>
                <Badge size="lg" variant="light" color={loadColor(health.load_avg.five)}>{health.load_avg.five ?? '—'}</Badge>
              </Group>
              <Group gap={4}>
                <Text size="xs" c="dimmed">15m</Text>
                <Badge size="lg" variant="light" color={loadColor(health.load_avg.fifteen)}>{health.load_avg.fifteen ?? '—'}</Badge>
              </Group>
            </Group>
          </Paper>
        </SimpleGrid>
      )}
    </Stack>
  );
}
