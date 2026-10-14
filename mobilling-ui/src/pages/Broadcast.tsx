import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Title, Group, Paper, Stack, SegmentedControl, TextInput, Textarea,
  MultiSelect, Button, Table, Badge, Text, Pagination, Loader, Select, Alert,
  ActionIcon, Tooltip, Drawer, FileInput, Image,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconSend, IconBrandWhatsapp, IconEye, IconRepeat, IconInfoCircle, IconPhoto, IconChartBar } from '@tabler/icons-react';
import {
  getBroadcasts, sendBroadcast, getBroadcastRecipients, resendFailedBroadcast, previewBroadcast, getMosmsContacts,
  type Broadcast as BroadcastType, type SendBroadcastPayload, type BroadcastRecipient,
  type BroadcastPreviewResponse, type BroadcastSource,
} from '../api/broadcasts';
import { getClients } from '../api/clients';
import { getMosmsStatus } from '../api/settings';
import { formatDate } from '../utils/formatDate';
import { countSmsSegments } from '../utils/smsSegments';

const TEMPLATES: Record<string, { subject: string; body: string; sms_body: string; whatsapp_body: string }> = {
  maintenance: {
    subject: 'Scheduled Maintenance Notice',
    body: 'Dear Client,\n\nWe will be performing scheduled maintenance on [date] from [start time] to [end time].\n\nDuring this period, our services may be temporarily unavailable. We apologise for any inconvenience.\n\nThank you for your patience.',
    sms_body: 'Maintenance on [date] [start]-[end]. Services may be briefly unavailable. We apologise for any inconvenience.',
    whatsapp_body: 'Dear Client,\n\nWe will be performing scheduled maintenance on [date] from [start time] to [end time]. Services may be briefly unavailable during this window. We apologise for any inconvenience.',
  },
  service_update: {
    subject: 'Service Update',
    body: 'Dear Client,\n\nWe are pleased to inform you about an important update to our services.\n\n[Describe the update here]\n\nIf you have any questions, please do not hesitate to contact us.\n\nBest regards.',
    sms_body: 'Service update: [brief description]. Contact us for details.',
    whatsapp_body: 'Dear Client,\n\nWe are pleased to inform you about an important update to our services: [describe the update here]. Contact us if you have any questions.',
  },
  unavailability: {
    subject: 'Service Unavailability Notice',
    body: 'Dear Client,\n\nWe regret to inform you that our services will be unavailable on [date] due to [reason].\n\nWe expect to resume normal operations by [time/date]. We apologise for any inconvenience caused.\n\nThank you for your understanding.',
    sms_body: 'Our services will be unavailable on [date] due to [reason]. Normal operations resume by [time].',
    whatsapp_body: 'Dear Client,\n\nOur services will be unavailable on [date] due to [reason]. We expect to resume normal operations by [time/date]. We apologise for any inconvenience.',
  },
  holiday: {
    subject: 'Holiday Notice',
    body: 'Dear Client,\n\nPlease note that our offices will be closed on [date(s)] for [holiday name].\n\nWe will resume normal business hours on [return date].\n\nWishing you a wonderful holiday!',
    sms_body: 'Our offices will be closed [date(s)] for [holiday]. We resume on [return date].',
    whatsapp_body: 'Dear Client,\n\nPlease note that our offices will be closed on [date(s)] for [holiday name]. We resume normal business hours on [return date]. Wishing you a wonderful holiday!',
  },
  general: {
    subject: 'Important Announcement',
    body: 'Dear Client,\n\nWe would like to bring the following to your attention:\n\n[Your announcement here]\n\nPlease feel free to reach out if you have any questions.\n\nBest regards.',
    sms_body: '[Your announcement here]. Contact us for more info.',
    whatsapp_body: 'Dear Client,\n\n[Your announcement here]\n\nPlease feel free to reach out if you have any questions.',
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
  const navigate = useNavigate();
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

  // Fetch MoBilling's own MoSMS address book for the "MoSMS Contacts" source picker.
  const { data: mosmsContactsData } = useQuery({
    queryKey: ['broadcast-mosms-contacts'],
    queryFn: () => getMosmsContacts(),
  });
  // MoSMS wallet balance — SMS and WhatsApp are billed from separate pools.
  const { data: mosmsStatusData } = useQuery({
    queryKey: ['broadcast-mosms-balance'],
    queryFn: () => getMosmsStatus(),
  });
  const smsBalance = mosmsStatusData?.data?.data?.balance?.sms_balance ?? null;
  const whatsappBalance = mosmsStatusData?.data?.data?.balance?.whatsapp_balance ?? null;

  const mosmsContactOptions = Array.from(
    (mosmsContactsData?.data?.data || [])
      .filter((c) => c.phone)
      // MoSMS's own address book can have the same phone saved more than once
      // (e.g. under different names) — Mantine's MultiSelect requires unique
      // option values, and sending would dedupe them anyway, so collapse here.
      .reduce((map, c) => {
        if (!map.has(c.phone as string)) {
          map.set(c.phone as string, {
            value: c.phone as string,
            label: `${c.name || c.phone}${c.email ? ` (${c.email})` : ''}`,
          });
        }
        return map;
      }, new Map<string, { value: string; label: string }>())
      .values(),
  );

  // Fetch broadcast history — polls while anything on this page is still
  // sending in the background (broadcasts now dispatch after the response
  // returns, so counts fill in live rather than arriving all at once).
  const { data: historyData, isLoading: historyLoading } = useQuery({
    queryKey: ['broadcasts', page],
    queryFn: () => getBroadcasts({ page, per_page: 15 }),
    refetchInterval: (query) => {
      const rows: BroadcastType[] = query.state.data?.data?.data || [];
      return rows.some((r) => r.in_progress) ? 3000 : false;
    },
  });

  const broadcasts: BroadcastType[] = historyData?.data?.data || [];
  const totalPages = historyData?.data?.last_page || 1;

  const [recipientsFor, setRecipientsFor] = useState<{ broadcast: BroadcastType; status: 'sent' | 'failed' } | null>(null);
  const { data: recipientsData, isLoading: recipientsLoading } = useQuery({
    queryKey: ['broadcast-recipients', recipientsFor?.broadcast.id, recipientsFor?.status],
    queryFn: () => getBroadcastRecipients(recipientsFor!.broadcast.id, recipientsFor!.status),
    enabled: !!recipientsFor,
  });
  const viewedRecipients: BroadcastRecipient[] = recipientsData?.data?.data || [];

  const [preview, setPreview] = useState<BroadcastPreviewResponse | null>(null);
  const previewMutation = useMutation({
    mutationFn: (data: { channel: string; sources?: BroadcastSource[]; client_ids?: string[]; contact_phones?: string[] }) => previewBroadcast(data),
    onSuccess: (res) => setPreview(res.data),
    onError: (err: any) => {
      notifications.show({
        title: 'Could not load recipients',
        message: err.response?.data?.message || 'Something went wrong',
        color: 'red',
      });
    },
  });

  const resendMutation = useMutation({
    mutationFn: (id: string) => resendFailedBroadcast(id),
    onSuccess: (res) => {
      notifications.show({ title: 'Resend started', message: res.data.message, color: 'teal' });
      queryClient.invalidateQueries({ queryKey: ['broadcasts'] });
    },
    onError: (err: any) => {
      notifications.show({
        title: 'Could not resend',
        message: err.response?.data?.message || 'Something went wrong',
        color: 'red',
      });
    },
  });

  // Form
  const form = useForm<SendBroadcastPayload>({
    initialValues: {
      channel: 'email',
      sources: ['mobilling'],
      subject: '',
      body: '',
      sms_body: '',
      whatsapp_body: '',
      whatsapp_image: null,
      client_ids: [],
      contact_phones: [],
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
      whatsapp_body: (v, values) =>
        values.channel === 'whatsapp' && !v ? 'WhatsApp message is required' : null,
    },
  });

  const mutation = useMutation({
    mutationFn: (data: SendBroadcastPayload) => {
      const sources = data.sources?.length ? data.sources : ['mobilling' as const];
      const payload: SendBroadcastPayload = { channel: data.channel, sources };
      if (['email', 'both'].includes(data.channel)) {
        payload.subject = data.subject;
        payload.body = data.body;
      }
      if (['sms', 'both'].includes(data.channel)) {
        payload.sms_body = data.sms_body;
      }
      if (data.channel === 'whatsapp') {
        payload.whatsapp_body = data.whatsapp_body;
        payload.whatsapp_image = data.whatsapp_image;
      }
      if (sources.includes('mobilling') && data.client_ids && data.client_ids.length > 0) {
        payload.client_ids = data.client_ids;
      }
      if (sources.includes('mosms_contacts') && data.contact_phones && data.contact_phones.length > 0) {
        payload.contact_phones = data.contact_phones;
      }
      return sendBroadcast(payload);
    },
    onSuccess: (res) => {
      const d = res.data;
      notifications.show({
        title: 'Broadcast started',
        message: `Sending to ${d.total_recipients} recipient(s) in the background — watch History below for live progress.`,
        color: 'blue',
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
  const sources = form.values.sources?.length ? form.values.sources : ['mobilling' as const];
  const showEmail = ['email', 'both'].includes(channel);
  const showSms = ['sms', 'both'].includes(channel);
  const showWhatsapp = channel === 'whatsapp';
  const isMobillingSource = sources.includes('mobilling');
  const isMosmsContactsSource = sources.includes('mosms_contacts');

  // What an SMS send will actually produce: one text per selected client
  // (or every client if none selected) who has a phone number on file.
  const allClients: any[] = clientsData?.data?.data || [];
  const selectedIds: string[] = form.values.client_ids ?? [];
  const smsPool = selectedIds.length > 0 ? allClients.filter((c) => selectedIds.includes(c.id)) : allClients;
  const smsRecipients = smsPool.filter((c) => c.phone).length;
  const clientListTruncated = (clientsData?.data?.total ?? 0) > allClients.length;
  const smsLength = form.values.sms_body?.length || 0;
  // Matches MoSmS's own SmsGatewayService::countSegments() exactly — plain GSM-7
  // text gets 160 chars in one segment then 153/segment after that, but a
  // single emoji/non-GSM-7 character switches the WHOLE message to Unicode
  // billing (70 then 67/segment), which a flat "/160" estimate would miss.
  const smsSegments = countSmsSegments(form.values.sms_body || '');
  const previewSmsCreditsNeeded = preview ? preview.total * smsSegments : null;
  const previewWhatsappCreditsNeeded = preview ? preview.total : null;

  return (
    <Stack>
      <Group justify="space-between">
        <Title order={2}>Broadcast</Title>
        <Button
          variant="light"
          leftSection={<IconChartBar size={16} />}
          onClick={() => navigate('/reports/communication-log')}
        >
          View delivery report
        </Button>
      </Group>

      {/* Compose */}
      <Paper shadow="xs" p="md" withBorder>
        <form onSubmit={form.onSubmit((values) => mutation.mutate(values))}>
          <Stack>
            <SegmentedControl
              data={[
                { label: 'Email', value: 'email' },
                { label: 'SMS', value: 'sms' },
                { label: 'WhatsApp', value: 'whatsapp' },
                { label: 'Both (Email + SMS)', value: 'both' },
              ]}
              {...form.getInputProps('channel')}
            />

            <MultiSelect
              label="Send to"
              description="Pick one or more sources — a contact appearing in more than one is only messaged once."
              data={[
                { value: 'mobilling', label: 'MoBilling clients' },
                { value: 'mosms_contacts', label: 'MoSMS Contacts (our own MoSMS address book)' },
              ]}
              value={sources}
              onChange={(v) => form.setFieldValue('sources', (v.length ? v : ['mobilling']) as BroadcastSource[])}
            />

            {isMosmsContactsSource && (
              <MultiSelect
                label="MoSMS Contacts to include"
                placeholder={`All ${mosmsContactOptions.length} contacts (leave empty to send to everyone)`}
                data={mosmsContactOptions}
                searchable
                clearable
                {...form.getInputProps('contact_phones')}
              />
            )}

            <Select
              label="Template"
              placeholder="Start from a template (optional)"
              data={templateOptions}
              clearable
              onChange={(value) => {
                if (value && TEMPLATES[value]) {
                  const t = TEMPLATES[value];
                  form.setValues({ subject: t.subject, body: t.body, sms_body: t.sms_body, whatsapp_body: t.whatsapp_body });
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
                description={`${smsLength}/160 characters · each recipient gets 1 SMS`}
                {...form.getInputProps('sms_body')}
              />
            )}

            {showWhatsapp && (
              <>
                <Textarea
                  label="WhatsApp Message"
                  placeholder="Type your WhatsApp message..."
                  minRows={4}
                  autosize
                  {...form.getInputProps('whatsapp_body')}
                />
                <FileInput
                  label="Poster (optional)"
                  description="Attach an image to send alongside the message, e.g. a holiday poster (JPG/PNG/WEBP, max 2MB)"
                  placeholder="Choose an image..."
                  accept="image/jpeg,image/png,image/webp"
                  leftSection={<IconPhoto size={16} />}
                  clearable
                  {...form.getInputProps('whatsapp_image')}
                />
                {form.values.whatsapp_image && (
                  <Image
                    src={URL.createObjectURL(form.values.whatsapp_image)}
                    alt="Poster preview"
                    radius="sm"
                    mah={200}
                    w="auto"
                    fit="contain"
                  />
                )}
              </>
            )}

            {isMobillingSource && (
              <MultiSelect
                label="Recipients"
                placeholder="All clients (leave empty to send to everyone)"
                data={clientOptions}
                searchable
                clearable
                {...form.getInputProps('client_ids')}
              />
            )}

            {isMobillingSource && showSms && (
              <Alert
                variant="light"
                color={smsRecipients === 0 ? 'red' : 'blue'}
                icon={<IconInfoCircle size={16} />}
              >
                {smsRecipients === 0 ? (
                  'No recipients on this list have a phone number, so no SMS will be sent.'
                ) : (
                  <>
                    This will send <b>{smsRecipients}</b> SMS{smsRecipients === 1 ? '' : ' messages'}
                    {' '}(one per client with a phone number).
                  </>
                )}
                {clientListTruncated && selectedIds.length === 0 && (
                  <Text size="xs" mt={4}>
                    Only the first {allClients.length} clients are counted here; the final number is shown after sending.
                  </Text>
                )}
              </Alert>
            )}

            {(showSms || showWhatsapp) && (
              <Text size="xs" c="dimmed">
                MoSMS balance: {showSms && <>{smsBalance ?? '—'} SMS credit(s)</>}{showSms && showWhatsapp && ' · '}
                {showWhatsapp && <>{whatsappBalance ?? '—'} WhatsApp credit(s)</>}
                {' '}— click "Preview recipients" below to see exactly how many you'll use.
              </Text>
            )}

            <Group>
              <Button
                variant="default"
                leftSection={<IconEye size={16} />}
                loading={previewMutation.isPending}
                onClick={() => previewMutation.mutate({
                  channel: form.values.channel,
                  sources,
                  client_ids: isMobillingSource && form.values.client_ids?.length ? form.values.client_ids : undefined,
                  contact_phones: isMosmsContactsSource && form.values.contact_phones?.length ? form.values.contact_phones : undefined,
                })}
              >
                Preview recipients
              </Button>
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
                    <Table.Th></Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {broadcasts.map((b) => (
                    <Table.Tr key={b.id}>
                      <Table.Td>{formatDate(b.created_at)}</Table.Td>
                      <Table.Td>
                        <Badge
                          color={b.channel === 'email' ? 'blue' : b.channel === 'sms' ? 'green' : b.channel === 'whatsapp' ? 'teal' : 'violet'}
                          variant="light"
                          size="sm"
                          leftSection={b.channel === 'whatsapp' ? <IconBrandWhatsapp size={12} /> : undefined}
                        >
                          {b.channel.toUpperCase()}
                        </Badge>
                        {b.retry_of_broadcast_id && (
                          <Badge size="xs" color="gray" variant="outline" ml={4}>retry</Badge>
                        )}
                      </Table.Td>
                      <Table.Td style={{ maxWidth: 250 }}>
                        <Text truncate size="sm">
                          {b.subject || b.sms_body || b.whatsapp_body || '-'}
                        </Text>
                      </Table.Td>
                      <Table.Td>{b.total_recipients}</Table.Td>
                      <Table.Td>
                        <Group gap={4} wrap="nowrap">
                          <Text c="green" fw={500}>{b.sent_count}</Text>
                          {(b.sent_client_ids?.length ?? 0) > 0 && (
                            <Tooltip label="View numbers that received it">
                              <ActionIcon variant="subtle" color="green" size="sm"
                                onClick={() => setRecipientsFor({ broadcast: b, status: 'sent' })}>
                                <IconEye size={13} />
                              </ActionIcon>
                            </Tooltip>
                          )}
                        </Group>
                      </Table.Td>
                      <Table.Td>
                        {b.in_progress ? (
                          <Group gap={4} wrap="nowrap"><Loader size="xs" /><Text size="xs" c="dimmed">sending…</Text></Group>
                        ) : (
                          <Text c={b.failed_count > 0 ? 'red' : undefined} fw={b.failed_count > 0 ? 500 : undefined}>
                            {b.failed_count}
                          </Text>
                        )}
                      </Table.Td>
                      <Table.Td>{b.sender?.name || '-'}</Table.Td>
                      <Table.Td>
                        <Group gap={4} wrap="nowrap">
                          {!b.in_progress && (
                            <Tooltip label="View real delivery report (not just sent/failed)">
                              <ActionIcon variant="light" color="blue" onClick={() => navigate(`/broadcast/${b.id}/delivery-report`)}>
                                <IconChartBar size={15} />
                              </ActionIcon>
                            </Tooltip>
                          )}
                          {!b.in_progress && b.failed_count > 0 && (
                            <>
                              <Tooltip label="View failed recipients">
                                <ActionIcon variant="light" color="red" onClick={() => setRecipientsFor({ broadcast: b, status: 'failed' })}>
                                  <IconEye size={15} />
                                </ActionIcon>
                              </Tooltip>
                              {(b.failed_client_ids?.length ?? 0) > 0 && (
                                <Tooltip label="Resend to failed recipients only">
                                  <ActionIcon variant="light" color="teal" loading={resendMutation.isPending && resendMutation.variables === b.id}
                                    onClick={() => resendMutation.mutate(b.id)}>
                                    <IconRepeat size={15} />
                                  </ActionIcon>
                                </Tooltip>
                              )}
                            </>
                          )}
                        </Group>
                      </Table.Td>
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

      <Drawer
        opened={!!recipientsFor}
        onClose={() => setRecipientsFor(null)}
        title={
          <Text fw={700}>
            {recipientsFor?.status === 'sent' ? 'Delivered to' : 'Failed recipients'}
            {recipientsFor ? ` — ${formatDate(recipientsFor.broadcast.created_at)}` : ''}
          </Text>
        }
        position="right"
        size="md"
      >
        {recipientsLoading ? (
          <Group justify="center" py="xl"><Loader /></Group>
        ) : viewedRecipients.length === 0 ? (
          <Text c="dimmed" size="sm">
            No per-recipient detail is available for this broadcast — it predates individual
            delivery tracking, so only the total count is known
            ({recipientsFor?.status === 'sent' ? recipientsFor?.broadcast.sent_count : recipientsFor?.broadcast.failed_count}).
          </Text>
        ) : (
          <Stack gap="xs">
            <Text size="sm" c="dimmed">{viewedRecipients.length} recipient(s) {recipientsFor?.status === 'sent' ? 'received it' : 'failed'}:</Text>
            {viewedRecipients.map((r) => (
              <Paper key={r.id} withBorder p="xs" radius="sm">
                <Text size="sm" fw={500}>{r.name}</Text>
                <Text size="xs" c="dimmed">{[r.phone, r.email].filter(Boolean).join(' · ') || '—'}</Text>
                {r.reason && (
                  <Text size="xs" c="red" mt={4}>{r.reason}</Text>
                )}
              </Paper>
            ))}
          </Stack>
        )}
      </Drawer>

      <Drawer
        opened={!!preview}
        onClose={() => setPreview(null)}
        title={<Text fw={700}>Who this will reach</Text>}
        position="right"
        size="md"
      >
        {preview && (
          <Stack gap="xs">
            <Text size="sm" c="dimmed">
              {preview.total} recipient(s) will be messaged.
              {preview.duplicates_removed > 0 && (
                <> {preview.duplicates_removed} duplicate contact(s) (same phone/email on more than one client) were skipped, so no one gets it twice.</>
              )}
            </Text>

            {(channel === 'sms' || channel === 'both') && previewSmsCreditsNeeded !== null && (
              <Alert
                variant="light"
                color={smsBalance !== null && previewSmsCreditsNeeded > smsBalance ? 'red' : 'blue'}
                icon={<IconInfoCircle size={16} />}
              >
                Needs <b>{previewSmsCreditsNeeded}</b> SMS credit(s) ({preview.total} recipient(s) × {smsSegments} segment(s)/message).
                You have <b>{smsBalance ?? '—'}</b>.
                {smsBalance !== null && previewSmsCreditsNeeded > smsBalance && ' Top up before sending — it will stop partway otherwise.'}
              </Alert>
            )}

            {channel === 'whatsapp' && previewWhatsappCreditsNeeded !== null && (
              <Alert
                variant="light"
                color={whatsappBalance !== null && previewWhatsappCreditsNeeded > whatsappBalance ? 'red' : 'blue'}
                icon={<IconInfoCircle size={16} />}
              >
                Needs <b>{previewWhatsappCreditsNeeded}</b> WhatsApp credit(s). You have <b>{whatsappBalance ?? '—'}</b>.
                {whatsappBalance !== null && previewWhatsappCreditsNeeded > whatsappBalance && ' Top up before sending — it will stop partway otherwise.'}
              </Alert>
            )}

            {preview.total === 0 ? (
              <Alert color="yellow" icon={<IconInfoCircle size={18} />}>
                No clients match this channel/recipient selection.
              </Alert>
            ) : (
              preview.recipients.map((r) => (
                <Paper key={r.id} withBorder p="xs" radius="sm">
                  <Text size="sm" fw={500}>{r.name}</Text>
                  <Text size="xs" c="dimmed">{[r.phone, r.email].filter(Boolean).join(' · ') || '—'}</Text>
                </Paper>
              ))
            )}
          </Stack>
        )}
      </Drawer>
    </Stack>
  );
}
