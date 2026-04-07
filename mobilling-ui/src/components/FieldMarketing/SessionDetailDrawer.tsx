import { useState } from 'react';
import {
  Drawer, Stack, Text, Group, Badge, Button,
  ActionIcon, Modal, LoadingOverlay, Box,
} from '@mantine/core';
import { IconPlus, IconTrash, IconUserCheck, IconEdit, IconPhone } from '@tabler/icons-react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  getSessionDetail, createVisit, updateVisit, deleteVisit, convertVisit,
  VISIT_STATUSES, type FieldSession, type FieldVisit,
} from '../../api/fieldMarketing';
import { usePermissions } from '../../hooks/usePermissions';
import VisitForm from './VisitForm';
import ConvertVisitModal from './ConvertVisitModal';
import FollowupDrawer from './FollowupDrawer';

interface Props {
  session: FieldSession | null;
  onClose: () => void;
}

const statusMeta = Object.fromEntries(VISIT_STATUSES.map(s => [s.value, s]));

export default function SessionDetailDrawer({ session, onClose }: Props) {
  const { can } = usePermissions();
  const qc = useQueryClient();
  const [addingVisit, setAddingVisit]     = useState(false);
  const [editVisit, setEditVisit]         = useState<FieldVisit | null>(null);
  const [convertVisitItem, setConvertVisitItem] = useState<FieldVisit | null>(null);
  const [followupVisit, setFollowupVisit]       = useState<FieldVisit | null>(null);

  const { data, isFetching } = useQuery({
    queryKey: ['field-session', session?.id],
    queryFn:  () => getSessionDetail(session!.id),
    enabled:  !!session,
  });

  const invalidate = () => {
    qc.invalidateQueries({ queryKey: ['field-session', session?.id] });
    qc.invalidateQueries({ queryKey: ['field-sessions'] });
  };

  const addMutation = useMutation({
    mutationFn: (v: Parameters<typeof createVisit>[1]) => createVisit(session!.id, v),
    onSuccess: () => { setAddingVisit(false); invalidate(); },
  });

  const updateMutation = useMutation({
    mutationFn: (v: Parameters<typeof updateVisit>[2]) => updateVisit(session!.id, editVisit!.id, v),
    onSuccess: () => { setEditVisit(null); invalidate(); },
  });

  const deleteMutation = useMutation({
    mutationFn: (visitId: string) => deleteVisit(session!.id, visitId),
    onSuccess: invalidate,
  });

  const convertMutation = useMutation({
    mutationFn: (d: Parameters<typeof convertVisit>[2]) => convertVisit(session!.id, convertVisitItem!.id, d),
    onSuccess: () => { setConvertVisitItem(null); invalidate(); },
  });

  const visits: FieldVisit[] = data?.visits ?? [];

  return (
    <>
      <Drawer
        opened={!!session}
        onClose={onClose}
        title={session ? `${session.area} — ${session.visit_date}` : ''}
        position="right"
        size="lg"
        styles={{ body: { padding: 16 } }}
      >
        <Box pos="relative" mih={100}>
          <LoadingOverlay visible={isFetching} />
          <Stack>
            {session?.summary && (
              <Text size="sm" c="dimmed">{session.summary}</Text>
            )}

            <Group justify="space-between">
              <Text fw={600}>Visits ({visits.length})</Text>
              {can('field_visits.create') && (
                <Button size="xs" leftSection={<IconPlus size={14} />} onClick={() => setAddingVisit(true)}>
                  Log Visit
                </Button>
              )}
            </Group>

            {visits.map(v => {
              const meta = statusMeta[v.status];
              return (
                <Box key={v.id} style={{ border: '1px solid var(--mantine-color-default-border)', borderRadius: 8, padding: 12 }}>
                  <Group justify="space-between" align="flex-start">
                    <Stack gap={4}>
                      <Text fw={600}>{v.business_name}</Text>
                      <Text size="sm" c="dimmed">{v.location}</Text>
                      {v.phone && <Text size="sm">{v.phone}</Text>}
                      <Group gap={4} mt={4}>
                        {v.services.map(s => <Badge key={s} size="xs" variant="outline">{s}</Badge>)}
                      </Group>
                      {v.feedback && <Text size="sm" c="dimmed" mt={4}>{v.feedback}</Text>}
                      {v.client && (
                        <Badge color="green" size="sm" mt={4}>Client: {v.client.name}</Badge>
                      )}
                    </Stack>
                    <Stack gap={4} align="flex-end">
                      <Badge color={meta?.color ?? 'gray'}>{meta?.label ?? v.status}</Badge>
                      <Group gap={4}>
                        {can('field_visits.log') && (
                          <ActionIcon size="sm" color="teal" variant="subtle" title="Call logs"
                            onClick={() => setFollowupVisit(v)}>
                            <IconPhone size={14} />
                          </ActionIcon>
                        )}
                        {can('field_visits.convert') && v.status !== 'converted' && (
                          <ActionIcon size="sm" color="green" variant="subtle" title="Convert to client"
                            onClick={() => setConvertVisitItem(v)}>
                            <IconUserCheck size={14} />
                          </ActionIcon>
                        )}
                        {can('field_visits.update') && (
                          <ActionIcon size="sm" color="blue" variant="subtle" title="Edit"
                            onClick={() => setEditVisit(v)}>
                            <IconEdit size={14} />
                          </ActionIcon>
                        )}
                        {can('field_visits.delete') && (
                          <ActionIcon size="sm" color="red" variant="subtle" title="Delete"
                            loading={deleteMutation.isPending}
                            onClick={() => { if (confirm('Delete this visit?')) deleteMutation.mutate(v.id); }}>
                            <IconTrash size={14} />
                          </ActionIcon>
                        )}
                      </Group>
                    </Stack>
                  </Group>
                </Box>
              );
            })}

            {visits.length === 0 && !isFetching && (
              <Text c="dimmed" ta="center" py="xl" size="sm">No visits logged yet</Text>
            )}
          </Stack>
        </Box>
      </Drawer>

      {/* Add Visit Modal */}
      <Modal opened={addingVisit} onClose={() => setAddingVisit(false)} title="Log Visit" size="md" centered>
        <VisitForm onSubmit={v => addMutation.mutate(v)} loading={addMutation.isPending} />
      </Modal>

      {/* Edit Visit Modal */}
      <Modal opened={!!editVisit} onClose={() => setEditVisit(null)} title="Edit Visit" size="md" centered>
        {editVisit && (
          <VisitForm visit={editVisit} onSubmit={v => updateMutation.mutate(v)} loading={updateMutation.isPending} />
        )}
      </Modal>

      {/* Convert Modal */}
      <ConvertVisitModal
        visit={convertVisitItem}
        onClose={() => setConvertVisitItem(null)}
        onConvert={d => convertMutation.mutate(d)}
        loading={convertMutation.isPending}
      />

      {/* Followup Drawer */}
      <FollowupDrawer
        visit={followupVisit}
        onClose={() => setFollowupVisit(null)}
      />
    </>
  );
}
