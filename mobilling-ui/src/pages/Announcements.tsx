import { useState } from 'react';
import {
  Title, Stack, Group, Table, Badge, Text, Paper, Button, ActionIcon, Modal,
  TextInput, Textarea, Switch, Loader, Center, Tooltip,
} from '@mantine/core';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { IconNews, IconPlus, IconEdit, IconTrash, IconEye, IconEyeOff } from '@tabler/icons-react';
import {
  getAnnouncements, createAnnouncement, updateAnnouncement, deleteAnnouncement,
  AnnouncementRow,
} from '../api/announcements';
import dayjs from 'dayjs';

export default function Announcements() {
  const qc = useQueryClient();
  const [modalOpen, setModalOpen] = useState(false);
  const [editing, setEditing] = useState<AnnouncementRow | null>(null);
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [publish, setPublish] = useState(true);

  const { data, isLoading } = useQuery({ queryKey: ['announcements'], queryFn: getAnnouncements });
  const items: AnnouncementRow[] = data?.data?.data ?? [];

  const invalidate = () => qc.invalidateQueries({ queryKey: ['announcements'] });

  const saveMutation = useMutation({
    mutationFn: () => editing
      ? updateAnnouncement(editing.id, { title: title.trim(), body: body.trim(), is_published: publish })
      : createAnnouncement({ title: title.trim(), body: body.trim(), is_published: publish }),
    onSuccess: () => {
      invalidate();
      notifications.show({ message: editing ? 'Announcement updated.' : 'Announcement created.', color: 'green' });
      setModalOpen(false);
    },
    onError: () => notifications.show({ message: 'Save failed.', color: 'red' }),
  });

  const togglePublish = useMutation({
    mutationFn: (a: AnnouncementRow) => updateAnnouncement(a.id, { is_published: !a.is_published }),
    onSuccess: () => invalidate(),
  });

  const deleteMutation = useMutation({
    mutationFn: deleteAnnouncement,
    onSuccess: () => {
      invalidate();
      notifications.show({ message: 'Announcement deleted.', color: 'gray' });
    },
  });

  const openModal = (a: AnnouncementRow | null) => {
    setEditing(a);
    setTitle(a?.title ?? '');
    setBody(a?.body ?? '');
    setPublish(a?.is_published ?? true);
    setModalOpen(true);
  };

  return (
    <Stack>
      <Group justify="space-between">
        <Group gap="xs">
          <IconNews size={22} />
          <Title order={2}>Announcements</Title>
        </Group>
        <Button leftSection={<IconPlus size={16} />} onClick={() => openModal(null)}>
          New Announcement
        </Button>
      </Group>

      {isLoading ? (
        <Center py="xl"><Loader /></Center>
      ) : items.length === 0 ? (
        <Center py="xl"><Text c="dimmed">No announcements yet — published ones appear in the client portal.</Text></Center>
      ) : (
        <Paper withBorder radius="md">
          <Table highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Title</Table.Th>
                <Table.Th>Published</Table.Th>
                <Table.Th>Status</Table.Th>
                <Table.Th></Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {items.map((a) => (
                <Table.Tr key={a.id}>
                  <Table.Td>
                    <Text size="sm" fw={600}>{a.title}</Text>
                    <Text size="xs" c="dimmed" lineClamp={1}>{a.body}</Text>
                  </Table.Td>
                  <Table.Td>
                    <Text size="xs" c="dimmed">
                      {a.published_at ? dayjs(a.published_at).format('D MMM YYYY HH:mm') : '—'}
                    </Text>
                  </Table.Td>
                  <Table.Td>
                    <Badge size="sm" color={a.is_published ? 'green' : 'gray'} variant="light">
                      {a.is_published ? 'Published' : 'Draft'}
                    </Badge>
                  </Table.Td>
                  <Table.Td>
                    <Group gap={4} justify="flex-end">
                      <Tooltip label={a.is_published ? 'Unpublish' : 'Publish'}>
                        <ActionIcon variant="light" color={a.is_published ? 'gray' : 'green'}
                          onClick={() => togglePublish.mutate(a)}>
                          {a.is_published ? <IconEyeOff size={15} /> : <IconEye size={15} />}
                        </ActionIcon>
                      </Tooltip>
                      <ActionIcon variant="light" onClick={() => openModal(a)}>
                        <IconEdit size={15} />
                      </ActionIcon>
                      <ActionIcon variant="light" color="red" onClick={() => deleteMutation.mutate(a.id)}>
                        <IconTrash size={15} />
                      </ActionIcon>
                    </Group>
                  </Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        </Paper>
      )}

      <Modal opened={modalOpen} onClose={() => setModalOpen(false)}
        title={editing ? 'Edit Announcement' : 'New Announcement'} centered size="lg">
        <Stack gap="sm">
          <TextInput label="Title" required value={title} onChange={(e) => setTitle(e.currentTarget.value)} />
          <Textarea label="Body" required minRows={6} autosize maxRows={14}
            placeholder="What do you want your clients to know?"
            value={body} onChange={(e) => setBody(e.currentTarget.value)} />
          <Switch label="Published (visible to clients)" checked={publish}
            onChange={(e) => setPublish(e.currentTarget.checked)} />
          <Group justify="flex-end">
            <Button variant="default" onClick={() => setModalOpen(false)}>Cancel</Button>
            <Button disabled={!title.trim() || !body.trim()} loading={saveMutation.isPending}
              onClick={() => saveMutation.mutate()}>
              Save
            </Button>
          </Group>
        </Stack>
      </Modal>
    </Stack>
  );
}
