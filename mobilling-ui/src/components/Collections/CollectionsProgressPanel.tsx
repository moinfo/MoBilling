import { Paper, Stack, Group, Text, Progress, Badge, Button, SimpleGrid, Loader } from '@mantine/core';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { IconCoin, IconChecks } from '@tabler/icons-react';
import {
  getCollectionsProgress, autoVerifyCollections, type StaffTarget,
} from '../../api/staffTargets';
import { formatCurrency } from '../../utils/formatCurrency';

interface Props {
  target: StaffTarget;
  /** Show the admin "Auto-verify collections" button (needs staff_targets.verify). */
  showAutoVerify?: boolean;
}

/**
 * Live progress for the "collections" criteria of a staff target: collected-to-date vs goal,
 * assigned invoices/balance, projected commission. Optionally lets an admin auto-verify.
 */
export default function CollectionsProgressPanel({ target, showAutoVerify = false }: Props) {
  const qc = useQueryClient();
  const { data, isLoading, isError } = useQuery({
    queryKey: ['collections-progress', target.id, target.status],
    queryFn: () => getCollectionsProgress(target.id),
  });
  const progress = data?.data?.data;

  const verifyMutation = useMutation({
    mutationFn: () => autoVerifyCollections(target.id),
    onSuccess: (res) => {
      const t = res.data.data;
      notifications.show({
        title: 'Collections verified',
        message: `Collected ${formatCurrency(res.data.collected)}. Total commission: ${formatCurrency(t.total_commission)}.`,
        color: 'green',
      });
      qc.invalidateQueries({ predicate: (q) => String(q.queryKey[0]).startsWith('staff-targets') || q.queryKey[0] === 'collections-progress' });
    },
    onError: (err: any) => {
      notifications.show({
        title: 'Cannot auto-verify',
        message: err?.response?.data?.message ?? 'Auto-verify failed.',
        color: 'red',
      });
    },
  });

  const confirmVerify = () => modals.openConfirmModal({
    title: 'Auto-verify collections',
    children: (
      <Text size="sm">
        This computes the collections goal from real payments received on {target.user.name}'s
        assigned invoices during the target period, calculates commission, and marks the target verified.
      </Text>
    ),
    labels: { confirm: 'Auto-verify', cancel: 'Cancel' },
    confirmProps: { color: 'green' },
    onConfirm: () => verifyMutation.mutate(),
  });

  if (isLoading) return <Loader size="xs" />;
  if (isError || !progress) return <Text size="xs" c="red">Could not load collections progress.</Text>;

  const projectedTotal = progress.criteria.reduce((s, c) => s + c.projected_commission, 0);
  const earnedTotal = target.criteria
    .filter(c => c.type === 'collections')
    .reduce((s, c) => s + (Number(c.commission_earned) || 0), 0);
  const verified = target.status === 'verified';

  return (
    <Paper withBorder p="sm" radius="md" bg="var(--mantine-color-default)">
      <Stack gap="sm">
        <Group justify="space-between">
          <Group gap="xs">
            <IconCoin size={16} />
            <Text size="sm" fw={600}>Collections progress</Text>
          </Group>
          {showAutoVerify && !verified && (
            <Button size="xs" color="green" variant="light" leftSection={<IconChecks size={14} />}
              onClick={confirmVerify} loading={verifyMutation.isPending}>
              Auto-verify collections
            </Button>
          )}
        </Group>

        <SimpleGrid cols={{ base: 2, sm: 4 }} spacing="xs">
          <div>
            <Text size="xs" c="dimmed">Collected in period</Text>
            <Text size="sm" fw={700} c="green">{formatCurrency(progress.collected)}</Text>
          </div>
          <div>
            <Text size="xs" c="dimmed">Invoices assigned (unpaid)</Text>
            <Text size="sm" fw={700}>{progress.assigned_invoices}</Text>
          </div>
          <div>
            <Text size="xs" c="dimmed">Balance assigned</Text>
            <Text size="sm" fw={700} c="red">{formatCurrency(progress.assigned_balance)}</Text>
          </div>
          <div>
            <Text size="xs" c="dimmed">{verified ? 'Commission earned' : 'Commission if verified now'}</Text>
            <Text size="sm" fw={700}>{formatCurrency(verified ? earnedTotal : projectedTotal)}</Text>
          </div>
        </SimpleGrid>

        {progress.criteria.map(c => {
          const pct = c.goal_value > 0 ? Math.min(100, (c.collected / c.goal_value) * 100) : 0;
          return (
            <div key={c.id}>
              <Group justify="space-between" mb={3}>
                <Text size="xs" fw={500}>{c.label}</Text>
                <Group gap={6}>
                  <Text size="xs" c="dimmed">
                    {formatCurrency(c.collected)} / {formatCurrency(c.goal_value)}
                  </Text>
                  {c.goal_met && <Badge size="xs" color="green">Goal met</Badge>}
                </Group>
              </Group>
              <Progress size="sm" radius="sm" value={pct}
                color={c.goal_met ? 'green' : pct >= 60 ? 'blue' : pct > 0 ? 'orange' : 'gray'} />
            </div>
          );
        })}
      </Stack>
    </Paper>
  );
}
