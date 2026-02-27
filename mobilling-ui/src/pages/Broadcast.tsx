import { useState } from 'react';
import {
  Title, Group, Paper, Stack, SegmentedControl, TextInput, Textarea,
  MultiSelect, Button, Table, Badge, Text, Pagination, Loader, Select,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconSend } from '@tabler/icons-react';
import { getBroadcasts, sendBroadcast, type Broadcast as BroadcastType, type SendBroadcastPayload } from '../api/broadcasts';
import { getClients } from '../api/clients';
import { formatDate } from '../utils/formatDate';

const TEMPLATES: Record<string, { subject: string; body: string; sms_body: string }> = {
  maintenance: {
    subject: 'Scheduled Maintenance Notice',
    body: 'Dear Client,\n\nWe will be performing scheduled maintenance on [date] from [start time] to [end time].\n\nDuring this period, our services may be temporarily unavailable. We apologise for any inconvenience.\n\nThank you for your patience.',
    sms_body: 'Maintenance on [date] [start]-[end]. Services may be briefly unavailable. We apologise for any inconvenience.',
  },
  service_update: {
    subject: 'Service Update',
    body: 'Dear Client,\n\nWe are pleased to inform you about an important update to our services.\n\n[Describe the update here]\n\nIf you have any questions, please do not hesitate to contact us.\n\nBest regards.',
    sms_body: 'Service update: [brief description]. Contact us for details.',
  },
  unavailability: {
    subject: 'Service Unavailability Notice',
    body: 'Dear Client,\n\nWe regret to inform you that our services will be unavailable on [date] due to [reason].\n\nWe expect to resume normal operations by [time/date]. We apologise for any inconvenience caused.\n\nThank you for your understanding.',
    sms_body: 'Our services will be unavailable on [date] due to [reason]. Normal operations resume by [time].',
  },
  holiday: {
    subject: 'Holiday Notice',
    body: 'Dear Client,\n\nPlease note that our offices will be closed on [date(s)] for [holiday name].\n\nWe will resume normal business hours on [return date].\n\nWishing you a wonderful holiday!',
    sms_body: 'Our offices will be closed [date(s)] for [holiday]. We resume on [return date].',
  },
  general: {
    subject: 'Important Announcement',
    body: 'Dear Client,\n\nWe would like to bring the following to your attention:\n\n[Your announcement here]\n\nPlease feel free to reach out if you have any questions.\n\nBest regards.',
    sms_body: '[Your announcement here]. Contact us for more info.',
  },
};

const templateOptions = [
  { value: 'maintenance', label: 'Scheduled Maintenance' },
  { value: 'service_update', label: 'Service Update' },
  { value: 'unavailability', label: 'Service Unavailability' },
  { value: 'holiday', label: 'Holiday Notice' },
  { value: 'general', label: 'General Announcement' },
];

export default function Broadcast() {
  const queryClient = useQueryClient();
  const [page, setPage] = useState(1);

  // Fetch clients for recipient picker
  const { data: clientsData } = useQuery({
    queryKey: ['clients', 'broadcast-picker'],
    queryFn: () => getClients({ per_page: 500 }),
  });

  const clientOptions = (clientsData?.data?.data || []).map((c: any) => ({
    value: c.id,
    label: `${c.name}${c.email ? ` (${c.email})` : ''}`,
  }));

  // Fetch broadcast history
  const { data: historyData, isLoading: historyLoading } = useQuery({
    queryKey: ['broadcasts', page],
    queryFn: () => getBroadcasts({ page, per_page: 15 }),
  });

  const broadcasts: BroadcastType[] = historyData?.data?.data || [];
  const totalPages = historyData?.data?.last_page || 1;

  // Form
  const form = useForm<SendBroadcastPayload>({
    initialValues: {
      channel: 'email',
      subject: '',
      body: '',
      sms_body: '',
      client_ids: [],
    },
    validate: {
      subject: (v, values) =>
        ['email', 'both'].includes(values.channel) && !v ? 'Subject is required for email' : null,
      body: (v, values) =>
        ['email', 'both'].includes(values.channel) && !v ? 'Email body is required' : null,
      sms_body: (v, values) => {
        if (['sms', 'both'].includes(values.channel) && !v) return 'SMS body is required';
        if (v && v.length > 160) return 'SMS body must be 160 characters or less';
        return null;
      },
    },
  });

  const mutation = useMutation({
    mutationFn: (data: SendBroadcastPayload) => {
      const payload: SendBroadcastPayload = { channel: data.channel };
      if (['email', 'both'].includes(data.channel)) {
        payload.subject = data.subject;
        payload.body = data.body;
      }
      if (['sms', 'both'].includes(data.channel)) {
        payload.sms_body = data.sms_body;
      }
      if (data.client_ids && data.client_ids.length > 0) {
        payload.client_ids = data.client_ids;
      }
      return sendBroadcast(payload);
    },
    onSuccess: (res) => {
      const d = res.data;
      notifications.show({
        title: 'Broadcast sent',
        message: `${d.sent_count} delivered, ${d.failed_count} failed out of ${d.total_recipients} recipients`,
        color: d.failed_count > 0 ? 'orange' : 'green',
      });
      form.reset();
      queryClient.invalidateQueries({ queryKey: ['broadcasts'] });
    },
    onError: (err: any) => {
      notifications.show({
        title: 'Failed to send broadcast',
        message: err.response?.data?.message || 'Something went wrong',
        color: 'red',
      });
    },
  });

  const channel = form.values.channel;
  const showEmail = ['email', 'both'].includes(channel);
  const showSms = ['sms', 'both'].includes(channel);

  return (
    <Stack>
      <Title order={2}>Broadcast</Title>

      {/* Compose */}
      <Paper shadow="xs" p="md" withBorder>
        <form onSubmit={form.onSubmit((values) => mutation.mutate(values))}>
          <Stack>
            <SegmentedControl
              data={[
                { label: 'Email', value: 'email' },
                { label: 'SMS', value: 'sms' },
                { label: 'Both', value: 'both' },
              ]}
              {...form.getInputProps('channel')}
            />

            <Select
              label="Template"
              placeholder="Start from a template (optional)"
              data={templateOptions}
              clearable
              onChange={(value) => {
                if (value && TEMPLATES[value]) {
                  const t = TEMPLATES[value];
                  form.setValues({ subject: t.subject, body: t.body, sms_body: t.sms_body });
                }
              }}
            />

            {showEmail && (
              <>
                <TextInput
                  label="Subject"
                  placeholder="e.g. Scheduled Maintenance Notice"
                  {...form.getInputProps('subject')}
                />
                <Textarea
                  label="Email Body"
                  placeholder="Type your message..."
                  minRows={4}
                  autosize
                  {...form.getInputProps('body')}
                />
              </>
            )}

            {showSms && (
              <Textarea
                label="SMS Body"
                placeholder="Type your SMS message..."
                minRows={2}
                maxRows={3}
                description={`${form.values.sms_body?.length || 0}/160 characters`}
                {...form.getInputProps('sms_body')}
              />
            )}

            <MultiSelect
              label="Recipients"
              placeholder="All clients (leave empty to send to everyone)"
              data={clientOptions}
              searchable
              clearable
              {...form.getInputProps('client_ids')}
            />

            <Group>
              <Button
                type="submit"
                leftSection={<IconSend size={16} />}
                loading={mutation.isPending}
              >
                Send Broadcast
              </Button>
            </Group>
          </Stack>
        </form>
      </Paper>

      {/* History */}
      <Paper shadow="xs" p="md" withBorder>
        <Title order={4} mb="md">History</Title>
        {historyLoading ? (
          <Group justify="center" py="xl"><Loader /></Group>
        ) : broadcasts.length === 0 ? (
          <Text c="dimmed" ta="center" py="xl">No broadcasts yet</Text>
        ) : (
          <>
            <Table.ScrollContainer minWidth={700}>
              <Table striped highlightOnHover>
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th>Date</Table.Th>
                    <Table.Th>Channel</Table.Th>
                    <Table.Th>Subject / Message</Table.Th>
                    <Table.Th>Recipients</Table.Th>
                    <Table.Th>Delivered</Table.Th>
                    <Table.Th>Failed</Table.Th>
                    <Table.Th>Sent By</Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {broadcasts.map((b) => (
                    <Table.Tr key={b.id}>
                      <Table.Td>{formatDate(b.created_at)}</Table.Td>
                      <Table.Td>
                        <Badge
                          color={b.channel === 'email' ? 'blue' : b.channel === 'sms' ? 'green' : 'violet'}
                          variant="light"
                          size="sm"
                        >
                          {b.channel.toUpperCase()}
                        </Badge>
                      </Table.Td>
                      <Table.Td style={{ maxWidth: 250 }}>
                        <Text truncate size="sm">
                          {b.subject || b.sms_body || '-'}
                        </Text>
                      </Table.Td>
                      <Table.Td>{b.total_recipients}</Table.Td>
                      <Table.Td>
                        <Text c="green" fw={500}>{b.sent_count}</Text>
                      </Table.Td>
                      <Table.Td>
                        <Text c={b.failed_count > 0 ? 'red' : undefined} fw={b.failed_count > 0 ? 500 : undefined}>
                          {b.failed_count}
                        </Text>
                      </Table.Td>
                      <Table.Td>{b.sender?.name || '-'}</Table.Td>
                    </Table.Tr>
                  ))}
                </Table.Tbody>
              </Table>
            </Table.ScrollContainer>
            {totalPages > 1 && (
              <Group justify="center" mt="md">
                <Pagination value={page} onChange={setPage} total={totalPages} />
              </Group>
            )}
          </>
        )}
      </Paper>
    </Stack>
  );
}
