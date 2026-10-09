import { useState } from 'react';
import { Stack, Paper, Title, TextInput, Button, Group, PasswordInput, Text, LoadingOverlay } from '@mantine/core';
import { useForm } from '@mantine/form';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { getPortalProfile, updatePortalProfile, updatePortalCompany, changePortalPassword } from '../../api/portal';
import { useAuth } from '../../context/AuthContext';
import TwoFactorSetup from '../../components/TwoFactorSetup';

export default function PortalProfile() {
  const { refreshUser } = useAuth();
  const queryClient = useQueryClient();
  const [changingPassword, setChangingPassword] = useState(false);

  const { data, isLoading } = useQuery({
    queryKey: ['portal-profile'],
    queryFn: () => getPortalProfile(),
  });

  const profile = data?.data;

  const profileForm = useForm({
    initialValues: { name: '', phone: '' },
  });

  // Sync form when data loads
  if (profile && !profileForm.isDirty()) {
    const u = profile.user;
    if (profileForm.values.name !== u.name || profileForm.values.phone !== (u.phone || '')) {
      profileForm.setValues({ name: u.name, phone: u.phone || '' });
    }
  }

  const isPortalAdmin = profile?.user?.role === 'admin';

  const companyForm = useForm({
    initialValues: { name: '', email: '', phone: '', tax_id: '', address: '' },
    validate: {
      name: (v) => (v.trim() ? null : 'Required'),
    },
  });

  // Sync form when data loads — only matters for admins, who get the editable form.
  if (profile && isPortalAdmin && !companyForm.isDirty()) {
    const c = profile.client;
    const next = {
      name: c?.name || '', email: c?.email || '', phone: c?.phone || '',
      tax_id: c?.tax_id || '', address: c?.address || '',
    };
    if (JSON.stringify(next) !== JSON.stringify(companyForm.values)) {
      companyForm.setValues(next);
    }
  }

  const companyMutation = useMutation({
    mutationFn: updatePortalCompany,
    onSuccess: () => {
      notifications.show({ title: 'Success', message: 'Company information updated', color: 'green' });
      queryClient.invalidateQueries({ queryKey: ['portal-profile'] });
    },
    onError: (err: any) => notifications.show({
      title: 'Error',
      message: err.response?.data?.message || 'Failed to update company information',
      color: 'red',
    }),
  });

  const passwordForm = useForm({
    initialValues: { current_password: '', password: '', password_confirmation: '' },
    validate: {
      current_password: (v) => (v.length > 0 ? null : 'Required'),
      password: (v) => (v.length >= 8 ? null : 'Minimum 8 characters'),
      password_confirmation: (v, values) => (v === values.password ? null : 'Passwords do not match'),
    },
  });

  const updateMutation = useMutation({
    mutationFn: updatePortalProfile,
    onSuccess: () => {
      notifications.show({ title: 'Success', message: 'Profile updated', color: 'green' });
      queryClient.invalidateQueries({ queryKey: ['portal-profile'] });
      refreshUser();
    },
  });

  const passwordMutation = useMutation({
    mutationFn: changePortalPassword,
    onSuccess: () => {
      notifications.show({ title: 'Success', message: 'Password changed', color: 'green' });
      passwordForm.reset();
      setChangingPassword(false);
    },
    onError: (err: any) => {
      notifications.show({
        title: 'Error',
        message: err.response?.data?.message || 'Failed to change password',
        color: 'red',
      });
    },
  });

  return (
    <Stack gap="lg" pos="relative">
      <LoadingOverlay visible={isLoading} />
      <Title order={3}>Profile</Title>

      {profile && (
        <>
          <Paper withBorder p="md">
            <Text fw={600} mb="md">Company Information</Text>
            {isPortalAdmin ? (
              <form onSubmit={companyForm.onSubmit((values) => companyMutation.mutate(values))}>
                <Stack gap="sm">
                  <Group grow>
                    <TextInput label="Company Name" required {...companyForm.getInputProps('name')} />
                    <TextInput label="Email" {...companyForm.getInputProps('email')} />
                  </Group>
                  <Group grow>
                    <TextInput label="Phone" {...companyForm.getInputProps('phone')} />
                    <TextInput label="Tax ID" {...companyForm.getInputProps('tax_id')} />
                  </Group>
                  <TextInput label="Address" {...companyForm.getInputProps('address')} />
                  <Group>
                    <Button type="submit" loading={companyMutation.isPending}>Save Company Information</Button>
                  </Group>
                </Stack>
              </form>
            ) : (
              <>
                <Group gap="xl">
                  <div>
                    <Text size="xs" c="dimmed">Company Name</Text>
                    <Text fw={500} tt="uppercase">{profile.client?.name}</Text>
                  </div>
                  <div>
                    <Text size="xs" c="dimmed">Email</Text>
                    <Text fw={500}>{profile.client?.email || '-'}</Text>
                  </div>
                  <div>
                    <Text size="xs" c="dimmed">Phone</Text>
                    <Text fw={500}>{profile.client?.phone || '-'}</Text>
                  </div>
                  <div>
                    <Text size="xs" c="dimmed">Tax ID</Text>
                    <Text fw={500}>{profile.client?.tax_id || '-'}</Text>
                  </div>
                </Group>
                {profile.client?.address && (
                  <div style={{ marginTop: 8 }}>
                    <Text size="xs" c="dimmed">Address</Text>
                    <Text fw={500}>{profile.client.address}</Text>
                  </div>
                )}
                <Text size="xs" c="dimmed" mt="sm">Only a portal admin on this account can edit company information.</Text>
              </>
            )}
          </Paper>

          <Paper withBorder p="md">
            <Text fw={600} mb="md">Your Details</Text>
            <form onSubmit={profileForm.onSubmit((values) => updateMutation.mutate(values))}>
              <Group grow>
                <TextInput label="Name" {...profileForm.getInputProps('name')} />
                <TextInput label="Phone" {...profileForm.getInputProps('phone')} />
              </Group>
              <TextInput label="Email" value={profile.user.email} disabled mt="sm" />
              <Button type="submit" mt="md" loading={updateMutation.isPending}>
                Update Profile
              </Button>
            </form>
          </Paper>

          <Paper withBorder p="md">
            <Group justify="space-between" mb="md">
              <Text fw={600}>Change Password</Text>
              {!changingPassword && (
                <Button variant="light" size="xs" onClick={() => setChangingPassword(true)}>
                  Change Password
                </Button>
              )}
            </Group>
            {changingPassword && (
              <form onSubmit={passwordForm.onSubmit((values) => passwordMutation.mutate(values))}>
                <Stack gap="sm">
                  <PasswordInput label="Current Password" {...passwordForm.getInputProps('current_password')} />
                  <PasswordInput label="New Password" {...passwordForm.getInputProps('password')} />
                  <PasswordInput label="Confirm Password" {...passwordForm.getInputProps('password_confirmation')} />
                  <Group>
                    <Button type="submit" loading={passwordMutation.isPending}>Change Password</Button>
                    <Button variant="subtle" onClick={() => { setChangingPassword(false); passwordForm.reset(); }}>
                      Cancel
                    </Button>
                  </Group>
                </Stack>
              </form>
            )}
          </Paper>

          <TwoFactorSetup />
        </>
      )}
    </Stack>
  );
}
