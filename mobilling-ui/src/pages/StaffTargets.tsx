import { useState, useEffect } from 'react';
import {
  Title, Tabs, Stack, Group, Button, Badge, Text, Paper, ActionIcon,
  Textarea, Modal, Loader, Center, ThemeIcon, Select, Divider,
  NumberInput, TextInput, ScrollArea, SimpleGrid, Progress,
  Table, Collapse, Checkbox, RingProgress,
} from '@mantine/core';
import { DatePickerInput } from '@mantine/dates';
import { useDisclosure } from '@mantine/hooks';
import { useForm } from '@mantine/form';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import {
  IconPlus, IconEdit, IconTrash, IconCheck, IconChevronDown, IconChevronUp,
  IconTarget, IconUsers, IconCoin, IconAlertTriangle, IconX,
  IconClipboardCheck, IconMoodHappy, IconLayoutDashboard, IconTrendingUp,
} from '@tabler/icons-react';
import dayjs from 'dayjs';
import {
  getTargets, createTarget, updateTarget, deleteTarget,
  selfReportTarget, verifyTarget, getCommissionSummary,
  type StaffTarget, type TargetCriterion, type CriterionType, type CommissionType,
  type CommissionSummaryEntry,
} from '../api/staffTargets';
import { usePermissions } from '../hooks/usePermissions';
import { useAuth } from '../context/AuthContext';
import { formatCurrency, getTenantCurrency } from '../utils/formatCurrency';

// ── Config ─────────────────────────────────────────────────────────────────────

const STATUS_CONFIG: Record<string, { color: string; label: string }> = {
  active:        { color: 'blue',   label: 'Active'          },
  self_reported: { color: 'orange', label: 'Awaiting Review' },
  verified:      { color: 'green',  label: 'Verified'        },
  cancelled:     { color: 'gray',   label: 'Cancelled'       },
};

const TYPE_LABELS: Record<CriterionType, string> = {
  customer_count: 'Customer Count',
  revenue:        'Revenue',
  item_sales:     'Item Sales',
  custom:         'Custom',
};

const DEFAULT_UNITS: Record<CriterionType, string> = {
  customer_count: 'customers',
  revenue:        getTenantCurrency(),
  item_sales:     'units',
  custom:         'units',
};

// ── Helpers ───────────────────────────────────────────────────────────────────

function fmtNum(n: number | null, unit?: string): string {
  if (n === null) return '—';
  const f = n >= 1000 ? n.toLocaleString() : String(n);
  return unit ? `${f} ${unit}` : f;
}

function commissionLabel(c: TargetCriterion): string {
  if (c.commission_type === 'none') return 'No commission';
  if (c.commission_type === 'fixed') return `${formatCurrency(c.commission_value ?? 0)} fixed`;
  return `${c.commission_value}% of achieved`;
}

function criterionPotential(c: TargetCriterion, usedValue?: number): number {
  const val = usedValue ?? c.goal_value;
  if (c.commission_type === 'none') return 0;
  if (c.commission_type === 'fixed') return c.commission_value ?? 0;
  return (c.commission_value ?? 0) / 100 * val;
}

function groupBonusPotential(t: StaffTarget): number {
  if (t.group_commission_type === 'none') return 0;
  if (t.group_commission_type === 'fixed') return t.group_commission_value ?? 0;
  return (t.group_commission_value ?? 0) / 100 * (t.staff_salary ?? 0);
}

// ── Main page ─────────────────────────────────────────────────────────────────

export default function StaffTargets() {
  const { can } = usePermissions();
  const canManage  = can('staff_targets.manage');
  const canVerify  = can('staff_targets.verify');
  const canViewTeam = canManage || canVerify || can('staff_reports.view_all');
  const canSubmit  = can('staff_targets.submit');

  // Show "Managed Targets" tab when the user manages at least one target,
  // OR for admins (canManage) so they can see the feature without waiting for assignment.
  const { data: managedData } = useQuery({
    queryKey: ['staff-targets-managed'],
    queryFn: () => getTargets({ managed_only: true }),
    enabled: canSubmit,
  });
  const managedTargets: StaffTarget[] = managedData?.data?.data ?? [];
  const showManagedTab = canManage || managedTargets.length > 0;

  return (
    <Stack>
      <Title order={2}>Staff Targets & Commission</Title>
      <Tabs defaultValue={canSubmit ? 'dashboard' : 'team'} keepMounted={false}>
        <Tabs.List>
          {canSubmit && (
            <Tabs.Tab value="dashboard" leftSection={<IconLayoutDashboard size={15} />}>Dashboard</Tabs.Tab>
          )}
          {canSubmit && (
            <Tabs.Tab value="mine" leftSection={<IconTarget size={15} />}>My Targets</Tabs.Tab>
          )}
          {showManagedTab && (
            <Tabs.Tab value="managed" leftSection={<IconClipboardCheck size={15} />}>Managed Targets</Tabs.Tab>
          )}
          {canViewTeam && (
            <Tabs.Tab value="team" leftSection={<IconUsers size={15} />}>Team Targets</Tabs.Tab>
          )}
          {canViewTeam && (
            <Tabs.Tab value="commission" leftSection={<IconCoin size={15} />}>Commission Summary</Tabs.Tab>
          )}
        </Tabs.List>

        {canSubmit && (
          <Tabs.Panel value="dashboard" pt="md">
            <DashboardTab />
          </Tabs.Panel>
        )}
        {canSubmit && (
          <Tabs.Panel value="mine" pt="md">
            <MyTargetsTab can={can} />
          </Tabs.Panel>
        )}
        {showManagedTab && (
          <Tabs.Panel value="managed" pt="md">
            <ManagedTargetsTab targets={managedTargets} />
          </Tabs.Panel>
        )}
        {canViewTeam && (
          <Tabs.Panel value="team" pt="md">
            <TeamTargetsTab canManage={canManage} canVerify={canVerify} />
          </Tabs.Panel>
        )}
        {canViewTeam && (
          <Tabs.Panel value="commission" pt="md">
            <CommissionSummaryTab />
          </Tabs.Panel>
        )}
      </Tabs>
    </Stack>
  );
}

// ── Managed Targets Tab ────────────────────────────────────────────────────────

function ManagedTargetsTab({ targets }: { targets: StaffTarget[] }) {
  if (targets.length === 0) {
    return (
      <Paper withBorder p="xl" radius="md">
        <Stack align="center" gap="xs">
          <ThemeIcon size="xl" radius="xl" variant="light" color="gray">
            <IconClipboardCheck size={24} />
          </ThemeIcon>
          <Text fw={600}>You aren't managing any targets yet</Text>
          <Text size="sm" c="dimmed" ta="center" maw={520}>
            When someone assigns you as a manager on a target (in the
            "Manager / Team-Lead Commission" section), it will appear here
            with your override commission and the staff's progress.
          </Text>
          <Text size="xs" c="dimmed" ta="center" maw={520}>
            To assign yourself or another colleague as manager: open
            "Team Targets" → edit a target → set the Manager field.
          </Text>
        </Stack>
      </Paper>
    );
  }

  const totalEarned = targets
    .filter(t => t.status === 'verified')
    .reduce((sum, t) => sum + (t.manager_commission_earned ?? 0), 0);
  const verifiedCount = targets.filter(t => t.status === 'verified').length;
  const activeCount   = targets.filter(t => t.status === 'active' || t.status === 'self_reported').length;

  return (
    <Stack>
      <SimpleGrid cols={{ base: 1, sm: 3 }} spacing="sm">
        <Paper withBorder p="sm" radius="md">
          <Text size="xs" c="dimmed">Targets you manage</Text>
          <Text size="xl" fw={700}>{targets.length}</Text>
          <Text size="xs" c="dimmed">{activeCount} active · {verifiedCount} verified</Text>
        </Paper>
        <Paper withBorder p="sm" radius="md">
          <Text size="xs" c="dimmed">Manager commission earned</Text>
          <Text size="xl" fw={700} c={totalEarned > 0 ? 'green' : undefined}>
            {formatCurrency(totalEarned)}
          </Text>
          <Text size="xs" c="dimmed">From verified targets only</Text>
        </Paper>
        <Paper withBorder p="sm" radius="md">
          <Text size="xs" c="dimmed">Pending verification</Text>
          <Text size="xl" fw={700}>{activeCount}</Text>
          <Text size="xs" c="dimmed">Will be calculated on verify</Text>
        </Paper>
      </SimpleGrid>

      <Stack gap="sm">
        {targets.map(t => {
          const goalsMet = t.criteria.filter(c => c.goal_met === true).length;
          const totalCriteria = t.criteria.length;
          const allMet = totalCriteria > 0 && goalsMet === totalCriteria;
          const cfg = STATUS_CONFIG[t.status];
          return (
            <Paper key={t.id} withBorder p="sm" radius="md">
              <Group justify="space-between" wrap="nowrap" mb="xs">
                <div>
                  <Group gap="xs">
                    <Text fw={600}>{t.title}</Text>
                    <Badge size="xs" color={cfg.color}>{cfg.label}</Badge>
                  </Group>
                  <Text size="xs" c="dimmed">
                    Staff: {t.user.name} · {dayjs(t.period_start).format('D MMM')} – {dayjs(t.period_end).format('D MMM YYYY')}
                  </Text>
                </div>
                <Stack gap={2} align="flex-end">
                  {t.manager_commission_type !== 'none' && (
                    <Text size="xs" c="dimmed">
                      Your commission: {t.manager_commission_type === 'fixed'
                        ? `${formatCurrency(t.manager_commission_value ?? 0)} (fixed)`
                        : `${t.manager_commission_value}% of gross`}
                    </Text>
                  )}
                  {t.status === 'verified' && (t.manager_commission_earned ?? 0) > 0 && (
                    <Badge color="green" variant="filled">
                      Earned {formatCurrency(t.manager_commission_earned!)}
                    </Badge>
                  )}
                  {t.status === 'verified' && (t.manager_commission_earned ?? 0) === 0 && t.manager_commission_type !== 'none' && (
                    <Badge color="gray">Not earned</Badge>
                  )}
                </Stack>
              </Group>
              {totalCriteria > 0 && (
                <Group gap="xs" wrap="nowrap" mb="xs">
                  <Progress value={(goalsMet / totalCriteria) * 100} size="sm" style={{ flex: 1 }}
                    color={allMet ? 'green' : t.status === 'verified' ? 'orange' : 'blue'} />
                  <Text size="xs" c="dimmed" style={{ flexShrink: 0 }}>
                    {goalsMet}/{totalCriteria} goals
                  </Text>
                </Group>
              )}
              {/* Staff commission breakdown — visible to manager */}
              {t.status === 'verified' && (
                <SimpleGrid cols={{ base: 2, sm: 4 }} spacing="xs">
                  <div>
                    <Text size="xs" c="dimmed">Staff gross</Text>
                    <Text size="sm" fw={500}>{formatCurrency(t.gross_commission)}</Text>
                  </div>
                  {(t.salary_deduction_earned ?? 0) > 0 && (
                    <div>
                      <Text size="xs" c="dimmed">Salary deduction</Text>
                      <Text size="sm" fw={500} c="red">−{formatCurrency(t.salary_deduction_earned!)}</Text>
                    </div>
                  )}
                  <div>
                    <Text size="xs" c="dimmed">Staff total</Text>
                    <Text size="sm" fw={500} c={t.total_commission > 0 ? 'green' : undefined}>
                      {formatCurrency(t.total_commission)}
                    </Text>
                  </div>
                  <div>
                    <Text size="xs" c="dimmed">Your override</Text>
                    <Text size="sm" fw={500} c={(t.manager_commission_earned ?? 0) > 0 ? 'green' : 'dimmed'}>
                      {formatCurrency(t.manager_commission_earned ?? 0)}
                    </Text>
                  </div>
                </SimpleGrid>
              )}
            </Paper>
          );
        })}
      </Stack>
    </Stack>
  );
}

// ── Dashboard Tab ──────────────────────────────────────────────────────────────

function DashboardTab() {
  const { user } = useAuth();
  const { data, isLoading } = useQuery({
    queryKey: ['staff-targets-mine'],
    queryFn: () => getTargets(),
  });
  // Always show only the logged-in user's own targets, regardless of role
  const allTargets: StaffTarget[] = data?.data?.data ?? [];
  const targets = allTargets.filter(t => t.user.id === user?.id);

  const activeTargets   = targets.filter(t => t.status === 'active' || t.status === 'self_reported');
  const verifiedTargets = targets.filter(t => t.status === 'verified');

  // Distinct managers across the user's active targets
  const managersByTarget = activeTargets.filter(t => t.manager).map(t => ({
    target_title: t.title,
    manager: t.manager!,
  }));

  const totalEarned    = verifiedTargets.reduce((s, t) => s + t.total_commission, 0);
  const totalDeducted  = verifiedTargets.reduce((s, t) => s + (t.salary_deduction_earned ?? 0), 0);

  // Theoretical potential from active targets (assuming all goals met)
  const totalPotential = activeTargets.reduce((s, t) => {
    const critPot = t.criteria.reduce((cs, c) => cs + criterionPotential(c), 0);
    const groupPot = groupBonusPotential(t);
    return s + critPot + groupPot;
  }, 0);

  if (isLoading) return <Center py="xl"><Loader /></Center>;

  return (
    <Stack>
      {/* Stat cards */}
      <SimpleGrid cols={{ base: 2, sm: 4 }} spacing="sm">
        <StatCard label="Commission Earned" value={formatCurrency(totalEarned)} color="green" icon={<IconCoin size={18} />} />
        <StatCard label="Potential (Active)" value={formatCurrency(totalPotential)} color="blue" icon={<IconTrendingUp size={18} />} />
        <StatCard label="Active Targets" value={String(activeTargets.length)} color="blue" icon={<IconTarget size={18} />} />
        {totalDeducted > 0 && (
          <StatCard label="Deductions" value={formatCurrency(totalDeducted)} color="red" icon={<IconAlertTriangle size={18} />} />
        )}
      </SimpleGrid>

      {/* Your team — supervisor + per-target managers */}
      {(user?.supervisor || managersByTarget.length > 0) && (
        <Paper withBorder p="sm" radius="md">
          <Group gap="xs" mb="xs">
            <ThemeIcon size="sm" variant="light" color="blue" radius="xl">
              <IconUsers size={14} />
            </ThemeIcon>
            <Text fw={600} size="sm">Your team</Text>
          </Group>
          <SimpleGrid cols={{ base: 1, sm: 2 }} spacing="sm">
            {user?.supervisor && (
              <div>
                <Text size="xs" c="dimmed">Supervisor</Text>
                <Text size="sm" fw={500}>{user.supervisor.name}</Text>
                {user.supervisor.email && (
                  <Text size="xs" c="dimmed">{user.supervisor.email}</Text>
                )}
              </div>
            )}
            {managersByTarget.length > 0 && (
              <div>
                <Text size="xs" c="dimmed">
                  {managersByTarget.length === 1 ? 'Target manager' : 'Target managers'}
                </Text>
                <Stack gap={2}>
                  {managersByTarget.map((m, i) => (
                    <Text key={i} size="sm">
                      <Text span fw={500}>{m.manager.name}</Text>
                      <Text span c="dimmed" size="xs"> — {m.target_title}</Text>
                    </Text>
                  ))}
                </Stack>
              </div>
            )}
          </SimpleGrid>
        </Paper>
      )}

      {/* Active targets progress */}
      {activeTargets.length > 0 && (
        <>
          <Text fw={600} size="sm" mt="sm">Active Target Progress</Text>
          <Stack gap="sm">
            {activeTargets.map(t => <TargetProgressCard key={t.id} target={t} />)}
          </Stack>
        </>
      )}

      {/* Recent earnings */}
      {verifiedTargets.length > 0 && (
        <>
          <Text fw={600} size="sm" mt="sm">Recent Commission Earned</Text>
          <Stack gap="xs">
            {verifiedTargets.slice(0, 5).map(t => (
              <Paper key={t.id} withBorder p="sm" radius="md">
                <Group justify="space-between" wrap="nowrap">
                  <div>
                    <Text size="sm" fw={500}>{t.title}</Text>
                    <Text size="xs" c="dimmed">
                      {dayjs(t.period_start).format('D MMM')} – {dayjs(t.period_end).format('D MMM YYYY')}
                      {t.salary_deduction_earned ? ` · Deduction: ${formatCurrency(t.salary_deduction_earned)}` : ''}
                    </Text>
                  </div>
                  <Badge
                    color={t.total_commission > 0 ? 'green' : 'gray'}
                    variant="light" size="md">
                    {formatCurrency(t.total_commission)}
                  </Badge>
                </Group>
              </Paper>
            ))}
          </Stack>
        </>
      )}

      {activeTargets.length === 0 && verifiedTargets.length === 0 && (
        <Center py="xl">
          <Stack align="center" gap="xs">
            <ThemeIcon size="xl" variant="light" color="gray" radius="xl">
              <IconTarget size={24} />
            </ThemeIcon>
            <Text c="dimmed">No targets assigned to you yet.</Text>
          </Stack>
        </Center>
      )}
    </Stack>
  );
}

function StatCard({ label, value, color, icon }: { label: string; value: string; color: string; icon: React.ReactNode }) {
  return (
    <Paper withBorder p="sm" radius="md">
      <Group gap="xs" mb={4}>
        <ThemeIcon size="sm" variant="light" color={color} radius="xl">{icon}</ThemeIcon>
        <Text size="xs" c="dimmed">{label}</Text>
      </Group>
      <Text fw={700} size="lg" c={color}>{value}</Text>
    </Paper>
  );
}

function TargetProgressCard({ target: t }: { target: StaffTarget }) {
  const daysLeft   = dayjs(t.period_end).diff(dayjs(), 'day');
  const groupBonus = groupBonusPotential(t);

  // Determine all-goals-met based on achieved values (for active/self_reported)
  const selfAllMet = t.criteria.length > 0
    && t.criteria.every(c => (c.achieved_value ?? 0) >= c.goal_value);

  const metCount = t.criteria.filter(c => (c.achieved_value ?? 0) >= c.goal_value).length;
  const overallPct = t.criteria.length > 0
    ? Math.round(t.criteria.reduce((s, c) => s + Math.min(100, (c.achieved_value ?? 0) / c.goal_value * 100), 0) / t.criteria.length)
    : 0;

  return (
    <Paper withBorder p="md" radius="md"
      style={{ borderLeft: `3px solid var(--mantine-color-${STATUS_CONFIG[t.status].color}-5)` }}>
      <Stack gap="sm">
        {/* Header */}
        <Group justify="space-between" wrap="nowrap">
          <Group gap="xs" wrap="nowrap" style={{ flex: 1, minWidth: 0 }}>
            <Badge size="sm" color={STATUS_CONFIG[t.status].color} variant="dot">
              {STATUS_CONFIG[t.status].label}
            </Badge>
            <Text size="sm" fw={600} truncate>{t.title}</Text>
          </Group>
          <Group gap="xs" style={{ flexShrink: 0 }}>
            <RingProgress size={48} thickness={4} roundCaps
              sections={[{ value: overallPct, color: overallPct >= 100 ? 'green' : overallPct >= 60 ? 'blue' : 'orange' }]}
              label={<Text size="9px" ta="center" fw={700}>{overallPct}%</Text>}
            />
            <Stack gap={0} align="flex-end">
              <Text size="xs" fw={500} c={daysLeft <= 2 ? 'red' : daysLeft <= 5 ? 'orange' : 'dimmed'}>
                {daysLeft > 0 ? `${daysLeft}d left` : 'Ended'}
              </Text>
              <Text size="xs" c="dimmed">{metCount}/{t.criteria.length} goals</Text>
            </Stack>
          </Group>
        </Group>

        {/* Per-criterion progress */}
        <Stack gap="xs">
          {t.criteria.map(c => {
            const achieved  = c.achieved_value ?? 0;
            const pct       = Math.min(100, c.goal_value > 0 ? (achieved / c.goal_value) * 100 : 0);
            const goalMet   = achieved >= c.goal_value;
            const remaining = Math.max(0, c.goal_value - achieved);
            const potential = criterionPotential(c);

            return (
              <div key={c.id}>
                <Group justify="space-between" mb={3}>
                  <Text size="xs" fw={500}>{c.label}</Text>
                  <Group gap={6}>
                    {t.status === 'self_reported' && (
                      <Text size="xs" c="dimmed">{fmtNum(achieved, c.unit)} / {fmtNum(c.goal_value, c.unit)}</Text>
                    )}
                    {t.status === 'active' && (
                      <Text size="xs" c="dimmed">Target: {fmtNum(c.goal_value, c.unit)}</Text>
                    )}
                    {goalMet && <Badge size="xs" color="green">✓</Badge>}
                  </Group>
                </Group>
                <Progress size="sm" radius="sm" mb={3}
                  value={t.status === 'self_reported' ? pct : 0}
                  color={goalMet ? 'green' : pct >= 60 ? 'blue' : pct > 0 ? 'orange' : 'gray'}
                />
                <Group justify="space-between">
                  <Text size="xs" c={goalMet ? 'green' : 'dimmed'}>
                    {t.status === 'self_reported'
                      ? goalMet ? '✓ Goal achieved!' : `${fmtNum(remaining, c.unit)} to go`
                      : `Need ${fmtNum(c.goal_value, c.unit)}`}
                  </Text>
                  {potential > 0 && (
                    <Text size="xs" c={goalMet ? 'green' : 'dimmed'}>
                      {goalMet ? '+ ' : ''}{formatCurrency(potential)} {goalMet ? 'earned' : 'at stake'}
                    </Text>
                  )}
                </Group>
              </div>
            );
          })}
        </Stack>

        {/* Group bonus */}
        {t.group_commission_type !== 'none' && groupBonus > 0 && (
          <Paper withBorder p="xs" radius="sm" bg={selfAllMet ? 'green.0' : 'yellow.0'}>
            <Group gap="xs">
              <IconMoodHappy size={14} color={selfAllMet ? 'green' : 'orange'} />
              <Text size="xs" fw={500} c={selfAllMet ? 'green' : 'orange'}>
                Group bonus {formatCurrency(groupBonus)} —{' '}
                {selfAllMet ? 'All goals met! 🎉' : `Meet all ${t.criteria.length} goals to earn it`}
              </Text>
            </Group>
          </Paper>
        )}

        {/* Deduction risk */}
        {t.deduct_on_failure && t.staff_salary && !selfAllMet && (
          <Paper withBorder p="xs" radius="sm" bg="red.0">
            <Group gap="xs">
              <IconAlertTriangle size={14} color="red" />
              <Text size="xs" c="red" fw={500}>
                Risk: {formatCurrency(t.staff_salary / 2)} salary deduction if any goal is missed
              </Text>
            </Group>
          </Paper>
        )}
      </Stack>
    </Paper>
  );
}

// ── My Targets Tab ─────────────────────────────────────────────────────────────

function MyTargetsTab({ can }: { can: (p: string) => boolean }) {
  const { user } = useAuth();
  const qc = useQueryClient();
  const [reporting, setReporting] = useState<StaffTarget | null>(null);
  const [reportModal, { open: openReport, close: closeReport }] = useDisclosure(false);

  const { data, isLoading } = useQuery({
    queryKey: ['staff-targets-mine'],
    queryFn: () => getTargets(),
  });
  // Only show the current user's own targets (supervisors still see own targets here)
  const allTargets: StaffTarget[] = data?.data?.data ?? [];
  const targets = allTargets.filter(t => t.user.id === user?.id);

  return (
    <Stack>
      {isLoading ? (
        <Center py="xl"><Loader /></Center>
      ) : targets.length === 0 ? (
        <Center py="xl">
          <Stack align="center" gap="xs">
            <ThemeIcon size="xl" variant="light" color="gray" radius="xl">
              <IconTarget size={24} />
            </ThemeIcon>
            <Text c="dimmed">No targets assigned to you yet.</Text>
          </Stack>
        </Center>
      ) : (
        <Stack gap="sm">
          {targets.map(t => (
            <TargetCard key={t.id} target={t}
              actions={
                (t.status === 'active' || t.status === 'self_reported') && can('staff_targets.submit') ? (
                  <Button size="xs" variant="light" color="blue"
                    leftSection={<IconClipboardCheck size={13} />}
                    onClick={() => { setReporting(t); openReport(); }}>
                    {t.status === 'self_reported' ? 'Update Report' : 'Enter Achieved'}
                  </Button>
                ) : null
              }
            />
          ))}
        </Stack>
      )}

      {reporting && (
        <SelfReportModal
          target={reporting} opened={reportModal}
          onClose={() => { closeReport(); setReporting(null); }}
          onSaved={() => qc.invalidateQueries({ queryKey: ['staff-targets-mine'] })}
        />
      )}
    </Stack>
  );
}

// ── Team Targets Tab ───────────────────────────────────────────────────────────

function TeamTargetsTab({ canManage, canVerify }: {
  canManage: boolean; canVerify: boolean;
}) {
  const qc = useQueryClient();
  const [statusFilter, setStatusFilter] = useState('');
  const [editing, setEditing]     = useState<StaffTarget | null>(null);
  const [verifying, setVerifying] = useState<StaffTarget | null>(null);
  const [formModal, { open: openForm, close: closeForm }]       = useDisclosure(false);
  const [verifyModal, { open: openVerify, close: closeVerify }] = useDisclosure(false);

  const { data, isLoading } = useQuery({
    queryKey: ['staff-targets-team', statusFilter],
    queryFn: () => getTargets({ status: statusFilter || undefined }),
  });
  const targets: StaffTarget[] = data?.data?.data ?? [];

  const deleteMutation = useMutation({
    mutationFn: deleteTarget,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['staff-targets-team'] });
      notifications.show({ message: 'Target deleted.', color: 'green' });
    },
    onError: (err: any) =>
      notifications.show({ message: err?.response?.data?.message ?? 'Cannot delete.', color: 'red' }),
  });

  return (
    <Stack>
      <Group justify="space-between" wrap="nowrap">
        <Select
          size="xs" placeholder="All statuses" clearable
          value={statusFilter} onChange={v => setStatusFilter(v ?? '')}
          data={Object.entries(STATUS_CONFIG).map(([v, c]) => ({ value: v, label: c.label }))}
          style={{ width: 180 }}
        />
        {canManage && (
          <Button size="sm" leftSection={<IconPlus size={16} />}
            onClick={() => { setEditing(null); openForm(); }}>
            New Target
          </Button>
        )}
      </Group>

      {isLoading ? (
        <Center py="xl"><Loader /></Center>
      ) : targets.length === 0 ? (
        <Center py="xl"><Text c="dimmed">No targets found.</Text></Center>
      ) : (
        <Stack gap="sm">
          {targets.map(t => (
            <TargetCard key={t.id} target={t}
              actions={
                <Group gap="xs" wrap="nowrap">
                  {canManage && t.status === 'active' && (
                    <>
                      <ActionIcon size="sm" variant="subtle"
                        onClick={() => { setEditing(t); openForm(); }}>
                        <IconEdit size={14} />
                      </ActionIcon>
                      <ActionIcon size="sm" variant="subtle" color="red"
                        onClick={() => deleteMutation.mutate(t.id)}>
                        <IconTrash size={14} />
                      </ActionIcon>
                    </>
                  )}
                  {canVerify && t.status === 'self_reported' && (
                    <Button size="xs" variant="light" color="green"
                      leftSection={<IconCheck size={13} />}
                      onClick={() => { setVerifying(t); openVerify(); }}>
                      Verify
                    </Button>
                  )}
                  {canVerify && t.status === 'verified' && (
                    <Button size="xs" variant="subtle" color="gray"
                      onClick={() => { setVerifying(t); openVerify(); }}>
                      Re-verify
                    </Button>
                  )}
                </Group>
              }
            />
          ))}
        </Stack>
      )}

      <TargetFormModal
        opened={formModal} onClose={closeForm} existing={editing}
        onSaved={() => qc.invalidateQueries({ queryKey: ['staff-targets-team'] })}
      />
      {verifying && (
        <VerifyModal
          target={verifying} opened={verifyModal}
          onClose={() => { closeVerify(); setVerifying(null); }}
          onSaved={() => qc.invalidateQueries({ queryKey: ['staff-targets-team'] })}
        />
      )}
    </Stack>
  );
}

// ── Commission Summary Tab ──────────────────────────────────────────────────────

function CommissionSummaryTab() {
  const { data, isLoading } = useQuery({
    queryKey: ['staff-commission-summary'],
    queryFn: () => getCommissionSummary(),
  });
  const entries: CommissionSummaryEntry[] = data?.data?.data ?? [];
  const totalNet       = entries.reduce((s, e) => s + e.total_commission, 0);
  const totalDeduction = entries.reduce((s, e) => s + e.salary_deductions, 0);

  return (
    <Stack>
      {isLoading ? (
        <Center py="xl"><Loader /></Center>
      ) : entries.length === 0 ? (
        <Center py="xl"><Text c="dimmed">No verified targets with commission yet.</Text></Center>
      ) : (
        <>
          <SimpleGrid cols={{ base: 1, sm: totalDeduction > 0 ? 3 : 1 }} spacing="sm">
            <Paper withBorder p="md" radius="md" bg="green.0">
              <Group gap="xs">
                <ThemeIcon color="green" variant="light" radius="xl"><IconCoin size={16} /></ThemeIcon>
                <Text size="sm" fw={700} c="green">
                  Net Payable: {formatCurrency(totalNet)}
                </Text>
              </Group>
            </Paper>
            {totalDeduction > 0 && (
              <>
                <Paper withBorder p="md" radius="md">
                  <Text size="xs" c="dimmed">Gross Commission</Text>
                  <Text fw={700}>{formatCurrency(entries.reduce((s, e) => s + e.gross_commission, 0))}</Text>
                </Paper>
                <Paper withBorder p="md" radius="md" bg="red.0">
                  <Text size="xs" c="dimmed">Salary Deductions</Text>
                  <Text fw={700} c="red">− {formatCurrency(totalDeduction)}</Text>
                </Paper>
              </>
            )}
          </SimpleGrid>

          <Table striped withTableBorder highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Staff Member</Table.Th>
                <Table.Th>Verified Targets</Table.Th>
                {totalDeduction > 0 && <Table.Th ta="right">Deduction</Table.Th>}
                <Table.Th ta="right">Net Commission</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {entries.map(e => (
                <Table.Tr key={e.user.id}>
                  <Table.Td fw={500}>{e.user.name}</Table.Td>
                  <Table.Td>
                    <Stack gap={2}>
                      {e.targets.map(t => (
                        <Group key={t.id} gap="xs">
                          <Text size="xs">{t.title}</Text>
                          <Text size="xs" c="dimmed">({t.period})</Text>
                          {t.commission_earned > 0 && (
                            <Badge size="xs" color="green" variant="light">
                              {formatCurrency(t.commission_earned)}
                            </Badge>
                          )}
                          {t.salary_deduction > 0 && (
                            <Badge size="xs" color="red" variant="light">
                              −{formatCurrency(t.salary_deduction)}
                            </Badge>
                          )}
                        </Group>
                      ))}
                    </Stack>
                  </Table.Td>
                  {totalDeduction > 0 && (
                    <Table.Td ta="right">
                      {e.salary_deductions > 0
                        ? <Text size="sm" c="red">−{formatCurrency(e.salary_deductions)}</Text>
                        : <Text size="sm" c="dimmed">—</Text>}
                    </Table.Td>
                  )}
                  <Table.Td ta="right">
                    <Text fw={700} c={e.total_commission > 0 ? 'green' : 'dimmed'}>
                      {formatCurrency(e.total_commission)}
                    </Text>
                  </Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        </>
      )}
    </Stack>
  );
}

// ── Target Card ────────────────────────────────────────────────────────────────

function TargetCard({ target: t, actions }: { target: StaffTarget; actions?: React.ReactNode }) {
  const [expanded, setExpanded] = useState(false);
  const statusCfg  = STATUS_CONFIG[t.status];
  const totalCrit  = t.criteria.length;
  const metCrit    = t.criteria.filter(c => c.goal_met).length;
  return (
    <Paper withBorder p="sm" radius="md"
      style={{
        cursor: 'pointer',
        borderLeft: t.status === 'verified' ? '3px solid var(--mantine-color-green-5)' : undefined,
      }}
      onClick={() => setExpanded(e => !e)}>
      <Stack gap="xs">
        <Group justify="space-between" wrap="nowrap">
          <Group gap="xs" wrap="nowrap" style={{ flex: 1, minWidth: 0 }}>
            <Badge size="sm" color={statusCfg.color} variant="dot">{statusCfg.label}</Badge>
            <Text size="sm" fw={600} truncate>{t.title}</Text>
            <Text size="xs" c="dimmed" style={{ flexShrink: 0 }}>
              {dayjs(t.period_start).format('D MMM')} – {dayjs(t.period_end).format('D MMM YYYY')}
            </Text>
          </Group>
          <Group gap="xs" wrap="nowrap" onClick={e => e.stopPropagation()}>
            {t.status === 'verified' && t.total_commission > 0 && (
              <Badge size="sm" color="green" variant="light" leftSection={<IconCoin size={10} />}>
                {formatCurrency(t.total_commission)}
              </Badge>
            )}
            {t.status === 'verified' && (t.salary_deduction_earned ?? 0) > 0 && (
              <Badge size="sm" color="red" variant="light">
                −{formatCurrency(t.salary_deduction_earned!)}
              </Badge>
            )}
            <Text size="xs" c="dimmed">{t.user.name}</Text>
            {actions}
            <ActionIcon size="xs" variant="transparent" color="dimmed">
              {expanded ? <IconChevronUp size={14} /> : <IconChevronDown size={14} />}
            </ActionIcon>
          </Group>
        </Group>

        {t.status !== 'active' && totalCrit > 0 && (
          <Progress size="xs"
            value={t.status === 'verified' ? (metCrit / totalCrit) * 100 : 50}
            color={t.status === 'verified' ? (metCrit === totalCrit ? 'green' : 'orange') : 'blue'}
          />
        )}

        <Collapse in={expanded}>
          <Stack gap="sm" mt="xs">
            {t.description && <Text size="xs" c="dimmed">{t.description}</Text>}

            {/* Criteria table */}
            <div style={{ overflowX: 'auto' }}>
              <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '13px' }}>
                <thead>
                  <tr style={{ borderBottom: '1px solid var(--mantine-color-default-border)' }}>
                    <th style={{ padding: '4px 8px', textAlign: 'left' }}>Goal</th>
                    <th style={{ padding: '4px 8px', textAlign: 'right' }}>Target</th>
                    <th style={{ padding: '4px 8px', textAlign: 'right' }}>Reported</th>
                    <th style={{ padding: '4px 8px', textAlign: 'right' }}>Verified</th>
                    <th style={{ padding: '4px 8px', textAlign: 'right' }}>Commission</th>
                    <th style={{ padding: '4px 8px', textAlign: 'center' }}>Status</th>
                  </tr>
                </thead>
                <tbody>
                  {t.criteria.map(c => (
                    <tr key={c.id} style={{ borderBottom: '1px solid var(--mantine-color-default-border)' }}>
                      <td style={{ padding: '6px 8px' }}>
                        <Stack gap={0}>
                          <Text size="xs" fw={500}>{c.label}</Text>
                          <Text size="xs" c="dimmed">{TYPE_LABELS[c.type]}</Text>
                        </Stack>
                      </td>
                      <td style={{ padding: '6px 8px', textAlign: 'right' }}>
                        <Text size="xs">{fmtNum(c.goal_value, c.unit)}</Text>
                      </td>
                      <td style={{ padding: '6px 8px', textAlign: 'right' }}>
                        <Text size="xs" c={c.achieved_value !== null ? 'blue' : 'dimmed'}>
                          {fmtNum(c.achieved_value, c.unit)}
                        </Text>
                      </td>
                      <td style={{ padding: '6px 8px', textAlign: 'right' }}>
                        <Text size="xs" c={c.verified_value !== null ? (c.goal_met ? 'green' : 'orange') : 'dimmed'}>
                          {fmtNum(c.verified_value, c.unit)}
                        </Text>
                      </td>
                      <td style={{ padding: '6px 8px', textAlign: 'right' }}>
                        <Text size="xs" c={c.commission_earned ? 'green' : 'dimmed'}>
                          {c.commission_earned != null
                            ? formatCurrency(c.commission_earned)
                            : commissionLabel(c)}
                        </Text>
                      </td>
                      <td style={{ padding: '6px 8px', textAlign: 'center' }}>
                        {c.goal_met === true  && <Badge size="xs" color="green">Met</Badge>}
                        {c.goal_met === false && <Badge size="xs" color="red">Missed</Badge>}
                        {c.goal_met === null  && <Badge size="xs" color="gray">Pending</Badge>}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            {/* Group bonus & salary info */}
            {(t.group_commission_type !== 'none' || t.deduct_on_failure) && (
              <Paper withBorder p="xs" radius="sm">
                <Stack gap={4}>
                  {t.group_commission_type !== 'none' && (
                    <Group gap="xs" wrap="nowrap">
                      <Text size="xs" fw={500} style={{ flexShrink: 0 }}>Group bonus:</Text>
                      <Text size="xs" c="dimmed">
                        {t.group_commission_type === 'fixed'
                          ? `${formatCurrency(t.group_commission_value ?? 0)} if ALL goals met`
                          : `${t.group_commission_value}% of salary if ALL goals met`}
                      </Text>
                      {t.group_commission_earned != null && t.group_commission_earned > 0 && (
                        <Badge size="xs" color="green">Earned: {formatCurrency(t.group_commission_earned)}</Badge>
                      )}
                      {t.status === 'verified' && (t.group_commission_earned === 0 || t.group_commission_earned == null) && (
                        <Badge size="xs" color="gray">Not earned</Badge>
                      )}
                    </Group>
                  )}
                  {t.deduct_on_failure && t.staff_salary && (
                    <Group gap="xs" wrap="nowrap">
                      <Text size="xs" fw={500} style={{ flexShrink: 0 }}>Failure penalty:</Text>
                      <Text size="xs" c="dimmed">
                        {formatCurrency(t.staff_salary / 2)} deduction if any goal missed
                      </Text>
                      {(t.salary_deduction_earned ?? 0) > 0 && (
                        <Badge size="xs" color="red">Deducted: {formatCurrency(t.salary_deduction_earned!)}</Badge>
                      )}
                    </Group>
                  )}
                </Stack>
              </Paper>
            )}

            {t.manager && (
              <Paper withBorder p="xs" radius="sm">
                <Group gap="xs" wrap="nowrap">
                  <Text size="xs" fw={500} style={{ flexShrink: 0 }}>Manager:</Text>
                  <Text size="xs">{t.manager.name}</Text>
                  {t.manager_commission_type !== 'none' && (
                    <Text size="xs" c="dimmed">
                      · {t.manager_commission_type === 'fixed'
                        ? `${formatCurrency(t.manager_commission_value ?? 0)} if ALL goals met`
                        : `${t.manager_commission_value}% of gross commission if ALL goals met`}
                    </Text>
                  )}
                  {(t.manager_commission_earned ?? 0) > 0 && (
                    <Badge size="xs" color="green">Earned: {formatCurrency(t.manager_commission_earned!)}</Badge>
                  )}
                  {t.status === 'verified' && t.manager_commission_type !== 'none' && (t.manager_commission_earned ?? 0) === 0 && (
                    <Badge size="xs" color="gray">Not earned</Badge>
                  )}
                </Group>
              </Paper>
            )}

            {t.supervisor_notes && (
              <Paper withBorder p="xs" radius="sm" bg="green.0">
                <Group gap="xs">
                  <IconMoodHappy size={14} />
                  <Text size="xs" fs="italic">"{t.supervisor_notes}"</Text>
                  <Text size="xs" c="dimmed">— {t.verified_by?.name}</Text>
                </Group>
              </Paper>
            )}

            <Text size="xs" c="dimmed">
              Assigned by {t.assigned_by.name} · {dayjs(t.created_at).format('D MMM YYYY')}
              {t.verified_at && ` · Verified ${dayjs(t.verified_at).format('D MMM YYYY')}`}
            </Text>
          </Stack>
        </Collapse>
      </Stack>
    </Paper>
  );
}

// ── Self-Report Modal ──────────────────────────────────────────────────────────

function SelfReportModal({ target, opened, onClose, onSaved }: {
  target: StaffTarget; opened: boolean; onClose: () => void; onSaved: () => void;
}) {
  const [values, setValues] = useState<Record<string, number>>({});

  useEffect(() => {
    if (opened) {
      const init: Record<string, number> = {};
      target.criteria.forEach(c => { init[c.id] = c.achieved_value ?? 0; });
      setValues(init);
    }
  }, [opened, target]);

  const mutation = useMutation({
    mutationFn: () => selfReportTarget(target.id, {
      criteria: target.criteria.map(c => ({ id: c.id, achieved_value: values[c.id] ?? 0 })),
    }),
    onSuccess: () => {
      notifications.show({ message: 'Achievement submitted for review.', color: 'green' });
      onSaved(); onClose();
    },
    onError: () => notifications.show({ message: 'Failed to submit.', color: 'red' }),
  });

  const allMet = target.criteria.every(c => (values[c.id] ?? 0) >= c.goal_value);
  const groupBonus = groupBonusPotential(target);

  return (
    <Modal opened={opened} onClose={onClose} title={`Report Achievement — ${target.title}`}
      centered size="lg" scrollAreaComponent={ScrollArea.Autosize}>
      <Stack gap="md">
        <Text size="xs" c="dimmed">
          Enter what you actually achieved for each goal. Your supervisor will verify and confirm.
        </Text>

        <Stack gap="sm">
          {target.criteria.map(c => {
            const val = values[c.id] ?? 0;
            const met = val >= c.goal_value;
            return (
              <Paper key={c.id} withBorder p="sm" radius="md">
                <Group justify="space-between" wrap="nowrap" mb="xs">
                  <div>
                    <Text size="sm" fw={600}>{c.label}</Text>
                    <Text size="xs" c="dimmed">{TYPE_LABELS[c.type]} · Target: {fmtNum(c.goal_value, c.unit)}</Text>
                  </div>
                  <Badge size="xs" variant="light">{commissionLabel(c)}</Badge>
                </Group>
                <NumberInput
                  label={`Achieved (${c.unit})`} min={0}
                  value={val}
                  onChange={v => setValues(prev => ({ ...prev, [c.id]: Number(v) || 0 }))}
                  suffix={` ${c.unit}`}
                  leftSection={met ? <IconCheck size={14} color="green" /> : <IconAlertTriangle size={14} color="orange" />}
                />
                {met && (
                  <Text size="xs" c="green" mt={4}>
                    ✓ Goal met! Commission: {commissionLabel(c)}
                  </Text>
                )}
              </Paper>
            );
          })}
        </Stack>

        {/* Group bonus / deduction preview */}
        {(target.group_commission_type !== 'none' || target.deduct_on_failure) && (
          <Paper withBorder p="sm" radius="md" bg={allMet ? 'green.0' : 'orange.0'}>
            <Stack gap={4}>
              {target.group_commission_type !== 'none' && groupBonus > 0 && (
                <Group gap="xs">
                  <Text size="xs" fw={500}>Group bonus:</Text>
                  <Text size="xs" c={allMet ? 'green' : 'orange'}>
                    {formatCurrency(groupBonus)} — {allMet ? '🎉 All goals met!' : 'Not yet earned'}
                  </Text>
                </Group>
              )}
              {target.deduct_on_failure && target.staff_salary && !allMet && (
                <Group gap="xs">
                  <IconAlertTriangle size={13} color="orange" />
                  <Text size="xs" c="orange">
                    Risk: {formatCurrency(target.staff_salary / 2)} deduction if supervisor confirms missed goals
                  </Text>
                </Group>
              )}
            </Stack>
          </Paper>
        )}

        <Group justify="flex-end">
          <Button variant="default" onClick={onClose}>Cancel</Button>
          <Button loading={mutation.isPending} onClick={() => mutation.mutate()}
            leftSection={<IconClipboardCheck size={14} />}>
            Submit for Verification
          </Button>
        </Group>
      </Stack>
    </Modal>
  );
}

// ── Verify Modal ───────────────────────────────────────────────────────────────

function VerifyModal({ target, opened, onClose, onSaved }: {
  target: StaffTarget; opened: boolean; onClose: () => void; onSaved: () => void;
}) {
  const [values, setValues] = useState<Record<string, number>>({});
  const [notes, setNotes]   = useState('');

  useEffect(() => {
    if (opened) {
      const init: Record<string, number> = {};
      target.criteria.forEach(c => { init[c.id] = c.verified_value ?? c.achieved_value ?? 0; });
      setValues(init);
      setNotes(target.supervisor_notes ?? '');
    }
  }, [opened, target]);

  const mutation = useMutation({
    mutationFn: () => verifyTarget(target.id, {
      criteria: target.criteria.map(c => ({ id: c.id, verified_value: values[c.id] ?? 0 })),
      supervisor_notes: notes || undefined,
    }),
    onSuccess: () => {
      notifications.show({ message: 'Target verified. Commission calculated.', color: 'green' });
      onSaved(); onClose();
    },
    onError: () => notifications.show({ message: 'Failed to verify.', color: 'red' }),
  });

  // Live commission preview
  const criteriaCommission = target.criteria.reduce((sum, c) => {
    const v   = values[c.id] ?? 0;
    const met = v >= c.goal_value;
    if (!met || c.commission_type === 'none') return sum;
    if (c.commission_type === 'fixed') return sum + (c.commission_value ?? 0);
    return sum + (c.commission_value ?? 0) / 100 * v;
  }, 0);

  const allGoalsMet = target.criteria.every(c => (values[c.id] ?? 0) >= c.goal_value);
  const groupBonus  = allGoalsMet ? groupBonusPotential(target) : 0;
  const deduction   = !allGoalsMet && target.deduct_on_failure
    ? (target.staff_salary ?? 0) / 2 : 0;
  const netTotal    = criteriaCommission + groupBonus - deduction;

  return (
    <Modal opened={opened} onClose={onClose}
      title={<Group gap="xs">
        <Text fw={600}>{target.user.name} — {target.title}</Text>
        <Badge size="sm" color="orange" variant="light">Verify</Badge>
      </Group>}
      centered size="xl" scrollAreaComponent={ScrollArea.Autosize}>
      <Stack gap="md">
        <SimpleGrid cols={2} spacing="xs">
          <Text size="xs" c="dimmed">Period: {dayjs(target.period_start).format('D MMM')} – {dayjs(target.period_end).format('D MMM YYYY')}</Text>
          <Text size="xs" c="dimmed" ta="right">Assigned by: {target.assigned_by.name}</Text>
        </SimpleGrid>

        <Stack gap="sm">
          {target.criteria.map(c => {
            const v   = values[c.id] ?? 0;
            const met = v >= c.goal_value;
            const earned = !met || c.commission_type === 'none' ? 0
              : c.commission_type === 'fixed' ? (c.commission_value ?? 0)
              : (c.commission_value ?? 0) / 100 * v;

            return (
              <Paper key={c.id} withBorder p="sm" radius="md"
                style={{ borderLeft: met ? '3px solid var(--mantine-color-green-5)' : '3px solid var(--mantine-color-orange-5)' }}>
                <Group justify="space-between" mb="xs" wrap="nowrap">
                  <div>
                    <Text size="sm" fw={600}>{c.label}</Text>
                    <Text size="xs" c="dimmed">
                      Target: {fmtNum(c.goal_value, c.unit)}
                      {c.achieved_value != null && ` · Self-reported: ${fmtNum(c.achieved_value, c.unit)}`}
                    </Text>
                  </div>
                  <Stack gap={2} align="flex-end">
                    <Badge size="xs" variant="light">{commissionLabel(c)}</Badge>
                    {earned > 0 && (
                      <Badge size="xs" color="green" variant="filled">
                        {formatCurrency(earned)} earned
                      </Badge>
                    )}
                  </Stack>
                </Group>
                <NumberInput
                  label={`Verified value (${c.unit})`} min={0} value={v}
                  onChange={val => setValues(prev => ({ ...prev, [c.id]: Number(val) || 0 }))}
                  leftSection={met ? <IconCheck size={14} color="green" /> : <IconX size={14} color="orange" />}
                />
                {met
                  ? <Text size="xs" c="green" mt={4}>Goal met ✓</Text>
                  : <Text size="xs" c="orange" mt={4}>Goal not met ({fmtNum(c.goal_value - v, c.unit)} short)</Text>}
              </Paper>
            );
          })}
        </Stack>

        {/* Commission breakdown */}
        <Paper withBorder p="sm" radius="md" bg={netTotal > 0 ? 'green.0' : netTotal < 0 ? 'red.0' : undefined}>
          <Stack gap="xs">
            <Group justify="space-between">
              <Text size="xs" c="dimmed">Individual commissions:</Text>
              <Text size="xs" fw={500}>{formatCurrency(criteriaCommission)}</Text>
            </Group>
            {target.group_commission_type !== 'none' && (
              <Group justify="space-between">
                <Group gap="xs">
                  <Text size="xs" c="dimmed">Group bonus:</Text>
                  <Badge size="xs" color={allGoalsMet ? 'green' : 'gray'} variant="light">
                    {allGoalsMet ? 'All goals ✓' : 'Not earned'}
                  </Badge>
                </Group>
                <Text size="xs" fw={500} c={allGoalsMet ? 'green' : 'dimmed'}>
                  {allGoalsMet ? `+ ${formatCurrency(groupBonus)}` : '—'}
                </Text>
              </Group>
            )}
            {target.deduct_on_failure && target.staff_salary && (
              <Group justify="space-between">
                <Group gap="xs">
                  <Text size="xs" c="dimmed">Salary deduction:</Text>
                  <Badge size="xs" color={!allGoalsMet ? 'red' : 'gray'} variant="light">
                    {!allGoalsMet ? 'Applied' : 'Not applied'}
                  </Badge>
                </Group>
                <Text size="xs" fw={500} c={!allGoalsMet ? 'red' : 'dimmed'}>
                  {!allGoalsMet ? `− ${formatCurrency(deduction)}` : '—'}
                </Text>
              </Group>
            )}
            {target.manager && target.manager_commission_type !== 'none' && (() => {
              const grossPreview = criteriaCommission + groupBonus;
              const managerEarned = allGoalsMet
                ? (target.manager_commission_type === 'fixed'
                    ? (target.manager_commission_value ?? 0)
                    : (target.manager_commission_value ?? 0) / 100 * grossPreview)
                : 0;
              return (
                <Group justify="space-between">
                  <Group gap="xs">
                    <Text size="xs" c="dimmed">Manager ({target.manager.name}):</Text>
                    <Badge size="xs" color={allGoalsMet ? 'green' : 'gray'} variant="light">
                      {allGoalsMet ? 'All goals ✓' : 'Not earned'}
                    </Badge>
                  </Group>
                  <Text size="xs" fw={500} c={allGoalsMet ? 'green' : 'dimmed'}>
                    {allGoalsMet ? formatCurrency(managerEarned) : '—'}
                  </Text>
                </Group>
              );
            })()}
            <Divider />
            <Group justify="space-between">
              <Text size="sm" fw={700}>Net payable:</Text>
              <Text size="sm" fw={700} c={netTotal > 0 ? 'green' : netTotal < 0 ? 'red' : 'dimmed'}>
                {formatCurrency(netTotal)}
              </Text>
            </Group>
          </Stack>
        </Paper>

        <Textarea label="Feedback / Notes (optional)"
          placeholder="Leave feedback for the staff member…"
          minRows={2} autosize maxRows={4}
          value={notes} onChange={e => setNotes(e.currentTarget.value)}
        />

        <Group justify="flex-end">
          <Button variant="default" onClick={onClose}>Cancel</Button>
          <Button loading={mutation.isPending} color="green"
            leftSection={<IconCheck size={14} />}
            onClick={() => mutation.mutate()}>
            Confirm & Calculate Commission
          </Button>
        </Group>
      </Stack>
    </Modal>
  );
}

// ── Create/Edit Target Modal ───────────────────────────────────────────────────

interface CriterionDraft {
  type:             CriterionType;
  label:            string;
  unit:             string;
  goal_value:       number;
  commission_type:  CommissionType;
  commission_value: number | '';
}

function TargetFormModal({ opened, onClose, existing, onSaved }: {
  opened: boolean; onClose: () => void;
  existing: StaffTarget | null; onSaved: () => void;
}) {
  const qc = useQueryClient();
  const { data: usersData } = useQuery({
    queryKey: ['staff-supervisors'],
    queryFn: () => import('../api/staffReports').then(m => m.getSupervisors()),
    enabled: opened,
  });
  const userOptions = (usersData?.data?.data ?? []).map((u: any) => ({ value: u.id, label: u.name }));

  const [periodDates, setPeriodDates]   = useState<[Date | null, Date | null]>([null, null]);
  const [criteria, setCriteria]         = useState<CriterionDraft[]>([emptyDraft()]);
  const [groupCommType, setGroupCommType]   = useState<CommissionType>('none');
  const [groupCommValue, setGroupCommValue] = useState<number | ''>('');
  const [staffSalary, setStaffSalary]   = useState<number | ''>('');
  const [deductOnFail, setDeductOnFail] = useState(false);
  const [managerId, setManagerId]               = useState<string | null>(null);
  const [managerCommType, setManagerCommType]   = useState<CommissionType>('none');
  const [managerCommValue, setManagerCommValue] = useState<number | ''>('');

  const form = useForm({
    initialValues: { user_id: '', title: '', description: '' },
    validate: {
      user_id: v => !v ? 'Staff member is required' : null,
      title:   v => !v.trim() ? 'Title is required' : null,
    },
  });

  useEffect(() => {
    if (opened) {
      if (existing) {
        form.setValues({ user_id: existing.user.id, title: existing.title, description: existing.description ?? '' });
        setPeriodDates([new Date(existing.period_start), new Date(existing.period_end)]);
        setCriteria(existing.criteria.map(c => ({
          type: c.type, label: c.label, unit: c.unit,
          goal_value: c.goal_value,
          commission_type: c.commission_type,
          commission_value: c.commission_value ?? '',
        })));
        setGroupCommType(existing.group_commission_type ?? 'none');
        setGroupCommValue(existing.group_commission_value ?? '');
        setStaffSalary(existing.staff_salary ?? '');
        setDeductOnFail(existing.deduct_on_failure ?? false);
        setManagerId(existing.manager?.id ?? null);
        setManagerCommType(existing.manager_commission_type ?? 'none');
        setManagerCommValue(existing.manager_commission_value ?? '');
      } else {
        form.reset();
        setPeriodDates([null, null]);
        setCriteria([emptyDraft()]);
        setGroupCommType('none');
        setGroupCommValue('');
        setStaffSalary('');
        setDeductOnFail(false);
        setManagerId(null);
        setManagerCommType('none');
        setManagerCommValue('');
      }
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [opened, existing?.id]);

  const mutation = useMutation({
    mutationFn: (v: ReturnType<typeof form.getValues>) => {
      const payload = {
        user_id:               v.user_id,
        title:                 v.title,
        description:           v.description || undefined,
        period_start:          dayjs(periodDates[0]!).format('YYYY-MM-DD'),
        period_end:            dayjs(periodDates[1]!).format('YYYY-MM-DD'),
        group_commission_type: groupCommType,
        group_commission_value: groupCommValue !== '' ? Number(groupCommValue) : undefined,
        staff_salary:          staffSalary !== '' ? Number(staffSalary) : undefined,
        deduct_on_failure:     deductOnFail,
        manager_id:               managerId,
        manager_commission_type:  managerId ? managerCommType : 'none',
        manager_commission_value: managerId && managerCommValue !== '' ? Number(managerCommValue) : undefined,
        criteria: criteria.map(c => ({
          type: c.type, label: c.label,
          unit: c.unit || DEFAULT_UNITS[c.type],
          goal_value: c.goal_value,
          commission_type: c.commission_type,
          commission_value: c.commission_value !== '' ? Number(c.commission_value) : undefined,
        })),
      };
      return existing ? updateTarget(existing.id, payload) : createTarget(payload);
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['staff-targets-team'] });
      onSaved(); onClose();
      notifications.show({ message: existing ? 'Target updated.' : 'Target created.', color: 'green' });
    },
    onError: (err: any) =>
      notifications.show({ message: err?.response?.data?.message ?? 'Failed to save.', color: 'red' }),
  });

  const addCriterion = () => setCriteria(prev => [...prev, emptyDraft()]);
  const removeCriterion = (i: number) => setCriteria(prev => prev.filter((_, idx) => idx !== i));
  const updateCrit = (i: number, patch: Partial<CriterionDraft>) =>
    setCriteria(prev => prev.map((c, idx) => idx === i ? { ...c, ...patch } : c));

  const canSubmit = !!periodDates[0] && !!periodDates[1] && criteria.length > 0
    && criteria.every(c => c.label && c.goal_value > 0);

  const groupBonusPreview = groupCommType === 'fixed' && groupCommValue !== ''
    ? formatCurrency(Number(groupCommValue))
    : groupCommType === 'percentage' && groupCommValue !== '' && staffSalary !== ''
    ? formatCurrency(Number(groupCommValue) / 100 * Number(staffSalary))
    : null;

  return (
    <Modal opened={opened} onClose={onClose}
      title={existing ? 'Edit Target' : 'Create New Target'}
      centered size="xl" scrollAreaComponent={ScrollArea.Autosize}>
      <form onSubmit={form.onSubmit(v => mutation.mutate(v))}>
        <Stack gap="md">
          {/* Staff + period */}
          <SimpleGrid cols={{ base: 1, sm: 2 }} spacing="sm">
            {!existing ? (
              <Select label="Staff member" placeholder="Select staff"
                data={userOptions} searchable required {...form.getInputProps('user_id')} />
            ) : (
              <div>
                <Text size="xs" c="dimmed" fw={500} mb={4}>Staff member</Text>
                <Text size="sm" fw={600}>{existing.user.name}</Text>
              </div>
            )}
            <DatePickerInput type="range" label="Period" placeholder="Start – End"
              value={periodDates}
              onChange={(v) => setPeriodDates([v[0] ? new Date(v[0] as any) : null, v[1] ? new Date(v[1] as any) : null])}
              required />
          </SimpleGrid>

          <TextInput label="Title" placeholder="e.g. May 2026 Sales Target"
            required {...form.getInputProps('title')} />
          <Textarea label="Description (optional)" minRows={2} autosize maxRows={4}
            {...form.getInputProps('description')} />

          <Divider label="Goals & Commission" labelPosition="left" />

          {/* Criteria builder */}
          <Stack gap="sm">
            {criteria.map((c, i) => (
              <Paper key={i} withBorder p="sm" radius="md">
                <Group justify="space-between" mb="sm">
                  <Text size="xs" fw={700} tt="uppercase" c="dimmed">Goal {i + 1}</Text>
                  {criteria.length > 1 && (
                    <ActionIcon size="xs" color="red" variant="subtle" onClick={() => removeCriterion(i)}>
                      <IconX size={12} />
                    </ActionIcon>
                  )}
                </Group>

                <SimpleGrid cols={{ base: 1, sm: 2 }} spacing="sm">
                  <Select label="Type"
                    data={Object.entries(TYPE_LABELS).map(([v, l]) => ({ value: v, label: l }))}
                    value={c.type}
                    onChange={v => { const type = v as CriterionType; updateCrit(i, { type, unit: DEFAULT_UNITS[type] }); }}
                  />
                  <TextInput label="Label" placeholder="e.g. New customers, Domain sales"
                    value={c.label} onChange={e => updateCrit(i, { label: e.currentTarget.value })} required />
                  <NumberInput label="Target value" min={0}
                    value={c.goal_value}
                    onChange={v => updateCrit(i, { goal_value: Number(v) || 0 })}
                    suffix={` ${c.unit}`} required />
                  <TextInput label="Unit" placeholder="customers / domains"
                    value={c.unit} onChange={e => updateCrit(i, { unit: e.currentTarget.value })} />
                </SimpleGrid>

                <Divider my="sm" variant="dashed" label="Per-Goal Commission" labelPosition="center" />

                <SimpleGrid cols={{ base: 1, sm: 2 }} spacing="sm">
                  <Select label="Commission type"
                    data={[
                      { value: 'none', label: 'No commission' },
                      { value: 'fixed', label: `Fixed amount (${getTenantCurrency()})` },
                      { value: 'percentage', label: 'Percentage of achieved' },
                    ]}
                    value={c.commission_type}
                    onChange={v => updateCrit(i, { commission_type: v as CommissionType, commission_value: '' })}
                  />
                  {c.commission_type !== 'none' && (
                    <NumberInput
                      label={c.commission_type === 'fixed' ? `Amount (${getTenantCurrency()})` : 'Percentage (%)'}
                      min={0} max={c.commission_type === 'percentage' ? 100 : undefined}
                      suffix={c.commission_type === 'percentage' ? '%' : undefined}
                      value={c.commission_value === '' ? undefined : c.commission_value}
                      onChange={v => updateCrit(i, { commission_value: v === undefined ? '' : Number(v) })}
                    />
                  )}
                </SimpleGrid>
                {c.commission_type !== 'none' && c.commission_value !== '' && (
                  <Text size="xs" c="green" mt="xs">
                    If goal met: {c.commission_type === 'fixed'
                      ? `${formatCurrency(Number(c.commission_value))} fixed`
                      : `${c.commission_value}% of their verified ${c.unit}`}
                  </Text>
                )}
              </Paper>
            ))}

            <Button size="xs" variant="light" leftSection={<IconPlus size={13} />}
              onClick={addCriterion} style={{ alignSelf: 'flex-start' }}>
              Add Another Goal
            </Button>
          </Stack>

          {/* Group bonus */}
          <Divider label="Group Bonus (if ALL goals met)" labelPosition="left" />
          <Paper withBorder p="sm" radius="md">
            <Stack gap="sm">
              <Text size="xs" c="dimmed">Award a bonus only when every goal is achieved simultaneously.</Text>
              <SimpleGrid cols={{ base: 1, sm: 2 }} spacing="sm">
                <Select label="Bonus type"
                  data={[
                    { value: 'none', label: 'No group bonus' },
                    { value: 'fixed', label: `Fixed amount (${getTenantCurrency()})` },
                    { value: 'percentage', label: '% of monthly salary' },
                  ]}
                  value={groupCommType}
                  onChange={v => { setGroupCommType(v as CommissionType); setGroupCommValue(''); }}
                />
                {groupCommType !== 'none' && (
                  <NumberInput
                    label={groupCommType === 'fixed' ? `Bonus amount (${getTenantCurrency()})` : 'Percentage of salary (%)'}
                    min={0} max={groupCommType === 'percentage' ? 100 : undefined}
                    suffix={groupCommType === 'percentage' ? '%' : undefined}
                    value={groupCommValue === '' ? undefined : groupCommValue}
                    onChange={v => setGroupCommValue(v === undefined ? '' : Number(v))}
                  />
                )}
              </SimpleGrid>
              {groupBonusPreview && (
                <Text size="xs" c="green">
                  If all goals met: {groupBonusPreview} group bonus
                  {groupCommType === 'percentage' ? ' (% of salary)' : ''}
                </Text>
              )}
              {groupCommType === 'percentage' && staffSalary === '' && (
                <Text size="xs" c="dimmed">Set salary below to preview the bonus amount.</Text>
              )}
            </Stack>
          </Paper>

          {/* Salary & failure penalty */}
          <Divider label="Salary & Failure Penalty" labelPosition="left" />
          <Paper withBorder p="sm" radius="md">
            <Stack gap="sm">
              <NumberInput
                label={`Monthly salary (${getTenantCurrency()})`}
                description="Used for group bonus % calculation and failure deduction."
                placeholder="Optional" min={0}
                prefix={`${getTenantCurrency()} `}
                value={staffSalary === '' ? undefined : staffSalary}
                onChange={v => {
                  setStaffSalary(v === undefined ? '' : Number(v));
                  if (v === undefined || Number(v) === 0) setDeductOnFail(false);
                }}
              />
              <Checkbox
                label="Deduct half salary on failure"
                description="If any goal is missed, deduct 50% of the monthly salary."
                checked={deductOnFail}
                onChange={e => setDeductOnFail(e.currentTarget.checked)}
                disabled={staffSalary === '' || staffSalary === 0}
              />
              {deductOnFail && staffSalary !== '' && Number(staffSalary) > 0 && (
                <Text size="xs" c="red">
                  If any goal missed: {formatCurrency(Number(staffSalary) / 2)} deducted from pay.
                </Text>
              )}
            </Stack>
          </Paper>

          {/* Manager (team-lead override commission) */}
          <Divider label="Manager / Team-Lead Commission (optional)" labelPosition="left" />
          <Paper withBorder p="sm" radius="md">
            <Stack gap="sm">
              <Text size="xs" c="dimmed">
                Assign a colleague to oversee this target. They earn an override commission only when ALL goals are met.
              </Text>
              <Select
                label="Manager"
                placeholder="Select a manager (optional)"
                data={userOptions.filter((u: any) => u.value !== form.values.user_id)}
                value={managerId}
                onChange={v => { setManagerId(v); if (!v) { setManagerCommType('none'); setManagerCommValue(''); } }}
                searchable clearable
              />
              {managerId && (
                <SimpleGrid cols={{ base: 1, sm: 2 }} spacing="sm">
                  <Select
                    label="Commission type"
                    data={[
                      { value: 'none', label: 'No override commission' },
                      { value: 'fixed', label: `Fixed amount (${getTenantCurrency()})` },
                      { value: 'percentage', label: "% of staff's gross commission" },
                    ]}
                    value={managerCommType}
                    onChange={v => { setManagerCommType(v as CommissionType); setManagerCommValue(''); }}
                  />
                  {managerCommType !== 'none' && (
                    <NumberInput
                      label={managerCommType === 'fixed' ? `Amount (${getTenantCurrency()})` : 'Percentage (%)'}
                      min={0} max={managerCommType === 'percentage' ? 100 : undefined}
                      suffix={managerCommType === 'percentage' ? '%' : undefined}
                      value={managerCommValue === '' ? undefined : managerCommValue}
                      onChange={v => setManagerCommValue(v === undefined ? '' : Number(v))}
                    />
                  )}
                </SimpleGrid>
              )}
              {managerId && managerCommType !== 'none' && managerCommValue !== '' && (
                <Text size="xs" c="green">
                  If all goals met: manager earns {managerCommType === 'fixed'
                    ? formatCurrency(Number(managerCommValue))
                    : `${managerCommValue}% of staff's gross commission`}
                </Text>
              )}
            </Stack>
          </Paper>

          <Group justify="flex-end">
            <Button variant="default" onClick={onClose}>Cancel</Button>
            <Button type="submit" loading={mutation.isPending} disabled={!canSubmit}>
              {existing ? 'Update Target' : 'Create Target'}
            </Button>
          </Group>
        </Stack>
      </form>
    </Modal>
  );
}

function emptyDraft(): CriterionDraft {
  return {
    type: 'customer_count', label: '', unit: 'customers',
    goal_value: 0, commission_type: 'none', commission_value: '',
  };
}
