import {
  ActionIcon,
  Indicator,
  Popover,
  Text,
  Group,
  Stack,
  ScrollArea,
  Button,
  Box,
  Divider,
  useComputedColorScheme,
} from '@mantine/core';
import { useDisclosure } from '@mantine/hooks';
import { IconBell, IconCheck } from '@tabler/icons-react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useNavigate } from 'react-router-dom';
import dayjs from 'dayjs';
import relativeTime from 'dayjs/plugin/relativeTime';
import {
  getNotifications,
  getUnreadCount,
  markAsRead,
  markAllAsRead,
  type AppNotification,
} from '../../api/notifications';

dayjs.extend(relativeTime);

export default function NotificationBell() {
  const [opened, { toggle, close }] = useDisclosure(false);
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const colorScheme = useComputedColorScheme('light');
  const dark = colorScheme === 'dark';

  const { data: countData } = useQuery({
    queryKey: ['notifications', 'unread-count'],
    queryFn: () => getUnreadCount().then((r) => r.data),
    refetchInterval: 30_000,
  });

  const { data: listData } = useQuery({
    queryKey: ['notifications', 'list'],
    queryFn: () => getNotifications({ per_page: 20 }).then((r) => r.data),
    enabled: opened,
  });

  const invalidate = () => {
    queryClient.invalidateQueries({ queryKey: ['notifications'] });
  };

  const readMutation = useMutation({
    mutationFn: markAsRead,
    onSuccess: invalidate,
  });

  const readAllMutation = useMutation({
    mutationFn: markAllAsRead,
    onSuccess: invalidate,
  });

  const unreadCount = countData?.count ?? 0;
  const notifications = listData?.data ?? [];

  const handleClick = (n: AppNotification) => {
    if (!n.read_at) readMutation.mutate(n.id);
    if (n.data.url) {
      close();
      navigate(n.data.url);
    }
  };

  return (
    <Popover
      width={380}
      position="bottom-end"
      shadow="md"
      opened={opened}
      onChange={toggle}
    >
      <Popover.Target>
        <Indicator
          color="red"
          size={18}
          label={unreadCount > 99 ? '99+' : unreadCount}
          disabled={unreadCount === 0}
          offset={4}
        >
          <ActionIcon variant="default" size="lg" onClick={toggle} aria-label="Notifications">
            <IconBell size={18} />
          </ActionIcon>
        </Indicator>
      </Popover.Target>

      <Popover.Dropdown p={0}>
        <Group justify="space-between" px="md" py="xs">
          <Text fw={600} size="sm">
            Notifications
          </Text>
          {unreadCount > 0 && (
            <Button
              variant="subtle"
              size="compact-xs"
              leftSection={<IconCheck size={14} />}
              onClick={() => readAllMutation.mutate()}
              loading={readAllMutation.isPending}
            >
              Mark all read
            </Button>
          )}
        </Group>
        <Divider />

        <ScrollArea.Autosize mah={400}>
          {notifications.length === 0 ? (
            <Text c="dimmed" ta="center" py="xl" size="sm">
              No notifications yet
            </Text>
          ) : (
            <Stack gap={0}>
              {notifications.map((n) => (
                <Box
                  key={n.id}
                  px="md"
                  py="sm"
                  bg={n.read_at ? undefined : (dark ? 'dark.5' : 'blue.0')}
                  style={{
                    cursor: n.data.url ? 'pointer' : 'default',
                    transition: 'background-color 150ms',
                  }}
                  onMouseEnter={(e) => {
                    e.currentTarget.style.backgroundColor = dark
                      ? 'var(--mantine-color-dark-4)'
                      : 'var(--mantine-color-gray-1)';
                  }}
                  onMouseLeave={(e) => {
                    e.currentTarget.style.backgroundColor = n.read_at
                      ? ''
                      : dark
                        ? 'var(--mantine-color-dark-5)'
                        : 'var(--mantine-color-blue-0)';
                  }}
                  onClick={() => handleClick(n)}
                >
                  <Group justify="space-between" wrap="nowrap" align="flex-start">
                    <Box style={{ flex: 1, minWidth: 0 }}>
                      <Group gap={6} wrap="nowrap">
                        {!n.read_at && (
                          <Box
                            w={8}
                            h={8}
                            bg="blue.5"
                            style={{ borderRadius: '50%', flexShrink: 0 }}
                          />
                        )}
                        <Text size="sm" fw={600} truncate>
                          {n.data.title}
                        </Text>
                      </Group>
                      <Text size="xs" c="dimmed" lineClamp={2} mt={2}>
                        {n.data.message}
                      </Text>
                    </Box>
                    <Text size="xs" c="dimmed" style={{ flexShrink: 0 }}>
                      {dayjs(n.created_at).fromNow()}
                    </Text>
                  </Group>
                </Box>
              ))}
            </Stack>
          )}
        </ScrollArea.Autosize>
      </Popover.Dropdown>
    </Popover>
  );
}
