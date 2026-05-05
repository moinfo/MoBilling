import { useState, useEffect } from 'react';
import {
  Title, Tabs, Stack, Group, Button, Badge, Text, Paper, ActionIcon,
  Textarea, Modal, Loader, Center, ThemeIcon, Select, Divider,
  NumberInput, TextInput, ScrollArea, SimpleGrid, Progress,
  Table, Collapse,
} from '@mantine/core';
import { DatePickerInput } from '@mantine/dates';
import { useDisclosure } from '@mantine/hooks';
import { useForm } from '@mantine/form';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import {
  IconPlus, IconEdit, IconTrash, IconCheck, IconChevronDown, IconChevronUp,
  IconTarget, IconUsers, IconCoin, IconAlertTriangle, IconX,
  IconClipboardCheck, IconMoodHappy,
} from '@tabler/icons-react';
import dayjs from 'dayjs';
import {
  getTargets, createTarget, updateTarget, deleteTarget,
  selfReportTarget, verifyTarget, getCommissionSummary,
  type StaffTarget, type TargetCriterion, type CriterionType, type CommissionType,
} from '../api/staffTargets';
import { usePermissions } from '../hooks/usePermissions';

// ── Config ─────────────────────────────────────────────────────────────────────

const STATUS_CONFIG: Record<string, { color: string; label: string }> = {
  active:       { color: 'blue',   label: 'Active'         },
  self_reported:{ color: 'orange', label: 'Awaiting Review' },
  verified:     { color: 'green',  label: 'Verified'        },
  cancelled:    { color: 'gray',   label: 'Cancelled'       },
};

const TYPE_LABELS: Record<CriterionType, string> = {
  customer_count: 'Customer Count',
  revenue:        'Revenue',
  item_sales:     'Item Sales',
  custom:         'Custom',
};

const DEFAULT_UNITS: Record<CriterionType, string> = {
  customer_count: 'customers',
  revenue:        'KES',
  item_sales:     'units',
  custom:         'units',
};

// ── Helpers ───────────────────────────────────────────────────────────────────

function fmtNum(n: number | null, unit?: string): string {
  if (n === null) return '—';
  const formatted = n >= 1000 ? n.toLocaleString() : String(n);
  return unit ? `${formatted} ${unit}` : formatted;
}

function commissionLabel(c: TargetCriterion): string {
  if (c.commission_type === 'none') return 'No commission';
  if (c.commission_type === 'fixed') return `KES ${(c.commission_value ?? 0).toLocaleString()} fixed`;
  return `${c.commission_value}% of achieved`;
}

// ── Main page ─────────────────────────────────────────────────────────────────

export default function StaffTargets() {
  const { can } = usePermissions();
  const canManage = can('staff_targets.manage');
  const canVerify = can('staff_targets.verify');
  const canViewTeam = canManage || canVerify || can('staff_reports.view_all');

  return (
    <Stack>
      <Title order={2}>Staff Targets & Commission</Title>
      <Tabs defaultValue={can('staff_targets.submit') ? 'mine' : 'team'} keepMounted={false}>
        <Tabs.List>
          {can('staff_targets.submit') && (
            <Tabs.Tab value="mine" leftSection={<IconTarget size={15} />}>My Targets</Tabs.Tab>
          )}
          {canViewTeam && (
            <Tabs.Tab value="team" leftSection={<IconUsers size={15} />}>Team Targets</Tabs.Tab>
          )}
          {canViewTeam && (
            <Tabs.Tab value="commission" leftSection={<IconCoin size={15} />}>Commission Summary</Tabs.Tab>
          )}
        </Tabs.List>

        {can('staff_targets.submit') && (
          <Tabs.Panel value="mine" pt="md">
            <MyTargetsTab can={can} />
          </Tabs.Panel>
        )}
        {canViewTeam && (
          <Tabs.Panel value="team" pt="md">
            <TeamTargetsTab can={can} canManage={canManage} canVerify={canVerify} />
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

// ── My Targets Tab ─────────────────────────────────────────────────────────────

function MyTargetsTab({ can }: { can: (p: string) => boolean }) {
  const qc = useQueryClient();
  const [reporting, setReporting] = useState<StaffTarget | null>(null);
  const [reportModal, { open: openReport, close: closeReport }] = useDisclosure(false);

  const { data, isLoading } = useQuery({
    queryKey: ['staff-targets-mine'],
    queryFn: () => getTargets(),
  });
  const targets: StaffTarget[] = (data?.data?.data ?? []).filter(t => true); // own only (backend filters)

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

function TeamTargetsTab({ can, canManage, canVerify }: {
  can: (p: string) => boolean; canManage: boolean; canVerify: boolean;
}) {
  const qc = useQueryClient();
  const [statusFilter, setStatusFilter] = useState('');
  const [editing, setEditing]   = useState<StaffTarget | null>(null);
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
    queryFn: getCommissionSummary,
  });
  const entries = data?.data?.data ?? [];
  const total = entries.reduce((sum, e) => sum + e.total_commission, 0);

  return (
    <Stack>
      {isLoading ? (
        <Center py="xl"><Loader /></Center>
      ) : entries.length === 0 ? (
        <Center py="xl"><Text c="dimmed">No verified targets with commission yet.</Text></Center>
      ) : (
        <>
          <Paper withBorder p="md" radius="md" bg="green.0">
            <Group gap="xs">
              <ThemeIcon color="green" variant="light" radius="xl">
                <IconCoin size={16} />
              </ThemeIcon>
              <Text size="sm" fw={700} c="green">
                Total Commission Payable: KES {total.toLocaleString()}
              </Text>
            </Group>
          </Paper>

          <Table striped withTableBorder highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Staff Member</Table.Th>
                <Table.Th>Verified Targets</Table.Th>
                <Table.Th ta="right">Total Commission</Table.Th>
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
                              KES {t.commission_earned.toLocaleString()}
                            </Badge>
                          )}
                        </Group>
                      ))}
                    </Stack>
                  </Table.Td>
                  <Table.Td ta="right">
                    <Text fw={700} c="green">KES {e.total_commission.toLocaleString()}</Text>
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
  const statusCfg = STATUS_CONFIG[t.status];
  const totalCriteria = t.criteria.length;
  const metCriteria   = t.criteria.filter(c => c.goal_met).length;

  return (
    <Paper withBorder p="sm" radius="md"
      style={{
        cursor: 'pointer',
        borderLeft: t.status === 'verified' ? '3px solid var(--mantine-color-green-5)' : undefined,
      }}
      onClick={() => setExpanded(e => !e)}>
      <Stack gap="xs">
        {/* Header */}
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
                KES {t.total_commission.toLocaleString()}
              </Badge>
            )}
            <Text size="xs" c="dimmed">{t.user.name}</Text>
            {actions}
            <ActionIcon size="xs" variant="transparent" color="dimmed">
              {expanded ? <IconChevronUp size={14} /> : <IconChevronDown size={14} />}
            </ActionIcon>
          </Group>
        </Group>

        {/* Progress bar for self-reported/verified */}
        {t.status !== 'active' && totalCriteria > 0 && (
          <Progress
            size="xs"
            value={t.status === 'verified' ? (metCriteria / totalCriteria) * 100 : 50}
            color={t.status === 'verified' ? (metCriteria === totalCriteria ? 'green' : 'orange') : 'blue'}
          />
        )}

        <Collapse in={expanded}>
          <Stack gap="sm" mt="xs">
            {t.description && (
              <Text size="xs" c="dimmed">{t.description}</Text>
            )}

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
                            ? `KES ${c.commission_earned.toLocaleString()}`
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

            {/* Supervisor notes */}
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

  return (
    <Modal opened={opened} onClose={onClose} title={`Report Achievement — ${target.title}`}
      centered size="lg" scrollAreaComponent={ScrollArea.Autosize}>
      <Stack gap="md">
        <Text size="xs" c="dimmed">
          Enter what you actually achieved for each goal. Your supervisor will verify and confirm the values.
        </Text>

        <Stack gap="sm">
          {target.criteria.map(c => (
            <Paper key={c.id} withBorder p="sm" radius="md">
              <Group justify="space-between" wrap="nowrap" mb="xs">
                <div>
                  <Text size="sm" fw={600}>{c.label}</Text>
                  <Text size="xs" c="dimmed">{TYPE_LABELS[c.type]} · Target: {fmtNum(c.goal_value, c.unit)}</Text>
                </div>
                <Badge size="xs" variant="light">{commissionLabel(c)}</Badge>
              </Group>
              <NumberInput
                label={`Achieved (${c.unit})`}
                min={0}
                value={values[c.id] ?? 0}
                onChange={v => setValues(prev => ({ ...prev, [c.id]: Number(v) || 0 }))}
                suffix={` ${c.unit}`}
                leftSection={
                  (values[c.id] ?? 0) >= c.goal_value
                    ? <IconCheck size={14} color="green" />
                    : <IconAlertTriangle size={14} color="orange" />
                }
              />
              {(values[c.id] ?? 0) >= c.goal_value && (
                <Text size="xs" c="green" mt={4}>
                  ✓ Goal met! Commission: {commissionLabel(c)}
                </Text>
              )}
            </Paper>
          ))}
        </Stack>

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
  const previewCommission = target.criteria.reduce((sum, c) => {
    const v   = values[c.id] ?? 0;
    const met = v >= c.goal_value;
    if (!met || c.commission_type === 'none') return sum;
    if (c.commission_type === 'fixed') return sum + (c.commission_value ?? 0);
    return sum + (c.commission_value ?? 0) / 100 * v;
  }, 0);

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
            const v      = values[c.id] ?? 0;
            const met    = v >= c.goal_value;
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
                        KES {earned.toLocaleString()} earned
                      </Badge>
                    )}
                  </Stack>
                </Group>
                <NumberInput
                  label={`Verified value (${c.unit})`}
                  min={0}
                  value={v}
                  onChange={val => setValues(prev => ({ ...prev, [c.id]: Number(val) || 0 }))}
                  leftSection={met ? <IconCheck size={14} color="green" /> : <IconX size={14} color="orange" />}
                />
                {met
                  ? <Text size="xs" c="green" mt={4}>Goal met ✓</Text>
                  : <Text size="xs" c="orange" mt={4}>Goal not met ({fmtNum(c.goal_value - v, c.unit)} short)</Text>
                }
              </Paper>
            );
          })}
        </Stack>

        {/* Commission preview */}
        <Paper withBorder p="sm" radius="md" bg={previewCommission > 0 ? 'green.0' : undefined}>
          <Group gap="xs">
            <IconCoin size={16} />
            <Text size="sm" fw={700}>
              Total commission to award: KES {previewCommission.toLocaleString()}
            </Text>
          </Group>
        </Paper>

        <Textarea
          label="Feedback / Notes (optional)"
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

  // Fetch all tenant users for staff selector
  const { data: usersData } = useQuery({
    queryKey: ['staff-supervisors'],   // reuse existing query that lists all users
    queryFn: () => import('../api/staffReports').then(m => m.getSupervisors()),
    enabled: opened && !existing,
  });
  const userOptions = (usersData?.data?.data ?? []).map((u: any) => ({ value: u.id, label: u.name }));

  const [periodDates, setPeriodDates] = useState<[Date | null, Date | null]>([null, null]);
  const [criteria, setCriteria] = useState<CriterionDraft[]>([emptyDraft()]);

  const form = useForm({
    initialValues: {
      user_id:     '',
      title:       '',
      description: '',
    },
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
      } else {
        form.reset();
        setPeriodDates([null, null]);
        setCriteria([emptyDraft()]);
      }
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [opened, existing?.id]);

  const mutation = useMutation({
    mutationFn: (v: ReturnType<typeof form.getValues>) => {
      const payload = {
        user_id:      v.user_id,
        title:        v.title,
        description:  v.description || undefined,
        period_start: dayjs(periodDates[0]!).format('YYYY-MM-DD'),
        period_end:   dayjs(periodDates[1]!).format('YYYY-MM-DD'),
        criteria: criteria.map(c => ({
          type:             c.type,
          label:            c.label,
          unit:             c.unit || DEFAULT_UNITS[c.type],
          goal_value:       c.goal_value,
          commission_type:  c.commission_type,
          commission_value: c.commission_value !== '' ? Number(c.commission_value) : undefined,
        })),
      };
      return existing ? updateTarget(existing.id, payload) : createTarget(payload);
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['staff-targets-team'] });
      onSaved();
      onClose();
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

  return (
    <Modal opened={opened} onClose={onClose}
      title={existing ? 'Edit Target' : 'Create New Target'}
      centered size="xl" scrollAreaComponent={ScrollArea.Autosize}>
      <form onSubmit={form.onSubmit(v => mutation.mutate(v))}>
        <Stack gap="md">
          {/* Staff + period */}
          <SimpleGrid cols={{ base: 1, sm: 2 }} spacing="sm">
            {!existing && (
              <Select label="Staff member" placeholder="Select staff"
                data={userOptions} searchable required
                {...form.getInputProps('user_id')} />
            )}
            {existing && (
              <div>
                <Text size="xs" c="dimmed" fw={500} mb={4}>Staff member</Text>
                <Text size="sm" fw={600}>{existing.user.name}</Text>
              </div>
            )}
            <DatePickerInput
              type="range"
              label="Period"
              placeholder="Start – End"
              value={periodDates}
              onChange={setPeriodDates}
              required
            />
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
                    <ActionIcon size="xs" color="red" variant="subtle"
                      onClick={() => removeCriterion(i)}>
                      <IconX size={12} />
                    </ActionIcon>
                  )}
                </Group>

                <SimpleGrid cols={{ base: 1, sm: 2 }} spacing="sm">
                  <Select label="Type"
                    data={Object.entries(TYPE_LABELS).map(([v, l]) => ({ value: v, label: l }))}
                    value={c.type}
                    onChange={v => {
                      const type = v as CriterionType;
                      updateCrit(i, { type, unit: DEFAULT_UNITS[type] });
                    }}
                  />
                  <TextInput label="Label"
                    placeholder="e.g. New customers, Domain sales"
                    value={c.label}
                    onChange={e => updateCrit(i, { label: e.currentTarget.value })}
                    required
                  />
                  <NumberInput label="Target value" min={0}
                    value={c.goal_value}
                    onChange={v => updateCrit(i, { goal_value: Number(v) || 0 })}
                    suffix={` ${c.unit}`}
                    required
                  />
                  <TextInput label="Unit" placeholder="customers / KES / domains"
                    value={c.unit}
                    onChange={e => updateCrit(i, { unit: e.currentTarget.value })}
                  />
                </SimpleGrid>

                <Divider my="sm" variant="dashed" label="Commission" labelPosition="center" />

                <SimpleGrid cols={{ base: 1, sm: 2 }} spacing="sm">
                  <Select label="Commission type"
                    data={[
                      { value: 'none',       label: 'No commission'  },
                      { value: 'fixed',      label: 'Fixed amount (KES)' },
                      { value: 'percentage', label: 'Percentage of achieved' },
                    ]}
                    value={c.commission_type}
                    onChange={v => updateCrit(i, { commission_type: v as CommissionType, commission_value: '' })}
                  />
                  {c.commission_type !== 'none' && (
                    <NumberInput
                      label={c.commission_type === 'fixed' ? 'Amount (KES)' : 'Percentage (%)'}
                      min={0}
                      max={c.commission_type === 'percentage' ? 100 : undefined}
                      suffix={c.commission_type === 'percentage' ? '%' : undefined}
                      value={c.commission_value === '' ? undefined : c.commission_value}
                      onChange={v => updateCrit(i, { commission_value: v === undefined ? '' : Number(v) })}
                    />
                  )}
                </SimpleGrid>

                {/* Preview */}
                {c.commission_type !== 'none' && c.commission_value !== '' && (
                  <Text size="xs" c="green" mt="xs">
                    If goal met: staff earns{' '}
                    {c.commission_type === 'fixed'
                      ? `KES ${Number(c.commission_value).toLocaleString()} fixed`
                      : `${c.commission_value}% of their verified ${c.unit}`
                    }
                  </Text>
                )}
              </Paper>
            ))}

            <Button size="xs" variant="light" leftSection={<IconPlus size={13} />}
              onClick={addCriterion} style={{ alignSelf: 'flex-start' }}>
              Add Another Goal
            </Button>
          </Stack>

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
