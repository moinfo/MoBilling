import { useState } from 'react';
import {
  Box, Paper, Title, Text, Stack, Button, TextInput, Alert, Progress, Group, Badge,
} from '@mantine/core';
import { useParams } from 'react-router-dom';
import { IconWifi, IconAlertTriangle } from '@tabler/icons-react';
import { getPublicWifiBalance, PublicWifiBalance } from '../../api/publicWifi';

const formatDuration = (seconds: number) => {
  const d = Math.floor(seconds / 86400);
  const h = Math.floor((seconds % 86400) / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const parts = [];
  if (d) parts.push(`${d}d`);
  if (h) parts.push(`${h}h`);
  if (m || parts.length === 0) parts.push(`${m}m`);
  return parts.join(' ');
};

export default function WifiBalanceCheck() {
  const { routerId } = useParams<{ routerId: string }>();
  const [code, setCode] = useState('');
  const [result, setResult] = useState<PublicWifiBalance | null>(null);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const check = async () => {
    if (!code.trim() || !routerId) return;
    setLoading(true);
    setError('');
    setResult(null);
    try {
      const res = await getPublicWifiBalance(routerId, code.trim());
      setResult(res.data.data);
    } catch (e: any) {
      setError(e?.response?.data?.message ?? 'Could not check that voucher. Please try again.');
    } finally {
      setLoading(false);
    }
  };

  const dataPercentUsed = result?.data_cap_mb && result?.data_used_mb != null
    ? Math.min(100, (result.data_used_mb / result.data_cap_mb) * 100)
    : null;
  const timePercentUsed = result?.duration_seconds && result?.time_used_seconds != null
    ? Math.min(100, (result.time_used_seconds / result.duration_seconds) * 100)
    : null;
  const hasStartedUsingTime = (result?.time_used_seconds ?? 0) > 0;

  return (
    <Box maw={420} mx="auto" mt="xl" px="md">
      <Stack align="center" mb="lg">
        <IconWifi size={40} color="var(--mantine-color-blue-6)" />
        <Title order={3} ta="center">Angalia Salio la Voucher</Title>
        <Text c="dimmed" size="sm" ta="center">Weka code yako ya WiFi uone muda na data iliyobaki.</Text>
      </Stack>

      <Paper withBorder p="md" radius="md">
        <Stack>
          <TextInput
            label="Voucher Code" placeholder="e.g. MKAJQNZR" value={code}
            onChange={(e) => setCode(e.currentTarget.value.toUpperCase())}
            onKeyDown={(e) => { if (e.key === 'Enter') check(); }}
          />
          <Button fullWidth loading={loading} disabled={!code.trim()} onClick={check}>Angalia Salio</Button>

          {error && (
            <Alert color="red" icon={<IconAlertTriangle size={18} />}>{error}</Alert>
          )}

          {result && (
            <Stack gap={6} mt="xs">
              <Group justify="space-between">
                <Text size="sm" c="dimmed">Code</Text>
                <Text size="sm" fw={600}>{result.hotspot_username}</Text>
              </Group>

              {result.duration_seconds ? (
                <>
                  <Group justify="space-between">
                    <Text size="sm" c="dimmed">Muda</Text>
                    {result.time_remaining_seconds != null ? (
                      hasStartedUsingTime ? (
                        <Badge color={result.time_remaining_seconds > 0 ? 'blue' : 'red'} variant="light">
                          {result.time_remaining_seconds > 0 ? `${formatDuration(result.time_remaining_seconds)} imebaki` : 'Imeisha'}
                        </Badge>
                      ) : (
                        <Text size="sm" fw={600}>Bado hujaanza kutumia</Text>
                      )
                    ) : (
                      <Text size="sm" c="dimmed">Haipatikani kwa sasa</Text>
                    )}
                  </Group>
                  {!hasStartedUsingTime && (
                    <Text size="xs" c="dimmed">
                      Utapata {formatDuration(result.duration_seconds)} ya matumizi tangu utakapoanza kuunganika kwa mara ya kwanza.
                    </Text>
                  )}
                  {hasStartedUsingTime && timePercentUsed != null && (
                    <Progress value={timePercentUsed} color={timePercentUsed > 90 ? 'red' : 'blue'} />
                  )}
                </>
              ) : (
                <Group justify="space-between">
                  <Text size="sm" c="dimmed">Muda</Text>
                  <Text size="sm">Hakuna kikomo</Text>
                </Group>
              )}

              {result.data_cap_mb ? (
                <>
                  <Group justify="space-between">
                    <Text size="sm" c="dimmed">Data</Text>
                    <Text size="sm" fw={600}>
                      {result.data_remaining_mb != null
                        ? `${(result.data_remaining_mb / 1024).toFixed(2)}GB imebaki / ${(result.data_cap_mb / 1024).toFixed(2)}GB`
                        : 'Haipatikani kwa sasa'}
                    </Text>
                  </Group>
                  {dataPercentUsed != null && (
                    <Progress value={dataPercentUsed} color={dataPercentUsed > 90 ? 'red' : 'blue'} />
                  )}
                </>
              ) : (
                <Group justify="space-between">
                  <Text size="sm" c="dimmed">Data</Text>
                  <Text size="sm">Hakuna kikomo</Text>
                </Group>
              )}

              {!result.router_reachable && (
                <Text size="xs" c="dimmed" ta="center" mt={4}>
                  Router haipatikani kwa sasa — taarifa ya data inaweza isiwe sahihi kwa muda.
                </Text>
              )}
            </Stack>
          )}
        </Stack>
      </Paper>
    </Box>
  );
}
