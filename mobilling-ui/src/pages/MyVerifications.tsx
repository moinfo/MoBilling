import { useState } from 'react';
import {
  Title, Card, Text, Group, Stack, Badge, Button, Modal, Textarea, Box, Alert, ThemeIcon, Radio, Divider, Loader, Center,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  IconCheck, IconAlertTriangle, IconClock, IconShield, IconClipboardCheck, IconWorld,
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
  const systems: SystemVerification[] = data?.data?.data || [];
  const today = dayjs().format('dddd, DD MMM YYYY');
  const pendingCount = systems.filter((s) => !s.todays_report).length;
  const issueCount = systems.filter((s) => s.todays_report?.status === 'issue').length;

  const form = useForm({
    initialValues: { status: 'ok' as 'ok' | 'issue', notes: '' },
    validate: {
      notes: (v, all) => (all.status === 'issue' && !v.trim() ? 'Eleza changamoto / Please describe the issue' : null),
    },
  });

  const submitMutation = useMutation({
    mutationFn: ({ id, values }: { id: string; values: typeof form.values }) =>
      submitVerificationReport(id, { status: values.status, notes: values.notes || undefined }),
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
    form.setValues({ status: 'ok', notes: '' });
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
                    {s.client_id && (
                      <Text size="xs" c="dimmed">Client ID: <Text span ff="monospace">{s.client_id}</Text></Text>
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
                        </Group>
                        {s.todays_report!.notes && (
                          <Text size="sm" c={isIssue ? 'red.7' : undefined}>{s.todays_report!.notes}</Text>
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
