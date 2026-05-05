import { Fragment, useState, useEffect } from 'react';
import {
  Title, Tabs, Stack, Group, Button, Badge, Text, Paper, ActionIcon,
  TextInput, Textarea, Modal, Switch, NumberInput, MultiSelect, Checkbox,
  Divider, Loader, Center, ThemeIcon, SimpleGrid, Progress, Table,
} from '@mantine/core';
import { DatePickerInput, MonthPickerInput } from '@mantine/dates';
import { useDisclosure } from '@mantine/hooks';
import { useForm } from '@mantine/form';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import {
  IconPlus, IconEdit, IconTrash, IconPhone, IconCalendar,
  IconUser, IconSettings, IconNotes, IconUsers, IconCheck,
  IconStar, IconMoodHappy, IconMoodNeutral, IconMoodSad, IconMessageCircle,
  IconTarget, IconUserPlus, IconChartBar,
} from '@tabler/icons-react';
import { Rating } from '@mantine/core';
import dayjs from 'dayjs';
import isoWeek from 'dayjs/plugin/isoWeek';
dayjs.extend(isoWeek);
import {
  getServices, createService, updateService, deleteService,
  getCustomers, createCustomer, updateCustomer, deleteCustomer,
  createFeedback, deleteFeedback,
  getServedTarget, upsertServedTarget, getServedWeeklySummary,
  getServedReport,
  type ServedService, type ServedCustomer, type ServedTarget,
  type ServedReport, type ServedReportDay,
} from '../api/servedCustomers';
import { usePermissions } from '../hooks/usePermissions';

export default function ServedCustomers() {
  const { can } = usePermissions();

  return (
    <Stack>
      <Title order={2}>Served Customers</Title>
      <Tabs
        defaultValue={can('served.read') ? 'customers' : can('served.settings') ? 'target' : 'services'}
        keepMounted={false}
      >
        <Tabs.List>
          {can('served.read') && (
            <Tabs.Tab value="customers" leftSection={<IconUsers size={15} />}>Customers</Tabs.Tab>
          )}
          {can('served.read') && (
            <Tabs.Tab value="target" leftSection={<IconTarget size={15} />}>Target</Tabs.Tab>
          )}
          {can('served.read') && (
            <Tabs.Tab value="report" leftSection={<IconChartBar size={15} />}>Report</Tabs.Tab>
          )}
          {can('served.settings') && (
            <Tabs.Tab value="services" leftSection={<IconSettings size={15} />}>Services</Tabs.Tab>
          )}
        </Tabs.List>
        {can('served.read') && (
          <Tabs.Panel value="customers" pt="md">
            <CustomersTab can={can} />
          </Tabs.Panel>
        )}
        {can('served.read') && (
          <Tabs.Panel value="target" pt="md">
            <TargetTab can={can} />
          </Tabs.Panel>
        )}
        {can('served.read') && (
          <Tabs.Panel value="report" pt="md">
            <ReportTab can={can} />
          </Tabs.Panel>
        )}
        {can('served.settings') && (
          <Tabs.Panel value="services" pt="md">
            <ServicesTab can={can} />
          </Tabs.Panel>
        )}
      </Tabs>
    </Stack>
  );
}

// ── Customers Tab ────────────────────────────────────────────────────────────

const OUTCOME_CONFIG = {
  satisfied:    { color: 'green',  icon: <IconMoodHappy   size={13} />, label: 'Satisfied'    },
  neutral:      { color: 'yellow', icon: <IconMoodNeutral size={13} />, label: 'Neutral'       },
  dissatisfied: { color: 'red',    icon: <IconMoodSad     size={13} />, label: 'Dissatisfied'  },
} as const;

function CustomersTab({ can }: { can: (p: string) => boolean }) {
  const qc = useQueryClient();
  const [dateFilter, setDateFilter] = useState<string | null>(null);
  const [search, setSearch]         = useState('');
  const [editing, setEditing]       = useState<ServedCustomer | null>(null);
  const [feedbackTarget, setFeedbackTarget] = useState<ServedCustomer | null>(null);
  const [modal,         { open,         close         }] = useDisclosure(false);
  const [feedbackModal, { open: openFb, close: closeFb }] = useDisclosure(false);

  const { data, isLoading } = useQuery({
    queryKey: ['served-customers', dateFilter, search],
    queryFn: () => getCustomers({
      date:   dateFilter ? dayjs(dateFilter).format('YYYY-MM-DD') : undefined,
      search: search || undefined,
    }),
  });
  const customers: ServedCustomer[] = data?.data?.data ?? [];

  const deleteMutation = useMutation({
    mutationFn: deleteCustomer,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['served-customers'] });
      notifications.show({ message: 'Record deleted.', color: 'green' });
    },
  });

  // Group by date for display
  const grouped = customers.reduce<Record<string, ServedCustomer[]>>((acc, c) => {
    (acc[c.served_date] ??= []).push(c);
    return acc;
  }, {});
  const sortedDates = Object.keys(grouped).sort((a, b) => b.localeCompare(a));

  return (
    <Stack>
      {/* Filters */}
      <Group justify="space-between" wrap="nowrap">
        <Group gap="xs">
          <DatePickerInput
            size="xs" placeholder="Filter by date" clearable
            leftSection={<IconCalendar size={14} />}
            value={dateFilter} onChange={v => setDateFilter(v ? dayjs(v as any).format('YYYY-MM-DD') : null)}
            style={{ width: 160 }}
          />
          <TextInput
            size="xs" placeholder="Search name or phone…"
            value={search} onChange={e => setSearch(e.currentTarget.value)}
            style={{ width: 200 }}
          />
          <Text size="xs" c="dimmed">{customers.length} record{customers.length !== 1 ? 's' : ''}</Text>
        </Group>
        {can('served.create') && (
          <Button leftSection={<IconPlus size={16} />} onClick={() => { setEditing(null); open(); }}>
            Add Record
          </Button>
        )}
      </Group>

      {/* List grouped by date */}
      {isLoading ? <Center py="xl"><Loader /></Center> : sortedDates.length === 0 ? (
        <Center py="xl"><Text c="dimmed">No records yet.</Text></Center>
      ) : (
        <Stack gap="md">
          {sortedDates.map(date => (
            <div key={date}>
              <Group gap="xs" mb="xs">
                <Text size="sm" fw={700} c="blue">{dayjs(date).format('ddd, D MMM YYYY')}</Text>
                <Badge size="sm" variant="light">{grouped[date].length}</Badge>
              </Group>
              <Stack gap="xs">
                {grouped[date].map(c => (
                  <Paper key={c.id} withBorder p="sm" radius="md">
                    <Group justify="space-between" wrap="nowrap">
                      <Group gap="md" wrap="nowrap" style={{ minWidth: 0, flex: 1 }}>
                        <ThemeIcon size="md" variant="light" color="teal" radius="xl">
                          <IconUser size={14} />
                        </ThemeIcon>
                        <div style={{ minWidth: 0 }}>
                          <Text size="sm" fw={600}>{c.name}</Text>
                          {c.phone && (
                            <Group gap={4}>
                              <IconPhone size={11} color="var(--mantine-color-dimmed)" />
                              <Text size="xs" c="dimmed">{c.phone}</Text>
                            </Group>
                          )}
                          {c.services.length > 0 && (
                            <Group gap={4} mt={4} wrap="wrap">
                              {c.services.map(s => (
                                <Badge key={s.id} size="xs" variant="light" color="teal"
                                  leftSection={<IconCheck size={9} />}>
                                  {s.name}
                                </Badge>
                              ))}
                            </Group>
                          )}
                          {c.feedbacks.length > 0 && (() => {
                            const last = c.feedbacks[0];
                            const cfg = last.outcome ? OUTCOME_CONFIG[last.outcome] : null;
                            return (
                              <Group gap={4} mt={4} wrap="wrap">
                                {cfg && (
                                  <Badge size="xs" color={cfg.color} variant="light" leftSection={cfg.icon}>
                                    {cfg.label}
                                  </Badge>
                                )}
                                {last.rating && (
                                  <Badge size="xs" color="yellow" variant="light" leftSection={<IconStar size={9} />}>
                                    {last.rating}/5
                                  </Badge>
                                )}
                                <Badge size="xs" color="gray" variant="dot">
                                  {c.feedbacks.length} feedback{c.feedbacks.length !== 1 ? 's' : ''}
                                </Badge>
                              </Group>
                            );
                          })()}
                          {c.notes && (
                            <Text size="xs" c="dimmed" lineClamp={1} mt={2}>{c.notes}</Text>
                          )}
                          {c.created_by && (
                            <Text size="xs" c="dimmed" mt={2}>Added by {c.created_by.name}</Text>
                          )}
                        </div>
                      </Group>
                      <Group gap="xs" wrap="nowrap">
                        {can('served.create') && (
                          <ActionIcon size="sm" variant="light" color="blue"
                            title="Call & log feedback"
                            onClick={e => { e.stopPropagation(); setFeedbackTarget(c); openFb(); }}>
                            <IconMessageCircle size={14} />
                          </ActionIcon>
                        )}
                        {can('served.update') && (
                          <ActionIcon size="sm" variant="subtle"
                            onClick={() => { setEditing(c); open(); }}>
                            <IconEdit size={14} />
                          </ActionIcon>
                        )}
                        {can('served.delete') && (
                          <ActionIcon size="sm" variant="subtle" color="red"
                            onClick={() => deleteMutation.mutate(c.id)}>
                            <IconTrash size={14} />
                          </ActionIcon>
                        )}
                      </Group>
                    </Group>
                  </Paper>
                ))}
              </Stack>
            </div>
          ))}
        </Stack>
      )}

      <CustomerFormModal opened={modal} onClose={close} existing={editing} can={can} />
      {feedbackTarget && (
        <FeedbackModal
          customer={feedbackTarget}
          opened={feedbackModal}
          onClose={() => { closeFb(); setFeedbackTarget(null); }}
          can={can}
        />
      )}
    </Stack>
  );
}

function CustomerFormModal({ opened, onClose, existing, can }: {
  opened: boolean; onClose: () => void; existing: ServedCustomer | null;
  can: (p: string) => boolean;
}) {
  const qc = useQueryClient();

  const { data: servicesData } = useQuery({ queryKey: ['served-services'], queryFn: getServices });
  const serviceOptions = (servicesData?.data?.data ?? [])
    .filter(s => s.is_active)
    .map(s => ({ value: s.id, label: s.name }));

  const form = useForm({
    initialValues: {
      name:        existing?.name        ?? '',
      phone:       existing?.phone       ?? '',
      served_date: existing?.served_date ? new Date(existing.served_date) : new Date() as Date | null,
      notes:       existing?.notes       ?? '',
      service_ids: existing?.services.map(s => s.id) ?? [] as string[],
    },
    validate: {
      name:        v => !v.trim() ? 'Name is required' : null,
      served_date: v => !v ? 'Date is required' : null,
    },
  });

  useEffect(() => {
    if (existing) {
      form.setValues({
        name:        existing.name,
        phone:       existing.phone ?? '',
        served_date: new Date(existing.served_date),
        notes:       existing.notes ?? '',
        service_ids: existing.services.map(s => s.id),
      });
    } else {
      form.reset();
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [existing?.id]);

  const mutation = useMutation({
    mutationFn: (v: ReturnType<typeof form.getValues>) => {
      const payload = {
        name:        v.name,
        phone:       v.phone || undefined,
        served_date: dayjs(v.served_date!).format('YYYY-MM-DD'),
        notes:       v.notes || undefined,
        service_ids: v.service_ids,
      };
      return existing
        ? updateCustomer(existing.id, payload)
        : createCustomer(payload);
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['served-customers'] });
      notifications.show({ message: existing ? 'Record updated.' : 'Customer recorded.', color: 'green' });
      form.reset();
      onClose();
    },
    onError: (err: any) => {
      const msg = err?.response?.data?.message ?? 'Failed to save record.';
      notifications.show({ message: msg, color: 'red', title: 'Duplicate' });
    },
  });

  return (
    <Modal opened={opened} onClose={onClose}
      title={existing ? 'Edit Record' : 'Record Served Customer'}
      centered size="sm">
      <form onSubmit={form.onSubmit(v => mutation.mutate(v))}>
        <Stack gap="sm">
          <TextInput label="Customer name" required placeholder="John Doe"
            leftSection={<IconUser size={14} />}
            {...form.getInputProps('name')} />

          <TextInput label="Phone number" placeholder="+254 700 000 000"
            leftSection={<IconPhone size={14} />}
            {...form.getInputProps('phone')} />

          {can('served.change_date') ? (
            <DatePickerInput label="Date served" required
              leftSection={<IconCalendar size={14} />}
              {...form.getInputProps('served_date')} />
          ) : (
            <TextInput
              label="Date served"
              readOnly
              leftSection={<IconCalendar size={14} />}
              value={dayjs(form.values.served_date ?? new Date()).format('D MMM YYYY')}
              description="Only managers can change the served date"
            />
          )}

          <MultiSelect
            label="Services received"
            placeholder="Select services…"
            data={serviceOptions}
            searchable clearable
            {...form.getInputProps('service_ids')}
          />

          <Textarea label="Notes" placeholder="Additional notes…"
            minRows={2} leftSection={<IconNotes size={14} />}
            {...form.getInputProps('notes')} />

          <Group justify="flex-end" mt="xs">
            <Button variant="default" onClick={onClose}>Cancel</Button>
            <Button type="submit" loading={mutation.isPending}>
              {existing ? 'Update' : 'Save'}
            </Button>
          </Group>
        </Stack>
      </form>
    </Modal>
  );
}

// ── Feedback Modal ───────────────────────────────────────────────────────────

function FeedbackModal({ customer, opened, onClose, can }: {
  customer: ServedCustomer; opened: boolean; onClose: () => void;
  can: (p: string) => boolean;
}) {
  const qc = useQueryClient();

  const form = useForm({
    initialValues: {
      rating:         0,
      outcome:        '' as '' | 'satisfied' | 'neutral' | 'dissatisfied',
      feedback:       '',
      challenges:     '',
      internal_notes: '',
    },
  });

  const mutation = useMutation({
    mutationFn: (v: ReturnType<typeof form.getValues>) =>
      createFeedback(customer.id, {
        rating:         v.rating || undefined,
        outcome:        v.outcome || undefined,
        feedback:       v.feedback || undefined,
        challenges:     v.challenges || undefined,
        internal_notes: v.internal_notes || undefined,
      }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['served-customers'] });
      notifications.show({ message: 'Feedback logged.', color: 'green' });
      form.reset();
      onClose();
    },
  });

  const deleteFb = useMutation({
    mutationFn: (fbId: string) => deleteFeedback(customer.id, fbId),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['served-customers'] }),
  });

  return (
    <Modal opened={opened} onClose={onClose}
      title={
        <Group gap="xs">
          <IconMessageCircle size={16} />
          <Text fw={600}>Feedback — {customer.name}</Text>
        </Group>
      }
      centered size="md">
      <Stack gap="md">
        {/* Past feedbacks */}
        {customer.feedbacks.length > 0 && (
          <Stack gap="xs">
            <Text size="xs" fw={600} c="dimmed" tt="uppercase">Previous calls</Text>
            {customer.feedbacks.map(fb => {
              const cfg = fb.outcome ? OUTCOME_CONFIG[fb.outcome] : null;
              return (
                <Paper key={fb.id} withBorder p="xs" radius="sm">
                  <Group justify="space-between" wrap="nowrap" align="flex-start">
                    <Stack gap={4} style={{ flex: 1, minWidth: 0 }}>
                      <Group gap="xs">
                        <Text size="xs" c="dimmed">
                          {dayjs(fb.called_at).format('D MMM YYYY HH:mm')}
                          {fb.created_by && ` · ${fb.created_by.name}`}
                        </Text>
                        {cfg && <Badge size="xs" color={cfg.color} variant="light" leftSection={cfg.icon}>{cfg.label}</Badge>}
                        {fb.rating && (
                          <Rating value={fb.rating} readOnly size="xs" />
                        )}
                      </Group>
                      {fb.feedback && <Text size="xs">"{fb.feedback}"</Text>}
                      {fb.challenges && (
                        <Text size="xs" c="orange">Challenges: {fb.challenges}</Text>
                      )}
                      {fb.internal_notes && (
                        <Text size="xs" c="dimmed" fs="italic">Notes: {fb.internal_notes}</Text>
                      )}
                    </Stack>
                    {can('served.delete') && (
                      <ActionIcon size="xs" variant="subtle" color="red"
                        onClick={() => deleteFb.mutate(fb.id)}>
                        <IconTrash size={11} />
                      </ActionIcon>
                    )}
                  </Group>
                </Paper>
              );
            })}
          </Stack>
        )}

        {/* New feedback form */}
        {can('served.create') && (
          <>
            {customer.feedbacks.length > 0 && <Divider label="Log new call" labelPosition="center" />}
            <form onSubmit={form.onSubmit(v => mutation.mutate(v))}>
              <Stack gap="sm">
                <Group gap="xl">
                  <div>
                    <Text size="sm" fw={500} mb={4}>Rating</Text>
                    <Rating size="md" value={form.values.rating}
                      onChange={v => form.setFieldValue('rating', v)} />
                  </div>
                  <div>
                    <Text size="sm" fw={500} mb={4}>Outcome</Text>
                    <Group gap="xs">
                      {(['satisfied', 'neutral', 'dissatisfied'] as const).map(o => {
                        const cfg = OUTCOME_CONFIG[o];
                        const active = form.values.outcome === o;
                        return (
                          <Badge
                            key={o} size="md"
                            color={active ? cfg.color : 'gray'}
                            variant={active ? 'filled' : 'light'}
                            leftSection={cfg.icon}
                            style={{ cursor: 'pointer' }}
                            onClick={() => form.setFieldValue('outcome', active ? '' : o)}
                          >
                            {cfg.label}
                          </Badge>
                        );
                      })}
                    </Group>
                  </div>
                </Group>

                <Textarea label="Customer feedback" placeholder="What did the customer say?"
                  minRows={2} {...form.getInputProps('feedback')} />

                <Textarea label="Challenges / Issues" placeholder="Any difficulties or complaints raised…"
                  minRows={2} {...form.getInputProps('challenges')} />

                <Textarea label="Internal notes" placeholder="Private notes for the team…"
                  minRows={1} {...form.getInputProps('internal_notes')} />

                <Group justify="flex-end">
                  <Button variant="default" onClick={onClose}>Cancel</Button>
                  <Button type="submit" loading={mutation.isPending}
                    leftSection={<IconMessageCircle size={14} />}>
                    Log Feedback
                  </Button>
                </Group>
              </Stack>
            </form>
          </>
        )}
      </Stack>
    </Modal>
  );
}

// ── Target Tab ───────────────────────────────────────────────────────────────

const DAY_NAMES = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

function weekStartStr(offset = 0) {
  return dayjs().isoWeekday(1).add(offset, 'week').format('YYYY-MM-DD');
}

function TargetTab({ can }: { can: (p: string) => boolean }) {
  const [weekOffset, setWeekOffset] = useState(0);
  const ws = weekStartStr(weekOffset);
  const we = dayjs(ws).add(6, 'day').format('YYYY-MM-DD');
  const [modal, { open, close }] = useDisclosure(false);

  const { data: targetData } = useQuery({ queryKey: ['served-target'], queryFn: getServedTarget });
  const { data: summaryData, isLoading } = useQuery({
    queryKey: ['served-weekly-summary', ws],
    queryFn: () => getServedWeeklySummary(ws),
  });

  const target  = targetData?.data?.data ?? null;
  const summary = summaryData?.data ?? null;

  const newDone      = summary?.new_customers_achieved ?? 0;
  const calledDone   = summary?.calls_achieved ?? 0;
  const newTarget    = summary?.new_customers_target ?? 0;
  const calledTarget = summary?.calls_target ?? 0;
  const newPct       = newTarget > 0 ? Math.min(100, Math.round((newDone / newTarget) * 100)) : 0;
  const calledPct    = calledTarget > 0 ? Math.min(100, Math.round((calledDone / calledTarget) * 100)) : 0;
  const barColor     = (p: number) => p >= 100 ? 'green' : p >= 50 ? 'yellow' : 'red';

  const daily = summary?.daily ?? [];

  return (
    <Stack>
      <Group justify="space-between">
        <Group gap="xs">
          <ActionIcon variant="default" onClick={() => setWeekOffset(o => o - 1)}>‹</ActionIcon>
          <Text fw={500} size="sm">{dayjs(ws).format('D MMM')} – {dayjs(we).format('D MMM YYYY')}</Text>
          <ActionIcon variant="default" onClick={() => setWeekOffset(o => o + 1)}>›</ActionIcon>
          {weekOffset !== 0 && (
            <Button size="xs" variant="light" onClick={() => setWeekOffset(0)}>This week</Button>
          )}
        </Group>
        {can('served.settings') && (
          <Button size="sm" leftSection={<IconTarget size={16} />} onClick={open}>
            {target ? 'Edit Target' : 'Set Target'}
          </Button>
        )}
      </Group>

      {isLoading ? <Center py="xl"><Loader /></Center> : !target ? (
        <Center py="xl">
          <Stack align="center" gap="xs">
            <Text c="dimmed">No target set yet.</Text>
            {can('served.settings') && (
              <Button size="xs" variant="light" onClick={open}>Set Target</Button>
            )}
          </Stack>
        </Center>
      ) : (
        <Stack gap="md">
          {/* Progress bars */}
          <Paper withBorder p="md" radius="md">
            <Stack gap="sm">
              <Group justify="space-between">
                <Group gap="xs">
                  <ThemeIcon size="sm" variant="light" color="teal"><IconUserPlus size={14} /></ThemeIcon>
                  <Text fw={500} size="sm">New Customers</Text>
                  <Text size="xs" c="dimmed">({target.new_customers_target}/day)</Text>
                </Group>
                <Badge size="lg" color={barColor(newPct)} variant="light">
                  {newDone} / {newTarget}
                </Badge>
              </Group>
              <Progress value={newPct} color={barColor(newPct)} size="sm" />

              <Group justify="space-between" mt="xs">
                <Group gap="xs">
                  <ThemeIcon size="sm" variant="light" color="blue"><IconMessageCircle size={14} /></ThemeIcon>
                  <Text fw={500} size="sm">Customers Called</Text>
                  <Text size="xs" c="dimmed">({target.called_customers_target}/day)</Text>
                </Group>
                <Badge size="lg" color={barColor(calledPct)} variant="light">
                  {calledDone} / {calledTarget}
                </Badge>
              </Group>
              <Progress value={calledPct} color={barColor(calledPct)} size="sm" />
            </Stack>
          </Paper>

          {/* Daily breakdown */}
          {daily.length > 0 && (
            <SimpleGrid cols={7} spacing="xs">
              {daily.map(day => (
                <Stack key={day.date} gap={2} align="center">
                  <Text size="xs" c="dimmed" fw={500}>{day.day_name}</Text>
                  <ThemeIcon size="sm"
                    variant={!day.is_active ? 'subtle' : day.new_customers > 0 || day.calls_made > 0 ? 'filled' : 'light'}
                    color={!day.is_active ? 'gray' : day.new_customers > 0 ? 'teal' : 'red'}>
                    {!day.is_active ? <IconCheck size={10} color="gray" /> : day.new_customers > 0 ? <IconCheck size={10} /> : <Text fz={9}>0</Text>}
                  </ThemeIcon>
                  {day.is_active && (
                    <Stack gap={0} align="center">
                      <Text fz={9} c="teal">{day.new_customers}👤</Text>
                      <Text fz={9} c="blue">{day.calls_made}📞</Text>
                    </Stack>
                  )}
                </Stack>
              ))}
            </SimpleGrid>
          )}
        </Stack>
      )}

      <ServedTargetFormModal opened={modal} onClose={close} existing={target} />
    </Stack>
  );
}

function ServedTargetFormModal({ opened, onClose, existing }: {
  opened: boolean; onClose: () => void; existing: ServedTarget | null;
}) {
  const qc = useQueryClient();

  const form = useForm({
    initialValues: {
      new_customers_target:    existing?.new_customers_target    ?? 10,
      called_customers_target: existing?.called_customers_target ?? 5,
      active_days:             existing?.active_days             ?? [1, 2, 3, 4, 5],
      effective_from:          existing?.effective_from ? new Date(existing.effective_from) : new Date() as Date | null,
    },
    validate: {
      active_days: v => v.length === 0 ? 'Select at least one day' : null,
    },
  });

  useEffect(() => {
    if (existing) {
      form.setValues({
        new_customers_target:    existing.new_customers_target,
        called_customers_target: existing.called_customers_target,
        active_days:             existing.active_days,
        effective_from:          new Date(existing.effective_from),
      });
    } else {
      form.reset();
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [existing?.id]);

  const mutation = useMutation({
    mutationFn: upsertServedTarget,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['served-target'] });
      qc.invalidateQueries({ queryKey: ['served-weekly-summary'] });
      notifications.show({ message: 'Target saved.', color: 'green' });
      onClose();
    },
  });

  const toggleDay = (day: number) => {
    const curr = form.values.active_days;
    form.setFieldValue('active_days',
      curr.includes(day) ? curr.filter(d => d !== day) : [...curr, day].sort()
    );
  };

  return (
    <Modal opened={opened} onClose={onClose}
      title={existing ? 'Edit Target' : 'Set Target'}
      centered size="sm">
      <form onSubmit={form.onSubmit(v => mutation.mutate({
        new_customers_target:    v.new_customers_target,
        called_customers_target: v.called_customers_target,
        active_days:             v.active_days,
        effective_from:          dayjs(v.effective_from!).format('YYYY-MM-DD'),
      }))}>
        <Stack gap="md">
          <Group grow>
            <NumberInput
              label="New customers / day"
              leftSection={<IconUserPlus size={14} />}
              min={1} max={999}
              {...form.getInputProps('new_customers_target')}
            />
            <NumberInput
              label="Calls / day"
              leftSection={<IconMessageCircle size={14} />}
              min={1} max={999}
              {...form.getInputProps('called_customers_target')}
            />
          </Group>

          <div>
            <Text size="sm" fw={500} mb={6}>Active days</Text>
            <Group gap="xs">
              {[1, 2, 3, 4, 5, 6, 7].map(day => (
                <Checkbox
                  key={day}
                  label={DAY_NAMES[day]}
                  checked={form.values.active_days.includes(day)}
                  onChange={() => toggleDay(day)}
                />
              ))}
            </Group>
            {form.errors.active_days && (
              <Text size="xs" c="red" mt={4}>{form.errors.active_days}</Text>
            )}
          </div>

          <DatePickerInput label="Effective from" required
            {...form.getInputProps('effective_from')} />

          <Group justify="flex-end">
            <Button variant="default" onClick={onClose}>Cancel</Button>
            <Button type="submit" loading={mutation.isPending}>Save Target</Button>
          </Group>
        </Stack>
      </form>
    </Modal>
  );
}

// ── Report Tab ───────────────────────────────────────────────────────────────

function ReportTab({ can: _can }: { can: (p: string) => boolean }) {
  const [month, setMonth] = useState<Date | null>(new Date());

  const startDate = month ? dayjs(month).startOf('month').format('YYYY-MM-DD') : '';
  const endDate   = month ? dayjs(month).endOf('month').format('YYYY-MM-DD')   : '';

  const { data, isLoading } = useQuery({
    queryKey: ['served-report', startDate, endDate],
    queryFn:  () => getServedReport(startDate, endDate),
    enabled:  !!month,
  });

  const report: ServedReport | null = (data as any)?.data ?? null;

  const pctColor = (pct: number | null) =>
    pct === null ? 'gray' : pct >= 100 ? 'green' : pct >= 50 ? 'yellow' : 'red';

  const weeks = (report?.daily ?? []).reduce<Record<number, ServedReportDay[]>>((acc, d) => {
    (acc[d.week] ??= []).push(d);
    return acc;
  }, {});

  const totalNewPct  = report && report.new_customers_target > 0
    ? Math.round(report.new_customers_achieved / report.new_customers_target * 100)
    : null;
  const totalCallPct = report && report.calls_target > 0
    ? Math.round(report.calls_achieved / report.calls_target * 100)
    : null;

  return (
    <Stack>
      <Group>
        <MonthPickerInput
          placeholder="Pick month"
          value={month}
          onChange={v => setMonth(v ? new Date(v as any) : null)}
          leftSection={<IconCalendar size={14} />}
          style={{ width: 180 }}
        />
      </Group>

      {isLoading ? (
        <Center py="xl"><Loader /></Center>
      ) : !report ? null : (
        <Stack gap="md">
          {/* Summary cards */}
          <SimpleGrid cols={{ base: 2, sm: 4 }} spacing="sm">
            {([
              { label: 'New Customers', done: report.new_customers_achieved, target: report.new_customers_target, pct: totalNewPct },
              { label: 'Customers Called', done: report.calls_achieved, target: report.calls_target, pct: totalCallPct },
            ] as const).map(s => (
              <Paper key={s.label} withBorder p="md" radius="md">
                <Text size="xs" c="dimmed" tt="uppercase" fw={600}>{s.label}</Text>
                <Text size="xl" fw={700}>{s.done}</Text>
                <Text size="xs" c="dimmed">Target: {s.target}</Text>
                {s.pct !== null && (
                  <Badge mt={4} size="sm" color={pctColor(s.pct)}>{s.pct}%</Badge>
                )}
              </Paper>
            ))}
          </SimpleGrid>

          {/* Daily table grouped by ISO week */}
          <Table striped highlightOnHover withTableBorder withColumnBorders fz="xs">
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Date</Table.Th>
                <Table.Th>Day</Table.Th>
                <Table.Th ta="center">New</Table.Th>
                <Table.Th ta="center">Target</Table.Th>
                <Table.Th ta="center">%</Table.Th>
                <Table.Th ta="center">Calls</Table.Th>
                <Table.Th ta="center">Target</Table.Th>
                <Table.Th ta="center">%</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {Object.entries(weeks).map(([weekKey, days]) => {
                const wNew  = days.reduce((s, d) => s + d.new_customers, 0);
                const wNT   = days.reduce((s, d) => s + d.new_target, 0);
                const wCall = days.reduce((s, d) => s + d.calls_made, 0);
                const wCT   = days.reduce((s, d) => s + d.calls_target, 0);
                const wNPct = wNT  > 0 ? Math.round(wNew  / wNT  * 100) : null;
                const wCPct = wCT  > 0 ? Math.round(wCall / wCT  * 100) : null;
                return (
                  <Fragment key={weekKey}>
                    {days.map(d => (
                      <Table.Tr key={d.date}
                        bg={!d.is_active ? 'var(--mantine-color-gray-1)' : undefined}
                        style={{ opacity: d.is_active ? 1 : 0.6 }}>
                        <Table.Td>{dayjs(d.date).format('D MMM')}</Table.Td>
                        <Table.Td c="dimmed">{d.day_name}</Table.Td>
                        <Table.Td ta="center">{d.is_active ? d.new_customers  : '–'}</Table.Td>
                        <Table.Td ta="center" c="dimmed">{d.is_active ? d.new_target    : '–'}</Table.Td>
                        <Table.Td ta="center">
                          {d.new_pct !== null
                            ? <Badge size="xs" color={pctColor(d.new_pct)}>{d.new_pct}%</Badge>
                            : '–'}
                        </Table.Td>
                        <Table.Td ta="center">{d.is_active ? d.calls_made    : '–'}</Table.Td>
                        <Table.Td ta="center" c="dimmed">{d.is_active ? d.calls_target  : '–'}</Table.Td>
                        <Table.Td ta="center">
                          {d.calls_pct !== null
                            ? <Badge size="xs" color={pctColor(d.calls_pct)}>{d.calls_pct}%</Badge>
                            : '–'}
                        </Table.Td>
                      </Table.Tr>
                    ))}
                    {/* Weekly subtotal */}
                    <Table.Tr fw={700} bg="var(--mantine-color-blue-0)">
                      <Table.Td colSpan={2} c="blue">Week {weekKey} total</Table.Td>
                      <Table.Td ta="center">{wNew}</Table.Td>
                      <Table.Td ta="center" c="dimmed">{wNT}</Table.Td>
                      <Table.Td ta="center">
                        {wNPct !== null ? <Badge size="xs" color={pctColor(wNPct)}>{wNPct}%</Badge> : '–'}
                      </Table.Td>
                      <Table.Td ta="center">{wCall}</Table.Td>
                      <Table.Td ta="center" c="dimmed">{wCT}</Table.Td>
                      <Table.Td ta="center">
                        {wCPct !== null ? <Badge size="xs" color={pctColor(wCPct)}>{wCPct}%</Badge> : '–'}
                      </Table.Td>
                    </Table.Tr>
                  </Fragment>
                );
              })}
            </Table.Tbody>
          </Table>
        </Stack>
      )}
    </Stack>
  );
}

// ── Services Tab ─────────────────────────────────────────────────────────────

function ServicesTab({ can }: { can: (p: string) => boolean }) {
  const qc = useQueryClient();
  const [editing, setEditing]    = useState<ServedService | null>(null);
  const [modal, { open, close }] = useDisclosure(false);

  const { data, isLoading } = useQuery({ queryKey: ['served-services'], queryFn: getServices });
  const services: ServedService[] = data?.data?.data ?? [];

  const toggleActive = useMutation({
    mutationFn: ({ id, is_active }: { id: string; is_active: boolean }) =>
      updateService(id, { is_active }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['served-services'] }),
  });

  const deleteMutation = useMutation({
    mutationFn: deleteService,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['served-services'] });
      notifications.show({ message: 'Service deleted.', color: 'green' });
    },
  });

  return (
    <Stack>
      <Group justify="space-between">
        <Text fw={600}>Services</Text>
        {can('served.settings') && (
          <Button size="sm" leftSection={<IconPlus size={16} />}
            onClick={() => { setEditing(null); open(); }}>
            Add Service
          </Button>
        )}
      </Group>

      {isLoading ? <Center py="xl"><Loader /></Center> : services.length === 0 ? (
        <Center py="xl"><Text c="dimmed">No services yet. Add one to get started.</Text></Center>
      ) : (
        <SimpleGrid cols={{ base: 1, sm: 2, md: 3 }} spacing="xs">
          {services.map(s => (
            <Paper key={s.id} withBorder p="sm" radius="md">
              <Group justify="space-between" wrap="nowrap">
                <div style={{ minWidth: 0 }}>
                  <Group gap="xs">
                    <Text size="sm" fw={600} lineClamp={1}>{s.name}</Text>
                    {!s.is_active && <Badge size="xs" color="gray">Inactive</Badge>}
                  </Group>
                  {s.description && (
                    <Text size="xs" c="dimmed" lineClamp={1}>{s.description}</Text>
                  )}
                </div>
                {can('served.settings') && (
                  <Group gap="xs" wrap="nowrap">
                    <Switch
                      size="xs" checked={s.is_active}
                      onChange={e => toggleActive.mutate({ id: s.id, is_active: e.currentTarget.checked })}
                    />
                    <ActionIcon size="sm" variant="subtle"
                      onClick={() => { setEditing(s); open(); }}>
                      <IconEdit size={14} />
                    </ActionIcon>
                    <ActionIcon size="sm" variant="subtle" color="red"
                      onClick={() => deleteMutation.mutate(s.id)}>
                      <IconTrash size={14} />
                    </ActionIcon>
                  </Group>
                )}
              </Group>
            </Paper>
          ))}
        </SimpleGrid>
      )}

      <ServiceFormModal opened={modal} onClose={close} existing={editing} />
    </Stack>
  );
}

function ServiceFormModal({ opened, onClose, existing }: {
  opened: boolean; onClose: () => void; existing: ServedService | null;
}) {
  const qc = useQueryClient();

  const form = useForm({
    initialValues: {
      name:        existing?.name        ?? '',
      description: existing?.description ?? '',
      sort_order:  existing?.sort_order  ?? 99,
      is_active:   existing?.is_active   ?? true,
    },
    validate: { name: v => !v.trim() ? 'Name is required' : null },
  });

  useEffect(() => {
    if (existing) {
      form.setValues({
        name:        existing.name,
        description: existing.description ?? '',
        sort_order:  existing.sort_order,
        is_active:   existing.is_active,
      });
    } else {
      form.reset();
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [existing?.id]);

  const mutation = useMutation({
    mutationFn: (v: ReturnType<typeof form.getValues>) => {
      const payload = {
        name:        v.name,
        description: v.description || undefined,
        sort_order:  v.sort_order,
        is_active:   v.is_active,
      };
      return existing
        ? updateService(existing.id, payload)
        : createService(payload);
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['served-services'] });
      notifications.show({ message: existing ? 'Service updated.' : 'Service added.', color: 'green' });
      form.reset();
      onClose();
    },
  });

  return (
    <Modal opened={opened} onClose={onClose}
      title={existing ? 'Edit Service' : 'Add Service'}
      centered size="xs">
      <form onSubmit={form.onSubmit(v => mutation.mutate(v))}>
        <Stack gap="sm">
          <TextInput label="Service name" required placeholder="Consultation"
            {...form.getInputProps('name')} />
          <TextInput label="Description" placeholder="Optional description"
            {...form.getInputProps('description')} />
          <Group grow>
            <NumberInput label="Sort order" min={0} max={99}
              {...form.getInputProps('sort_order')} />
            <Switch label="Active" mt="lg"
              checked={form.values.is_active}
              onChange={e => form.setFieldValue('is_active', e.currentTarget.checked)} />
          </Group>
          <Group justify="flex-end" mt="xs">
            <Button variant="default" onClick={onClose}>Cancel</Button>
            <Button type="submit" loading={mutation.isPending}>
              {existing ? 'Update' : 'Add'}
            </Button>
          </Group>
        </Stack>
      </form>
    </Modal>
  );
}
