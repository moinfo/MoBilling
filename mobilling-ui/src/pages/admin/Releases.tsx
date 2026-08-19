import { useState } from 'react';
import {
  Title, Table, Badge, ActionIcon, Modal, Stack, TextInput, Textarea,
  Switch, Button, Group, Text, Loader, Center, Paper,
} from '@mantine/core';
import { DateInput } from '@mantine/dates';
import { useForm } from '@mantine/form';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconPlus, IconEdit, IconTrash } from '@tabler/icons-react';
import dayjs from 'dayjs';
import { getReleases, createRelease, updateRelease, deleteRelease, Release, ReleaseFormData } from '../../api/admin';

export default function Releases() {
  const queryClient = useQueryClient();
  const [editRelease, setEditRelease] = useState<Release | null>(null);
  const [createOpen, setCreateOpen] = useState(false);

  const { data, isLoading } = useQuery({ queryKey: ['admin-releases'], queryFn: getReleases });
  const releases: Release[] = data?.data?.data || [];

  const deleteMut = useMutation({
    mutationFn: deleteRelease,
    onSuccess: () => {
      notifications.show({ title: 'Deleted', message: 'Release deleted', color: 'green' });
      queryClient.invalidateQueries({ queryKey: ['admin-releases'] });
    },
    onError: (err: any) => notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed to delete', color: 'red' }),
  });

  return (
    <>
      <Group justify="space-between" mb="md" wrap="wrap">
        <div>
          <Title order={2}>Releases</Title>
          <Text c="dimmed">"Check for Updates" catalog for self-hosted installs — the newest active row is what they're compared against.</Text>
        </div>
        <Button leftSection={<IconPlus size={16} />} onClick={() => setCreateOpen(true)}>Publish Release</Button>
      </Group>

      {isLoading ? (
        <Center py="xl"><Loader /></Center>
      ) : (
        <Paper withBorder>
          <Table.ScrollContainer minWidth={700}>
            <Table striped highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Version</Table.Th>
                  <Table.Th>Released</Table.Th>
                  <Table.Th>Changelog</Table.Th>
                  <Table.Th>Status</Table.Th>
                  <Table.Th w={80}>Actions</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {releases.map((r) => (
                  <Table.Tr key={r.id}>
                    <Table.Td fw={600}>{r.version}</Table.Td>
                    <Table.Td>{dayjs(r.released_at).format('DD MMM YYYY')}</Table.Td>
                    <Table.Td><Text size="xs" c="dimmed" lineClamp={2} maw={300}>{r.changelog || '—'}</Text></Table.Td>
                    <Table.Td><Badge color={r.is_active ? 'green' : 'gray'} variant="light">{r.is_active ? 'Active' : 'Inactive'}</Badge></Table.Td>
                    <Table.Td>
                      <Group gap={4}>
                        <ActionIcon variant="subtle" onClick={() => setEditRelease(r)}><IconEdit size={16} /></ActionIcon>
                        <ActionIcon variant="subtle" color="red" loading={deleteMut.isPending}
                          onClick={() => { if (confirm(`Delete release "${r.version}"?`)) deleteMut.mutate(r.id); }}>
                          <IconTrash size={16} />
                        </ActionIcon>
                      </Group>
                    </Table.Td>
                  </Table.Tr>
                ))}
                {releases.length === 0 && (
                  <Table.Tr><Table.Td colSpan={5}><Text ta="center" c="dimmed" py="md">No releases published yet</Text></Table.Td></Table.Tr>
                )}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        </Paper>
      )}

      <Modal opened={createOpen} onClose={() => setCreateOpen(false)} title="Publish Release">
        <ReleaseForm onSaved={() => { queryClient.invalidateQueries({ queryKey: ['admin-releases'] }); setCreateOpen(false); }} />
      </Modal>
      <Modal opened={!!editRelease} onClose={() => setEditRelease(null)} title={`Edit — ${editRelease?.version}`}>
        {editRelease && (
          <ReleaseForm existing={editRelease} onSaved={() => { queryClient.invalidateQueries({ queryKey: ['admin-releases'] }); setEditRelease(null); }} />
        )}
      </Modal>
    </>
  );
}

function ReleaseForm({ existing, onSaved }: { existing?: Release; onSaved: () => void }) {
  const form = useForm<ReleaseFormData>({
    initialValues: {
      version: existing?.version ?? '',
      changelog: existing?.changelog ?? '',
      download_url: existing?.download_url ?? '',
      released_at: existing?.released_at ?? dayjs().format('YYYY-MM-DD'),
      is_active: existing?.is_active ?? true,
    },
    validate: {
      version: (v) => (v.trim() ? null : 'Required'),
    },
  });

  const mutation = useMutation({
    mutationFn: (values: ReleaseFormData) => (existing ? updateRelease(existing.id, values) : createRelease(values)),
    onSuccess: () => {
      notifications.show({ title: 'Success', message: existing ? 'Release updated' : 'Release published', color: 'green' });
      onSaved();
    },
    onError: (err: any) => notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed to save release', color: 'red' }),
  });

  return (
    <form onSubmit={form.onSubmit((values) => mutation.mutate(values))}>
      <Stack>
        <TextInput label="Version" placeholder="2.1.0" required {...form.getInputProps('version')} />
        <DateInput label="Released" required
          value={new Date(form.values.released_at)}
          onChange={(v) => v && form.setFieldValue('released_at', dayjs(v as unknown as string).format('YYYY-MM-DD'))} />
        <Textarea label="Changelog" minRows={4} placeholder="- Fixed X&#10;- Added Y" {...form.getInputProps('changelog')} />
        <TextInput label="Download URL" placeholder="https://…/mobilling-2.1.0.zip" {...form.getInputProps('download_url')} />
        <Switch label="Active (shown as latest to self-hosted installs)" {...form.getInputProps('is_active', { type: 'checkbox' })} />
        <Group justify="flex-end">
          <Button type="submit" loading={mutation.isPending}>{existing ? 'Save' : 'Publish'}</Button>
        </Group>
      </Stack>
    </form>
  );
}
