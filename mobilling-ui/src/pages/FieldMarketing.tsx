import { useState, useEffect } from 'react';
import { useSearchParams } from 'react-router-dom';
import {
  Title, Stack, Group, Button, Badge, Table, Text, ActionIcon,
  Tabs, SimpleGrid, Card, ThemeIcon, Progress, Modal, Select,
  Box, LoadingOverlay, Tooltip,
} from '@mantine/core';
import { MonthPickerInput, DatePickerInput } from '@mantine/dates';
import {
  IconPlus, IconEdit, IconTrash, IconMapPin, IconUsers,
  IconTarget, IconChartBar, IconEye, IconList, IconTools,
} from '@tabler/icons-react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { usePermissions } from '../hooks/usePermissions';
import { notifications } from '@mantine/notifications';
import {
  getSessions, deleteSession, createSession, updateSession,
  getTargets, setTarget, getFieldStats, getAllVisits,
  VISIT_STATUSES, type FieldSession, type FieldTarget, type FieldVisitReport,
} from '../api/fieldMarketing';
import { getUsers } from '../api/users';
import SessionForm from '../components/FieldMarketing/SessionForm';
import SessionDetailDrawer from '../components/FieldMarketing/SessionDetailDrawer';
import TargetForm from '../components/FieldMarketing/TargetForm';
import ServicesManager from '../components/FieldMarketing/ServicesManager';


export default function FieldMarketing() {
  const { can } = usePermissions();
  const qc = useQueryClient();

  const [searchParams] = useSearchParams();
  const [tab, setTab] = useState<string | null>(searchParams.get('tab') ?? 'sessions');

  useEffect(() => {
    const t = searchParams.get('tab');
    if (t) setTab(t);
  }, [searchParams]);

  // Month/year picker — null means all months
  const [selectedMonth, setSelectedMonth] = useState<Date | null>(new Date());
  const safeDate = selectedMonth instanceof Date && !isNaN(selectedMonth.getTime())
    ? selectedMonth : null;
  const month = safeDate ? safeDate.getMonth() + 1 : new Date().getMonth() + 1;
  const year  = safeDate ? safeDate.getFullYear()  : new Date().getFullYear();
  const hasMonthFilter = safeDate !== null;

  // Sessions filters
  const [filterOfficer, setFilterOfficer] = useState('');

  // Visits report filters
  const [visitDateFrom, setVisitDateFrom] = useState<Date | null>(null);
  const [visitDateTo,   setVisitDateTo]   = useState<Date | null>(null);
  const [visitOfficer,  setVisitOfficer]  = useState('');
  const [visitStatus,   setVisitStatus]   = useState('');

  const toDateStr = (d: Date | null) => d ? d.toISOString().slice(0, 10) : undefined;

  // Modal/drawer state
  const [sessionModal, setSessionModal] = useState(false);
  const [editSession, setEditSession]   = useState<FieldSession | null>(null);
  const [detailSession, setDetailSession] = useState<FieldSession | null>(null);
  const [targetModal, setTargetModal]   = useState(false);

  // ── Data queries ─────────────────────────────────────────────────────────

  const { data: usersData } = useQuery({ queryKey: ['users'], queryFn: () => getUsers({ per_page: 100 }) });
  const users: { id: string; name: string }[] = usersData?.data?.data ?? [];

  const { data: sessions = [], isFetching: loadingSessions } = useQuery({
    queryKey: ['field-sessions', { month, year, officer: filterOfficer }],
    queryFn: () => getSessions({ month: hasMonthFilter ? month : undefined, year: hasMonthFilter ? year : undefined, officer_id: filterOfficer || undefined }),
    enabled: can('field_sessions.read'),
  });

  const { data: targets = [], isFetching: loadingTargets } = useQuery({
    queryKey: ['field-targets', month, year],
    queryFn:  () => getTargets(month, year),
    enabled:  can('field_targets.read') && tab === 'targets',
  });

  const { data: stats, isFetching: loadingStats } = useQuery({
    queryKey: ['field-stats', month, year],
    queryFn:  () => getFieldStats(month, year),
    enabled:  can('field_sessions.read') && tab === 'stats',
  });

  const { data: allVisits = [], isFetching: loadingVisits } = useQuery({
    queryKey: ['field-visits-report', { visitDateFrom, visitDateTo, visitOfficer, visitStatus }],
    queryFn:  () => getAllVisits({
      date_from:  toDateStr(visitDateFrom),
      date_to:    toDateStr(visitDateTo),
      officer_id: visitOfficer || undefined,
      status:     visitStatus  || undefined,
    }),
    enabled:  can('field_sessions.read') && tab === 'visits',
  });

  // ── Mutations ─────────────────────────────────────────────────────────────

  const invalidateSessions = () => qc.invalidateQueries({ queryKey: ['field-sessions'] });
  const invalidateTargets  = () => qc.invalidateQueries({ queryKey: ['field-targets'] });

  const createMutation = useMutation({
    mutationFn: createSession,
    onSuccess: () => { setSessionModal(false); invalidateSessions(); notifications.show({ message: 'Session created', color: 'green' }); },
    onError:   () => notifications.show({ message: 'Failed to create session', color: 'red' }),
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, data }: { id: string; data: Parameters<typeof updateSession>[1] }) => updateSession(id, data),
    onSuccess: () => { setEditSession(null); invalidateSessions(); notifications.show({ message: 'Session updated', color: 'green' }); },
    onError:   () => notifications.show({ message: 'Failed to update session', color: 'red' }),
  });

  const deleteMutation = useMutation({
    mutationFn: deleteSession,
    onSuccess: () => { invalidateSessions(); notifications.show({ message: 'Session deleted', color: 'orange' }); },
    onError:   () => notifications.show({ message: 'Failed to delete session', color: 'red' }),
  });

  const targetMutation = useMutation({
    mutationFn: setTarget,
    onSuccess: () => { setTargetModal(false); invalidateTargets(); notifications.show({ message: 'Target set', color: 'green' }); },
    onError:   () => notifications.show({ message: 'Failed to set target', color: 'red' }),
  });

  const officerOptions = [
    { value: '', label: 'All Officers' },
    ...users.map(u => ({ value: u.id, label: u.name })),
  ];

  const periodLabel = safeDate ? safeDate.toLocaleString('default', { month: 'short', year: 'numeric' }) : 'All Months';

  return (
    <Stack>
      <Group justify="space-between">
        <Title order={2}>Field Marketing</Title>
        <Group>
          <MonthPickerInput
            value={selectedMonth}
            onChange={(val) => {
              if (!val) { setSelectedMonth(null); return; }
              // Mantine v8 passes DateValue — cast via unknown
              const d = new Date(val as any) as Date;
              if (!isNaN(d.getTime())) setSelectedMonth(d);
            }}
            placeholder="All months"
            maxDate={new Date()}
            maxLevel="decade"
            clearable
            w={160}
            size="sm"
          />
          {tab === 'sessions' && can('field_sessions.create') && (
            <Button leftSection={<IconPlus size={16} />} onClick={() => setSessionModal(true)}>
              New Session
            </Button>
          )}
          {tab === 'targets' && can('field_targets.update') && (
            <Button leftSection={<IconTarget size={16} />} onClick={() => setTargetModal(true)}>
              Set Target
            </Button>
          )}
        </Group>
      </Group>

      <Tabs value={tab} onChange={setTab}>
        <Tabs.List>
          {can('field_sessions.read') && (
            <Tabs.Tab value="sessions" leftSection={<IconMapPin size={14} />}>Sessions</Tabs.Tab>
          )}
          {can('field_targets.read') && (
            <Tabs.Tab value="targets" leftSection={<IconTarget size={14} />}>Targets</Tabs.Tab>
          )}
          {can('field_sessions.read') && (
            <Tabs.Tab value="stats" leftSection={<IconChartBar size={14} />}>Stats</Tabs.Tab>
          )}
          {can('field_sessions.read') && (
            <Tabs.Tab value="visits" leftSection={<IconList size={14} />}>All Visits</Tabs.Tab>
          )}
          {can('marketing_services.read') && (
            <Tabs.Tab value="services" leftSection={<IconTools size={14} />}>Services</Tabs.Tab>
          )}
        </Tabs.List>

        {/* ── Sessions tab ────────────────────────────────────────────── */}
        <Tabs.Panel value="sessions" pt="md">
          <Stack>
            <Group>
              <Select
                data={officerOptions}
                value={filterOfficer}
                onChange={v => setFilterOfficer(v ?? '')}
                placeholder="Filter by officer"
                w={200}
                size="sm"
                clearable
              />
            </Group>

            <Box pos="relative">
              <LoadingOverlay visible={loadingSessions} />
              <Table striped highlightOnHover withTableBorder>
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th w={40}>#</Table.Th>
                    <Table.Th>Date</Table.Th>
                    <Table.Th>Officer</Table.Th>
                    <Table.Th>Area</Table.Th>
                    <Table.Th>Visits</Table.Th>
                    <Table.Th>Interested</Table.Th>
                    <Table.Th>Converted</Table.Th>
                    <Table.Th />
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {(sessions as FieldSession[]).map((s, idx) => (
                    <Table.Tr key={s.id}>
                      <Table.Td><Text size="sm" c="dimmed">{idx + 1}</Text></Table.Td>
                      <Table.Td>{s.visit_date}</Table.Td>
                      <Table.Td>{s.officer?.name}</Table.Td>
                      <Table.Td>{s.area}</Table.Td>
                      <Table.Td>{s.visits_count}</Table.Td>
                      <Table.Td>
                        <Badge color="blue" variant="light">{s.interested_count}</Badge>
                      </Table.Td>
                      <Table.Td>
                        <Badge color="green" variant="light">{s.converted_count}</Badge>
                      </Table.Td>
                      <Table.Td>
                        <Group gap={4} justify="flex-end">
                          <ActionIcon size="sm" variant="subtle" color="blue" title="View visits"
                            onClick={() => setDetailSession(s)}>
                            <IconEye size={14} />
                          </ActionIcon>
                          {can('field_sessions.update') && (
                            <ActionIcon size="sm" variant="subtle" color="gray" title="Edit"
                              onClick={() => setEditSession(s)}>
                              <IconEdit size={14} />
                            </ActionIcon>
                          )}
                          {can('field_sessions.delete') && (
                            <ActionIcon size="sm" variant="subtle" color="red" title="Delete"
                              loading={deleteMutation.isPending}
                              onClick={() => { if (confirm('Delete this session and all its visits?')) deleteMutation.mutate(s.id); }}>
                              <IconTrash size={14} />
                            </ActionIcon>
                          )}
                        </Group>
                      </Table.Td>
                    </Table.Tr>
                  ))}
                </Table.Tbody>
              </Table>
              {sessions.length === 0 && !loadingSessions && (
                <Text c="dimmed" ta="center" py="xl">No sessions for {periodLabel}</Text>
              )}
            </Box>
          </Stack>
        </Tabs.Panel>

        {/* ── Targets tab ─────────────────────────────────────────────── */}
        <Tabs.Panel value="targets" pt="md">
          <Box pos="relative" mih={100}>
            <LoadingOverlay visible={loadingTargets} />
            <SimpleGrid cols={{ base: 1, sm: 2, md: 3 }}>
              {(targets as FieldTarget[]).map(t => (
                <Card key={t.id} withBorder>
                  <Group justify="space-between" mb="xs">
                    <Text fw={600}>{t.officer?.name}</Text>
                    <ThemeIcon color={t.progress >= 100 ? 'green' : t.progress >= 50 ? 'yellow' : 'red'} variant="light" size="sm">
                      <IconUsers size={14} />
                    </ThemeIcon>
                  </Group>
                  <Text size="sm" c="dimmed" mb={4}>{periodLabel}</Text>
                  <Group justify="space-between" mb={4}>
                    <Text size="sm">Won: <Text span fw={600} c="green">{t.won_clients}</Text> / {t.target_clients}</Text>
                    <Text size="sm" c="dimmed">{t.total_visits} visits</Text>
                  </Group>
                  <Progress value={t.progress} color={t.progress >= 100 ? 'green' : t.progress >= 50 ? 'yellow' : 'red'} size="sm" />
                  <Text size="xs" c="dimmed" mt={4} ta="right">{t.progress}%</Text>
                </Card>
              ))}
            </SimpleGrid>
            {targets.length === 0 && !loadingTargets && (
              <Text c="dimmed" ta="center" py="xl">No targets set for {periodLabel}</Text>
            )}
          </Box>
        </Tabs.Panel>

        {/* ── Stats tab ────────────────────────────────────────────────── */}
        <Tabs.Panel value="stats" pt="md">
          <Box pos="relative" mih={100}>
            <LoadingOverlay visible={loadingStats} />
            {stats && (
              <Stack>
                <SimpleGrid cols={{ base: 2, sm: 4 }}>
                  <Card withBorder ta="center">
                    <Text size="xl" fw={700}>{stats.total_visits}</Text>
                    <Text size="sm" c="dimmed">Total Visits</Text>
                  </Card>
                  <Card withBorder ta="center">
                    <Text size="xl" fw={700} c="green">{stats.total_converted}</Text>
                    <Text size="sm" c="dimmed">Converted</Text>
                  </Card>
                  {VISIT_STATUSES.map(s => (
                    <Card key={s.value} withBorder ta="center">
                      <Text size="xl" fw={700} c={s.color}>{stats.by_status[s.value] ?? 0}</Text>
                      <Text size="sm" c="dimmed">{s.label}</Text>
                    </Card>
                  ))}
                </SimpleGrid>

                <Text fw={600} mt="md">By Officer</Text>
                <Table withTableBorder striped>
                  <Table.Thead>
                    <Table.Tr>
                      <Table.Th w={40}>#</Table.Th>
                      <Table.Th>Officer</Table.Th>
                      <Table.Th>Visits</Table.Th>
                      <Table.Th>Clients Won</Table.Th>
                      <Table.Th>Conversion Rate</Table.Th>
                    </Table.Tr>
                  </Table.Thead>
                  <Table.Tbody>
                    {stats.by_officer.map((r, idx) => (
                      <Table.Tr key={r.officer_id}>
                        <Table.Td><Text size="sm" c="dimmed">{idx + 1}</Text></Table.Td>
                        <Table.Td>{r.officer?.name ?? r.officer_id}</Table.Td>
                        <Table.Td>{r.visits}</Table.Td>
                        <Table.Td><Badge color="green">{r.won}</Badge></Table.Td>
                        <Table.Td>
                          {r.visits > 0 ? `${Math.round((r.won / r.visits) * 100)}%` : '—'}
                        </Table.Td>
                      </Table.Tr>
                    ))}
                  </Table.Tbody>
                </Table>
              </Stack>
            )}
            {!stats && !loadingStats && (
              <Text c="dimmed" ta="center" py="xl">No data for {periodLabel}</Text>
            )}
          </Box>
        </Tabs.Panel>

        {/* ── All Visits tab ───────────────────────────────────────────── */}
        <Tabs.Panel value="visits" pt="md">
          <Stack>
            {/* Filters */}
            <Group wrap="wrap">
              <DatePickerInput
                placeholder="From date"
                value={visitDateFrom}
                onChange={v => setVisitDateFrom(v as Date | null)}
                clearable
                size="sm"
                w={150}
              />
              <DatePickerInput
                placeholder="To date"
                value={visitDateTo}
                onChange={v => setVisitDateTo(v as Date | null)}
                clearable
                size="sm"
                w={150}
              />
              <Select
                data={officerOptions}
                value={visitOfficer}
                onChange={v => setVisitOfficer(v ?? '')}
                placeholder="All Officers"
                size="sm"
                w={180}
                clearable
              />
              <Select
                data={[
                  { value: '', label: 'All Statuses' },
                  ...VISIT_STATUSES.map(s => ({ value: s.value, label: s.label })),
                ]}
                value={visitStatus}
                onChange={v => setVisitStatus(v ?? '')}
                placeholder="All Statuses"
                size="sm"
                w={160}
                clearable
              />
              <Text size="sm" c="dimmed">{allVisits.length} visits</Text>
            </Group>

            <Box pos="relative">
              <LoadingOverlay visible={loadingVisits} />
              <Table striped highlightOnHover withTableBorder>
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th w={40}>#</Table.Th>
                    <Table.Th>Date</Table.Th>
                    <Table.Th>Officer</Table.Th>
                    <Table.Th>Area</Table.Th>
                    <Table.Th>Business</Table.Th>
                    <Table.Th>Location</Table.Th>
                    <Table.Th>Phone</Table.Th>
                    <Table.Th>Services</Table.Th>
                    <Table.Th>Status</Table.Th>
                    <Table.Th>Next Follow-up</Table.Th>
                    <Table.Th>Client</Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {(allVisits as FieldVisitReport[]).map((v, idx) => {
                    const statusMeta = VISIT_STATUSES.find(s => s.value === v.status);
                    return (
                      <Table.Tr key={v.id}>
                        <Table.Td><Text size="sm" c="dimmed">{idx + 1}</Text></Table.Td>
                        <Table.Td><Text size="sm">{v.visit_date}</Text></Table.Td>
                        <Table.Td><Text size="sm">{v.officer?.name}</Text></Table.Td>
                        <Table.Td><Text size="sm" c="dimmed">{v.area}</Text></Table.Td>
                        <Table.Td><Text size="sm" fw={500}>{v.business_name}</Text></Table.Td>
                        <Table.Td><Text size="sm">{v.location}</Text></Table.Td>
                        <Table.Td><Text size="sm">{v.phone ?? '—'}</Text></Table.Td>
                        <Table.Td>
                          <Group gap={4} wrap="wrap">
                            {v.services.map(s => (
                              <Tooltip key={s} label={s} withArrow>
                                <Badge size="xs" variant="outline">{s.length > 8 ? s.slice(0, 8) + '…' : s}</Badge>
                              </Tooltip>
                            ))}
                          </Group>
                        </Table.Td>
                        <Table.Td>
                          <Badge size="sm" color={statusMeta?.color ?? 'gray'} variant="light">
                            {statusMeta?.label ?? v.status}
                          </Badge>
                        </Table.Td>
                        <Table.Td>
                          <Text size="sm" c={v.next_followup_date && new Date(v.next_followup_date) < new Date() ? 'red' : 'dimmed'}>
                            {v.next_followup_date ?? '—'}
                          </Text>
                        </Table.Td>
                        <Table.Td>
                          {v.client
                            ? <Text size="sm" c="green">{v.client.name}</Text>
                            : <Text size="sm" c="dimmed">—</Text>}
                        </Table.Td>
                      </Table.Tr>
                    );
                  })}
                </Table.Tbody>
              </Table>
              {allVisits.length === 0 && !loadingVisits && (
                <Text c="dimmed" ta="center" py="xl">No visits found for selected filters</Text>
              )}
            </Box>
          </Stack>
        </Tabs.Panel>

        {/* ── Services tab ─────────────────────────────────────────────── */}
        <Tabs.Panel value="services" pt="md">
          <ServicesManager />
        </Tabs.Panel>
      </Tabs>

      {/* ── Session create modal ──────────────────────────────────────── */}
      <Modal opened={sessionModal} onClose={() => setSessionModal(false)} title="New Field Session" size="lg" centered>
        <SessionForm
          onSubmit={v => createMutation.mutate(v)}
          loading={createMutation.isPending}
        />
      </Modal>

      {/* ── Session edit modal ────────────────────────────────────────── */}
      <Modal opened={!!editSession} onClose={() => setEditSession(null)} title="Edit Session" size="lg" centered>
        {editSession && (
          <SessionForm
            session={editSession}
            onSubmit={v => updateMutation.mutate({ id: editSession.id, data: v })}
            loading={updateMutation.isPending}
          />
        )}
      </Modal>

      {/* ── Session detail drawer ─────────────────────────────────────── */}
      <SessionDetailDrawer
        session={detailSession}
        onClose={() => setDetailSession(null)}
      />

      {/* ── Set target modal ──────────────────────────────────────────── */}
      <Modal opened={targetModal} onClose={() => setTargetModal(false)} title={`Set Target — ${periodLabel}`} centered>
        <TargetForm
          month={month}
          year={year}
          onSubmit={v => targetMutation.mutate(v)}
          loading={targetMutation.isPending}
        />
      </Modal>
    </Stack>
  );
}
