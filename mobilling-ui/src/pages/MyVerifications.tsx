import { useState } from 'react';
import {
  Title, Card, Text, Group, Stack, Badge, Button, Modal, Textarea, NumberInput, Box, Alert, ThemeIcon, Radio, Divider, Loader, Center, CopyButton, ActionIcon, SimpleGrid,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  IconCheck, IconAlertTriangle, IconClock, IconShield, IconClipboardCheck, IconWorld, IconCopy, IconEye, IconEyeOff, IconLock, IconUser,
} from '@tabler/icons-react';
import { getMyVerifications, submitVerificationReport, SystemVerification } from '../api/systemVerifications';
import dayjs from 'dayjs';

export default function MyVerifications() {
  const queryClient = useQueryClient();
  const [submitting, setSubmitting] = useState<SystemVerification | null>(null);

  const { data, isLoading } = useQuery({
    queryKey: ['my-verifications'],
    queryFn: getMyVerifications,
  });
  const nowStr = dayjs().format('HH:mm:ss');
  // Each system can have its own window — not one rule for everyone.
  const withinWindow = (s: SystemVerification) => (s.window_from && s.window_to
    ? nowStr >= s.window_from && nowStr <= s.window_to
    : null);
  const [showPw, setShowPw] = useState<Record<string, boolean>>({});
  const systems: SystemVerification[] = data?.data?.data || [];
  const today = dayjs().format('dddd, DD MMM YYYY');
  const pendingCount = systems.filter((s) => !s.todays_report).length;
  const issueCount = systems.filter((s) => s.todays_report?.status === 'issue').length;

  const form = useForm({
    initialValues: {
      status: 'ok' as 'ok' | 'issue', notes: '',
      cash: '' as number | '', sales: '' as number | '', credit: '' as number | '', gain_loss: '' as number | '',
    },
    validate: {
      notes: (v, all) => (all.status === 'issue' && !v.trim() ? 'Eleza changamoto / Please describe the issue' : null),
      cash: (v) => (v === '' ? 'Required' : null),
      sales: (v) => (v === '' ? 'Required' : null),
      credit: (v) => (v === '' ? 'Required' : null),
      gain_loss: (v) => (v === '' ? 'Required' : null),
    },
  });

  const submitMutation = useMutation({
    mutationFn: ({ id, values }: { id: string; values: typeof form.values }) =>
      submitVerificationReport(id, {
        status: values.status,
        notes: values.notes || undefined,
        cash: Number(values.cash),
        sales: Number(values.sales),
        credit: Number(values.credit),
        gain_loss: Number(values.gain_loss),
      }),
    onSuccess: (_, vars) => {
      queryClient.invalidateQueries({ queryKey: ['my-verifications'] });
      const ok = vars.values.status === 'ok';
      notifications.show({
        title: ok ? 'Report submitted' : 'Issue reported',
        message: ok ? 'Asante kwa kuripoti.' : 'Admin amepokea taarifa. / Admin has been notified.',
        color: ok ? 'green' : 'orange',
      });
      setSubmitting(null);
      form.reset();
    },
    onError: (err: any) => notifications.show({
      title: 'Error',
      message: err.response?.data?.message || 'Failed to submit report',
      color: 'red',
    }),
  });

  const openSubmit = (s: SystemVerification) => {
    setSubmitting(s);
    form.setValues({ status: 'ok', notes: '', cash: '', sales: '', credit: '', gain_loss: '' });
  };

  if (isLoading) return <Center py="xl"><Loader /></Center>;

  return (
    <Stack>
      <Group justify="space-between" align="flex-end">
        <Box>
          <Title order={2}>My Verifications</Title>
          <Text size="sm" c="dimmed">{today}</Text>
        </Box>
        <Group gap="xs">
          {pendingCount > 0 && (
            <Badge color="yellow" size="lg" variant="light" leftSection={<IconClock size={12} />}>
              {pendingCount} pending today
            </Badge>
          )}
          {issueCount > 0 && (
            <Badge color="red" size="lg" variant="light" leftSection={<IconAlertTriangle size={12} />}>
              {issueCount} reported issue
            </Badge>
          )}
        </Group>
      </Group>

      {pendingCount > 0 && (
        <Alert color="yellow" icon={<IconClock size={16} />} title="Daily reports pending">
          Tafadhali kagua mifumo yako leo na uweke ripoti kabla ya saa mbili usiku.
        </Alert>
      )}



      {systems.length === 0 ? (
        <Card withBorder padding="xl">
          <Box ta="center">
            <ThemeIcon size="xl" variant="light" color="gray" radius="xl" mb="sm"><IconShield size={28} /></ThemeIcon>
            <Text c="dimmed">Hujapewa system yoyote ya kufuatilia bado.</Text>
            <Text size="xs" c="dimmed">Admin hajakupanga kufuatilia mfumo wowote.</Text>
          </Box>
        </Card>
      ) : (
        <Stack gap="md">
          {systems.map((s) => {
            const done = !!s.todays_report;
            const isIssue = done && s.todays_report!.status === 'issue';
            const accentColor = !done ? 'yellow' : isIssue ? 'red' : 'green';

            return (
              <Card key={s.id} withBorder padding="lg" radius="md"
                style={{ borderLeft: `4px solid var(--mantine-color-${accentColor}-6)` }}>
                <Group justify="space-between" align="flex-start" wrap="nowrap">
                  <Box style={{ minWidth: 0, flex: 1 }}>
                    <Group gap="xs" mb={4}>
                      <ThemeIcon size="md" variant="light" color={accentColor} radius="md">
                        {!done ? <IconClock size={16} /> : isIssue ? <IconAlertTriangle size={16} /> : <IconCheck size={16} />}
                      </ThemeIcon>
                      <Text fw={700}>{s.name}</Text>
                    </Group>
                    {s.domain_name && (
                      <Group gap={6} mb={2}>
                        <IconWorld size={12} color="var(--mantine-color-gray-6)" />
                        <Text size="xs" c="dimmed" ff="monospace">{s.domain_name}</Text>
                      </Group>
                    )}
                    {s.window_from && s.window_to && !done && (
                      <Text size="xs" c={withinWindow(s) === false ? 'orange' : 'dimmed'} mb={2}>
                        Muda wa ukaguzi: {s.window_from.slice(0, 5)} – {s.window_to.slice(0, 5)}
                        {withinWindow(s) === false && ' (nje ya muda sasa)'}
                      </Text>
                    )}
                    {s.client_id && (
                      <Text size="xs" c="dimmed">Client ID: <Text span ff="monospace">{s.client_id}</Text></Text>
                    )}
                    {(s.login_username || s.login_password) && (
                      <Group gap="md" mt={4}>
                        {s.login_username && (
                          <Group gap={4}>
                            <IconUser size={12} color="var(--mantine-color-gray-6)" />
                            <Text size="xs" ff="monospace">{s.login_username}</Text>
                            <CopyButton value={s.login_username}>
                              {({ copied, copy }) => (
                                <ActionIcon size="xs" variant="subtle" onClick={copy} title="Copy username">
                                  {copied ? <IconCheck size={12} /> : <IconCopy size={12} />}
                                </ActionIcon>
                              )}
                            </CopyButton>
                          </Group>
                        )}
                        {s.login_password && (
                          <Group gap={4}>
                            <IconLock size={12} color="var(--mantine-color-gray-6)" />
                            <Text size="xs" ff="monospace">{showPw[s.id] ? s.login_password : '••••••••'}</Text>
                            <ActionIcon size="xs" variant="subtle" onClick={() => setShowPw((p) => ({ ...p, [s.id]: !p[s.id] }))} title="Show/hide password">
                              {showPw[s.id] ? <IconEyeOff size={12} /> : <IconEye size={12} />}
                            </ActionIcon>
                            <CopyButton value={s.login_password}>
                              {({ copied, copy }) => (
                                <ActionIcon size="xs" variant="subtle" onClick={copy} title="Copy password">
                                  {copied ? <IconCheck size={12} /> : <IconCopy size={12} />}
                                </ActionIcon>
                              )}
                            </CopyButton>
                          </Group>
                        )}
                      </Group>
                    )}
                    {done && (
                      <Box mt="xs" p="xs" style={{ background: 'var(--mantine-color-gray-0)', borderRadius: 4 }}>
                        <Group gap="xs" mb={4}>
                          <Badge color={isIssue ? 'red' : 'green'} variant="light" size="sm">
                            {isIssue ? 'Issue Reported' : 'All OK'}
                          </Badge>
                          <Text size="xs" c="dimmed">
                            Reported at {dayjs(s.todays_report!.submitted_at).format('HH:mm')}
                          </Text>
                          {s.todays_report!.submitted_on_time === false && (
                            <Badge color="orange" variant="light" size="xs">Late</Badge>
                          )}
                        </Group>
                        <SimpleGrid cols={4} spacing="xs" mt={6}>
                          <Box><Text size="xs" c="dimmed">Cash</Text><Text size="sm" fw={600}>{s.todays_report!.cash ?? '—'}</Text></Box>
                          <Box><Text size="xs" c="dimmed">Sales</Text><Text size="sm" fw={600}>{s.todays_report!.sales ?? '—'}</Text></Box>
                          <Box><Text size="xs" c="dimmed">Credit</Text><Text size="sm" fw={600}>{s.todays_report!.credit ?? '—'}</Text></Box>
                          <Box><Text size="xs" c="dimmed">Gain/Loss</Text>
                            <Text size="sm" fw={600} c={s.todays_report!.gain_loss && Number(s.todays_report!.gain_loss) < 0 ? 'red' : undefined}>
                              {s.todays_report!.gain_loss ?? '—'}
                            </Text>
                          </Box>
                        </SimpleGrid>
                        {s.todays_report!.notes && (
                          <Text size="sm" mt={4} c={isIssue ? 'red.7' : undefined}>{s.todays_report!.notes}</Text>
                        )}
                      </Box>
                    )}
                  </Box>
                  <Box ta="right">
                    {!done ? (
                      <Button color="blue" leftSection={<IconClipboardCheck size={16} />}
                        onClick={() => openSubmit(s)}>
                        Submit today's report
                      </Button>
                    ) : (
                      <Badge color={isIssue ? 'red' : 'green'} variant="filled" size="lg">
                        Done
                      </Badge>
                    )}
                  </Box>
                </Group>
              </Card>
            );
          })}
        </Stack>
      )}

      {/* Submission modal */}
      <Modal opened={!!submitting} onClose={() => setSubmitting(null)}
        title={`Daily Verification — ${submitting?.name || ''}`} size="md">
        <form onSubmit={form.onSubmit((v) => { if (submitting) submitMutation.mutate({ id: submitting.id, values: v }); })}>
          <Stack>
            <Text size="sm" c="dimmed">
              Weka takwimu za kufungwa kwa mfumo leo (baada ya kukagua).
            </Text>
            <SimpleGrid cols={2} spacing="sm">
              <NumberInput label="Cash" placeholder="0" required min={0} decimalScale={2}
                {...form.getInputProps('cash')} />
              <NumberInput label="Sales" placeholder="0" required min={0} decimalScale={2}
                {...form.getInputProps('sales')} />
              <NumberInput label="Credit" placeholder="0" required min={0} decimalScale={2}
                {...form.getInputProps('credit')} />
              <NumberInput label="Gain / Loss" placeholder="0" required decimalScale={2}
                description="Negative kama hasara"
                {...form.getInputProps('gain_loss')} />
            </SimpleGrid>
            <Divider />
            <Text size="sm" c="dimmed">
              Umekagua mfumo huu leo. Je, kila kitu kiko sawa?
            </Text>
            <Radio.Group label="Status" required {...form.getInputProps('status')}>
              <Stack gap="xs" mt="xs">
                <Radio value="ok" label={
                  <Group gap="xs">
                    <ThemeIcon size="sm" variant="light" color="green" radius="xl"><IconCheck size={12} /></ThemeIcon>
                    <Box>
                      <Text size="sm" fw={500}>Sawa / All OK</Text>
                      <Text size="xs" c="dimmed">Nimeangalia sehemu zote, hesabu zimefungwa vizuri</Text>
                    </Box>
                  </Group>
                } />
                <Radio value="issue" label={
                  <Group gap="xs">
                    <ThemeIcon size="sm" variant="light" color="red" radius="xl"><IconAlertTriangle size={12} /></ThemeIcon>
                    <Box>
                      <Text size="sm" fw={500}>Kuna changamoto / Issue found</Text>
                      <Text size="xs" c="dimmed">Eleza chini, admin atapata notification mara moja</Text>
                    </Box>
                  </Group>
                } />
              </Stack>
            </Radio.Group>

            {form.values.status === 'issue' && (
              <>
                <Divider />
                <Textarea
                  label="Maelezo ya changamoto / Issue description"
                  placeholder="Eleza kwa undani — admin atapata taarifa hii ili afanyie kazi."
                  required
                  minRows={4}
                  {...form.getInputProps('notes')}
                />
              </>
            )}

            {form.values.status === 'ok' && (
              <Textarea
                label="Notes (optional)"
                placeholder="Maelezo ya ziada kama yapo"
                minRows={2}
                {...form.getInputProps('notes')}
              />
            )}

            <Group justify="flex-end">
              <Button variant="default" onClick={() => setSubmitting(null)}>Cancel</Button>
              <Button type="submit" color={form.values.status === 'issue' ? 'red' : 'blue'}
                loading={submitMutation.isPending}>
                {form.values.status === 'issue' ? 'Report Issue' : 'Submit OK'}
              </Button>
            </Group>
          </Stack>
        </form>
      </Modal>
    </Stack>
  );
}
