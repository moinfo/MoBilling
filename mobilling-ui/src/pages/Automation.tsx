import { useState } from 'react';
import {
  Title, Stack, SimpleGrid, Paper, Text, Group, Badge, Table,
  ThemeIcon, LoadingOverlay, Pagination, Select, SegmentedControl,
  Modal,
} from '@mantine/core';
import { useDisclosure } from '@mantine/hooks';
import { DatePickerInput } from '@mantine/dates';
import { useQuery } from '@tanstack/react-query';
import {
  IconFileInvoice, IconBell, IconFileSpreadsheet, IconCreditCardOff,
  IconMail, IconMessage, IconAlertTriangle, IconRobot,
} from '@tabler/icons-react';
import {
  getAutomationSummary,
  getCronLogs,
  getCommunicationLogs,
  type AutomationSummary,
  type CommunicationLogEntry,
} from '../api/automation';
import dayjs from 'dayjs';

export default function Automation() {
  const [date, setDate] = useState<Date | null>(new Date());
  const [cronPage, setCronPage] = useState(1);
  const [commPage, setCommPage] = useState(1);
  const [channelFilter, setChannelFilter] = useState<string | null>(null);
  const [statusFilter, setStatusFilter] = useState<string | null>(null);
  const [detailOpened, { open: openDetail, close: closeDetail }] = useDisclosure(false);
  const [selectedLog, setSelectedLog] = useState<CommunicationLogEntry | null>(null);

  const dateStr = date ? dayjs(date).format('YYYY-MM-DD') : undefined;

  const { data: summaryData, isLoading: summaryLoading } = useQuery({
    queryKey: ['automation-summary', dateStr],
    queryFn: () => getAutomationSummary(dateStr),
  });

  const { data: cronData, isLoading: cronLoading } = useQuery({
    queryKey: ['cron-logs', dateStr, cronPage],
    queryFn: () => getCronLogs({ date: dateStr, page: cronPage, per_page: 10 }),
  });

  const { data: commData, isLoading: commLoading } = useQuery({
    queryKey: ['comm-logs', dateStr, channelFilter, statusFilter, commPage],
    queryFn: () =>
      getCommunicationLogs({
        date: dateStr,
        channel: channelFilter || undefined,
        status: statusFilter || undefined,
        page: commPage,
        per_page: 10,
      }),
  });

  const summary: AutomationSummary | undefined = summaryData?.data?.data;
  const cronLogs = cronData?.data?.data ?? [];
  const cronMeta = cronData?.data as any;
  const commLogs = commData?.data?.data ?? [];
  const commMeta = commData?.data as any;

  return (
    <Stack gap="lg">
      <Group justify="space-between" align="flex-end">
        <Group gap="sm">
          <IconRobot size={28} />
          <Title order={2}>Automation</Title>
        </Group>
        <DatePickerInput
          value={date}
          onChange={(d) => { setDate(d); setCronPage(1); setCommPage(1); }}
          label="Date"
          w={160}
          clearable={false}
          maxDate={new Date()}
        />
      </Group>

      {/* Summary Cards */}
      <SimpleGrid cols={{ base: 2, sm: 4 }} pos="relative">
        <LoadingOverlay visible={summaryLoading} />
        <StatCard icon={<IconFileInvoice size={20} />} label="Invoices Created" value={summary?.invoices_created ?? 0} color="blue" />
        <StatCard icon={<IconBell size={20} />} label="Reminders Sent" value={summary?.reminders_sent ?? 0} color="violet" />
        <StatCard icon={<IconFileSpreadsheet size={20} />} label="Bills Generated" value={summary?.bills_generated ?? 0} color="teal" />
        <StatCard icon={<IconCreditCardOff size={20} />} label="Subscriptions Expired" value={summary?.subscriptions_expired ?? 0} color="orange" />
        <StatCard icon={<IconMail size={20} />} label="Emails Sent" value={summary?.emails_sent ?? 0} color="cyan" />
        <StatCard icon={<IconMessage size={20} />} label="SMS Sent" value={summary?.sms_sent ?? 0} color="green" />
        <StatCard icon={<IconAlertTriangle size={20} />} label="Failed" value={summary?.failed_communications ?? 0} color="red" />
      </SimpleGrid>

      {/* Cron Activity Log */}
      <Paper withBorder p="md" radius="md" pos="relative">
        <LoadingOverlay visible={cronLoading} />
        <Title order={4} mb="sm">Cron Activity</Title>
        {cronLogs.length === 0 ? (
          <Text c="dimmed" size="sm">No cron activity for this date.</Text>
        ) : (
          <>
            <Table.ScrollContainer minWidth={700}>
              <Table striped highlightOnHover>
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th>Command</Table.Th>
                    <Table.Th>Description</Table.Th>
                    <Table.Th>Status</Table.Th>
                    <Table.Th>Time</Table.Th>
                    <Table.Th>Duration</Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {cronLogs.map((log) => (
                    <Table.Tr key={log.id}>
                      <Table.Td>
                        <Text size="sm" ff="monospace">{log.command}</Text>
                      </Table.Td>
                      <Table.Td>
                        <Text size="sm">{log.description}</Text>
                        {log.error && <Text size="xs" c="red">{log.error}</Text>}
                      </Table.Td>
                      <Table.Td>
                        <Badge color={log.status === 'success' ? 'green' : 'red'} size="sm">
                          {log.status}
                        </Badge>
                      </Table.Td>
                      <Table.Td>
                        <Text size="sm">{dayjs(log.started_at).format('HH:mm:ss')}</Text>
                      </Table.Td>
                      <Table.Td>
                        <Text size="sm">
                          {log.finished_at
                            ? `${dayjs(log.finished_at).diff(dayjs(log.started_at), 'second')}s`
                            : '—'}
                        </Text>
                      </Table.Td>
                    </Table.Tr>
                  ))}
                </Table.Tbody>
              </Table>
            </Table.ScrollContainer>
            {(cronMeta?.last_page ?? 1) > 1 && (
              <Group justify="center" mt="md">
                <Pagination value={cronPage} onChange={setCronPage} total={cronMeta.last_page} />
              </Group>
            )}
          </>
        )}
      </Paper>

      {/* Communication Log */}
      <Paper withBorder p="md" radius="md" pos="relative">
        <LoadingOverlay visible={commLoading} />
        <Group justify="space-between" mb="sm" wrap="wrap">
          <Title order={4}>Communication Log</Title>
          <Group gap="sm">
            <SegmentedControl
              size="xs"
              value={channelFilter ?? 'all'}
              onChange={(v) => { setChannelFilter(v === 'all' ? null : v); setCommPage(1); }}
              data={[
                { label: 'All', value: 'all' },
                { label: 'Email', value: 'email' },
                { label: 'SMS', value: 'sms' },
              ]}
            />
            <Select
              size="xs"
              placeholder="Status"
              clearable
              w={120}
              value={statusFilter}
              onChange={(v) => { setStatusFilter(v); setCommPage(1); }}
              data={[
                { label: 'Sent', value: 'sent' },
                { label: 'Failed', value: 'failed' },
              ]}
            />
          </Group>
        </Group>
        {commLogs.length === 0 ? (
          <Text c="dimmed" size="sm">No communications for this date.</Text>
        ) : (
          <>
            <Table.ScrollContainer minWidth={700}>
              <Table striped highlightOnHover>
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th>Recipient</Table.Th>
                    <Table.Th>Channel</Table.Th>
                    <Table.Th>Type</Table.Th>
                    <Table.Th>Subject / Message</Table.Th>
                    <Table.Th>Status</Table.Th>
                    <Table.Th>Time</Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {commLogs.map((log) => (
                    <Table.Tr
                      key={log.id}
                      style={{ cursor: 'pointer' }}
                      onClick={() => { setSelectedLog(log); openDetail(); }}
                    >
                      <Table.Td>
                        <Text size="sm" truncate maw={200}>{log.recipient}</Text>
                      </Table.Td>
                      <Table.Td>
                        <Badge variant="light" color={log.channel === 'email' ? 'blue' : 'green'} size="sm">
                          {log.channel}
                        </Badge>
                      </Table.Td>
                      <Table.Td>
                        <Text size="sm">{log.type.replace(/_/g, ' ')}</Text>
                      </Table.Td>
                      <Table.Td>
                        <Text size="sm" truncate maw={250}>
                          {log.subject || log.message || '—'}
                        </Text>
                        {log.error && <Text size="xs" c="red" truncate maw={250}>{log.error}</Text>}
                      </Table.Td>
                      <Table.Td>
                        <Badge color={log.status === 'sent' ? 'green' : 'red'} size="sm">
                          {log.status}
                        </Badge>
                      </Table.Td>
                      <Table.Td>
                        <Text size="sm">{dayjs(log.created_at).format('HH:mm')}</Text>
                      </Table.Td>
                    </Table.Tr>
                  ))}
                </Table.Tbody>
              </Table>
            </Table.ScrollContainer>
            {(commMeta?.last_page ?? 1) > 1 && (
              <Group justify="center" mt="md">
                <Pagination value={commPage} onChange={setCommPage} total={commMeta.last_page} />
              </Group>
            )}
          </>
        )}
      </Paper>
      {/* Detail Modal */}
      <Modal opened={detailOpened} onClose={closeDetail} title="Communication Detail" size="lg">
        {selectedLog && (
          <Stack gap="sm">
            <Group justify="space-between">
              <Badge variant="light" color={selectedLog.channel === 'email' ? 'blue' : 'green'} size="lg">
                {selectedLog.channel}
              </Badge>
              <Badge color={selectedLog.status === 'sent' ? 'green' : 'red'} size="lg">
                {selectedLog.status}
              </Badge>
            </Group>

            <div>
              <Text size="xs" c="dimmed" tt="uppercase" fw={600}>Type</Text>
              <Text size="sm">{selectedLog.type.replace(/_/g, ' ')}</Text>
            </div>

            <div>
              <Text size="xs" c="dimmed" tt="uppercase" fw={600}>Recipient</Text>
              <Text size="sm">{selectedLog.recipient}</Text>
            </div>

            {selectedLog.subject && (
              <div>
                <Text size="xs" c="dimmed" tt="uppercase" fw={600}>Subject</Text>
                <Text size="sm">{selectedLog.subject}</Text>
              </div>
            )}

            {selectedLog.message && (
              <div>
                <Text size="xs" c="dimmed" tt="uppercase" fw={600}>Message</Text>
                <Paper withBorder p="sm" bg="var(--mantine-color-default)" style={{ whiteSpace: 'pre-wrap' }}>
                  <Text size="sm">{selectedLog.message}</Text>
                </Paper>
              </div>
            )}

            {selectedLog.error && (
              <div>
                <Text size="xs" c="dimmed" tt="uppercase" fw={600}>Error</Text>
                <Paper withBorder p="sm" bg="var(--mantine-color-red-light)">
                  <Text size="sm" c="red">{selectedLog.error}</Text>
                </Paper>
              </div>
            )}

            {selectedLog.metadata && Object.keys(selectedLog.metadata).length > 0 && (
              <div>
                <Text size="xs" c="dimmed" tt="uppercase" fw={600}>Metadata</Text>
                <Paper withBorder p="sm" bg="var(--mantine-color-default)">
                  {Object.entries(selectedLog.metadata).map(([key, val]) => (
                    <Text size="sm" key={key}><Text span fw={600}>{key}:</Text> {val}</Text>
                  ))}
                </Paper>
              </div>
            )}

            <div>
              <Text size="xs" c="dimmed" tt="uppercase" fw={600}>Sent At</Text>
              <Text size="sm">{dayjs(selectedLog.created_at).format('DD MMM YYYY, HH:mm:ss')}</Text>
            </div>
          </Stack>
        )}
      </Modal>
    </Stack>
  );
}

function StatCard({ icon, label, value, color }: { icon: React.ReactNode; label: string; value: number; color: string }) {
  return (
    <Paper withBorder p="md" radius="md">
      <Group gap="sm">
        <ThemeIcon variant="light" color={color} size="lg" radius="md">
          {icon}
        </ThemeIcon>
        <div>
          <Text size="xs" c="dimmed" tt="uppercase" fw={600}>{label}</Text>
          <Text size="lg" fw={700}>{value}</Text>
        </div>
      </Group>
    </Paper>
  );
}
