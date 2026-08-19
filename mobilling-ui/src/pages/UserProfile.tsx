import { useParams, useNavigate } from 'react-router-dom';
import { useState } from 'react';
import {
  Title, Text, Group, Badge, Table, Paper, SimpleGrid, Stack,
  Anchor, Loader, Center, Button, TextInput, Select, Textarea,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { IconArrowLeft, IconId, IconCalendarTime } from '@tabler/icons-react';
import {
  getEmployeeProfile, updateEmployeeProfile, EmployeeProfileFormData,
} from '../api/employeeProfile';
import { getLeaveRequests, LeaveRequest } from '../api/leave';
import { formatDate } from '../utils/formatDate';
import { usePermissions } from '../hooks/usePermissions';

const statusColors: Record<string, string> = {
  pending: 'yellow', approved: 'green', rejected: 'red', cancelled: 'gray',
};

export default function UserProfile() {
  const navigate = useNavigate();
  const { can } = usePermissions();
  const { userId } = useParams<{ userId: string }>();
  const queryClient = useQueryClient();
  const [editing, setEditing] = useState(false);
  const canUpdate = can('employees.update');

  const { data, isLoading } = useQuery({
    queryKey: ['employee-profile', userId],
    queryFn: () => getEmployeeProfile(userId!),
    enabled: !!userId,
  });

  const { data: leaveData } = useQuery({
    queryKey: ['leave-requests', userId],
    queryFn: () => getLeaveRequests({ user_id: userId }),
    enabled: !!userId,
  });

  const updateMut = useMutation({
    mutationFn: (values: EmployeeProfileFormData) => updateEmployeeProfile(userId!, values),
    onSuccess: () => {
      notifications.show({ title: 'Success', message: 'Profile updated', color: 'green' });
      queryClient.invalidateQueries({ queryKey: ['employee-profile', userId] });
      setEditing(false);
    },
    onError: (err: any) => notifications.show({
      title: 'Error', message: err.response?.data?.message || 'Failed to update profile', color: 'red',
    }),
  });

  const profile = data?.data?.data?.profile;
  const employeeUser = data?.data?.data?.user;
  const leaveRequests: LeaveRequest[] = leaveData?.data?.data ?? [];

  const form = useForm<EmployeeProfileFormData>({
    initialValues: {
      employee_number: profile?.employee_number ?? '',
      hire_date: profile?.hire_date ?? '',
      department: profile?.department ?? '',
      position: profile?.position ?? '',
      employment_type: profile?.employment_type ?? undefined,
      national_id: profile?.national_id ?? '',
      nssf_number: profile?.nssf_number ?? '',
      tin_number: profile?.tin_number ?? '',
      next_of_kin_name: profile?.next_of_kin_name ?? '',
      next_of_kin_phone: profile?.next_of_kin_phone ?? '',
      bank_name: profile?.bank_name ?? '',
      bank_branch: profile?.bank_branch ?? '',
      bank_account_name: profile?.bank_account_name ?? '',
      bank_account_number: profile?.bank_account_number ?? '',
      mobile_money_provider: profile?.mobile_money_provider ?? '',
      mobile_money_number: profile?.mobile_money_number ?? '',
      notes: profile?.notes ?? '',
    },
  });

  const startEditing = () => {
    form.setValues({
      employee_number: profile?.employee_number ?? '',
      hire_date: profile?.hire_date ?? '',
      department: profile?.department ?? '',
      position: profile?.position ?? '',
      employment_type: profile?.employment_type ?? undefined,
      national_id: profile?.national_id ?? '',
      nssf_number: profile?.nssf_number ?? '',
      tin_number: profile?.tin_number ?? '',
      next_of_kin_name: profile?.next_of_kin_name ?? '',
      next_of_kin_phone: profile?.next_of_kin_phone ?? '',
      bank_name: profile?.bank_name ?? '',
      bank_branch: profile?.bank_branch ?? '',
      bank_account_name: profile?.bank_account_name ?? '',
      bank_account_number: profile?.bank_account_number ?? '',
      mobile_money_provider: profile?.mobile_money_provider ?? '',
      mobile_money_number: profile?.mobile_money_number ?? '',
      notes: profile?.notes ?? '',
    });
    setEditing(true);
  };

  if (isLoading) {
    return <Center py="xl"><Loader /></Center>;
  }

  if (!employeeUser) {
    return <Text c="dimmed" ta="center" py="xl">Employee not found.</Text>;
  }

  return (
    <Stack gap="lg">
      <Group>
        <Anchor onClick={() => navigate('/users')} c="dimmed" size="sm" style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
          <IconArrowLeft size={14} /> Back to Team
        </Anchor>
      </Group>

      <Group justify="space-between" align="flex-start" wrap="wrap">
        <div>
          <Title order={2}>{employeeUser.name}</Title>
          <Group gap="md" mt={4}>
            <Text size="sm" c="dimmed">{employeeUser.email}</Text>
            {employeeUser.phone && <Text size="sm" c="dimmed">{employeeUser.phone}</Text>}
          </Group>
          <Group gap="xs" mt={6}>
            {employeeUser.role && <Badge size="sm" variant="light">{employeeUser.role.label}</Badge>}
            {profile?.department && <Badge size="sm" variant="light" color="blue">{profile.department}</Badge>}
            {profile?.position && <Text size="sm" c="dimmed">{profile.position}</Text>}
            {employeeUser.supervisor && <Text size="xs" c="dimmed">Reports to {employeeUser.supervisor.name}</Text>}
          </Group>
        </div>
        {canUpdate && !editing && (
          <Button size="xs" variant="light" leftSection={<IconId size={14} />} onClick={startEditing}>
            Edit Profile
          </Button>
        )}
      </Group>

      <Paper withBorder p="md" radius="md">
        <Title order={4} mb="sm">Employee Details</Title>
        {editing ? (
          <form onSubmit={form.onSubmit((values) => updateMut.mutate(values))}>
            <Stack gap="sm">
              <SimpleGrid cols={{ base: 1, sm: 2 }}>
                <TextInput label="Employee Number" {...form.getInputProps('employee_number')} />
                <TextInput label="Hire Date" type="date" {...form.getInputProps('hire_date')} />
                <TextInput label="Department" {...form.getInputProps('department')} />
                <TextInput label="Position" {...form.getInputProps('position')} />
                <Select label="Employment Type" data={[
                  { value: 'full_time', label: 'Full Time' },
                  { value: 'part_time', label: 'Part Time' },
                  { value: 'contract', label: 'Contract' },
                  { value: 'intern', label: 'Intern' },
                ]} {...form.getInputProps('employment_type')} />
                <TextInput label="National ID" {...form.getInputProps('national_id')} />
                <TextInput label="NSSF Number" {...form.getInputProps('nssf_number')} />
                <TextInput label="TIN Number" {...form.getInputProps('tin_number')} />
                <TextInput label="Next of Kin Name" {...form.getInputProps('next_of_kin_name')} />
                <TextInput label="Next of Kin Phone" {...form.getInputProps('next_of_kin_phone')} />
                <TextInput label="Bank Name" {...form.getInputProps('bank_name')} />
                <TextInput label="Bank Branch" {...form.getInputProps('bank_branch')} />
                <TextInput label="Bank Account Name" {...form.getInputProps('bank_account_name')} />
                <TextInput label="Bank Account Number" {...form.getInputProps('bank_account_number')} />
                <TextInput label="Mobile Money Provider" {...form.getInputProps('mobile_money_provider')} />
                <TextInput label="Mobile Money Number" {...form.getInputProps('mobile_money_number')} />
              </SimpleGrid>
              <Textarea label="Notes" minRows={2} {...form.getInputProps('notes')} />

              <Text size="xs" c="dimmed" mt="xs">
                PAYE/NSSF/WCF/SDL/etc. exemptions are managed under Payroll &gt; Settings/Statutory Rates &gt; Assign.
              </Text>

              <Group justify="flex-end">
                <Button variant="default" onClick={() => setEditing(false)}>Cancel</Button>
                <Button type="submit" loading={updateMut.isPending}>Save</Button>
              </Group>
            </Stack>
          </form>
        ) : profile ? (
          <Stack gap="sm">
            <SimpleGrid cols={{ base: 1, sm: 2, md: 3 }} spacing="sm">
              <ProfileField label="Employee Number" value={profile.employee_number} />
              <ProfileField label="Hire Date" value={profile.hire_date ? formatDate(profile.hire_date) : null} />
              <ProfileField label="Department" value={profile.department} />
              <ProfileField label="Position" value={profile.position} />
              <ProfileField label="Employment Type" value={profile.employment_type} />
              <ProfileField label="National ID" value={profile.national_id} />
              <ProfileField label="NSSF Number" value={profile.nssf_number} />
              <ProfileField label="TIN Number" value={profile.tin_number} />
              <ProfileField label="Next of Kin" value={profile.next_of_kin_name} />
              <ProfileField label="Next of Kin Phone" value={profile.next_of_kin_phone} />
              <ProfileField label="Bank" value={[profile.bank_name, profile.bank_account_number].filter(Boolean).join(' — ')} />
              <ProfileField label="Mobile Money" value={[profile.mobile_money_provider, profile.mobile_money_number].filter(Boolean).join(' — ')} />
            </SimpleGrid>
            {!profile.subject_to_paye && (
              <Group gap="xs">
                <Text size="xs" c="dimmed">Exempt from:</Text>
                <Badge size="sm" color="orange" variant="light">PAYE</Badge>
              </Group>
            )}
          </Stack>
        ) : (
          <Text c="dimmed" size="sm">No employee details on file yet.{canUpdate ? ' Click "Edit Profile" to add them.' : ''}</Text>
        )}
      </Paper>

      <Paper withBorder p="md" radius="md">
        <Group gap="sm" mb="sm"><IconCalendarTime size={18} /><Title order={4}>Leave History</Title></Group>
        {leaveRequests.length === 0 ? (
          <Text c="dimmed" size="sm">No leave requests.</Text>
        ) : (
          <Table.ScrollContainer minWidth={500}>
            <Table striped highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Type</Table.Th>
                  <Table.Th>Dates</Table.Th>
                  <Table.Th>Days</Table.Th>
                  <Table.Th>Status</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {leaveRequests.map((r) => (
                  <Table.Tr key={r.id}>
                    <Table.Td>{r.leave_type?.name ?? '—'}</Table.Td>
                    <Table.Td>{formatDate(r.start_date)} – {formatDate(r.end_date)}</Table.Td>
                    <Table.Td>{r.days}</Table.Td>
                    <Table.Td><Badge size="sm" color={statusColors[r.status]}>{r.status}</Badge></Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        )}
      </Paper>
    </Stack>
  );
}

function ProfileField({ label, value }: { label: string; value: string | null | undefined }) {
  return (
    <div>
      <Text size="xs" c="dimmed" tt="uppercase" fw={600}>{label}</Text>
      <Text size="sm">{value || '—'}</Text>
    </div>
  );
}
