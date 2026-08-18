import { Stack, Paper, Text, Badge, Group, Center, Loader, Alert } from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import { IconKey, IconAlertTriangle } from '@tabler/icons-react';
import dayjs from 'dayjs';
import { getLicenseStatus } from '../../api/license';

export default function LicenseStatusTab() {
  const { data, isLoading, isError } = useQuery({
    queryKey: ['license-status'],
    queryFn: getLicenseStatus,
    retry: false,
  });

  if (isLoading) return <Center py="xl"><Loader /></Center>;
  if (isError || !data?.data?.data) {
    return <Alert color="gray" icon={<IconAlertTriangle size={16} />}>License status is not available for this install.</Alert>;
  }

  const status = data.data.data;
  const daysLeft = status.expires_at ? dayjs(status.expires_at).diff(dayjs(), 'day') : null;
  const expiringSoon = daysLeft !== null && daysLeft <= 14 && daysLeft >= 0;
  const expired = daysLeft !== null && daysLeft < 0;

  return (
    <Stack maw={480}>
      <Text c="dimmed" size="sm">
        This install runs on a self-hosted MoBilling license, re-validated automatically once a day.
      </Text>

      {status.status === 'inactive' && (
        <Alert color="red" icon={<IconAlertTriangle size={16} />} title="License inactive">
          This install's license failed its last check. Contact support to reactivate.
        </Alert>
      )}
      {status.status === 'active' && expired && (
        <Alert color="red" icon={<IconAlertTriangle size={16} />} title="License expired">
          Renew to keep this install active — it will be locked out on the next scheduled check.
        </Alert>
      )}
      {status.status === 'active' && expiringSoon && (
        <Alert color="yellow" icon={<IconAlertTriangle size={16} />} title="Expiring soon">
          This license expires in {daysLeft} day{daysLeft === 1 ? '' : 's'} — renew soon to avoid an interruption.
        </Alert>
      )}

      <Paper withBorder p="md" radius="md">
        <Stack gap="sm">
          <Group justify="space-between">
            <Group gap="xs"><IconKey size={16} /><Text size="sm" c="dimmed">License Key</Text></Group>
            <Text size="sm" ff="monospace">{status.license_key ?? '—'}</Text>
          </Group>
          <Group justify="space-between">
            <Text size="sm" c="dimmed">Status</Text>
            <Badge color={status.status === 'active' ? 'green' : 'red'} variant="light">{status.status}</Badge>
          </Group>
          <Group justify="space-between">
            <Text size="sm" c="dimmed">Expires</Text>
            <Text size="sm">{status.expires_at ? dayjs(status.expires_at).format('DD MMM YYYY') : 'Perpetual'}</Text>
          </Group>
          <Group justify="space-between">
            <Text size="sm" c="dimmed">Last Checked</Text>
            <Text size="sm">{status.last_checked_at ? dayjs(status.last_checked_at).format('DD MMM YYYY HH:mm') : 'Never'}</Text>
          </Group>
        </Stack>
      </Paper>
    </Stack>
  );
}
