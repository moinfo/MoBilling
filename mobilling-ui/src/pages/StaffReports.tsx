import { useState, useEffect } from 'react';
import {
  Title, Tabs, Stack, Group, Button, Badge, Text, Paper, ActionIcon,
  Textarea, Modal, Loader, Center, ThemeIcon, Select, Divider,
  SegmentedControl, Avatar, ScrollArea,
} from '@mantine/core';
import { DatePickerInput, MonthPickerInput } from '@mantine/dates';
import { useDisclosure } from '@mantine/hooks';
import { useForm } from '@mantine/form';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { Rating } from '@mantine/core';
import {
  IconPlus, IconEdit, IconTrash, IconCalendar, IconCheck,
  IconClipboardList, IconUsers, IconStar, IconAlertCircle,
} from '@tabler/icons-react';
import dayjs from 'dayjs';
import isoWeek from 'dayjs/plugin/isoWeek';
dayjs.extend(isoWeek);
import {
  getReports, createReport, updateReport, deleteReport, reviewReport,
  type StaffReport,
} from '../api/staffReports';
import { usePermissions } from '../hooks/usePermissions';

// ── Config ───────────────────────────────────────────────────────────────────

const TYPE_CONFIG = {
  daily:   { color: 'blue',   label: 'Daily'   },
  weekly:  { color: 'teal',   label: 'Weekly'  },
  monthly: { color: 'violet', label: 'Monthly' },
} as const;

const STATUS_CONFIG = {
  submitted: { color: 'orange', label: 'Pending Review' },
  reviewed:  { color: 'green',  label: 'Reviewed'       },
} as const;

type ReportType = 'daily' | 'weekly' | 'monthly';

// ── Helpers ──────────────────────────────────────────────────────────────────

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

// ── Main page ────────────────────────────────────────────────────────────────

export default function StaffReports() {
  const { can } = usePermissions();

  return (
    <Stack>
      <Title order={2}>Staff Reports</Title>
      <Tabs
        defaultValue={can('staff_reports.submit') ? 'mine' : 'team'}
        keepMounted={false}
      >
        <Tabs.List>
          {can('staff_reports.submit') && (
            <Tabs.Tab value="mine" leftSection={<IconClipboardList size={15} />}>
              My Reports
            </Tabs.Tab>
          )}
          {can('staff_reports.review') && (
            <Tabs.Tab value="team" leftSection={<IconUsers size={15} />}>
              Team Reports
            </Tabs.Tab>
          )}
        </Tabs.List>

        {can('staff_reports.submit') && (
          <Tabs.Panel value="mine" pt="md">
            <MyReportsTab can={can} />
          </Tabs.Panel>
        )}
        {can('staff_reports.review') && (
          <Tabs.Panel value="team" pt="md">
            <TeamReportsTab can={can} />
          </Tabs.Panel>
        )}
      </Tabs>
    </Stack>
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
        onSaved={() => qc.invalidateQueries({ queryKey: ['staff-reports-mine'] })} />
    </Stack>
  );
}

// ── Team Reports Tab ──────────────────────────────────────────────────────────

function TeamReportsTab({ can }: { can: (p: string) => boolean }) {
  const qc = useQueryClient();
  const [typeFilter, setTypeFilter]     = useState('');
  const [statusFilter, setStatusFilter] = useState('');
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

  const grouped = reports.reduce<Record<string, StaffReport[]>>((acc, r) => {
    (acc[r.user.id] ??= []).push(r);
    return acc;
  }, {});

  return (
    <Stack>
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
        <Text size="xs" c="dimmed">{reports.length} report{reports.length !== 1 ? 's' : ''}</Text>
      </Group>

      {isLoading ? (
        <Center py="xl"><Loader /></Center>
      ) : reports.length === 0 ? (
        <Center py="xl"><Text c="dimmed">No reports found.</Text></Center>
      ) : (
        <Stack gap="lg">
          {Object.entries(grouped).map(([, userReports]) => {
            const user = userReports[0].user;
            return (
              <div key={user.id}>
                <Group gap="xs" mb="xs">
                  <Avatar size="sm" radius="xl" color="blue">{user.name[0]}</Avatar>
                  <Text size="sm" fw={700}>{user.name}</Text>
                  <Badge size="sm" variant="light">{userReports.length}</Badge>
                </Group>
                <Stack gap="xs" pl="md">
                  {userReports.map(r => (
                    <ReportCard key={r.id} report={r}
                      actions={
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
                        ) : null
                      }
                    />
                  ))}
                </Stack>
              </div>
            );
          })}
        </Stack>
      )}

      {reviewing && (
        <ReviewModal report={reviewing} opened={reviewModal}
          onClose={() => { closeReview(); setReviewing(null); }}
          onSaved={() => qc.invalidateQueries({ queryKey: ['staff-reports-team'] })} />
      )}
    </Stack>
  );
}

// ── Shared Report Card ────────────────────────────────────────────────────────

function ReportCard({ report: r, actions }: { report: StaffReport; actions?: React.ReactNode }) {
  const [expanded, setExpanded] = useState(false);
  const typeCfg  = TYPE_CONFIG[r.report_type];
  const statusCfg = STATUS_CONFIG[r.status];

  return (
    <Paper withBorder p="sm" radius="md" style={{ cursor: 'pointer' }}
      onClick={() => setExpanded(e => !e)}>
      <Stack gap="xs">
        {/* Header row */}
        <Group justify="space-between" wrap="nowrap">
          <Group gap="xs" wrap="nowrap" style={{ flex: 1, minWidth: 0 }}>
            <Badge size="sm" color={typeCfg.color} variant="light">{typeCfg.label}</Badge>
            <Text size="sm" fw={600}>{r.period_label}</Text>
          </Group>
          <Group gap="xs" wrap="nowrap" onClick={e => e.stopPropagation()}>
            <Badge size="sm" color={statusCfg.color} variant="dot">{statusCfg.label}</Badge>
            {r.rating && <Rating value={r.rating} readOnly size="xs" />}
            {actions}
          </Group>
        </Group>

        {/* Preview / expand */}
        {r.achievements && !expanded && (
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
                <Divider label="Review" labelPosition="left" />
                <Group gap="xs" align="flex-start">
                  <ThemeIcon size="sm" variant="light" color="green" radius="xl">
                    <IconCheck size={12} />
                  </ThemeIcon>
                  <Stack gap={2} style={{ flex: 1 }}>
                    <Group gap="xs">
                      <Text size="xs" c="dimmed">
                        Reviewed by {r.reviewer?.name} · {dayjs(r.reviewed_at!).format('D MMM YYYY')}
                      </Text>
                      {r.rating && <Rating value={r.rating} readOnly size="xs" />}
                    </Group>
                    {r.review_notes && (
                      <Text size="sm" fs="italic" c="dimmed">"{r.review_notes}"</Text>
                    )}
                  </Stack>
                </Group>
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
        setPeriodDate(reportType === 'weekly' ? normalizePeriodDate('weekly', today)
          : reportType === 'monthly' ? normalizePeriodDate('monthly', today) : today);
        form.reset();
      }
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [opened, existing?.id]);

  // Reset period when type changes (new report only)
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

  return (
    <Modal opened={opened} onClose={onClose}
      title={existing ? 'Edit Report' : 'Submit Report'}
      centered size="lg" scrollAreaComponent={ScrollArea.Autosize}>
      <form onSubmit={form.onSubmit(v => mutation.mutate(v))}>
        <Stack gap="md">
          {/* Type + period — locked when editing */}
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
                  onChange={v => setPeriodDate(v)}
                  leftSection={<IconCalendar size={14} />}
                  description={reportType === 'weekly' && periodDate
                    ? `Week: ${weekRangeLabel(periodDate)}`
                    : undefined}
                  required
                />
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
            <Button type="submit" loading={mutation.isPending}>
              {existing ? 'Update' : 'Submit Report'}
            </Button>
          </Group>
        </Stack>
      </form>
    </Modal>
  );
}

// ── Review Modal ──────────────────────────────────────────────────────────────

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
        </Group>
      }
      centered size="lg" scrollAreaComponent={ScrollArea.Autosize}>
      <Stack gap="md">
        {/* Report content — read only */}
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
