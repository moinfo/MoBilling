import { useState } from 'react';
import {
  Drawer, Stack, Text, Group, Badge, Button, Textarea, Select,
  Timeline, ThemeIcon, Divider, ActionIcon, Tooltip,
} from '@mantine/core';
import { DatePickerInput } from '@mantine/dates';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import {
  IconPhone, IconPhoneOff, IconPhoneCall, IconStar,
  IconPlus, IconTrash,
} from '@tabler/icons-react';
import { WhatsappContact } from '../../api/whatsappContacts';
import {
  getFollowups, createFollowup, deleteFollowup,
  OUTCOME_META, FollowupOutcome,
} from '../../api/whatsappFollowups';

const OUTCOME_OPTIONS = (Object.keys(OUTCOME_META) as FollowupOutcome[]).map((v) => ({
  value: v,
  label: OUTCOME_META[v].label,
}));

const outcomeIcon = (o: FollowupOutcome) => {
  switch (o) {
    case 'answered':       return <IconPhone size={14} />;
    case 'no_answer':      return <IconPhoneOff size={14} />;
    case 'callback':       return <IconPhoneCall size={14} />;
    case 'interested':     return <IconStar size={14} />;
    case 'not_interested': return <IconPhoneOff size={14} />;
    case 'converted':      return <IconStar size={14} />;
  }
};

interface Props {
  contact: WhatsappContact | null;
  onClose: () => void;
}

const toDateStr = (val: any): string | null => {
  if (!val) return null;
  const d = val instanceof Date ? val : new Date(val);
  return isNaN(d.getTime()) ? null : d.toISOString().split('T')[0];
};

export default function FollowupDrawer({ contact, onClose }: Props) {
  const qc = useQueryClient();
  const [outcome, setOutcome] = useState<FollowupOutcome>('answered');
  const [callDate, setCallDate] = useState<Date | null>(new Date());
  const [nextDate, setNextDate] = useState<Date | null>(null);
  const [notes, setNotes] = useState('');
  const [showForm, setShowForm] = useState(false);

  const { data, isLoading } = useQuery({
    queryKey: ['wa-followups', contact?.id],
    queryFn: () => getFollowups(contact!.id),
    enabled: !!contact,
  });

  const followups = data?.data ?? [];

  const addMutation = useMutation({
    mutationFn: () => createFollowup(contact!.id, {
      call_date: toDateStr(callDate)!,
      outcome,
      notes: notes || undefined,
      next_followup_date: toDateStr(nextDate) ?? undefined,
    } as any),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['wa-followups', contact?.id] });
      qc.invalidateQueries({ queryKey: ['whatsapp-contacts'] });
      notifications.show({ message: 'Follow-up logged', color: 'green' });
      setNotes('');
      setNextDate(null);
      setOutcome('answered');
      setShowForm(false);
    },
    onError: () => notifications.show({ message: 'Failed to save', color: 'red' }),
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => deleteFollowup(contact!.id, id),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['wa-followups', contact?.id] });
      notifications.show({ message: 'Deleted', color: 'red' });
    },
  });

  return (
    <Drawer
      opened={!!contact}
      onClose={onClose}
      title={contact ? `Follow-ups — ${contact.name}` : ''}
      position="right"
      size="md"
    >
      <Stack gap="md">
        {/* Contact quick info */}
        {contact && (
          <Group gap="xs">
            <Text size="sm" c="dimmed">{contact.phone}</Text>
            <Badge color="green" variant="light" size="sm">{contact.label.replace('_', ' ')}</Badge>
            {contact.next_followup_date && (
              <Badge color="orange" variant="light" size="sm">
                Next: {contact.next_followup_date}
              </Badge>
            )}
          </Group>
        )}

        {/* Log new follow-up button */}
        {!showForm ? (
          <Button
            leftSection={<IconPlus size={14} />}
            color="green"
            variant="light"
            onClick={() => setShowForm(true)}
          >
            Log a Call
          </Button>
        ) : (
          <Stack gap="sm" p="sm" style={{ border: '1px solid var(--mantine-color-default-border)', borderRadius: 8 }}>
            <Text fw={600} size="sm">New Call Log</Text>

            <Group grow>
              <DatePickerInput
                label="Call Date"
                required
                value={callDate}
                onChange={(v) => setCallDate(v as Date | null)}
              />
              <Select
                label="Outcome"
                required
                data={OUTCOME_OPTIONS}
                value={outcome}
                onChange={(v) => setOutcome((v ?? 'answered') as FollowupOutcome)}
              />
            </Group>

            <DatePickerInput
              label="Next Follow-up Date"
              clearable
              value={nextDate}
              onChange={(v) => setNextDate(v as Date | null)}
            />

            <Textarea
              label="Notes"
              placeholder="What was discussed..."
              rows={3}
              value={notes}
              onChange={(e) => setNotes(e.currentTarget.value)}
            />

            <Group justify="flex-end">
              <Button variant="default" size="xs" onClick={() => setShowForm(false)}>Cancel</Button>
              <Button
                size="xs"
                color="green"
                loading={addMutation.isPending}
                disabled={!callDate}
                onClick={() => addMutation.mutate()}
              >
                Save Log
              </Button>
            </Group>
          </Stack>
        )}

        <Divider label="Call History" labelPosition="left" />

        {/* History */}
        {isLoading ? (
          <Text c="dimmed" size="sm">Loading...</Text>
        ) : followups.length === 0 ? (
          <Text c="dimmed" size="sm" ta="center" py="lg">No calls logged yet</Text>
        ) : (
          <Timeline active={-1} bulletSize={28} lineWidth={2}>
            {followups.map((f) => (
              <Timeline.Item
                key={f.id}
                bullet={
                  <ThemeIcon color={OUTCOME_META[f.outcome].color} size={24} radius="xl">
                    {outcomeIcon(f.outcome)}
                  </ThemeIcon>
                }
                title={
                  <Group justify="space-between" gap={4}>
                    <Group gap={6}>
                      <Badge color={OUTCOME_META[f.outcome].color} variant="light" size="sm">
                        {OUTCOME_META[f.outcome].label}
                      </Badge>
                      <Text size="xs" c="dimmed">{f.call_date}</Text>
                      {f.user && <Text size="xs" c="dimmed">· {f.user.name}</Text>}
                    </Group>
                    <Tooltip label="Delete">
                      <ActionIcon size="xs" color="red" variant="subtle" onClick={() => deleteMutation.mutate(f.id)}>
                        <IconTrash size={12} />
                      </ActionIcon>
                    </Tooltip>
                  </Group>
                }
              >
                {f.notes && <Text size="sm" mt={4}>{f.notes}</Text>}
                {f.next_followup_date && (
                  <Text size="xs" c="orange" mt={4}>→ Follow up: {f.next_followup_date}</Text>
                )}
              </Timeline.Item>
            ))}
          </Timeline>
        )}
      </Stack>
    </Drawer>
  );
}
