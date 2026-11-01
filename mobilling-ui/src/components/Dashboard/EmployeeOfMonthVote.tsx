import { useState } from 'react';
import { Box, Card, Text, Select, Textarea, Button, Group, Badge, Table, Stack, ThemeIcon } from '@mantine/core';
import { IconTrophy, IconSparkles, IconGift } from '@tabler/icons-react';
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
 *
 * This is the one dashboard card that needs someone to actually DO
 * something before a deadline (unlike every other card, which is just a
 * number to read) — it's given a visible accent + a "MPYA" pulse on
 * purpose, so it doesn't blend into the rest of the page while voting is open.
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

  const { cycle, is_open_now, has_voted, candidates, turnout, results, my_vote } = current;
  const prettyPeriod = dayjs(`${cycle.period_month_key}-01`).format('MMMM YYYY');
  const canVoteNow = is_open_now && !has_voted;
  const myVoteCandidate = my_vote ? candidates.find((c) => c.id === my_vote.candidate_id) : null;

  return (
    <Box>
      <Card withBorder radius="md" p="lg" className={canVoteNow ? classes.eotmCard : undefined}>
        <Stack gap="md">
          <Group justify="space-between" align="flex-start" wrap="nowrap">
            <Group gap="xs" wrap="nowrap">
              <ThemeIcon size={36} radius="xl" variant="light" color="yellow">
                <IconTrophy size={20} />
              </ThemeIcon>
              <div>
                <Text fw={800} size="lg" lh={1.15}>Mfanyakazi Bora wa Mwezi</Text>
                <Text size="xs" c="dimmed">{prettyPeriod}</Text>
              </div>
            </Group>
            {canVoteNow && (
              <Badge
                color="red" variant="light" size="sm" radius="sm"
                leftSection={<span className={classes.eotmPulseDot} />}
              >
                PIGA KURA SASA
              </Badge>
            )}
          </Group>

          {is_open_now && (
            <Group gap={6}>
              <Badge color="teal" variant="light" size="sm">{turnout.voted} wamepiga kura</Badge>
              <Badge color="gray" variant="light" size="sm">{turnout.remaining} bado</Badge>
            </Group>
          )}

          {!!cycle.prize_amount && (
            <Group gap={8} align="center">
              <ThemeIcon size={24} radius="xl" variant="light" color="yellow">
                <IconGift size={14} />
              </ThemeIcon>
              <Text size="sm" fw={700} c="yellow.9">
                Zawadi kwa mshindi: TZS {Number(cycle.prize_amount).toLocaleString()}
              </Text>
            </Group>
          )}

          {canVoteNow ? (
            <Stack gap="sm">
              <Text size="sm">
                Chagua mfanyakazi bora wa mwezi {prettyPeriod}. Kura zinafunga tarehe{' '}
                <strong>{dayjs(cycle.voting_closes_on).format('D MMMM')}</strong> — haiwezekani kujipigia kura wewe mwenyewe.
              </Text>
              <Select
                label="Nani?"
                placeholder="Chagua mfanyakazi"
                searchable
                size="md"
                data={candidates.map((c) => ({ value: c.id, label: c.name }))}
                value={candidateId}
                onChange={setCandidateId}
              />
              <Textarea
                label="Kwa nini umemchagua?"
                placeholder="Andika sababu yako..."
                minRows={2}
                size="md"
                value={reason}
                onChange={(e) => setReason(e.currentTarget.value)}
              />
              <Button
                size="md"
                color="yellow"
                fullWidth
                leftSection={<IconSparkles size={16} />}
                disabled={!candidateId || reason.trim().length < 3}
                loading={voteMut.isPending}
                onClick={() => voteMut.mutate()}
              >
                Piga Kura
              </Button>
            </Stack>
          ) : (
            <Stack gap="xs">
              {has_voted && is_open_now && (
                <Stack gap={4}>
                  <Text size="sm" c="dimmed">Umepiga kura tayari kwa mzunguko huu — asante!</Text>
                  {myVoteCandidate && (
                    <Text size="sm">
                      Umempigia kura: <strong>{myVoteCandidate.name}</strong>
                    </Text>
                  )}
                  <Text size="xs" c="dimmed">
                    Matokeo ya kura wa wafanyakazi wote yataonekana hapa mara kura zitakapofungwa na kuhesabiwa kiotomatiki
                    tarehe {dayjs(cycle.voting_closes_on).format('D MMMM')}.
                  </Text>
                </Stack>
              )}

              {cycle.status === 'closed' && (
                <>
                  {cycle.winner ? (
                    <Group gap="xs">
                      <IconTrophy size={18} color="var(--mantine-color-yellow-6)" />
                      <Text size="sm" fw={600}>
                        Mshindi: {cycle.winner.name} ({cycle.winner_vote_count} kura)
                        {cycle.prize_amount ? ` — Zawadi TZS ${Number(cycle.prize_amount).toLocaleString()}` : ''}
                      </Text>
                    </Group>
                  ) : (
                    <Text size="sm" c="dimmed">Hakuna mshindi — hakuna kura zilizopigwa.</Text>
                  )}

                  <Text size="xs" c="dimmed" mt="xs">Matokeo ya kura — wafanyakazi wote:</Text>
                  <Table.ScrollContainer minWidth={280}>
                    <Table striped>
                      <Table.Tbody>
                        {(results ?? []).map((r) => (
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
                </>
              )}
            </Stack>
          )}
        </Stack>
      </Card>
    </Box>
  );
}
