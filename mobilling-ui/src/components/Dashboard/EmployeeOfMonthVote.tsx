import { useState } from 'react';
import { Box, Card, Text, Select, Textarea, Button, Group, Badge, Table, Stack } from '@mantine/core';
import { IconTrophy } from '@tabler/icons-react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import dayjs from 'dayjs';
import { getEotmCurrent, castEotmVote } from '../../api/employeeOfMonth';
import classes from './Dashboard.module.css';

/**
 * Self-service, no permission required — every active staff member can vote.
 * Renders nothing when the tenant hasn't enabled Employee of the Month
 * (getEotmCurrent returns data: null), or when there's genuinely no cycle
 * yet (first month after enabling, before the 1st rolls around).
 */
export default function EmployeeOfMonthVote() {
  const queryClient = useQueryClient();
  const [candidateId, setCandidateId] = useState<string | null>(null);
  const [reason, setReason] = useState('');

  const { data } = useQuery({ queryKey: ['eotm-current'], queryFn: getEotmCurrent });
  const current = data?.data?.data;

  const voteMut = useMutation({
    mutationFn: () => castEotmVote({ cycle_id: current!.cycle.id, candidate_id: candidateId!, reason }),
    onSuccess: () => {
      notifications.show({ title: 'Asante!', message: 'Kura yako imepokelewa.', color: 'green' });
      queryClient.invalidateQueries({ queryKey: ['eotm-current'] });
    },
    onError: (err: any) => notifications.show({
      title: 'Hitilafu', message: err.response?.data?.message || 'Imeshindwa kutuma kura.', color: 'red',
    }),
  });

  if (!current) return null;

  const { cycle, is_open_now, has_voted, candidates, results } = current;
  const prettyPeriod = dayjs(`${cycle.period_month_key}-01`).format('MMMM YYYY');
  const canVoteNow = is_open_now && !has_voted;

  return (
    <Box>
      <div className={classes.sectionLabel} style={{ marginBottom: 12 }}>
        <Text fw={700} size="sm" tt="uppercase" c="dimmed" style={{ letterSpacing: 0.5 }}>
          Employee of the Month — {prettyPeriod}
        </Text>
      </div>

      <Card withBorder radius="md" p="md">
        {canVoteNow ? (
          <Stack gap="sm">
            <Text size="sm">
              Piga kura mfanyakazi bora wa mwezi {prettyPeriod}. Kura zinafunguliwa tarehe {dayjs(cycle.voting_opens_on).format('D')}
              {' '}mpaka {dayjs(cycle.voting_closes_on).format('D MMM')}. Haiwezekani kujipigia kura wewe mwenyewe.
            </Text>
            <Select
              label="Nani?"
              placeholder="Chagua mfanyakazi"
              searchable
              data={candidates.map((c) => ({ value: c.id, label: c.name }))}
              value={candidateId}
              onChange={setCandidateId}
            />
            <Textarea
              label="Kwa nini umemchagua?"
              placeholder="Andika sababu yako..."
              minRows={2}
              value={reason}
              onChange={(e) => setReason(e.currentTarget.value)}
            />
            <Group justify="flex-end">
              <Button
                size="xs"
                disabled={!candidateId || reason.trim().length < 3}
                loading={voteMut.isPending}
                onClick={() => voteMut.mutate()}
              >
                Piga Kura
              </Button>
            </Group>
          </Stack>
        ) : (
          <Stack gap="xs">
            {has_voted && is_open_now && (
              <Text size="sm" c="dimmed">Umepiga kura tayari kwa mzunguko huu — asante!</Text>
            )}
            {cycle.status === 'closed' && cycle.winner && (
              <Group gap="xs">
                <IconTrophy size={18} color="var(--mantine-color-yellow-6)" />
                <Text size="sm" fw={600}>
                  Mshindi: {cycle.winner.name} ({cycle.winner_vote_count} kura)
                  {cycle.prize_amount ? ` — Zawadi TZS ${Number(cycle.prize_amount).toLocaleString()}` : ''}
                </Text>
              </Group>
            )}
            {cycle.status === 'closed' && !cycle.winner && (
              <Text size="sm" c="dimmed">Hakuna mshindi — hakuna kura zilizopigwa.</Text>
            )}

            <Text size="xs" c="dimmed" mt="xs">Matokeo ya kura — wafanyakazi wote:</Text>
            <Table.ScrollContainer minWidth={280}>
              <Table striped>
                <Table.Tbody>
                  {results.map((r) => (
                    <Table.Tr key={r.user_id}>
                      <Table.Td>{r.name}</Table.Td>
                      <Table.Td style={{ textAlign: 'right' }}>
                        <Badge size="sm" variant={r.votes > 0 ? 'light' : 'outline'} color={r.votes > 0 ? 'blue' : 'gray'}>
                          {r.votes} kura
                        </Badge>
                      </Table.Td>
                    </Table.Tr>
                  ))}
                </Table.Tbody>
              </Table>
            </Table.ScrollContainer>
          </Stack>
        )}
      </Card>
    </Box>
  );
}
