import { useState } from 'react';
import {
  Stack, Paper, Title, Text, Group, Badge, Button, Textarea, Center, Loader,
  ActionIcon, Avatar, Alert, Grid, FileButton, Anchor,
} from '@mantine/core';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { useNavigate, useParams } from 'react-router-dom';
import { IconArrowLeft, IconMessageCircle, IconSend, IconLock, IconHeadset, IconUser, IconPaperclip, IconX } from '@tabler/icons-react';
import { getPortalTicket, closePortalTicket } from '../../api/portal';
import {
  replyPortalTicketWithFiles, downloadPortalTicketAttachment, PortalTicketReply,
} from '../../api/portalTickets';
import { TICKET_STATUS_META, departmentLabel } from './PortalTickets';
import dayjs from 'dayjs';

const priorityColor: Record<string, string> = { low: 'gray', medium: 'blue', high: 'red' };

export default function PortalTicketView() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const qc = useQueryClient();
  const [message, setMessage] = useState('');
  const [files, setFiles] = useState<File[]>([]);

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
    mutationFn: () => replyPortalTicketWithFiles(id!, message.trim(), files),
    onSuccess: () => { setMessage(''); setFiles([]); invalidate(); },
    onError: () => notifications.show({ message: 'Failed to send reply.', color: 'red' }),
  });

  const closeMutation = useMutation({
    mutationFn: () => closePortalTicket(id!),
    onSuccess: () => { invalidate(); notifications.show({ message: 'Ticket closed. Replying will reopen it.', color: 'gray' }); },
  });

  if (isLoading || !t) {
    return <Center py="xl"><Loader /></Center>;
  }

  const meta = TICKET_STATUS_META[t.status] ?? { label: t.status, color: 'gray' };
  // WHMCS shows newest first; keep chronological (oldest first) for readability.
  const replies: PortalTicketReply[] = t.replies ?? [];

  return (
    <Stack gap="lg" maw={960}>
      <Group justify="space-between" wrap="wrap">
        <Group gap="xs">
          <ActionIcon variant="subtle" onClick={() => navigate('/portal/tickets')}><IconArrowLeft size={18} /></ActionIcon>
          <IconMessageCircle size={22} />
          <div>
            <Title order={4}>{t.subject}</Title>
            <Text size="xs" c="dimmed">#{t.ticket_number}</Text>
          </div>
        </Group>
        <Group gap="xs">
          <Badge size="lg" color={meta.color} variant="filled" radius="xl">{meta.label}</Badge>
          {t.status !== 'closed' && (
            <Button size="xs" variant="light" color="gray" leftSection={<IconLock size={13} />}
              loading={closeMutation.isPending} onClick={() => closeMutation.mutate()}>
              Close Ticket
            </Button>
          )}
        </Group>
      </Group>

      {/* Ticket information */}
      <Paper withBorder radius="md" p="md">
        <Grid>
          <Grid.Col span={{ base: 6, sm: 3 }}>
            <Text size="xs" c="dimmed" fw={700} tt="uppercase">Department</Text>
            <Text size="sm">{departmentLabel(t.department)}</Text>
          </Grid.Col>
          <Grid.Col span={{ base: 6, sm: 3 }}>
            <Text size="xs" c="dimmed" fw={700} tt="uppercase">Priority</Text>
            <Badge size="sm" variant="light" color={priorityColor[t.priority] ?? 'gray'}>{t.priority}</Badge>
          </Grid.Col>
          <Grid.Col span={{ base: 6, sm: 3 }}>
            <Text size="xs" c="dimmed" fw={700} tt="uppercase">Related Service</Text>
            <Text size="sm">{t.related_service ?? '—'}</Text>
          </Grid.Col>
          <Grid.Col span={{ base: 6, sm: 3 }}>
            <Text size="xs" c="dimmed" fw={700} tt="uppercase">Opened</Text>
            <Text size="sm">{dayjs(t.created_at).format('D MMM YYYY HH:mm')}</Text>
          </Grid.Col>
        </Grid>
      </Paper>

      {t.status === 'closed' && (
        <Alert color="gray" variant="light">
          This ticket is closed. Sending a new reply below will reopen it.
        </Alert>
      )}

      {/* Conversation */}
      <Stack gap="sm">
        {replies.map((r) => {
          const isStaff = r.author_type === 'staff';
          return (
            <Paper key={r.id} withBorder radius="md" p="md"
              style={{
                background: isStaff ? 'var(--mantine-color-blue-light)' : undefined,
                borderLeft: `3px solid var(--mantine-color-${isStaff ? 'blue' : 'gray'}-5)`,
              }}>
              <Group justify="space-between" mb={6}>
                <Group gap="xs">
                  <Avatar size="sm" radius="xl" color={isStaff ? 'blue' : 'gray'}>
                    {isStaff ? <IconHeadset size={15} /> : <IconUser size={15} />}
                  </Avatar>
                  <div>
                    <Text size="sm" fw={700}>{r.author_name}</Text>
                    <Text size="xs" c="dimmed">{isStaff ? 'Support Staff' : 'You / Your team'}</Text>
                  </div>
                </Group>
                <Text size="xs" c="dimmed">{dayjs(r.created_at).format('dddd, D MMMM YYYY (HH:mm)')}</Text>
              </Group>
              <Text size="sm" style={{ whiteSpace: 'pre-wrap' }}>{r.message}</Text>
              {(r.attachments ?? []).length > 0 && (
                <Group gap="xs" mt={8}>
                  {(r.attachments ?? []).map((a) => (
                    <Anchor key={a.id} size="xs" component="button" type="button"
                      onClick={() => downloadPortalTicketAttachment(a)}>
                      <Group gap={4} wrap="nowrap">
                        <IconPaperclip size={13} /> {a.original_name}
                      </Group>
                    </Anchor>
                  ))}
                </Group>
              )}
            </Paper>
          );
        })}
      </Stack>

      {/* Reply box */}
      <Paper withBorder radius="md" p="md">
        <Text fw={700} mb="xs">Reply</Text>
        <Stack gap="xs">
          <Textarea
            placeholder={t.status === 'closed' ? 'Write a reply to reopen this ticket…' : 'Write your reply…'}
            minRows={4} autosize maxRows={10}
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
            <FileButton onChange={(picked) => setFiles((prev) => [...prev, ...picked].slice(0, 5))}
              accept=".pdf,.png,.jpg,.jpeg,.txt,.zip,.doc,.docx,.xls,.xlsx" multiple>
              {(props) => (
                <Button {...props} size="sm" variant="light" leftSection={<IconPaperclip size={15} />}>
                  Attach
                </Button>
              )}
            </FileButton>
            <Button leftSection={<IconSend size={15} />}
              disabled={!message.trim()} loading={replyMutation.isPending}
              onClick={() => replyMutation.mutate()}>
              Send Reply
            </Button>
          </Group>
        </Stack>
      </Paper>
    </Stack>
  );
}
