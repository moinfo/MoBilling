import { useState } from 'react';
import {
  Drawer, Stack, Text, Group, Badge, Button, Textarea, Select,
  Timeline, ThemeIcon, Divider, ActionIcon,
} from '@mantine/core';
import { DatePickerInput } from '@mantine/dates';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { IconPhone, IconPhoneOff, IconPhoneCall, IconX, IconPlus, IconTrash } from '@tabler/icons-react';
import {
  getFollowups, createFollowup, deleteFollowup,
  OUTCOME_META, type FollowupOutcome, type FieldVisit,
} from '../../api/fieldMarketing';
import { usePermissions } from '../../hooks/usePermissions';

const OUTCOME_OPTIONS = (Object.keys(OUTCOME_META) as FollowupOutcome[]).map(v => ({
  value: v,
  label: OUTCOME_META[v].label,
}));

const outcomeIcon = (outcome: FollowupOutcome) => {
  if (outcome === 'answered' || outcome === 'interested' || outcome === 'converted')
    return <IconPhone size={14} />;
  if (outcome === 'no_answer')
    return <IconPhoneOff size={14} />;
  return <IconPhoneCall size={14} />;
};

const toDateStr = (val: unknown): string => {
  if (!val) return '';
  if (val instanceof Date) return val.toISOString().slice(0, 10);
  const d = new Date(val as string);
  return isNaN(d.getTime()) ? '' : d.toISOString().slice(0, 10);
};

interface Props {
  visit: FieldVisit | null;
  onClose: () => void;
}

export default function FollowupDrawer({ visit, onClose }: Props) {
  const { can } = usePermissions();
  const qc = useQueryClient();
  const [showForm, setShowForm] = useState(false);
  const [outcome, setOutcome] = useState<FollowupOutcome | null>(null);
  const [notes, setNotes] = useState('');
  const [callDate, setCallDate] = useState<Date | null>(new Date());
  const [nextDate, setNextDate] = useState<Date | null>(null);

  const { data: followups = [], isFetching } = useQuery({
    queryKey: ['field-followups', visit?.id],
    queryFn: () => getFollowups(visit!.id),
    enabled: !!visit,
  });

  const invalidate = () => {
    qc.invalidateQueries({ queryKey: ['field-followups', visit?.id] });
    qc.invalidateQueries({ queryKey: ['field-session', visit?.session_id] });
    qc.invalidateQueries({ queryKey: ['field-sessions'] });
  };

  const saveMutation = useMutation({
    mutationFn: () => createFollowup(visit!.id, {
      call_date:          toDateStr(callDate),
      outcome:            outcome!,
      notes:              notes || undefined,
      next_followup_date: toDateStr(nextDate) || undefined,
    }),
    onSuccess: () => {
      setShowForm(false);
      setOutcome(null);
      setNotes('');
      setCallDate(new Date());
      setNextDate(null);
      invalidate();
      notifications.show({ message: 'Call logged', color: 'green' });
    },
    onError: () => notifications.show({ message: 'Failed to log call', color: 'red' }),
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => deleteFollowup(visit!.id, id),
    onSuccess: invalidate,
  });

  const canSave = !!outcome && !!callDate;

  return (
    <Drawer
      opened={!!visit}
      onClose={onClose}
      title={visit ? `Follow-up: ${visit.business_name}` : ''}
      position="right"
      size="md"
    >
      <Stack>
        {/* Visit info */}
        {visit && (
          <Group gap="xs">
            <Text size="sm" c="dimmed">{visit.location}</Text>
            {visit.phone && <Text size="sm">{visit.phone}</Text>}
          </Group>
        )}

        <Divider label="Call History" labelPosition="left" />

        {/* Timeline */}
        {followups.length === 0 && !isFetching ? (
          <Text c="dimmed" size="sm" fs="italic">No calls logged yet</Text>
        ) : (
          <Timeline active={followups.length - 1} bulletSize={28} lineWidth={2}>
            {followups.map(f => {
              const meta = OUTCOME_META[f.outcome];
              return (
                <Timeline.Item
                  key={f.id}
                  bullet={
                    <ThemeIcon size={24} radius="xl" color={meta.color} variant="filled">
                      {outcomeIcon(f.outcome)}
                    </ThemeIcon>
                  }
                  title={
                    <Group justify="space-between" wrap="nowrap">
                      <Group gap={6}>
                        <Badge size="xs" color={meta.color}>{meta.label}</Badge>
                        <Text size="xs" c="dimmed">{f.call_date}</Text>
                        <Text size="xs" c="dimmed">by {f.user?.name}</Text>
                      </Group>
                      {can('field_visits.log') && (
                        <ActionIcon size="xs" color="red" variant="subtle"
                          loading={deleteMutation.isPending}
                          onClick={() => { if (confirm('Delete this call log?')) deleteMutation.mutate(f.id); }}>
                          <IconTrash size={12} />
                        </ActionIcon>
                      )}
                    </Group>
                  }
                >
                  {f.notes && <Text size="xs" mt={2}>{f.notes}</Text>}
                  {f.next_followup_date && (
                    <Text size="xs" c="teal" mt={2}>Next: {f.next_followup_date}</Text>
                  )}
                </Timeline.Item>
              );
            })}
          </Timeline>
        )}

        {/* Log new call */}
        {can('field_visits.log') && (
          <>
            <Divider />
            {!showForm ? (
              <Button
                leftSection={<IconPlus size={14} />}
                variant="light"
                onClick={() => setShowForm(true)}
              >
                Log a Call
              </Button>
            ) : (
              <Stack gap="xs">
                <Group justify="space-between">
                  <Text fw={600} size="sm">Log Call</Text>
                  <ActionIcon size="sm" variant="subtle" onClick={() => setShowForm(false)}>
                    <IconX size={14} />
                  </ActionIcon>
                </Group>
                <DatePickerInput
                  label="Call Date"
                  value={callDate}
                  onChange={val => setCallDate(val as Date | null)}
                  maxDate={new Date()}
                  required
                />
                <Select
                  label="Outcome"
                  placeholder="What happened?"
                  data={OUTCOME_OPTIONS}
                  value={outcome}
                  onChange={v => setOutcome(v as FollowupOutcome)}
                  required
                />
                <Textarea
                  label="Notes"
                  placeholder="What was discussed?"
                  minRows={2}
                  value={notes}
                  onChange={e => setNotes(e.currentTarget.value)}
                />
                <DatePickerInput
                  label="Schedule Next Follow-up"
                  placeholder="Optional"
                  value={nextDate}
                  onChange={val => setNextDate(val as Date | null)}
                  minDate={new Date()}
                  clearable
                />
                <Button
                  onClick={() => saveMutation.mutate()}
                  loading={saveMutation.isPending}
                  disabled={!canSave}
                >
                  Save Call Log
                </Button>
              </Stack>
            )}
          </>
        )}
      </Stack>
    </Drawer>
  );
}
