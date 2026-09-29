import { Group, Stack, Badge, Text, ActionIcon, Tooltip } from '@mantine/core';
import { IconPhoneCall } from '@tabler/icons-react';
import { FollowupSummary } from '../../api/followups';
import { formatDate } from '../../utils/formatDate';
import { timeAgo } from '../../utils/timeAgo';
import { outcomeColors, outcomeLabels } from '../../utils/followupColors';

interface Props {
  summary?: FollowupSummary | null;
  onClick: () => void;
}

/** Compact "Follow-up" column cell for the Invoices table: last outcome, time since last call, next due date. */
export default function FollowupCell({ summary, onClick }: Props) {
  if (!summary || !summary.has_followup) {
    return (
      <Group gap={6} wrap="nowrap">
        <Text size="xs" c="dimmed">No follow-up yet</Text>
        <Tooltip label="Start a follow-up">
          <ActionIcon size="sm" color="teal" variant="light" onClick={onClick}>
            <IconPhoneCall size={14} />
          </ActionIcon>
        </Tooltip>
      </Group>
    );
  }

  const tooltipLines = [
    summary.assigned_to ? `Assigned to: ${summary.assigned_to}` : null,
    summary.last_notes ? `Notes: ${summary.last_notes}` : null,
  ].filter(Boolean).join('\n');

  return (
    <Tooltip label={tooltipLines || 'No notes yet'} multiline maw={260} disabled={!tooltipLines}>
      <Group gap={6} wrap="nowrap" onClick={onClick} style={{ cursor: 'pointer' }}>
        <Stack gap={2}>
          <Group gap={4}>
            {summary.assigned_to && (
              <Badge size="xs" variant="light" color="gray">{summary.assigned_to}</Badge>
            )}
            {summary.last_outcome ? (
              <Badge size="xs" variant="light" color={outcomeColors[summary.last_outcome] || 'gray'}>
                {outcomeLabels[summary.last_outcome] || summary.last_outcome}
              </Badge>
            ) : (
              <Badge size="xs" variant="light" color="blue">Scheduled</Badge>
            )}
          </Group>
          <Group gap={4}>
            {summary.last_call_date && (
              <Text size="xs" c="dimmed">{timeAgo(summary.last_call_date)}</Text>
            )}
            {summary.next_followup && (
              <Badge
                size="xs"
                color={summary.next_followup_overdue ? 'red' : 'blue'}
                variant={summary.next_followup_overdue ? 'filled' : 'light'}
              >
                {summary.next_followup_overdue ? 'Overdue: ' : 'Next: '}{formatDate(summary.next_followup)}
              </Badge>
            )}
          </Group>
        </Stack>
        <ActionIcon size="sm" color="teal" variant="light" onClick={(e) => { e.stopPropagation(); onClick(); }}>
          <IconPhoneCall size={14} />
        </ActionIcon>
      </Group>
    </Tooltip>
  );
}
