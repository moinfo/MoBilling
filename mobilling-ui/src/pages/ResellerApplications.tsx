import { useState } from 'react';
import {
  Stack, Paper, Title, Text, Group, Badge, Table, Button, Modal, Textarea, Tabs,
  ScrollArea, LoadingOverlay, Alert, SimpleGrid, Divider,
} from '@mantine/core';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { IconBuildingStore, IconCheck, IconX, IconInfoCircle, IconRocket } from '@tabler/icons-react';
import {
  listResellerApplications, approveResellerApplication, rejectResellerApplication,
  ResellerApplicationStaffRecord,
} from '../api/resellerApplications';

const STATUS_COLOR: Record<string, string> = {
  pending: 'yellow', approved: 'blue', rejected: 'red', provisioned: 'green',
};

const CATEGORY_LABEL: Record<string, string> = {
  domain: 'Domain registration', hosting: 'Website hosting', email: 'Business email', linode: 'Cloud servers',
};

export default function ResellerApplications() {
  const qc = useQueryClient();
  const [status, setStatus] = useState<string>('pending');
  const [selected, setSelected] = useState<ResellerApplicationStaffRecord | null>(null);
  const [rejectOpen, setRejectOpen] = useState(false);
  const [rejectReason, setRejectReason] = useState('');
  const [approveNote, setApproveNote] = useState('');
  const [approveOpen, setApproveOpen] = useState(false);

  const { data, isLoading } = useQuery({
    queryKey: ['reseller-applications', status],
    queryFn: () => listResellerApplications({ status: status === 'all' ? undefined : status }),
  });
  const applications = data?.data?.data ?? [];

  const approveMut = useMutation({
    mutationFn: (id: string) => approveResellerApplication(id, approveNote || undefined),
    onSuccess: (res) => {
      notifications.show({ title: 'Approved', message: res.data.message, color: 'green' });
      qc.invalidateQueries({ queryKey: ['reseller-applications'] });
      setApproveOpen(false);
      setSelected(null);
      setApproveNote('');
    },
    onError: (e: any) => notifications.show({ message: e.response?.data?.message || 'Could not approve.', color: 'red' }),
  });

  const rejectMut = useMutation({
    mutationFn: (id: string) => rejectResellerApplication(id, rejectReason),
    onSuccess: (res) => {
      notifications.show({ title: 'Rejected', message: res.data.message, color: 'gray' });
      qc.invalidateQueries({ queryKey: ['reseller-applications'] });
      setRejectOpen(false);
      setSelected(null);
      setRejectReason('');
    },
    onError: (e: any) => notifications.show({ message: e.response?.data?.message || 'Could not reject.', color: 'red' }),
  });

  return (
    <Stack gap="lg">
      <Group gap="xs">
        <IconBuildingStore size={22} />
        <Title order={3}>Reseller Applications</Title>
      </Group>

      <Tabs value={status} onChange={(v) => setStatus(v || 'pending')}>
        <Tabs.List>
          <Tabs.Tab value="pending">Pending</Tabs.Tab>
          <Tabs.Tab value="approved">Approved</Tabs.Tab>
          <Tabs.Tab value="provisioned">Provisioned</Tabs.Tab>
          <Tabs.Tab value="rejected">Rejected</Tabs.Tab>
          <Tabs.Tab value="all">All</Tabs.Tab>
        </Tabs.List>
      </Tabs>

      <Paper withBorder radius="md" pos="relative" mih={200}>
        <LoadingOverlay visible={isLoading} />
        <ScrollArea>
          <Table miw={700}>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Brand</Table.Th>
                <Table.Th>Domain</Table.Th>
                <Table.Th>Client</Table.Th>
                <Table.Th>Categories</Table.Th>
                <Table.Th>Status</Table.Th>
                <Table.Th>Submitted</Table.Th>
                <Table.Th></Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {applications.length === 0 && (
                <Table.Tr><Table.Td colSpan={7}><Text ta="center" c="dimmed" py="md">No applications.</Text></Table.Td></Table.Tr>
              )}
              {applications.map((a) => (
                <Table.Tr key={a.id}>
                  <Table.Td fw={500}>{a.brand_name}</Table.Td>
                  <Table.Td>{a.requested_domain}</Table.Td>
                  <Table.Td>{a.client?.name ?? '—'}</Table.Td>
                  <Table.Td>
                    <Group gap={4}>
                      {a.categories.map((c) => <Badge key={c} size="xs" variant="light">{CATEGORY_LABEL[c] ?? c}</Badge>)}
                    </Group>
                  </Table.Td>
                  <Table.Td><Badge color={STATUS_COLOR[a.status]} variant="light">{a.status}</Badge></Table.Td>
                  <Table.Td>{new Date(a.created_at).toLocaleDateString('en-GB')}</Table.Td>
                  <Table.Td>
                    <Button size="xs" variant="light" onClick={() => setSelected(a)}>View</Button>
                  </Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        </ScrollArea>
      </Paper>

      <Modal opened={!!selected} onClose={() => setSelected(null)} title={selected?.brand_name} size="lg">
        {selected && (
          <Stack gap="sm">
            <SimpleGrid cols={{ base: 1, sm: 2 }} spacing="xs">
              <Text size="sm"><b>Requested domain:</b> {selected.requested_domain}</Text>
              <Text size="sm"><b>Status:</b> <Badge color={STATUS_COLOR[selected.status]} variant="light">{selected.status}</Badge></Text>
              <Text size="sm"><b>Client:</b> {selected.client?.name ?? '—'}</Text>
              <Text size="sm"><b>Client email:</b> {selected.client?.email ?? '—'}</Text>
              <Text size="sm"><b>Contact:</b> {selected.contact_name}</Text>
              <Text size="sm"><b>Contact email:</b> {selected.contact_email}</Text>
              <Text size="sm"><b>Contact phone:</b> {selected.contact_phone ?? '—'}</Text>
              <Text size="sm"><b>Submitted:</b> {new Date(selected.created_at).toLocaleString()}</Text>
            </SimpleGrid>
            <Divider label="Categories requested" />
            <Group gap={4}>
              {selected.categories.map((c) => <Badge key={c} variant="light">{CATEGORY_LABEL[c] ?? c}</Badge>)}
            </Group>
            {selected.staff_note && (
              <Alert icon={<IconInfoCircle size={16} />} color="gray" title="Staff note">
                {selected.staff_note}
              </Alert>
            )}

            {selected.status === 'pending' && (
              <Group justify="flex-end" mt="sm">
                <Button color="red" variant="light" leftSection={<IconX size={14} />}
                  onClick={() => setRejectOpen(true)}>
                  Reject
                </Button>
                <Button color="green" leftSection={<IconCheck size={14} />}
                  onClick={() => setApproveOpen(true)}>
                  Approve
                </Button>
              </Group>
            )}
            {selected.status === 'approved' && (
              <Alert icon={<IconRocket size={16} />} color="blue" title="Ready to provision">
                This application is approved. Go to Provision to review the plan (infrastructure, products,
                cost prices) and create the tenant.
              </Alert>
            )}
          </Stack>
        )}
      </Modal>

      <Modal opened={approveOpen} onClose={() => setApproveOpen(false)} title="Approve application">
        <Stack gap="sm">
          <Text size="sm">This approves the application. It does not create the tenant yet — provisioning is a separate step.</Text>
          <Textarea label="Note (optional)" value={approveNote} onChange={(e) => setApproveNote(e.currentTarget.value)} />
          <Group justify="flex-end">
            <Button variant="default" onClick={() => setApproveOpen(false)}>Cancel</Button>
            <Button color="green" loading={approveMut.isPending} onClick={() => selected && approveMut.mutate(selected.id)}>
              Confirm approve
            </Button>
          </Group>
        </Stack>
      </Modal>

      <Modal opened={rejectOpen} onClose={() => setRejectOpen(false)} title="Reject application">
        <Stack gap="sm">
          <Textarea label="Reason (required, shared with the client)" required
            value={rejectReason} onChange={(e) => setRejectReason(e.currentTarget.value)} minRows={3} />
          <Group justify="flex-end">
            <Button variant="default" onClick={() => setRejectOpen(false)}>Cancel</Button>
            <Button color="red" loading={rejectMut.isPending} disabled={!rejectReason.trim()}
              onClick={() => selected && rejectMut.mutate(selected.id)}>
              Confirm reject
            </Button>
          </Group>
        </Stack>
      </Modal>
    </Stack>
  );
}
