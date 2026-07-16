import { useState, useEffect } from 'react';
import {
  Title, Tabs, Stack, Group, Button, Badge, Text, Paper, ActionIcon,
  Textarea, Modal, Loader, Center, ThemeIcon, Select, Divider, Switch,
  SegmentedControl, Avatar, ScrollArea, RingProgress, SimpleGrid,
  NumberInput, Alert, TextInput,
} from '@mantine/core';
import { DatePickerInput, MonthPickerInput, TimeInput } from '@mantine/dates';
import { useDisclosure } from '@mantine/hooks';
import { useForm } from '@mantine/form';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { Rating } from '@mantine/core';
import {
  IconPlus, IconEdit, IconTrash, IconCalendar, IconCheck,
  IconClipboardList, IconUsers, IconStar, IconAlertCircle,
  IconSettings, IconChartBar, IconAlertTriangle, IconMoodHappy,
  IconClock, IconTarget, IconTrendingUp, IconEye, IconArrowLeft,
  IconSearch,
} from '@tabler/icons-react';
import dayjs from 'dayjs';
import isoWeek from 'dayjs/plugin/isoWeek';
dayjs.extend(isoWeek);
import {
  getReports, createReport, updateReport, deleteReport, reviewReport,
  getDashboard, getSettings, updateSettings, getSupervisors, updateSupervisor,
  type StaffReport, type ReportSettings, type MonthStats, type StaffStat,
  type StaffWithSupervisor,
} from '../api/staffReports';
import { usePermissions } from '../hooks/usePermissions';

// ── Config ────────────────────────────────────────────────────────────────────

const TYPE_CONFIG = {
  daily:   { color: 'blue',   label: 'Daily'   },
  weekly:  { color: 'teal',   label: 'Weekly'  },
  monthly: { color: 'violet', label: 'Monthly' },
} as const;

const STATUS_CONFIG = {
  submitted: { color: 'orange', label: 'Pending Review' },
  reviewed:  { color: 'green',  label: 'Reviewed'       },
} as const;

const DAY_NAMES: Record<number, string> = {
  1: 'Monday', 2: 'Tuesday', 3: 'Wednesday',
  4: 'Thursday', 5: 'Friday', 6: 'Saturday', 7: 'Sunday',
};

type ReportType = 'daily' | 'weekly' | 'monthly';

// ── Helpers ───────────────────────────────────────────────────────────────────

function normalizePeriodDate(type: ReportType, date: Date): Date {
  const d = dayjs(date);
  if (type === 'weekly')  return d.isoWeekday(1).toDate();
  if (type === 'monthly') return d.startOf('month').toDate();
  return date;
}

function weekRangeLabel(date: Date): string {
  const mon = dayjs(date).isoWeekday(1);
  return `${mon.format('D MMM')} – ${mon.add(6, 'day').format('D MMM YYYY')}`;
}

// ── Main page ─────────────────────────────────────────────────────────────────

export default function StaffReports() {
  const { can } = usePermissions();

  // can see team reports if they can review (assigned subordinates) or view_all (everyone)
  const canSeeTeam = can('staff_reports.review') || can('staff_reports.view_all');
  // settings only for those who can manage reviews
  const canManage  = can('staff_reports.review');

  return (
    <Stack>
      <Title order={2}>Staff Reports</Title>
      <Tabs defaultValue="dashboard" keepMounted={false}>
        <Tabs.List>
          <Tabs.Tab value="dashboard" leftSection={<IconChartBar size={15} />}>
            Dashboard
          </Tabs.Tab>
          {can('staff_reports.submit') && (
            <Tabs.Tab value="mine" leftSection={<IconClipboardList size={15} />}>
              My Reports
            </Tabs.Tab>
          )}
          {canSeeTeam && (
            <Tabs.Tab value="team" leftSection={<IconUsers size={15} />}>
              Team Reports
            </Tabs.Tab>
          )}
          {canManage && (
            <Tabs.Tab value="settings" leftSection={<IconSettings size={15} />}>
              Settings
            </Tabs.Tab>
          )}
        </Tabs.List>

        <Tabs.Panel value="dashboard" pt="md">
          <DashboardTab can={can} canSeeTeam={canSeeTeam} />
        </Tabs.Panel>

        {can('staff_reports.submit') && (
          <Tabs.Panel value="mine" pt="md">
            <MyReportsTab can={can} />
          </Tabs.Panel>
        )}
        {canSeeTeam && (
          <Tabs.Panel value="team" pt="md">
            <TeamReportsTab can={can} />
          </Tabs.Panel>
        )}
        {canManage && (
          <Tabs.Panel value="settings" pt="md">
            <SettingsTab />
          </Tabs.Panel>
        )}
      </Tabs>
    </Stack>
  );
}

// ── Dashboard Tab ─────────────────────────────────────────────────────────────

function DashboardTab({ can, canSeeTeam }: { can: (p: string) => boolean; canSeeTeam: boolean }) {
  const { data, isLoading } = useQuery({
    queryKey: ['staff-reports-dashboard'],
    queryFn:  getDashboard,
  });

  const dash = data?.data?.data;

  if (isLoading) return <Center py="xl"><Loader /></Center>;
  if (!dash)     return null;

  const { this_month, recent_reviews, settings, team } = dash;
  const month = dayjs().format('MMMM YYYY');
  const isSupervisor = canSeeTeam;

  return (
    <Stack gap="lg">
      {/* Supervisor: pending review alert */}
      {isSupervisor && team && team.pending_review > 0 && (
        <Alert
          icon={<IconAlertCircle size={16} />}
          color="orange"
          title={`${team.pending_review} report${team.pending_review !== 1 ? 's' : ''} awaiting your review`}
        >
          Open the Team Reports tab to review and leave feedback on your team's submissions.
        </Alert>
      )}

      {/* ── ADMIN: Team overview table ─────────────────────────────────────── */}
      {isSupervisor && team && team.staff.length > 0 && (
        <div>
          <Group gap="xs" mb="sm">
            <ThemeIcon size="sm" variant="light" color="blue" radius="xl">
              <IconTrendingUp size={14} />
            </ThemeIcon>
            <Text size="sm" fw={700} tt="uppercase" c="dimmed">Team Overview — {month}</Text>
          </Group>
          <TeamStatsTable staff={team.staff} />
        </div>
      )}

      {/* ── MY PROGRESS (always shown if user can submit) ─────────────────── */}
      {can('staff_reports.submit') && (
        <div>
          <Text size="sm" fw={600} c="dimmed" mb="sm" tt="uppercase">
            {isSupervisor ? 'My Progress' : month + ' Progress'}
          </Text>
          <SimpleGrid cols={{ base: 1, sm: 3 }} spacing="sm">
            <ProgressCard type="daily"   stats={this_month.daily}   settings={settings} />
            <ProgressCard type="weekly"  stats={this_month.weekly}  settings={settings} />
            <ProgressCard type="monthly" stats={this_month.monthly} settings={settings} />
          </SimpleGrid>
        </div>
      )}

      {/* Deadline info */}
      <Paper withBorder p="sm" radius="md">
        <Text size="xs" fw={600} c="dimmed" tt="uppercase" mb="xs">Submission Deadlines</Text>
        <Group gap="xl" wrap="wrap">
          <DeadlineInfo label="Daily" value={`by ${settings.daily_deadline_time}`} color="blue" />
          <DeadlineInfo
            label="Weekly"
            value={`${DAY_NAMES[settings.weekly_deadline_day]} by ${settings.weekly_deadline_time}`}
            color="teal"
          />
          <DeadlineInfo
            label="Monthly"
            value={`Day ${settings.monthly_deadline_day} by ${settings.monthly_deadline_time}`}
            color="violet"
          />
        </Group>
      </Paper>

      {/* Recent supervisor feedback (staff view) */}
      {!isSupervisor && (
        <>
          {recent_reviews.length > 0 && (
            <div>
              <Text size="sm" fw={600} c="dimmed" mb="sm" tt="uppercase">Recent Feedback from Supervisor</Text>
              <Stack gap="sm">
                {recent_reviews.map(r => (
                  <ReviewFeedbackCard key={r.id} report={r} />
                ))}
              </Stack>
            </div>
          )}
          {recent_reviews.length === 0 && (
            <Center py="md">
              <Text c="dimmed" size="sm">No reviewed reports yet — submit reports to receive supervisor feedback.</Text>
            </Center>
          )}
        </>
      )}
    </Stack>
  );
}

function DeadlineInfo({ label, value, color }: { label: string; value: string; color: string }) {
  return (
    <Group gap="xs">
      <Badge size="sm" color={color} variant="light">{label}</Badge>
      <Group gap={4}>
        <IconClock size={13} />
        <Text size="xs">{value}</Text>
      </Group>
    </Group>
  );
}

// ── Team Stats Table (supervisor dashboard) ───────────────────────────────────

function TeamStatsTable({ staff }: { staff: StaffStat[] }) {
  return (
    <Paper withBorder radius="md" style={{ overflow: 'hidden' }}>
      <div style={{ overflowX: 'auto' }}>
        <table style={{ width: '100%', borderCollapse: 'collapse' }}>
          <thead>
            <tr style={{ borderBottom: '1px solid var(--mantine-color-default-border)' }}>
              <th style={{ padding: '8px 12px', textAlign: 'left' }}>
                <Text size="xs" fw={700} c="dimmed" tt="uppercase">Staff Member</Text>
              </th>
              {(['daily', 'weekly', 'monthly'] as const).map(type => (
                <th key={type} style={{ padding: '8px 12px', textAlign: 'center' }}>
                  <Badge size="xs" color={TYPE_CONFIG[type].color} variant="light">
                    {TYPE_CONFIG[type].label}
                  </Badge>
                </th>
              ))}
              <th style={{ padding: '8px 12px', textAlign: 'center' }}>
                <Text size="xs" fw={700} c="dimmed" tt="uppercase">Late</Text>
              </th>
              <th style={{ padding: '8px 12px', textAlign: 'center' }}>
                <Text size="xs" fw={700} c="dimmed" tt="uppercase">Reviewed</Text>
              </th>
            </tr>
          </thead>
          <tbody>
            {staff.map((row, i) => {
              const totalLate     = row.daily.late + row.weekly.late + row.monthly.late;
              const totalReviewed = row.daily.reviewed + row.weekly.reviewed + row.monthly.reviewed;
              const totalSubmitted = row.daily.submitted + row.weekly.submitted + row.monthly.submitted;
              return (
                <tr key={row.user.id}
                  style={{
                    borderBottom: i < staff.length - 1 ? '1px solid var(--mantine-color-default-border)' : undefined,
                    background: totalSubmitted === 0 ? 'var(--mantine-color-red-light)' : undefined,
                  }}
                >
                  <td style={{ padding: '10px 12px' }}>
                    <Group gap="xs" wrap="nowrap">
                      <Avatar size="xs" radius="xl" color="blue">{row.user.name[0]}</Avatar>
                      <Text size="sm" fw={500}>{row.user.name}</Text>
                    </Group>
                  </td>
                  {(['daily', 'weekly', 'monthly'] as const).map(type => (
                    <td key={type} style={{ padding: '10px 12px', textAlign: 'center' }}>
                      <StatCell stat={row[type]} color={TYPE_CONFIG[type].color} />
                    </td>
                  ))}
                  <td style={{ padding: '10px 12px', textAlign: 'center' }}>
                    {totalLate > 0 ? (
                      <Badge size="sm" color="red" variant="light">{totalLate}</Badge>
                    ) : (
                      <Text size="xs" c="dimmed">—</Text>
                    )}
                  </td>
                  <td style={{ padding: '10px 12px', textAlign: 'center' }}>
                    {totalReviewed > 0 ? (
                      <Badge size="sm" color="green" variant="light">{totalReviewed}</Badge>
                    ) : (
                      <Text size="xs" c="dimmed">—</Text>
                    )}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </Paper>
  );
}

function StatCell({ stat, color }: { stat: MonthStats; color: string }) {
  const ratio = stat.target > 0 ? stat.submitted / stat.target : 0;
  const cellColor = ratio >= 1 ? 'green' : ratio >= 0.6 ? color : ratio > 0 ? 'orange' : 'red';
  const met = ratio >= 1;

  return (
    <Group gap={4} justify="center" wrap="nowrap">
      <Text size="sm" fw={600} c={cellColor}>
        {stat.submitted}/{stat.target}
      </Text>
      {met && (
        <ThemeIcon size={14} color="green" variant="transparent">
          <IconCheck size={11} />
        </ThemeIcon>
      )}
    </Group>
  );
}

function ProgressCard({ type, stats, settings }: {
  type: ReportType; stats: MonthStats; settings: ReportSettings;
}) {
  const cfg    = TYPE_CONFIG[type];
  const ratio  = stats.target > 0 ? stats.submitted / stats.target : 0;
  const pct    = Math.min(ratio, 1) * 100;
  const over   = stats.submitted > stats.target;

  const deadlineLabel = type === 'daily'
    ? `by ${settings.daily_deadline_time} daily`
    : type === 'weekly'
      ? `${DAY_NAMES[settings.weekly_deadline_day]} by ${settings.weekly_deadline_time}`
      : `Day ${settings.monthly_deadline_day} by ${settings.monthly_deadline_time}`;

  return (
    <Paper withBorder p="md" radius="md">
      <Group justify="space-between" align="flex-start" wrap="nowrap">
        <Stack gap={2} style={{ flex: 1 }}>
          <Badge size="sm" color={cfg.color} variant="light">{cfg.label}</Badge>
          <Group gap={4} mt={4}>
            <Text size="xl" fw={800} lh={1}>{stats.submitted}</Text>
            <Text size="sm" c="dimmed" mt={4}>/ {stats.target}</Text>
          </Group>
          <Text size="xs" c="dimmed">target this month</Text>

          <Group gap="xs" mt={6} wrap="wrap">
            {stats.reviewed > 0 && (
              <Group gap={3}>
                <ThemeIcon size={14} color="green" variant="transparent">
                  <IconCheck size={12} />
                </ThemeIcon>
                <Text size="xs" c="green">{stats.reviewed} reviewed</Text>
              </Group>
            )}
            {stats.late > 0 && (
              <Group gap={3}>
                <ThemeIcon size={14} color="red" variant="transparent">
                  <IconAlertTriangle size={12} />
                </ThemeIcon>
                <Text size="xs" c="red">{stats.late} late</Text>
              </Group>
            )}
          </Group>

          <Text size="xs" c="dimmed" mt={2}>{deadlineLabel}</Text>
        </Stack>

        <RingProgress
          size={70}
          thickness={7}
          roundCaps
          sections={[{
            value: pct,
            color: over ? 'green' : pct >= 75 ? cfg.color : pct >= 40 ? 'yellow' : 'red',
          }]}
          label={
            <Text ta="center" size="xs" fw={700} c={over ? 'green' : 'dimmed'}>
              {Math.round(pct)}%
            </Text>
          }
        />
      </Group>
    </Paper>
  );
}

// Card shown in Recent Feedback section of dashboard
function ReviewFeedbackCard({ report: r }: { report: StaffReport }) {
  const typeCfg = TYPE_CONFIG[r.report_type];
  return (
    <Paper withBorder p="sm" radius="md" style={{ borderLeft: '3px solid var(--mantine-color-green-5)' }}>
      <Group justify="space-between" wrap="nowrap">
        <Group gap="xs" wrap="nowrap">
          <Badge size="sm" color={typeCfg.color} variant="light">{typeCfg.label}</Badge>
          <Text size="sm" fw={600}>{r.period_label}</Text>
        </Group>
        <Group gap="xs" wrap="nowrap">
          {r.rating && <Rating value={r.rating} readOnly size="xs" />}
          <Text size="xs" c="dimmed">{dayjs(r.reviewed_at!).format('D MMM')}</Text>
        </Group>
      </Group>
      {r.review_notes && (
        <Text size="sm" c="dimmed" fs="italic" mt={6}>
          <IconMoodHappy size={12} style={{ marginRight: 4, verticalAlign: 'middle' }} />
          "{r.review_notes}"
          <Text span size="xs" c="dimmed" ml={6}>— {r.reviewer?.name}</Text>
        </Text>
      )}
      {!r.review_notes && (
        <Group gap={4} mt={4}>
          <ThemeIcon size={14} color="green" variant="transparent"><IconCheck size={12} /></ThemeIcon>
          <Text size="xs" c="dimmed">Reviewed by {r.reviewer?.name} — no written feedback</Text>
        </Group>
      )}
    </Paper>
  );
}

// ── My Reports Tab ────────────────────────────────────────────────────────────

function MyReportsTab({ can }: { can: (p: string) => boolean }) {
  const qc = useQueryClient();
  const [typeFilter, setTypeFilter] = useState('');
  const [editing, setEditing]       = useState<StaffReport | null>(null);
  const [modal, { open, close }]    = useDisclosure(false);

  const { data, isLoading } = useQuery({
    queryKey: ['staff-reports-mine', typeFilter],
    queryFn:  () => getReports({ report_type: typeFilter || undefined }),
  });
  const reports: StaffReport[] = data?.data?.data ?? [];

  const deleteMutation = useMutation({
    mutationFn: deleteReport,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['staff-reports-mine'] });
      qc.invalidateQueries({ queryKey: ['staff-reports-dashboard'] });
      notifications.show({ message: 'Report deleted.', color: 'green' });
    },
    onError: (err: any) => {
      notifications.show({ message: err?.response?.data?.message ?? 'Cannot delete this report.', color: 'red' });
    },
  });

  return (
    <Stack>
      <Group justify="space-between" wrap="nowrap">
        <SegmentedControl
          size="xs"
          value={typeFilter}
          onChange={setTypeFilter}
          data={[
            { value: '',        label: 'All'     },
            { value: 'daily',   label: 'Daily'   },
            { value: 'weekly',  label: 'Weekly'  },
            { value: 'monthly', label: 'Monthly' },
          ]}
        />
        {can('staff_reports.submit') && (
          <Button size="sm" leftSection={<IconPlus size={16} />}
            onClick={() => { setEditing(null); open(); }}>
            Submit Report
          </Button>
        )}
      </Group>

      {isLoading ? (
        <Center py="xl"><Loader /></Center>
      ) : reports.length === 0 ? (
        <Center py="xl">
          <Stack align="center" gap="xs">
            <ThemeIcon size="xl" variant="light" color="gray" radius="xl">
              <IconClipboardList size={24} />
            </ThemeIcon>
            <Text c="dimmed">No reports submitted yet.</Text>
            {can('staff_reports.submit') && (
              <Button size="xs" variant="light" leftSection={<IconPlus size={14} />}
                onClick={() => { setEditing(null); open(); }}>
                Submit your first report
              </Button>
            )}
          </Stack>
        </Center>
      ) : (
        <Stack gap="sm">
          {reports.map(r => (
            <ReportCard key={r.id} report={r}
              actions={
                r.status === 'submitted' ? (
                  <Group gap="xs" wrap="nowrap">
                    {can('staff_reports.submit') && (
                      <ActionIcon size="sm" variant="subtle"
                        onClick={() => { setEditing(r); open(); }}>
                        <IconEdit size={14} />
                      </ActionIcon>
                    )}
                    {can('staff_reports.submit') && (
                      <ActionIcon size="sm" variant="subtle" color="red"
                        onClick={() => deleteMutation.mutate(r.id)}>
                        <IconTrash size={14} />
                      </ActionIcon>
                    )}
                  </Group>
                ) : null
              }
            />
          ))}
        </Stack>
      )}

      <ReportFormModal opened={modal} onClose={close} existing={editing}
        onSaved={() => {
          qc.invalidateQueries({ queryKey: ['staff-reports-mine'] });
          qc.invalidateQueries({ queryKey: ['staff-reports-dashboard'] });
        }} />
    </Stack>
  );
}

// ── Team Reports Tab ──────────────────────────────────────────────────────────

type TeamUser = StaffReport['user'];

interface StaffSummary {
  user:     TeamUser;
  reports:  StaffReport[];
  total:    number;
  pending:  number;
  reviewed: number;
  late:     number;
  lastDate: string; // ISO of most recent submission
}

function TeamReportsTab({ can }: { can: (p: string) => boolean }) {
  const qc = useQueryClient();
  const [typeFilter, setTypeFilter]     = useState('');
  const [statusFilter, setStatusFilter] = useState('');
  const [search, setSearch]             = useState('');
  const [selectedId, setSelectedId]     = useState<string | null>(null);
  const [reviewing, setReviewing]       = useState<StaffReport | null>(null);
  const [reviewModal, { open: openReview, close: closeReview }] = useDisclosure(false);

  const { data, isLoading } = useQuery({
    queryKey: ['staff-reports-team', typeFilter, statusFilter],
    queryFn:  () => getReports({
      report_type: typeFilter  || undefined,
      status:      statusFilter || undefined,
    }),
  });
  const reports: StaffReport[] = data?.data?.data ?? [];

  // Group reports by staff member and build a per-staff summary
  const summaries: StaffSummary[] = Object.values(
    reports.reduce<Record<string, StaffSummary>>((acc, r) => {
      const s = (acc[r.user.id] ??= {
        user: r.user, reports: [], total: 0, pending: 0, reviewed: 0, late: 0, lastDate: '',
      });
      s.reports.push(r);
      s.total += 1;
      if (r.status === 'submitted') s.pending  += 1;
      if (r.status === 'reviewed')  s.reviewed += 1;
      if (r.is_late)                s.late     += 1;
      if (!s.lastDate || r.created_at > s.lastDate) s.lastDate = r.created_at;
      return acc;
    }, {})
  ).sort((a, b) => b.pending - a.pending || a.user.name.localeCompare(b.user.name));

  const filtered = summaries.filter(s =>
    s.user.name.toLowerCase().includes(search.trim().toLowerCase())
  );

  const selected = selectedId ? summaries.find(s => s.user.id === selectedId) : null;

  const reviewActions = (r: StaffReport) =>
    r.status === 'submitted' && can('staff_reports.review') ? (
      <Button size="xs" variant="light" color="green"
        leftSection={<IconCheck size={13} />}
        onClick={() => { setReviewing(r); openReview(); }}>
        Review
      </Button>
    ) : r.status === 'reviewed' && can('staff_reports.review') ? (
      <Button size="xs" variant="subtle" color="gray"
        onClick={() => { setReviewing(r); openReview(); }}>
        Edit review
      </Button>
    ) : null;

  // ── Detail view: one staff member's reports ───────────────────────────────
  if (selected) {
    const ordered = [...selected.reports]; // already period-desc from the API
    return (
      <Stack>
        <Group justify="space-between" wrap="nowrap">
          <Group gap="xs" wrap="nowrap">
            <Button size="xs" variant="subtle" leftSection={<IconArrowLeft size={14} />}
              onClick={() => setSelectedId(null)}>
              All staff
            </Button>
            <Avatar size="sm" radius="xl" color="blue">{selected.user.name[0]}</Avatar>
            <Text size="sm" fw={700}>{selected.user.name}</Text>
          </Group>
          <Group gap="xs">
            {selected.pending > 0 && (
              <Badge size="sm" color="orange" variant="light">{selected.pending} pending</Badge>
            )}
            {selected.late > 0 && (
              <Badge size="sm" color="red" variant="light">{selected.late} late</Badge>
            )}
            <Badge size="sm" color="green" variant="light">{selected.reviewed} reviewed</Badge>
          </Group>
        </Group>

        {/* Keep type/status filters available inside the detail view too */}
        <Group gap="xs">
          <SegmentedControl size="xs" value={typeFilter} onChange={setTypeFilter}
            data={[
              { value: '',        label: 'All types' },
              { value: 'daily',   label: 'Daily'     },
              { value: 'weekly',  label: 'Weekly'    },
              { value: 'monthly', label: 'Monthly'   },
            ]}
          />
          <Select size="xs" placeholder="All statuses" clearable
            value={statusFilter} onChange={v => setStatusFilter(v ?? '')}
            data={[
              { value: 'submitted', label: 'Pending Review' },
              { value: 'reviewed',  label: 'Reviewed'       },
            ]}
            style={{ width: 160 }}
          />
          <Text size="xs" c="dimmed">{ordered.length} report{ordered.length !== 1 ? 's' : ''}</Text>
        </Group>

        {ordered.length === 0 ? (
          <Center py="xl"><Text c="dimmed">No reports for this staff member.</Text></Center>
        ) : (
          <Stack gap="xs">
            {ordered.map(r => (
              <ReportCard key={r.id} report={r} actions={reviewActions(r)} />
            ))}
          </Stack>
        )}

        {reviewing && (
          <ReviewModal report={reviewing} opened={reviewModal}
            onClose={() => { closeReview(); setReviewing(null); }}
            onSaved={() => {
              qc.invalidateQueries({ queryKey: ['staff-reports-team'] });
              qc.invalidateQueries({ queryKey: ['staff-reports-dashboard'] });
            }} />
        )}
      </Stack>
    );
  }

  // ── Summary view: one row per staff member ────────────────────────────────
  return (
    <Stack>
      <Group gap="xs" wrap="wrap">
        <SegmentedControl size="xs" value={typeFilter} onChange={setTypeFilter}
          data={[
            { value: '',        label: 'All types' },
            { value: 'daily',   label: 'Daily'     },
            { value: 'weekly',  label: 'Weekly'    },
            { value: 'monthly', label: 'Monthly'   },
          ]}
        />
        <Select size="xs" placeholder="All statuses" clearable
          value={statusFilter} onChange={v => setStatusFilter(v ?? '')}
          data={[
            { value: 'submitted', label: 'Pending Review' },
            { value: 'reviewed',  label: 'Reviewed'       },
          ]}
          style={{ width: 160 }}
        />
        <TextInput size="xs" placeholder="Find staff…" leftSection={<IconSearch size={13} />}
          value={search} onChange={e => setSearch(e.currentTarget.value)}
          style={{ width: 200 }} />
        <Text size="xs" c="dimmed">
          {filtered.length} staff · {reports.length} report{reports.length !== 1 ? 's' : ''}
        </Text>
      </Group>

      {isLoading ? (
        <Center py="xl"><Loader /></Center>
      ) : filtered.length === 0 ? (
        <Center py="xl"><Text c="dimmed">No reports found.</Text></Center>
      ) : (
        <Paper withBorder radius="md" style={{ overflow: 'hidden' }}>
          <Stack gap={0}>
            {filtered.map((s, i) => (
              <Group
                key={s.user.id}
                justify="space-between"
                wrap="nowrap"
                p="sm"
                style={{
                  borderBottom: i < filtered.length - 1 ? '1px solid var(--mantine-color-default-border)' : undefined,
                }}
              >
                <Group gap="xs" wrap="nowrap" style={{ minWidth: 0 }}>
                  <Avatar size="sm" radius="xl" color="blue">{s.user.name[0]}</Avatar>
                  <div style={{ minWidth: 0 }}>
                    <Text size="sm" fw={600} truncate>{s.user.name}</Text>
                    <Text size="xs" c="dimmed">
                      {s.total} report{s.total !== 1 ? 's' : ''}
                      {s.lastDate ? ` · last ${dayjs(s.lastDate).format('D MMM YYYY')}` : ''}
                    </Text>
                  </div>
                </Group>

                <Group gap="xs" wrap="nowrap">
                  {s.pending > 0 && (
                    <Badge size="sm" color="orange" variant="light">{s.pending} pending</Badge>
                  )}
                  {s.late > 0 && (
                    <Badge size="sm" color="red" variant="light">{s.late} late</Badge>
                  )}
                  {s.reviewed > 0 && (
                    <Badge size="sm" color="green" variant="light">{s.reviewed} reviewed</Badge>
                  )}
                  <Button size="xs" variant="light" leftSection={<IconEye size={13} />}
                    onClick={() => setSelectedId(s.user.id)}>
                    View
                  </Button>
                </Group>
              </Group>
            ))}
          </Stack>
        </Paper>
      )}
    </Stack>
  );
}

// ── Settings Tab ──────────────────────────────────────────────────────────────

function SettingsTab() {
  const qc = useQueryClient();

  const { data, isLoading } = useQuery({
    queryKey: ['staff-report-settings'],
    queryFn:  getSettings,
  });
  const settings = data?.data?.data;

  const form = useForm<ReportSettings>({
    initialValues: {
      daily_target: 20, weekly_target: 4, monthly_target: 1,
      daily_deadline_time: '18:00',
      weekly_deadline_day: 5, weekly_deadline_time: '17:00',
      monthly_deadline_day: 28, monthly_deadline_time: '17:00',
      penalties_enabled: true,
      penalty_missing_daily: 5000, penalty_late: 2000,
      penalty_missing_weekly: 7000, penalty_missing_monthly: 10000,
    },
  });

  useEffect(() => {
    if (settings) form.setValues(settings);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [settings]);

  const mutation = useMutation({
    mutationFn: updateSettings,
    onSuccess: (res) => {
      qc.invalidateQueries({ queryKey: ['staff-report-settings'] });
      qc.invalidateQueries({ queryKey: ['staff-reports-dashboard'] });
      form.setValues(res.data.data);
      notifications.show({ message: 'Settings saved.', color: 'green' });
    },
    onError: () => notifications.show({ message: 'Failed to save settings.', color: 'red' }),
  });

  if (isLoading) return <Center py="xl"><Loader /></Center>;

  return (
    <Stack gap="xl">
      {/* ── Targets + Deadlines ──────────────────────────────────────────── */}
      <form onSubmit={form.onSubmit(v => mutation.mutate(v))}>
        <Stack gap="lg" maw={560}>
          <div>
            <Group gap="xs" mb="xs">
              <ThemeIcon size="sm" variant="light" color="blue" radius="xl">
                <IconTarget size={14} />
              </ThemeIcon>
              <Text size="sm" fw={700}>Monthly Submission Targets</Text>
            </Group>
            <Text size="xs" c="dimmed" mb="sm">
              How many reports of each type should staff submit per month.
            </Text>
            <SimpleGrid cols={3} spacing="sm">
              <NumberInput label="Daily target" min={1} max={200}
                {...form.getInputProps('daily_target')} />
              <NumberInput label="Weekly target" min={1} max={50}
                {...form.getInputProps('weekly_target')} />
              <NumberInput label="Monthly target" min={1} max={12}
                {...form.getInputProps('monthly_target')} />
            </SimpleGrid>
          </div>

          <Divider />

          <div>
            <Group gap="xs" mb="xs">
              <ThemeIcon size="sm" variant="light" color="orange" radius="xl">
                <IconClock size={14} />
              </ThemeIcon>
              <Text size="sm" fw={700}>Submission Deadlines</Text>
            </Group>
            <Text size="xs" c="dimmed" mb="sm">
              Reports submitted after these deadlines will be marked as late.
            </Text>
            <Stack gap="md">
              <Paper withBorder p="sm" radius="md">
                <Badge size="sm" color="blue" variant="light" mb="xs">Daily</Badge>
                <Text size="xs" c="dimmed" mb="xs">Submit by this time on the same day.</Text>
                <TimeInput label="Deadline time" leftSection={<IconClock size={14} />}
                  {...form.getInputProps('daily_deadline_time')} style={{ maxWidth: 180 }} />
              </Paper>

              <Paper withBorder p="sm" radius="md">
                <Badge size="sm" color="teal" variant="light" mb="xs">Weekly</Badge>
                <Text size="xs" c="dimmed" mb="xs">Submit by this day and time within the report week (Mon–Sun).</Text>
                <Group gap="sm" align="flex-end">
                  <Select label="Deadline day"
                    data={Object.entries(DAY_NAMES).map(([v, l]) => ({ value: String(v), label: l }))}
                    value={String(form.values.weekly_deadline_day)}
                    onChange={v => form.setFieldValue('weekly_deadline_day', Number(v))}
                    style={{ width: 160 }} />
                  <TimeInput label="Deadline time" leftSection={<IconClock size={14} />}
                    {...form.getInputProps('weekly_deadline_time')} style={{ width: 160 }} />
                </Group>
              </Paper>

              <Paper withBorder p="sm" radius="md">
                <Badge size="sm" color="violet" variant="light" mb="xs">Monthly</Badge>
                <Text size="xs" c="dimmed" mb="xs">Submit by day N of the same reporting month (1–28).</Text>
                <Group gap="sm" align="flex-end">
                  <NumberInput label="Deadline day" min={1} max={28}
                    {...form.getInputProps('monthly_deadline_day')} style={{ width: 160 }} />
                  <TimeInput label="Deadline time" leftSection={<IconClock size={14} />}
                    {...form.getInputProps('monthly_deadline_time')} style={{ width: 160 }} />
                </Group>
              </Paper>
            </Stack>
          </div>

          <Divider />

          {/* ── Deductions / Penalties ─────────────────────────────────── */}
          <div>
            <Group gap="xs" mb="xs" justify="space-between">
              <Group gap="xs">
                <ThemeIcon size="sm" variant="light" color="red" radius="xl">
                  <IconAlertTriangle size={14} />
                </ThemeIcon>
                <Text size="sm" fw={700}>Report Deductions</Text>
              </Group>
              <Switch label="Enabled" checked={!!form.values.penalties_enabled}
                onChange={(e) => form.setFieldValue('penalties_enabled', e.currentTarget.checked)} />
            </Group>
            <Text size="xs" c="dimmed" mb="sm">
              Amounts deducted from a staff member when a report is missed or submitted late.
              Missing-report deductions are applied automatically after each deadline; late deductions at submission.
            </Text>
            <SimpleGrid cols={{ base: 2, sm: 4 }} spacing="sm">
              <NumberInput label="Missing daily" min={0} thousandSeparator="," disabled={!form.values.penalties_enabled}
                {...form.getInputProps('penalty_missing_daily')} />
              <NumberInput label="Late report" min={0} thousandSeparator="," disabled={!form.values.penalties_enabled}
                {...form.getInputProps('penalty_late')} />
              <NumberInput label="Missing weekly" min={0} thousandSeparator="," disabled={!form.values.penalties_enabled}
                {...form.getInputProps('penalty_missing_weekly')} />
              <NumberInput label="Missing monthly" min={0} thousandSeparator="," disabled={!form.values.penalties_enabled}
                {...form.getInputProps('penalty_missing_monthly')} />
            </SimpleGrid>
          </div>

          <Group>
            <Button type="submit" loading={mutation.isPending}>Save Settings</Button>
          </Group>
        </Stack>
      </form>

      <Divider />

      {/* ── Supervisor Assignments ───────────────────────────────────────── */}
      <SupervisorAssignments />
    </Stack>
  );
}

// ── Supervisor Assignments (within Settings) ───────────────────────────────────

function SupervisorAssignments() {
  const qc = useQueryClient();

  const { data, isLoading } = useQuery({
    queryKey: ['staff-supervisors'],
    queryFn:  getSupervisors,
  });
  const staff: StaffWithSupervisor[] = data?.data?.data ?? [];

  const mutation = useMutation({
    mutationFn: ({ userId, supervisorId }: { userId: string; supervisorId: string | null }) =>
      updateSupervisor(userId, supervisorId),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['staff-supervisors'] });
      notifications.show({ message: 'Supervisor updated.', color: 'green' });
    },
    onError: () => notifications.show({ message: 'Failed to update supervisor.', color: 'red' }),
  });

  // All users can be chosen as supervisor (any user in the tenant)
  const supervisorOptions = staff.map(u => ({ value: u.id, label: u.name }));

  return (
    <div>
      <Group gap="xs" mb="xs">
        <ThemeIcon size="sm" variant="light" color="teal" radius="xl">
          <IconUsers size={14} />
        </ThemeIcon>
        <Text size="sm" fw={700}>Staff Supervisor Assignments</Text>
      </Group>
      <Text size="xs" c="dimmed" mb="md">
        Assign a supervisor to each staff member. Supervisors can review and track the reports of their assigned staff.
      </Text>

      {isLoading ? (
        <Center py="md"><Loader size="sm" /></Center>
      ) : (
        <Paper withBorder radius="md" style={{ overflow: 'hidden' }}>
          <Stack gap={0}>
            {staff.map((member, i) => (
              <Group
                key={member.id}
                justify="space-between"
                p="sm"
                style={{
                  borderBottom: i < staff.length - 1 ? '1px solid var(--mantine-color-default-border)' : undefined,
                }}
              >
                <Group gap="xs">
                  <Avatar size="sm" radius="xl" color="blue">{member.name[0]}</Avatar>
                  <Text size="sm" fw={500}>{member.name}</Text>
                </Group>
                <Select
                  size="xs"
                  placeholder="No supervisor"
                  clearable
                  searchable
                  data={supervisorOptions.filter(o => o.value !== member.id)}
                  value={member.supervisor?.id ?? null}
                  onChange={v => mutation.mutate({ userId: member.id, supervisorId: v ?? null })}
                  style={{ width: 220 }}
                  disabled={mutation.isPending}
                />
              </Group>
            ))}
            {staff.length === 0 && (
              <Center py="md">
                <Text c="dimmed" size="sm">No staff members found.</Text>
              </Center>
            )}
          </Stack>
        </Paper>
      )}
    </div>
  );
}

// ── Shared Report Card ─────────────────────────────────────────────────────────

function ReportCard({ report: r, actions }: { report: StaffReport; actions?: React.ReactNode }) {
  const [expanded, setExpanded] = useState(false);
  const typeCfg   = TYPE_CONFIG[r.report_type];
  const statusCfg = STATUS_CONFIG[r.status];

  return (
    <Paper withBorder p="sm" radius="md" style={{
      cursor: 'pointer',
      borderLeft: r.status === 'reviewed' ? '3px solid var(--mantine-color-green-5)' : undefined,
    }}
      onClick={() => setExpanded(e => !e)}>
      <Stack gap="xs">
        {/* Header row */}
        <Group justify="space-between" wrap="nowrap">
          <Group gap="xs" wrap="nowrap" style={{ flex: 1, minWidth: 0 }}>
            <Badge size="sm" color={typeCfg.color} variant="light">{typeCfg.label}</Badge>
            <Text size="sm" fw={600}>{r.period_label}</Text>
            {r.is_late && (
              <Badge size="xs" color="red" variant="light" leftSection={<IconAlertTriangle size={10} />}>
                Late
              </Badge>
            )}
          </Group>
          <Group gap="xs" wrap="nowrap" onClick={e => e.stopPropagation()}>
            <Badge size="sm" color={statusCfg.color} variant="dot">{statusCfg.label}</Badge>
            {r.rating && <Rating value={r.rating} readOnly size="xs" />}
            {actions}
          </Group>
        </Group>

        {/* Reviewed: show feedback preview even when collapsed */}
        {r.status === 'reviewed' && !expanded && r.review_notes && (
          <Group gap="xs" mt={2}>
            <ThemeIcon size={14} color="green" variant="transparent">
              <IconCheck size={12} />
            </ThemeIcon>
            <Text size="xs" c="dimmed" fs="italic" lineClamp={1}>
              "{r.review_notes}" — {r.reviewer?.name}
            </Text>
          </Group>
        )}
        {r.status === 'reviewed' && !expanded && !r.review_notes && (
          <Group gap="xs" mt={2}>
            <ThemeIcon size={14} color="green" variant="transparent">
              <IconCheck size={12} />
            </ThemeIcon>
            <Text size="xs" c="dimmed">Reviewed by {r.reviewer?.name} · {dayjs(r.reviewed_at!).format('D MMM YYYY')}</Text>
          </Group>
        )}

        {/* Preview / expand */}
        {r.achievements && !expanded && r.status !== 'reviewed' && (
          <Text size="xs" c="dimmed" lineClamp={2}>{r.achievements}</Text>
        )}

        {expanded && (
          <Stack gap="sm" mt="xs">
            {r.achievements && (
              <div>
                <Text size="xs" fw={600} c="teal" tt="uppercase" mb={2}>Achievements</Text>
                <Text size="sm" style={{ whiteSpace: 'pre-wrap' }}>{r.achievements}</Text>
              </div>
            )}
            {r.challenges && (
              <div>
                <Text size="xs" fw={600} c="orange" tt="uppercase" mb={2}>Challenges</Text>
                <Text size="sm" style={{ whiteSpace: 'pre-wrap' }}>{r.challenges}</Text>
              </div>
            )}
            {r.plans && (
              <div>
                <Text size="xs" fw={600} c="blue" tt="uppercase" mb={2}>Plans for next period</Text>
                <Text size="sm" style={{ whiteSpace: 'pre-wrap' }}>{r.plans}</Text>
              </div>
            )}
            {r.notes && (
              <div>
                <Text size="xs" fw={600} c="dimmed" tt="uppercase" mb={2}>Additional Notes</Text>
                <Text size="sm" style={{ whiteSpace: 'pre-wrap' }}>{r.notes}</Text>
              </div>
            )}

            {r.status === 'reviewed' && (
              <>
                <Divider label="Supervisor Review" labelPosition="left" />
                <Paper withBorder p="sm" radius="sm" bg="green.0">
                  <Group gap="xs" align="flex-start">
                    <ThemeIcon size="sm" variant="light" color="green" radius="xl">
                      <IconCheck size={12} />
                    </ThemeIcon>
                    <Stack gap={2} style={{ flex: 1 }}>
                      <Group gap="xs">
                        <Text size="xs" c="dimmed">
                          Reviewed by <Text span fw={600}>{r.reviewer?.name}</Text> · {dayjs(r.reviewed_at!).format('D MMM YYYY HH:mm')}
                        </Text>
                        {r.rating && <Rating value={r.rating} readOnly size="xs" />}
                      </Group>
                      {r.review_notes ? (
                        <Text size="sm" fs="italic">"{r.review_notes}"</Text>
                      ) : (
                        <Text size="xs" c="dimmed">No written feedback provided.</Text>
                      )}
                    </Stack>
                  </Group>
                </Paper>
              </>
            )}

            <Text size="xs" c="dimmed">Submitted {dayjs(r.created_at).format('D MMM YYYY HH:mm')}</Text>
          </Stack>
        )}
      </Stack>
    </Paper>
  );
}

// ── Submit / Edit Modal ────────────────────────────────────────────────────────

function ReportFormModal({ opened, onClose, existing, onSaved }: {
  opened: boolean; onClose: () => void;
  existing: StaffReport | null; onSaved: () => void;
}) {
  const [reportType, setReportType] = useState<ReportType>(existing?.report_type ?? 'daily');
  const [periodDate, setPeriodDate] = useState<Date | null>(new Date());

  const { data: settingsData } = useQuery({
    queryKey: ['staff-report-settings'],
    queryFn:  getSettings,
  });
  const settings = settingsData?.data?.data;

  // Determine if current period + type is past deadline
  const isDeadlinePassed = (): boolean => {
    if (!settings || !periodDate) return false;
    const now = new Date();
    if (reportType === 'daily') {
      const [h, m] = settings.daily_deadline_time.split(':').map(Number);
      const deadline = new Date(periodDate);
      deadline.setHours(h, m, 0, 0);
      return now > deadline;
    }
    if (reportType === 'weekly') {
      const mon = dayjs(periodDate).isoWeekday(1);
      const [h, m] = settings.weekly_deadline_time.split(':').map(Number);
      const deadline = mon.add(settings.weekly_deadline_day - 1, 'day').toDate();
      deadline.setHours(h, m, 0, 0);
      return now > deadline;
    }
    if (reportType === 'monthly') {
      const [h, m] = settings.monthly_deadline_time.split(':').map(Number);
      const deadline = new Date(dayjs(periodDate).startOf('month').toDate());
      deadline.setDate(settings.monthly_deadline_day);
      deadline.setHours(h, m, 0, 0);
      return now > deadline;
    }
    return false;
  };

  const form = useForm({
    initialValues: {
      achievements: existing?.achievements ?? '',
      challenges:   existing?.challenges   ?? '',
      plans:        existing?.plans        ?? '',
      notes:        existing?.notes        ?? '',
    },
    validate: {
      achievements: v => !v.trim() ? 'Achievements are required' : null,
    },
  });

  useEffect(() => {
    if (opened) {
      setReportType(existing?.report_type ?? 'daily');
      if (existing) {
        setPeriodDate(new Date(existing.period_date));
        form.setValues({
          achievements: existing.achievements ?? '',
          challenges:   existing.challenges   ?? '',
          plans:        existing.plans        ?? '',
          notes:        existing.notes        ?? '',
        });
      } else {
        const today = new Date();
        setPeriodDate(normalizePeriodDate(reportType, today));
        form.reset();
      }
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [opened, existing?.id]);

  useEffect(() => {
    if (!existing) {
      const today = new Date();
      setPeriodDate(normalizePeriodDate(reportType, today));
    }
  }, [reportType, existing]);

  const mutation = useMutation({
    mutationFn: (v: ReturnType<typeof form.getValues>) => {
      if (existing) {
        return updateReport(existing.id, {
          achievements: v.achievements || undefined,
          challenges:   v.challenges   || undefined,
          plans:        v.plans        || undefined,
          notes:        v.notes        || undefined,
        });
      }
      const normalized = normalizePeriodDate(reportType, periodDate!);
      return createReport({
        report_type:  reportType,
        period_date:  dayjs(normalized).format('YYYY-MM-DD'),
        achievements: v.achievements || undefined,
        challenges:   v.challenges   || undefined,
        plans:        v.plans        || undefined,
        notes:        v.notes        || undefined,
      });
    },
    onSuccess: () => {
      notifications.show({ message: existing ? 'Report updated.' : 'Report submitted.', color: 'green' });
      onSaved();
      onClose();
    },
    onError: (err: any) => {
      const msg = err?.response?.data?.message ?? 'Failed to save report.';
      notifications.show({ message: msg, color: 'red', title: 'Error' });
    },
  });

  const deadlinePassed = !existing && isDeadlinePassed();

  return (
    <Modal opened={opened} onClose={onClose}
      title={existing ? 'Edit Report' : 'Submit Report'}
      centered size="lg" scrollAreaComponent={ScrollArea.Autosize}>
      <form onSubmit={form.onSubmit(v => mutation.mutate(v))}>
        <Stack gap="md">
          {!existing && (
            <Stack gap="sm">
              <div>
                <Text size="sm" fw={500} mb={6}>Report type</Text>
                <SegmentedControl fullWidth
                  value={reportType}
                  onChange={v => setReportType(v as ReportType)}
                  data={[
                    { value: 'daily',   label: 'Daily'   },
                    { value: 'weekly',  label: 'Weekly'  },
                    { value: 'monthly', label: 'Monthly' },
                  ]}
                />
              </div>

              {reportType === 'monthly' ? (
                <MonthPickerInput
                  label="Month"
                  value={periodDate}
                  onChange={v => setPeriodDate(v ? new Date(v as any) : null)}
                  leftSection={<IconCalendar size={14} />}
                  required
                />
              ) : (
                <DatePickerInput
                  label={reportType === 'weekly' ? 'Any day in the week' : 'Date'}
                  value={periodDate}
                  onChange={v => setPeriodDate(v ? new Date(v as any) : null)}
                  leftSection={<IconCalendar size={14} />}
                  description={reportType === 'weekly' && periodDate
                    ? `Week: ${weekRangeLabel(periodDate)}`
                    : undefined}
                  required
                />
              )}

              {deadlinePassed && (
                <Alert icon={<IconAlertTriangle size={14} />} color="orange" py="xs">
                  The submission deadline for this period has passed. This report will be marked as late.
                </Alert>
              )}
            </Stack>
          )}

          {existing && (
            <Group gap="xs">
              <Badge color={TYPE_CONFIG[existing.report_type].color} variant="light">
                {TYPE_CONFIG[existing.report_type].label}
              </Badge>
              <Text size="sm" fw={500}>{existing.period_label}</Text>
            </Group>
          )}

          <Divider />

          <Textarea
            label="Achievements"
            description="What did you accomplish this period?"
            placeholder="Completed X, delivered Y, resolved Z…"
            minRows={3} autosize maxRows={8}
            required
            {...form.getInputProps('achievements')}
          />

          <Textarea
            label="Challenges"
            description="What obstacles did you face?"
            placeholder="Any difficulties, blockers, or issues encountered…"
            minRows={2} autosize maxRows={6}
            leftSection={<IconAlertCircle size={14} />}
            {...form.getInputProps('challenges')}
          />

          <Textarea
            label="Plans for next period"
            description="What will you focus on next?"
            placeholder="Key priorities and goals for the upcoming period…"
            minRows={2} autosize maxRows={6}
            {...form.getInputProps('plans')}
          />

          <Textarea
            label="Additional notes"
            placeholder="Anything else to share with your manager…"
            minRows={1} autosize maxRows={4}
            {...form.getInputProps('notes')}
          />

          <Group justify="flex-end">
            <Button variant="default" onClick={onClose}>Cancel</Button>
            <Button type="submit" loading={mutation.isPending}
              color={deadlinePassed ? 'orange' : undefined}>
              {existing ? 'Update' : deadlinePassed ? 'Submit (Late)' : 'Submit Report'}
            </Button>
          </Group>
        </Stack>
      </form>
    </Modal>
  );
}

// ── Review Modal ───────────────────────────────────────────────────────────────

function ReviewModal({ report, opened, onClose, onSaved }: {
  report: StaffReport; opened: boolean; onClose: () => void; onSaved: () => void;
}) {
  const form = useForm({
    initialValues: {
      rating:       report.rating ?? 0,
      review_notes: report.review_notes ?? '',
    },
  });

  useEffect(() => {
    if (opened) {
      form.setValues({
        rating:       report.rating ?? 0,
        review_notes: report.review_notes ?? '',
      });
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [opened, report.id]);

  const mutation = useMutation({
    mutationFn: (v: ReturnType<typeof form.getValues>) =>
      reviewReport(report.id, {
        rating:       v.rating || undefined,
        review_notes: v.review_notes || undefined,
      }),
    onSuccess: () => {
      notifications.show({ message: 'Review saved.', color: 'green' });
      onSaved();
      onClose();
    },
  });

  const typeCfg = TYPE_CONFIG[report.report_type];

  return (
    <Modal opened={opened} onClose={onClose}
      title={
        <Group gap="xs">
          <Badge color={typeCfg.color} variant="light">{typeCfg.label}</Badge>
          <Text fw={600}>{report.user.name} · {report.period_label}</Text>
          {report.is_late && (
            <Badge size="xs" color="red" variant="light">Late</Badge>
          )}
        </Group>
      }
      centered size="lg" scrollAreaComponent={ScrollArea.Autosize}>
      <Stack gap="md">
        <ScrollArea.Autosize mah={320}>
          <Stack gap="sm">
            {report.achievements && (
              <div>
                <Text size="xs" fw={600} c="teal" tt="uppercase" mb={2}>Achievements</Text>
                <Text size="sm" style={{ whiteSpace: 'pre-wrap' }}>{report.achievements}</Text>
              </div>
            )}
            {report.challenges && (
              <div>
                <Text size="xs" fw={600} c="orange" tt="uppercase" mb={2}>Challenges</Text>
                <Text size="sm" style={{ whiteSpace: 'pre-wrap' }}>{report.challenges}</Text>
              </div>
            )}
            {report.plans && (
              <div>
                <Text size="xs" fw={600} c="blue" tt="uppercase" mb={2}>Plans for next period</Text>
                <Text size="sm" style={{ whiteSpace: 'pre-wrap' }}>{report.plans}</Text>
              </div>
            )}
            {report.notes && (
              <div>
                <Text size="xs" fw={600} c="dimmed" tt="uppercase" mb={2}>Additional notes</Text>
                <Text size="sm" style={{ whiteSpace: 'pre-wrap' }}>{report.notes}</Text>
              </div>
            )}
          </Stack>
        </ScrollArea.Autosize>

        <Divider label="Your assessment" labelPosition="center" />

        <form onSubmit={form.onSubmit(v => mutation.mutate(v))}>
          <Stack gap="sm">
            <div>
              <Text size="sm" fw={500} mb={6}>Rating</Text>
              <Rating size="lg"
                value={form.values.rating}
                onChange={v => form.setFieldValue('rating', v)}
              />
            </div>

            <Textarea
              label="Feedback"
              placeholder="Share your assessment, commendations, or areas for improvement…"
              minRows={3} autosize maxRows={6}
              leftSection={<IconStar size={14} />}
              {...form.getInputProps('review_notes')}
            />

            <Group justify="flex-end">
              <Button variant="default" onClick={onClose}>Cancel</Button>
              <Button type="submit" loading={mutation.isPending}
                leftSection={<IconCheck size={14} />}>
                Save Review
              </Button>
            </Group>
          </Stack>
        </form>
      </Stack>
    </Modal>
  );
}
