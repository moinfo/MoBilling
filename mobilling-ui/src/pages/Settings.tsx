import { useState } from 'react';
import {
  Title, Tabs, TextInput, Textarea, PasswordInput, Select, Button,
  Stack, Divider, Paper, Group, Alert, NumberInput, Switch, Loader, Center, Overlay, Box,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconBuilding, IconUser, IconAlertCircle, IconMail } from '@tabler/icons-react';
import { useAuth } from '../context/AuthContext';
import { updateCompany, updateProfile, CompanyData, ProfileData, getEmailSettings, updateEmailSettings, testEmailSettings, EmailSettings as EmailSettingsType, EmailSettingsFormData } from '../api/settings';
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
          <Tabs.Tab value="email" leftSection={<IconMail size={16} />}>
            Email
          </Tabs.Tab>
        </Tabs.List>

        <Tabs.Panel value="company">
          <CompanyTab user={user} isAdmin={isAdmin} refreshUser={refreshUser} />
        </Tabs.Panel>
        <Tabs.Panel value="profile">
          <ProfileTab user={user} refreshUser={refreshUser} />
        </Tabs.Panel>
        <Tabs.Panel value="email">
          <EmailTab isAdmin={isAdmin} />
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

function EmailTab({ isAdmin }: { isAdmin: boolean }) {
  const queryClient = useQueryClient();

  const { data, isLoading } = useQuery({
    queryKey: ['email-settings'],
    queryFn: getEmailSettings,
  });

  const settings: EmailSettingsType | undefined = data?.data?.data;
  const emailDisabled = settings ? !settings.email_enabled : true;

  const form = useForm<EmailSettingsFormData>({
    initialValues: {
      smtp_host: settings?.smtp_host ?? '',
      smtp_port: settings?.smtp_port ?? 587,
      smtp_username: settings?.smtp_username ?? '',
      smtp_password: '',
      smtp_encryption: settings?.smtp_encryption ?? 'tls',
      smtp_from_email: settings?.smtp_from_email ?? '',
      smtp_from_name: settings?.smtp_from_name ?? '',
    },
  });

  // Re-initialize when data loads
  const [initialized, setInitialized] = useState(false);
  if (settings && !initialized) {
    form.setValues({
      smtp_host: settings.smtp_host ?? '',
      smtp_port: settings.smtp_port ?? 587,
      smtp_username: settings.smtp_username ?? '',
      smtp_password: '',
      smtp_encryption: settings.smtp_encryption ?? 'tls',
      smtp_from_email: settings.smtp_from_email ?? '',
      smtp_from_name: settings.smtp_from_name ?? '',
    });
    setInitialized(true);
  }

  const saveMutation = useMutation({
    mutationFn: (values: EmailSettingsFormData) => updateEmailSettings(values),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['email-settings'] });
      notifications.show({ title: 'Success', message: 'Email settings updated', color: 'green' });
    },
    onError: (err: any) => {
      notifications.show({
        title: 'Error',
        message: err.response?.data?.message || 'Failed to update email settings',
        color: 'red',
      });
    },
  });

  const testMutation = useMutation({
    mutationFn: testEmailSettings,
    onSuccess: (res) => {
      notifications.show({ title: 'Success', message: res.data.message, color: 'green' });
    },
    onError: (err: any) => {
      notifications.show({
        title: 'Test Failed',
        message: err.response?.data?.message || 'Failed to send test email',
        color: 'red',
      });
    },
  });

  if (isLoading) {
    return <Center py="xl"><Loader /></Center>;
  }

  return (
    <Paper p="lg" withBorder maw={600} pos="relative">
      {emailDisabled && (
        <Box pos="absolute" top={0} left={0} right={0} bottom={0} style={{ zIndex: 10 }}>
          <Overlay color="#000" backgroundOpacity={0.03} blur={1} />
          <Alert icon={<IconAlertCircle size={16} />} color="orange" m="md" style={{ position: 'relative', zIndex: 11 }}>
            Email has been disabled by the administrator. Contact your platform admin to enable email delivery.
          </Alert>
        </Box>
      )}

      {!isAdmin && !emailDisabled && (
        <Alert icon={<IconAlertCircle size={16} />} color="yellow" mb="md">
          Only admins can edit email settings.
        </Alert>
      )}

      <form onSubmit={form.onSubmit((values) => saveMutation.mutate(values))}>
        <Stack>
          <TextInput label="SMTP Host" placeholder="smtp.gmail.com" disabled={emailDisabled || !isAdmin} {...form.getInputProps('smtp_host')} />
          <NumberInput label="SMTP Port" placeholder="587" min={1} max={65535} disabled={emailDisabled || !isAdmin} {...form.getInputProps('smtp_port')} />
          <TextInput label="SMTP Username" placeholder="user@example.com" disabled={emailDisabled || !isAdmin} {...form.getInputProps('smtp_username')} />
          <PasswordInput
            label="SMTP Password"
            placeholder={settings?.has_password ? '••••••• (unchanged)' : 'Enter password'}
            disabled={emailDisabled || !isAdmin}
            {...form.getInputProps('smtp_password')}
          />
          <Select
            label="Encryption"
            data={[
              { value: 'tls', label: 'TLS' },
              { value: 'ssl', label: 'SSL' },
              { value: 'none', label: 'None' },
            ]}
            disabled={emailDisabled || !isAdmin}
            {...form.getInputProps('smtp_encryption')}
          />
          <TextInput label="From Email" placeholder="noreply@company.com" disabled={emailDisabled || !isAdmin} {...form.getInputProps('smtp_from_email')} />
          <TextInput label="From Name" placeholder="Company Name" disabled={emailDisabled || !isAdmin} {...form.getInputProps('smtp_from_name')} />

          {isAdmin && !emailDisabled && (
            <Group justify="flex-end">
              <Button
                variant="outline"
                loading={testMutation.isPending}
                onClick={() => testMutation.mutate()}
              >
                Send Test Email
              </Button>
              <Button type="submit" loading={saveMutation.isPending}>Save Settings</Button>
            </Group>
          )}
        </Stack>
      </form>
    </Paper>
  );
}
