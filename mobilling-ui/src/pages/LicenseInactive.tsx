import {
  Title, Text, Stack, Button, Group, Badge, Container, Paper, ThemeIcon, Center, Loader,
} from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import { IconKey, IconLogout, IconBrandWhatsapp } from '@tabler/icons-react';
import dayjs from 'dayjs';
import { useAuth } from '../context/AuthContext';
import { getLicenseStatus } from '../api/license';
import { useNavigate } from 'react-router-dom';

export default function LicenseInactive() {
  const { user, logout } = useAuth();
  const navigate = useNavigate();

  const { data, isLoading } = useQuery({
    queryKey: ['license-status'],
    queryFn: getLicenseStatus,
    retry: false,
  });

  const status = data?.data?.data;

  const handleLogout = async () => {
    await logout();
    navigate('/login');
  };

  return (
    <Container size="sm" py="xl">
      <Stack align="center" gap="xl">
        <Group justify="space-between" w="100%">
          <div>
            <Title order={2}>MoBilling</Title>
            <Text c="dimmed" size="sm">{user?.tenant?.name}</Text>
          </div>
          <Button variant="subtle" color="gray" leftSection={<IconLogout size={16} />} onClick={handleLogout}>
            Logout
          </Button>
        </Group>

        <Paper withBorder p="xl" radius="md" w="100%" ta="center">
          <ThemeIcon size={60} radius="xl" color="red" variant="light" mx="auto" mb="md">
            <IconKey size={32} />
          </ThemeIcon>
          <Title order={3} mb="xs">License Inactive</Title>
          <Text c="dimmed" maw={480} mx="auto">
            This install's license could not be verified on its last check. Access is paused until it's
            renewed or reactivated — your data is safe and nothing has been deleted.
          </Text>
        </Paper>

        {isLoading ? (
          <Center py="md"><Loader /></Center>
        ) : status && (
          <Paper withBorder p="md" radius="md" w="100%">
            <Stack gap="sm">
              <Group justify="space-between">
                <Text size="sm" c="dimmed">License Key</Text>
                <Text size="sm" ff="monospace">{status.license_key ?? '—'}</Text>
              </Group>
              <Group justify="space-between">
                <Text size="sm" c="dimmed">Status</Text>
                <Badge color="red" variant="light">{status.status}</Badge>
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
        )}

        <Button
          size="md"
          leftSection={<IconBrandWhatsapp size={18} />}
          component="a"
          href={`https://wa.me/255689011111?text=${encodeURIComponent(`My self-hosted MoBilling license (${status?.license_key ?? 'unknown key'}) is inactive — please help.`)}`}
          target="_blank"
        >
          Contact Support
        </Button>
      </Stack>
    </Container>
  );
}
