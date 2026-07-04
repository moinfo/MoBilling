import { useState } from 'react';
import {
  Title, Stack, Group, Table, Badge, Text, Paper, Select, TextInput, Loader,
  Center, Drawer, Button, Textarea, Pagination, ScrollArea, Tooltip, ActionIcon,
  FileButton, Anchor,
} from '@mantine/core';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import {
  IconSearch, IconMessageCircle, IconSend, IconLock, IconLockOpen, IconUserCog,
  IconPaperclip, IconX, IconMessageDots,
} from '@tabler/icons-react';
import {
  getTickets, getTicketStats, getTicket, replyTicket, setTicketStatus, assignTicket,
  downloadTicketAttachment,
  TicketRow, TICKET_STATUS_META, PRIORITY_COLORS,
} from '../api/tickets';
import { getCannedReplies, CannedReply } from '../api/cannedReplies';
import { getUsers, TenantUser } from '../api/users';
import { usePermissions } from '../hooks/usePermissions';
import dayjs from 'dayjs';

export default function Tickets() {
  const { can } = usePermissions();
  const [statusFilter, setStatusFilter] = useState('');
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(1);
  const [openId, setOpenId] = useState<string | null>(null);

  const params: Record<string, string> = { page: String(page) };
  if (statusFilter) params.status = statusFilter;
  if (search) params.search = search;

  const { data, isLoading } = useQuery({
    queryKey: ['tickets', params],
    queryFn: () => getTickets(params),
  });
  const tickets: TicketRow[] = data?.data?.data?.data ?? [];
  const lastPage: number = data?.data?.data?.last_page ?? 1;

  const { data: statsData } = useQuery({ queryKey: ['ticket-stats'], queryFn: getTicketStats });
  const stats = statsData?.data;

  return (
    <Stack>
      <Group justify="space-between">
        <Group gap="xs">
          <IconMessageCircle size={22} />
          <Title order={2}>Support Tickets</Title>
        </Group>
        {stats && (
          <Group gap="xs">
            <Badge variant="light" color="orange">{stats.awaiting_reply} awaiting reply</Badge>
            <Badge variant="light" color="blue">{stats.answered} answered</Badge>
            <Badge variant="light" color="gray">{stats.closed} closed</Badge>
          </Group>
        )}
      </Group>

      <Group gap="xs">
        <TextInput size="xs" w={240} placeholder="Search subject, number, client…"
          leftSection={<IconSearch size={13} />}
          value={search} onChange={(e) => { setSearch(e.currentTarget.value); setPage(1); }} />
        <Select size="xs" w={170} placeholder="All statuses" clearable
          value={statusFilter} onChange={(v) => { setStatusFilter(v ?? ''); setPage(1); }}
          data={Object.entries(TICKET_STATUS_META).map(([v, m]) => ({ value: v, label: m.label }))} />
      </Group>

      {isLoading ? (
        <Center py="xl"><Loader /></Center>
      ) : tickets.length === 0 ? (
        <Center py="xl"><Text c="dimmed">No tickets found.</Text></Center>
      ) : (
        <Paper withBorder radius="md">
          <Table.ScrollContainer minWidth={760}>
            <Table highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>#</Table.Th>
                  <Table.Th>Subject</Table.Th>
                  <Table.Th>Client</Table.Th>
                  <Table.Th>Priority</Table.Th>
                  <Table.Th>Assigned</Table.Th>
                  <Table.Th>Last activity</Table.Th>
                  <Table.Th>Status</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {tickets.map((t) => {
                  const meta = TICKET_STATUS_META[t.status];
                  return (
                    <Table.Tr key={t.id} style={{ cursor: 'pointer' }} onClick={() => setOpenId(t.id)}>
                      <Table.Td><Text size="sm" fw={600}>{t.ticket_number}</Text></Table.Td>
                      <Table.Td><Text size="sm" truncate maw={260}>{t.subject}</Text></Table.Td>
                      <Table.Td><Text size="sm">{t.client?.name ?? '—'}</Text></Table.Td>
                      <Table.Td>
                        <Badge size="xs" variant="light" color={PRIORITY_COLORS[t.priority]}>{t.priority}</Badge>
                      </Table.Td>
                      <Table.Td><Text size="sm" c="dimmed">{t.assignee?.name ?? '—'}</Text></Table.Td>
                      <Table.Td>
                        <Text size="xs" c="dimmed">
                          {t.last_reply_at ? dayjs(t.last_reply_at).format('D MMM YYYY HH:mm') : '—'}
                        </Text>
                      </Table.Td>
                      <Table.Td><Badge size="sm" color={meta.color} variant="light">{meta.label}</Badge></Table.Td>
                    </Table.Tr>
                  );
                })}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        </Paper>
      )}

      {lastPage > 1 && (
        <Group justify="center"><Pagination value={page} onChange={setPage} total={lastPage} size="sm" /></Group>
      )}

      <TicketThreadDrawer id={openId} onClose={() => setOpenId(null)} can={can} />
    </Stack>
  );
}

function TicketThreadDrawer({ id, onClose, can }: {
  id: string | null; onClose: () => void; can: (p: string) => boolean;
}) {
  const qc = useQueryClient();
  const [message, setMessage] = useState('');
  const [files, setFiles] = useState<File[]>([]);

  const { data, isLoading } = useQuery({
    queryKey: ['ticket', id],
    queryFn: () => getTicket(id!),
    enabled: !!id,
  });
  const t = data?.data?.data;

  const { data: cannedData } = useQuery({
    queryKey: ['canned-replies'],
    queryFn: getCannedReplies,
    enabled: !!id && can('tickets.reply'),
  });
  const cannedReplies: CannedReply[] = cannedData?.data?.data ?? [];

  const { data: usersData } = useQuery({
    queryKey: ['tenant-users-for-assign'],
    queryFn: () => getUsers({ per_page: 200 }),
    enabled: !!id && can('tickets.manage'),
  });
  const userOptions = (usersData?.data?.data ?? []).map((u: TenantUser) => ({ value: u.id, label: u.name }));

  const invalidate = () => {
    qc.invalidateQueries({ queryKey: ['tickets'] });
    qc.invalidateQueries({ queryKey: ['ticket-stats'] });
    qc.invalidateQueries({ queryKey: ['ticket', id] });
  };

  const replyMutation = useMutation({
    mutationFn: () => replyTicket(id!, message.trim(), files),
    onSuccess: () => {
      setMessage('');
      setFiles([]);
      invalidate();
      notifications.show({ message: 'Reply sent to the client.', color: 'green' });
    },
    onError: () => notifications.show({ message: 'Failed to send reply.', color: 'red' }),
  });

  const insertCanned = (cannedId: string | null) => {
    const c = cannedReplies.find((r) => r.id === cannedId);
    if (!c) return;
    setMessage((prev) => (prev.trim() ? `${prev}\n\n${c.body}` : c.body));
  };

  const statusMutation = useMutation({
    mutationFn: (status: 'open' | 'closed') => setTicketStatus(id!, status),
    onSuccess: () => { invalidate(); },
  });

  const assignMutation = useMutation({
    mutationFn: (userId: string | null) => assignTicket(id!, userId),
    onSuccess: () => { invalidate(); notifications.show({ message: 'Assignee updated.', color: 'green' }); },
  });

  return (
    <Drawer opened={!!id} onClose={onClose} position="right" size="lg"
      title={t ? `${t.ticket_number} — ${t.subject}` : 'Ticket'}>
      {isLoading || !t ? (
        <Center py="xl"><Loader /></Center>
      ) : (
        <Stack gap="sm" h="calc(100vh - 80px)">
          <Group justify="space-between">
            <Group gap="xs">
              <Badge color={TICKET_STATUS_META[t.status].color} variant="light">
                {TICKET_STATUS_META[t.status].label}
              </Badge>
              <Badge size="sm" variant="light" color={PRIORITY_COLORS[t.priority]}>{t.priority}</Badge>
              <Text size="sm" c="dimmed">{t.client?.name}</Text>
            </Group>
            <Group gap="xs">
              {can('tickets.manage') && (
                <Select size="xs" w={160} placeholder="Assign to…" clearable searchable
                  leftSection={<IconUserCog size={13} />}
                  data={userOptions} value={t.assignee?.id ?? null}
                  onChange={(v) => assignMutation.mutate(v)} />
              )}
              {can('tickets.manage') && t.status !== 'closed' && (
                <Tooltip label="Close ticket">
                  <ActionIcon variant="light" color="gray" onClick={() => statusMutation.mutate('closed')}>
                    <IconLock size={15} />
                  </ActionIcon>
                </Tooltip>
              )}
              {can('tickets.manage') && t.status === 'closed' && (
                <Tooltip label="Reopen ticket">
                  <ActionIcon variant="light" color="green" onClick={() => statusMutation.mutate('open')}>
                    <IconLockOpen size={15} />
                  </ActionIcon>
                </Tooltip>
              )}
            </Group>
          </Group>

          <ScrollArea style={{ flex: 1 }} offsetScrollbars>
            <Stack gap="sm">
              {(t.replies ?? []).map((r) => (
                <Paper key={r.id} withBorder p="sm" radius="md"
                  style={{
                    background: r.author_type === 'staff' ? 'var(--mantine-color-blue-light)' : undefined,
                    marginLeft: r.author_type === 'staff' ? 24 : 0,
                    marginRight: r.author_type === 'staff' ? 0 : 24,
                  }}>
                  <Group justify="space-between" mb={4}>
                    <Text size="xs" fw={700}>
                      {r.author_name} {r.author_type === 'staff' && <Badge size="xs" variant="light">staff</Badge>}
                    </Text>
                    <Text size="xs" c="dimmed">{dayjs(r.created_at).format('D MMM YYYY HH:mm')}</Text>
                  </Group>
                  <Text size="sm" style={{ whiteSpace: 'pre-wrap' }}>{r.message}</Text>
                  {(r.attachments ?? []).length > 0 && (
                    <Group gap="xs" mt={8}>
                      {(r.attachments ?? []).map((a) => (
                        <Tooltip key={a.id} label={`Download (${Math.max(1, Math.round(a.size / 1024))} KB)`}>
                          <Anchor size="xs" component="button" type="button"
                            onClick={() => downloadTicketAttachment(a)}>
                            <Group gap={4} wrap="nowrap">
                              <IconPaperclip size={13} /> {a.original_name}
                            </Group>
                          </Anchor>
                        </Tooltip>
                      ))}
                    </Group>
                  )}
                </Paper>
              ))}
            </Stack>
          </ScrollArea>

          {can('tickets.reply') && (
            <Stack gap="xs">
              <Textarea placeholder="Write a reply to the client…" minRows={3} autosize maxRows={6}
                value={message} onChange={(e) => setMessage(e.currentTarget.value)} />
              {files.length > 0 && (
                <Group gap="xs">
                  {files.map((f, i) => (
                    <Badge key={i} variant="light" rightSection={
                      <ActionIcon size="xs" variant="transparent" color="gray"
                        onClick={() => setFiles(files.filter((_, j) => j !== i))}>
                        <IconX size={11} />
                      </ActionIcon>
                    }>{f.name}</Badge>
                  ))}
                </Group>
              )}
              <Group justify="space-between">
                <Group gap="xs">
                  {cannedReplies.length > 0 && (
                    <Select size="xs" w={210} clearable searchable
                      placeholder="Insert canned reply…"
                      leftSection={<IconMessageDots size={13} />}
                      data={cannedReplies.map((c) => ({ value: c.id, label: c.title }))}
                      value={null}
                      onChange={insertCanned} />
                  )}
                  <FileButton onChange={(picked) => setFiles((prev) => [...prev, ...picked].slice(0, 5))}
                    accept=".pdf,.png,.jpg,.jpeg,.txt,.zip,.doc,.docx,.xls,.xlsx" multiple>
                    {(props) => (
                      <Button {...props} size="xs" variant="light" leftSection={<IconPaperclip size={13} />}>
                        Attach
                      </Button>
                    )}
                  </FileButton>
                </Group>
                <Button size="sm" leftSection={<IconSend size={14} />}
                  disabled={!message.trim()} loading={replyMutation.isPending}
                  onClick={() => replyMutation.mutate()}>
                  Send Reply
                </Button>
              </Group>
            </Stack>
          )}
        </Stack>
      )}
    </Drawer>
  );
}
