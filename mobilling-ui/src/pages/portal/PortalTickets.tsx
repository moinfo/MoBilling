import { useEffect, useState } from 'react';
import {
  Stack, Paper, Title, Table, Badge, LoadingOverlay, Button, Group, Text,
  Modal, TextInput, Textarea, Select, Drawer, ScrollArea, Loader, Center,
} from '@mantine/core';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { useSearchParams } from 'react-router-dom';
import { IconMessageCircle, IconPlus, IconSend, IconLock } from '@tabler/icons-react';
import {
  getPortalTickets, openPortalTicket, getPortalTicket, replyPortalTicket, closePortalTicket,
  PortalTicket,
} from '../../api/portal';
import dayjs from 'dayjs';

const STATUS_META: Record<string, { label: string; color: string }> = {
  open:           { label: 'Open',      color: 'green' },
  answered:       { label: 'Answered',  color: 'blue' },
  customer_reply: { label: 'Replied',   color: 'orange' },
  closed:         { label: 'Closed',    color: 'gray' },
};

export default function PortalTickets() {
  const [searchParams, setSearchParams] = useSearchParams();
  const [newOpen, setNewOpen] = useState(false);
  const [openId, setOpenId] = useState<string | null>(null);

  useEffect(() => {
    if (searchParams.get('new')) {
      setNewOpen(true);
      setSearchParams({}, { replace: true });
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const { data, isLoading } = useQuery({ queryKey: ['portal-tickets'], queryFn: getPortalTickets });
  const tickets: PortalTicket[] = data?.data?.data ?? [];

  return (
    <Stack gap="lg" pos="relative">
      <LoadingOverlay visible={isLoading} />
      <Group justify="space-between">
        <Group gap="xs">
          <IconMessageCircle size={22} />
          <Title order={3}>Support Tickets</Title>
        </Group>
        <Button leftSection={<IconPlus size={16} />} onClick={() => setNewOpen(true)}>
          Open New Ticket
        </Button>
      </Group>

      <Paper withBorder p="md">
        <Table.ScrollContainer minWidth={620}>
          <Table striped highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>#</Table.Th>
                <Table.Th>Subject</Table.Th>
                <Table.Th>Last Updated</Table.Th>
                <Table.Th>Status</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {tickets.length === 0 && (
                <Table.Tr><Table.Td colSpan={4}>
                  <Text c="dimmed" ta="center" py="md" size="sm">No tickets yet — open one if you need help.</Text>
                </Table.Td></Table.Tr>
              )}
              {tickets.map((t) => (
                <Table.Tr key={t.id} style={{ cursor: 'pointer' }} onClick={() => setOpenId(t.id)}>
                  <Table.Td><Text size="sm" fw={600}>{t.ticket_number}</Text></Table.Td>
                  <Table.Td><Text size="sm">{t.subject}</Text></Table.Td>
                  <Table.Td>
                    <Text size="xs" c="dimmed">
                      {t.last_reply_at ? dayjs(t.last_reply_at).format('dddd, D MMM YYYY (HH:mm)') : '—'}
                    </Text>
                  </Table.Td>
                  <Table.Td>
                    <Badge size="sm" color={STATUS_META[t.status]?.color ?? 'gray'} variant="filled" radius="xl">
                      {STATUS_META[t.status]?.label ?? t.status}
                    </Badge>
                  </Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      </Paper>

      <NewTicketModal opened={newOpen} onClose={() => setNewOpen(false)} onOpened={(id) => setOpenId(id)} />
      <ThreadDrawer id={openId} onClose={() => setOpenId(null)} />
    </Stack>
  );
}

function NewTicketModal({ opened, onClose, onOpened }: {
  opened: boolean; onClose: () => void; onOpened: (id: string) => void;
}) {
  const qc = useQueryClient();
  const [subject, setSubject] = useState('');
  const [message, setMessage] = useState('');
  const [priority, setPriority] = useState('medium');

  const mutation = useMutation({
    mutationFn: () => openPortalTicket({ subject: subject.trim(), message: message.trim(), priority }),
    onSuccess: (res: any) => {
      qc.invalidateQueries({ queryKey: ['portal-tickets'] });
      qc.invalidateQueries({ queryKey: ['portal-dashboard'] });
      notifications.show({ title: 'Ticket opened', message: res?.data?.message, color: 'green' });
      setSubject(''); setMessage(''); setPriority('medium');
      onClose();
      if (res?.data?.data?.id) onOpened(res.data.data.id);
    },
    onError: (e: any) => notifications.show({
      message: e?.response?.data?.message ?? 'Could not open the ticket.', color: 'red',
    }),
  });

  return (
    <Modal opened={opened} onClose={onClose} title="Open New Ticket" centered size="lg">
      <Stack gap="sm">
        <TextInput label="Subject" required value={subject}
          onChange={(e) => setSubject(e.currentTarget.value)} />
        <Select label="Priority" value={priority} onChange={(v) => setPriority(v ?? 'medium')}
          data={[
            { value: 'low', label: 'Low' },
            { value: 'medium', label: 'Medium' },
            { value: 'high', label: 'High' },
          ]} />
        <Textarea label="Message" required minRows={5} autosize maxRows={10}
          placeholder="Describe your issue or question…"
          value={message} onChange={(e) => setMessage(e.currentTarget.value)} />
        <Group justify="flex-end">
          <Button variant="default" onClick={onClose}>Cancel</Button>
          <Button disabled={!subject.trim() || !message.trim()} loading={mutation.isPending}
            onClick={() => mutation.mutate()}>
            Submit Ticket
          </Button>
        </Group>
      </Stack>
    </Modal>
  );
}

function ThreadDrawer({ id, onClose }: { id: string | null; onClose: () => void }) {
  const qc = useQueryClient();
  const [message, setMessage] = useState('');

  const { data, isLoading } = useQuery({
    queryKey: ['portal-ticket', id],
    queryFn: () => getPortalTicket(id!),
    enabled: !!id,
  });
  const t = data?.data?.data;

  const invalidate = () => {
    qc.invalidateQueries({ queryKey: ['portal-tickets'] });
    qc.invalidateQueries({ queryKey: ['portal-ticket', id] });
    qc.invalidateQueries({ queryKey: ['portal-dashboard'] });
  };

  const replyMutation = useMutation({
    mutationFn: () => replyPortalTicket(id!, message.trim()),
    onSuccess: () => { setMessage(''); invalidate(); },
    onError: () => notifications.show({ message: 'Failed to send reply.', color: 'red' }),
  });

  const closeMutation = useMutation({
    mutationFn: () => closePortalTicket(id!),
    onSuccess: () => { invalidate(); notifications.show({ message: 'Ticket closed.', color: 'gray' }); },
  });

  return (
    <Drawer opened={!!id} onClose={onClose} position="right" size="lg"
      title={t ? `${t.ticket_number} — ${t.subject}` : 'Ticket'}>
      {isLoading || !t ? (
        <Center py="xl"><Loader /></Center>
      ) : (
        <Stack gap="sm" h="calc(100vh - 80px)">
          <Group justify="space-between">
            <Badge color={STATUS_META[t.status]?.color ?? 'gray'} variant="light">
              {STATUS_META[t.status]?.label ?? t.status}
            </Badge>
            {t.status !== 'closed' && (
              <Button size="xs" variant="subtle" color="gray" leftSection={<IconLock size={13} />}
                onClick={() => closeMutation.mutate()}>
                Close Ticket
              </Button>
            )}
          </Group>

          <ScrollArea style={{ flex: 1 }} offsetScrollbars>
            <Stack gap="sm">
              {(t.replies ?? []).map((r) => (
                <Paper key={r.id} withBorder p="sm" radius="md"
                  style={{
                    background: r.author_type === 'staff' ? 'var(--mantine-color-blue-light)' : undefined,
                    marginLeft: r.author_type === 'staff' ? 0 : 24,
                    marginRight: r.author_type === 'staff' ? 24 : 0,
                  }}>
                  <Group justify="space-between" mb={4}>
                    <Text size="xs" fw={700}>
                      {r.author_type === 'staff' ? `${r.author_name} (Support)` : r.author_name}
                    </Text>
                    <Text size="xs" c="dimmed">{dayjs(r.created_at).format('D MMM YYYY HH:mm')}</Text>
                  </Group>
                  <Text size="sm" style={{ whiteSpace: 'pre-wrap' }}>{r.message}</Text>
                </Paper>
              ))}
            </Stack>
          </ScrollArea>

          <Stack gap="xs">
            <Textarea
              placeholder={t.status === 'closed' ? 'Replying will reopen this ticket…' : 'Write your reply…'}
              minRows={3} autosize maxRows={6}
              value={message} onChange={(e) => setMessage(e.currentTarget.value)} />
            <Group justify="flex-end">
              <Button size="sm" leftSection={<IconSend size={14} />}
                disabled={!message.trim()} loading={replyMutation.isPending}
                onClick={() => replyMutation.mutate()}>
                Send Reply
              </Button>
            </Group>
          </Stack>
        </Stack>
      )}
    </Drawer>
  );
}
