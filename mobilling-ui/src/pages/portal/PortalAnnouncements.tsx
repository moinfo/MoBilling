import { Stack, Paper, Title, Text, Group, LoadingOverlay, Center } from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import { IconNews } from '@tabler/icons-react';
import api from '../../api/axios';
import dayjs from 'dayjs';

interface NewsRow { id: string; title: string; body: string; published_at: string }

export default function PortalAnnouncements() {
  const { data, isLoading } = useQuery({
    queryKey: ['portal-announcements'],
    queryFn: () => api.get<{ data: NewsRow[] }>('/portal/announcements'),
  });
  const items: NewsRow[] = data?.data?.data ?? [];

  return (
    <Stack gap="lg" pos="relative">
      <LoadingOverlay visible={isLoading} />
      <Group gap="xs">
        <IconNews size={22} />
        <Title order={3}>News & Announcements</Title>
      </Group>

      {!isLoading && items.length === 0 && (
        <Center py="xl"><Text c="dimmed">No announcements yet.</Text></Center>
      )}

      {items.map((a) => (
        <Paper key={a.id} withBorder radius="md" p="lg">
          <Group justify="space-between" mb={4}>
            <Text fw={700}>{a.title}</Text>
            <Text size="xs" c="dimmed">{dayjs(a.published_at).format('dddd, D MMMM YYYY')}</Text>
          </Group>
          <Text size="sm" style={{ whiteSpace: 'pre-wrap' }}>{a.body}</Text>
        </Paper>
      ))}
    </Stack>
  );
}
