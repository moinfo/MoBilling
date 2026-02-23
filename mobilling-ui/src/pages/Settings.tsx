import { useState } from 'react';
import {
  Title, Tabs, TextInput, Textarea, PasswordInput, Select, Button,
  Stack, Divider, Paper, Group, Alert,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { notifications } from '@mantine/notifications';
import { IconBuilding, IconUser, IconAlertCircle } from '@tabler/icons-react';
import { useAuth } from '../context/AuthContext';
import { updateCompany, updateProfile, CompanyData, ProfileData } from '../api/settings';
import axios from 'axios';

const CURRENCIES = [
  { value: 'KES', label: 'KES - Kenya Shilling' },
  { value: 'USD', label: 'USD - US Dollar' },
  { value: 'EUR', label: 'EUR - Euro' },
  { value: 'GBP', label: 'GBP - British Pound' },
  { value: 'TZS', label: 'TZS - Tanzania Shilling' },
  { value: 'UGX', label: 'UGX - Uganda Shilling' },
];

export default function Settings() {
  const { user, refreshUser } = useAuth();
  const isAdmin = user?.role === 'admin';

  return (
    <>
      <Title order={2} mb="lg">Settings</Title>
      <Tabs defaultValue="company">
        <Tabs.List mb="md">
          <Tabs.Tab value="company" leftSection={<IconBuilding size={16} />}>
            Company Profile
          </Tabs.Tab>
          <Tabs.Tab value="profile" leftSection={<IconUser size={16} />}>
            My Profile
          </Tabs.Tab>
        </Tabs.List>

        <Tabs.Panel value="company">
          <CompanyTab user={user} isAdmin={isAdmin} refreshUser={refreshUser} />
        </Tabs.Panel>
        <Tabs.Panel value="profile">
          <ProfileTab user={user} refreshUser={refreshUser} />
        </Tabs.Panel>
      </Tabs>
    </>
  );
}

function CompanyTab({ user, isAdmin, refreshUser }: {
  user: ReturnType<typeof useAuth>['user'];
  isAdmin: boolean;
  refreshUser: () => Promise<void>;
}) {
  const [loading, setLoading] = useState(false);

  const form = useForm<CompanyData>({
    initialValues: {
      name: user?.tenant.name || '',
      email: user?.tenant.email || '',
      phone: user?.tenant.phone || '',
      address: user?.tenant.address || '',
      tax_id: user?.tenant.tax_id || '',
      currency: user?.tenant.currency || 'KES',
    },
    validate: {
      name: (v) => (v.trim() ? null : 'Company name is required'),
      email: (v) => (/^\S+@\S+\.\S+$/.test(v) ? null : 'Valid email is required'),
      currency: (v) => (v ? null : 'Currency is required'),
    },
  });

  const handleSubmit = async (values: CompanyData) => {
    setLoading(true);
    try {
      await updateCompany(values);
      await refreshUser();
      notifications.show({ title: 'Success', message: 'Company profile updated', color: 'green' });
    } catch (err) {
      if (axios.isAxiosError(err) && err.response?.status === 403) {
        notifications.show({ title: 'Forbidden', message: 'Only admins can update company settings', color: 'red' });
      } else {
        notifications.show({ title: 'Error', message: 'Failed to update company profile', color: 'red' });
      }
    } finally {
      setLoading(false);
    }
  };

  return (
    <Paper p="lg" withBorder maw={600}>
      {!isAdmin && (
        <Alert icon={<IconAlertCircle size={16} />} color="yellow" mb="md">
          Only admins can edit company settings.
        </Alert>
      )}
      <form onSubmit={form.onSubmit(handleSubmit)}>
        <Stack>
          <TextInput label="Company Name" required disabled={!isAdmin} {...form.getInputProps('name')} />
          <TextInput label="Email" required disabled={!isAdmin} {...form.getInputProps('email')} />
          <TextInput label="Phone" disabled={!isAdmin} {...form.getInputProps('phone')} />
          <Textarea label="Address" autosize minRows={2} disabled={!isAdmin} {...form.getInputProps('address')} />
          <TextInput label="KRA PIN / Tax ID" disabled={!isAdmin} {...form.getInputProps('tax_id')} />
          <Select label="Currency" required data={CURRENCIES} disabled={!isAdmin} {...form.getInputProps('currency')} />
          {isAdmin && (
            <Group justify="flex-end">
              <Button type="submit" loading={loading}>Save Company</Button>
            </Group>
          )}
        </Stack>
      </form>
    </Paper>
  );
}

function ProfileTab({ user, refreshUser }: {
  user: ReturnType<typeof useAuth>['user'];
  refreshUser: () => Promise<void>;
}) {
  const [loading, setLoading] = useState(false);

  const form = useForm({
    initialValues: {
      name: user?.name || '',
      email: user?.email || '',
      phone: user?.phone || '',
      current_password: '',
      password: '',
      password_confirmation: '',
    },
    validate: {
      name: (v) => (v.trim() ? null : 'Name is required'),
      email: (v) => (/^\S+@\S+\.\S+$/.test(v) ? null : 'Valid email is required'),
      password: (v, values) => {
        if (!v) return null;
        if (v.length < 8) return 'Password must be at least 8 characters';
        if (!values.current_password) return 'Current password is required to set a new password';
        return null;
      },
      password_confirmation: (v, values) => {
        if (!values.password) return null;
        return v === values.password ? null : 'Passwords do not match';
      },
    },
  });

  const handleSubmit = async (values: typeof form.values) => {
    setLoading(true);
    try {
      const payload: ProfileData = {
        name: values.name,
        email: values.email,
        phone: values.phone || null,
      };
      if (values.password) {
        payload.current_password = values.current_password;
        payload.password = values.password;
        payload.password_confirmation = values.password_confirmation;
      }
      await updateProfile(payload);
      await refreshUser();
      form.setFieldValue('current_password', '');
      form.setFieldValue('password', '');
      form.setFieldValue('password_confirmation', '');
      notifications.show({ title: 'Success', message: 'Profile updated', color: 'green' });
    } catch (err) {
      if (axios.isAxiosError(err) && err.response?.data?.errors) {
        const errors = err.response.data.errors as Record<string, string[]>;
        Object.entries(errors).forEach(([field, msgs]) => {
          form.setFieldError(field, msgs[0]);
        });
      } else {
        notifications.show({ title: 'Error', message: 'Failed to update profile', color: 'red' });
      }
    } finally {
      setLoading(false);
    }
  };

  return (
    <Paper p="lg" withBorder maw={600}>
      <form onSubmit={form.onSubmit(handleSubmit)}>
        <Stack>
          <TextInput label="Name" required {...form.getInputProps('name')} />
          <TextInput label="Email" required {...form.getInputProps('email')} />
          <TextInput label="Phone" {...form.getInputProps('phone')} />

          <Divider label="Change Password" labelPosition="left" mt="sm" />

          <PasswordInput label="Current Password" {...form.getInputProps('current_password')} />
          <PasswordInput label="New Password" {...form.getInputProps('password')} />
          <PasswordInput label="Confirm Password" {...form.getInputProps('password_confirmation')} />

          <Group justify="flex-end">
            <Button type="submit" loading={loading}>Save Profile</Button>
          </Group>
        </Stack>
      </form>
    </Paper>
  );
}
