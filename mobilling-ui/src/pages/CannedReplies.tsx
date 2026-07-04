import { useState } from 'react';
import {
  Title, Stack, Group, Table, Text, Paper, Button, ActionIcon, Modal,
  TextInput, Textarea, Loader, Center, Tooltip,
} from '@mantine/core';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { IconMessageDots, IconPlus, IconEdit, IconTrash } from '@tabler/icons-react';
import {
  getCannedReplies, createCannedReply, updateCannedReply, deleteCannedReply,
  CannedReply,
} from '../api/cannedReplies';

export default function CannedReplies() {
  const qc = useQueryClient();
  const [modalOpen, setModalOpen] = useState(false);
  const [editing, setEditing] = useState<CannedReply | null>(null);
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');

  const { data, isLoading } = useQuery({ queryKey: ['canned-replies'], queryFn: getCannedReplies });
  const items: CannedReply[] = data?.data?.data ?? [];

  const invalidate = () => qc.invalidateQueries({ queryKey: ['canned-replies'] });

  const saveMutation = useMutation({
    mutationFn: () => editing
      ? updateCannedReply(editing.id, { title: title.trim(), body: body.trim() })
      : createCannedReply({ title: title.trim(), body: body.trim() }),
    onSuccess: () => {
      invalidate();
      notifications.show({ message: editing ? 'Canned reply updated.' : 'Canned reply created.', color: 'green' });
      setModalOpen(false);
    },
    onError: () => notifications.show({ message: 'Save failed.', color: 'red' }),
  });

  const deleteMutation = useMutation({
    mutationFn: deleteCannedReply,
    onSuccess: () => {
      invalidate();
      notifications.show({ message: 'Canned reply deleted.', color: 'gray' });
    },
  });

  const openModal = (c: CannedReply | null) => {
    setEditing(c);
    setTitle(c?.title ?? '');
    setBody(c?.body ?? '');
    setModalOpen(true);
  };

  return (
    <Stack>
      <Group justify="space-between">
        <Group gap="xs">
          <IconMessageDots size={22} />
          <Title order={2}>Canned Replies</Title>
        </Group>
        <Button leftSection={<IconPlus size={16} />} onClick={() => openModal(null)}>
          New Canned Reply
        </Button>
      </Group>

      <Text size="sm" c="dimmed">
        Predefined responses staff can insert into a support-ticket reply.
      </Text>

      {isLoading ? (
        <Center py="xl"><Loader /></Center>
      ) : items.length === 0 ? (
        <Center py="xl"><Text c="dimmed">No canned replies yet.</Text></Center>
      ) : (
        <Paper withBorder radius="md">
          <Table.ScrollContainer minWidth={560}>
            <Table highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Title</Table.Th>
                  <Table.Th>Preview</Table.Th>
                  <Table.Th w={100}>Actions</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {items.map((c) => (
                  <Table.Tr key={c.id}>
                    <Table.Td><Text size="sm" fw={600}>{c.title}</Text></Table.Td>
                    <Table.Td><Text size="sm" c="dimmed" truncate maw={420}>{c.body}</Text></Table.Td>
                    <Table.Td>
                      <Group gap={4}>
                        <Tooltip label="Edit">
                          <ActionIcon variant="subtle" onClick={() => openModal(c)}><IconEdit size={16} /></ActionIcon>
                        </Tooltip>
                        <Tooltip label="Delete">
                          <ActionIcon variant="subtle" color="red"
                            onClick={() => { if (confirm(`Delete "${c.title}"?`)) deleteMutation.mutate(c.id); }}>
                            <IconTrash size={16} />
                          </ActionIcon>
                        </Tooltip>
                      </Group>
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        </Paper>
      )}

      <Modal opened={modalOpen} onClose={() => setModalOpen(false)}
        title={editing ? 'Edit Canned Reply' : 'New Canned Reply'} size="lg">
        <Stack>
          <TextInput label="Title" placeholder="e.g. Password reset instructions" required
            value={title} onChange={(e) => setTitle(e.currentTarget.value)} />
          <Textarea label="Body" placeholder="The response text…" required
            minRows={6} autosize maxRows={16}
            value={body} onChange={(e) => setBody(e.currentTarget.value)} />
          <Group justify="flex-end">
            <Button variant="default" onClick={() => setModalOpen(false)}>Cancel</Button>
            <Button loading={saveMutation.isPending} disabled={!title.trim() || !body.trim()}
              onClick={() => saveMutation.mutate()}>
              {editing ? 'Save Changes' : 'Create'}
            </Button>
          </Group>
        </Stack>
      </Modal>
    </Stack>
  );
}
