import { Paper, Text, ScrollArea, Stack, Group, Badge, Divider, Center, Loader } from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import { getClientFollowups } from '../../api/followups';
import { formatDate } from '../../utils/formatDate';
import { outcomeColors, outcomeLabels, statusColors } from '../../utils/followupColors';

interface Props {
  clientId: string | null | undefined;
  /** Dims every other entry so the invoice currently being worked stands out. */
  currentDocumentNumber?: string | null;
  maxHeight?: number;
}

/**
 * Recent follow-up history for a client (FollowupController::clientHistory) — so whoever is about to call
 * a client sees prior calls/outcomes/notes first, not just the current invoice on its own. Renders nothing
 * once loaded if the client has no prior history. Shared by LogFollowupModal (Invoices page) and
 * LogCallModal (Follow-ups / My Collections pages), extracted from LogFollowupModal's original inline block.
 */
export default function ClientFollowupHistory({ clientId, currentDocumentNumber, maxHeight = 180 }: Props) {
  const { data, isLoading } = useQuery({
    queryKey: ['client-followups', clientId],
    queryFn: () => getClientFollowups(clientId as string),
    enabled: !!clientId,
  });
  const history = data?.data?.data ?? [];

  if (isLoading && !history.length) {
    return <Center py="xs"><Loader size="xs" /></Center>;
  }
  if (!history.length) return null;

  return (
    <Paper withBorder p="sm" radius="sm">
      <Text size="xs" fw={600} c="dimmed" tt="uppercase" mb="xs">Previous follow-ups for this client</Text>
      <ScrollArea.Autosize mah={maxHeight}>
        <Stack gap={6}>
          {history.map((h) => (
            <Group key={h.id} justify="space-between" wrap="nowrap" gap="xs"
              opacity={h.document_number === currentDocumentNumber ? 1 : 0.65}>
              <div style={{ minWidth: 0 }}>
                <Group gap={6}>
                  <Text size="xs" c="dimmed">{h.call_date ? formatDate(h.call_date) : (h.created_at ? formatDate(h.created_at) : '—')}</Text>
                  <Text size="xs" fw={500}>{h.document_number}</Text>
                  {h.outcome && (
                    <Badge color={outcomeColors[h.outcome] || 'gray'} size="xs" variant="light">
                      {outcomeLabels[h.outcome] || h.outcome}
                    </Badge>
                  )}
                  <Badge color={statusColors[h.status] || 'gray'} size="xs">{h.status}</Badge>
                </Group>
                {h.notes && <Text size="xs" c="dimmed" truncate>{h.notes}</Text>}
              </div>
              <Text size="xs" c="dimmed" style={{ whiteSpace: 'nowrap' }}>{h.assigned_to || '—'}</Text>
            </Group>
          ))}
        </Stack>
      </ScrollArea.Autosize>
      <Divider mt="sm" />
    </Paper>
  );
}
