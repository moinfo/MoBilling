import { useState } from 'react';
import {
  Stack, Paper, Title, Text, Group, Button, TextInput, Textarea, Select,
  ActionIcon, Grid,
} from '@mantine/core';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { IconArrowLeft, IconMessageCircle, IconSend } from '@tabler/icons-react';
import { openPortalTicket, getPortalHosting, getPortalDomains } from '../../api/portal';
import { useAuth } from '../../context/AuthContext';
import { TICKET_DEPARTMENTS } from './PortalTickets';

export default function PortalTicketNew() {
  const navigate = useNavigate();
  const qc = useQueryClient();
  const { user } = useAuth();
  const [searchParams] = useSearchParams();

  const [department, setDepartment] = useState('support');
  const [relatedService, setRelatedService] = useState<string | null>(searchParams.get('service'));
  const [priority, setPriority] = useState('medium');
  const [subject, setSubject] = useState(searchParams.get('subject') ?? '');
  const [message, setMessage] = useState('');

  // Related service options: the client's hosting accounts + domains.
  const { data: hostingData } = useQuery({ queryKey: ['portal-hosting'], queryFn: getPortalHosting });
  const { data: domainsData } = useQuery({ queryKey: ['portal-domains'], queryFn: getPortalDomains });
  const serviceOptions = [
    ...((hostingData?.data?.data as any[]) ?? []).map((a) => `Hosting: ${a.domain}`),
    ...((domainsData?.data?.data as any[]) ?? []).map((d) => `Domain: ${d.name}`),
  ].map((v) => ({ value: v, label: v }));

  const mutation = useMutation({
    mutationFn: () => openPortalTicket({
      subject: subject.trim(),
      message: message.trim(),
      priority,
      department,
      related_service: relatedService ?? undefined,
    }),
    onSuccess: (res: any) => {
      qc.invalidateQueries({ queryKey: ['portal-tickets'] });
      qc.invalidateQueries({ queryKey: ['portal-dashboard'] });
      notifications.show({ title: 'Ticket opened', message: res?.data?.message, color: 'green', autoClose: 8000 });
      navigate(res?.data?.data?.id ? `/portal/tickets/${res.data.data.id}` : '/portal/tickets');
    },
    onError: (e: any) => notifications.show({
      message: e?.response?.data?.message ?? 'Could not open the ticket.', color: 'red',
    }),
  });

  return (
    <Stack gap="lg" maw={860}>
      <Group gap="xs">
        <ActionIcon variant="subtle" onClick={() => navigate('/portal/tickets')}><IconArrowLeft size={18} /></ActionIcon>
        <IconMessageCircle size={22} />
        <Title order={3}>Open New Ticket</Title>
      </Group>

      <Paper withBorder radius="md" p="lg">
        <Stack gap="sm">
          <Grid>
            <Grid.Col span={{ base: 12, sm: 6 }}>
              <TextInput label="Name" value={(user as any)?.name ?? ''} disabled />
            </Grid.Col>
            <Grid.Col span={{ base: 12, sm: 6 }}>
              <TextInput label="Email Address" value={(user as any)?.email ?? ''} disabled />
            </Grid.Col>
          </Grid>

          <Grid>
            <Grid.Col span={{ base: 12, sm: 4 }}>
              <Select label="Department" value={department} allowDeselect={false}
                onChange={(v) => setDepartment(v ?? 'support')} data={TICKET_DEPARTMENTS} />
            </Grid.Col>
            <Grid.Col span={{ base: 12, sm: 4 }}>
              <Select label="Related Service" placeholder="None" clearable searchable
                value={relatedService} onChange={setRelatedService} data={serviceOptions} />
            </Grid.Col>
            <Grid.Col span={{ base: 12, sm: 4 }}>
              <Select label="Priority" value={priority} allowDeselect={false}
                onChange={(v) => setPriority(v ?? 'medium')}
                data={[
                  { value: 'low', label: 'Low' },
                  { value: 'medium', label: 'Medium' },
                  { value: 'high', label: 'High' },
                ]} />
            </Grid.Col>
          </Grid>

          <TextInput label="Subject" required value={subject}
            onChange={(e) => setSubject(e.currentTarget.value)} />

          <Textarea label="Message" required minRows={7} autosize maxRows={14}
            placeholder="Describe your issue in as much detail as possible — include any error messages you see."
            value={message} onChange={(e) => setMessage(e.currentTarget.value)} />

          <Text size="xs" c="dimmed">
            We reply by email and here in the portal. Average response time is under one business day.
          </Text>

          <Group justify="flex-end">
            <Button variant="default" onClick={() => navigate('/portal/tickets')}>Cancel</Button>
            <Button leftSection={<IconSend size={15} />}
              disabled={!subject.trim() || !message.trim()} loading={mutation.isPending}
              onClick={() => mutation.mutate()}>
              Submit Ticket
            </Button>
          </Group>
        </Stack>
      </Paper>
    </Stack>
  );
}
