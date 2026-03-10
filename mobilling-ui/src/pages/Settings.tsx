import { useState } from 'react';
import {
  Title, Tabs, TextInput, Textarea, PasswordInput, Select, Button,
  Stack, Divider, Paper, Group, Alert, NumberInput, Switch, Loader, Center, Box,
  FileButton, Image, Text, Badge, ActionIcon, Accordion, ThemeIcon, Tooltip,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconBuilding, IconUser, IconAlertCircle, IconMail, IconBell, IconTemplate, IconCreditCard, IconPlus, IconTrash, IconBrandCashapp, IconBrandWhatsapp } from '@tabler/icons-react';
import { useAuth } from '../context/AuthContext';
import { usePermissions } from '../hooks/usePermissions';
import {
  updateCompany, updateProfile, uploadLogo,
  CompanyData, ProfileData,
  getEmailSettings, updateEmailSettings, testEmailSettings,
  EmailSettings as EmailSettingsType, EmailSettingsFormData,
  getReminderSettings, updateReminderSettings, ReminderSettings,
  getTemplates, updateTemplates, TemplateSettings,
  getPaymentMethods, updatePaymentMethods, PaymentMethod,
  getSubscriptionSettings, updateSubscriptionSettings, SubscriptionSettings,
  getPesapalSettings, updatePesapalSettings, PesapalSettings,
  getWhatsAppSettings, updateWhatsAppSettings, WhatsAppSettings,
} from '../api/settings';
import { getActiveCurrencies } from '../api/admin';
import axios from 'axios';

export default function Settings() {
  const { user, refreshUser } = useAuth();
  const { can } = usePermissions();

  const canCompany = can('settings.company');
  const canEmail = can('settings.email');
  const canReminders = can('settings.reminders');
  const canTemplates = can('settings.templates');
  const canPaymentMethods = can('settings.payment_methods');

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
          <Tabs.Tab value="reminders" leftSection={<IconBell size={16} />}>
            Reminders
          </Tabs.Tab>
          <Tabs.Tab value="templates" leftSection={<IconTemplate size={16} />}>
            Templates
          </Tabs.Tab>
          <Tabs.Tab value="payment-methods" leftSection={<IconCreditCard size={16} />}>
            Payment Methods
          </Tabs.Tab>
          {canReminders && (
            <Tabs.Tab value="whatsapp" leftSection={<IconBrandWhatsapp size={16} />}>
              WhatsApp
            </Tabs.Tab>
          )}
          {canCompany && (
            <Tabs.Tab value="pesapal" leftSection={<IconBrandCashapp size={16} />}>
              Pesapal
            </Tabs.Tab>
          )}
        </Tabs.List>

        <Tabs.Panel value="company">
          <CompanyTab user={user} isAdmin={canCompany} refreshUser={refreshUser} />
        </Tabs.Panel>
        <Tabs.Panel value="profile">
          <ProfileTab user={user} refreshUser={refreshUser} />
        </Tabs.Panel>
        <Tabs.Panel value="email">
          <EmailTab isAdmin={canEmail} />
        </Tabs.Panel>
        <Tabs.Panel value="reminders">
          <RemindersTab isAdmin={canReminders} />
        </Tabs.Panel>
        <Tabs.Panel value="templates">
          <TemplatesTab isAdmin={canTemplates} />
        </Tabs.Panel>
        <Tabs.Panel value="payment-methods">
          <PaymentMethodsTab isAdmin={canPaymentMethods} />
        </Tabs.Panel>
        <Tabs.Panel value="whatsapp">
          <WhatsAppTab isAdmin={canReminders} />
        </Tabs.Panel>
        <Tabs.Panel value="pesapal">
          <PesapalTab isAdmin={canCompany} />
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
  const [logoUploading, setLogoUploading] = useState(false);

  const { data: currencyData } = useQuery({
    queryKey: ['active-currencies'],
    queryFn: getActiveCurrencies,
  });
  const currencyOptions = (currencyData?.data?.data || []).map((c) => ({
    value: c.code,
    label: `${c.code} - ${c.name}`,
  }));

  const form = useForm<CompanyData>({
    initialValues: {
      name: user?.tenant?.name || '',
      email: user?.tenant?.email || '',
      phone: user?.tenant?.phone || '',
      address: user?.tenant?.address || '',
      tax_id: user?.tenant?.tax_id || '',
      currency: user?.tenant?.currency || 'TZS',
      website: user?.tenant?.website || '',
      bank_name: user?.tenant?.bank_name || '',
      bank_account_name: user?.tenant?.bank_account_name || '',
      bank_account_number: user?.tenant?.bank_account_number || '',
      bank_branch: user?.tenant?.bank_branch || '',
      payment_instructions: user?.tenant?.payment_instructions || '',
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

  const handleLogoUpload = async (file: File | null) => {
    if (!file) return;
    setLogoUploading(true);
    try {
      await uploadLogo(file);
      await refreshUser();
      notifications.show({ title: 'Success', message: 'Logo uploaded successfully', color: 'green' });
    } catch {
      notifications.show({ title: 'Error', message: 'Failed to upload logo', color: 'red' });
    } finally {
      setLogoUploading(false);
    }
  };

  return (
    <Paper p="lg" withBorder maw={600}>
      {!isAdmin && (
        <Alert icon={<IconAlertCircle size={16} />} color="yellow" mb="md">
          Only admins can edit company settings.
        </Alert>
      )}

      {/* Logo Upload */}
      <Stack mb="md">
        <Text fw={500} size="sm">Company Logo</Text>
        {user?.tenant?.logo_url && (
          <Image src={user.tenant.logo_url} alt="Company logo" maw={200} mah={80} fit="contain" />
        )}
        {isAdmin && (
          <FileButton onChange={handleLogoUpload} accept="image/jpeg,image/png,image/webp">
            {(props) => (
              <Button variant="outline" size="xs" loading={logoUploading} {...props}>
                {user?.tenant?.logo_url ? 'Change Logo' : 'Upload Logo'}
              </Button>
            )}
          </FileButton>
        )}
        <Text size="xs" c="dimmed">JPEG, PNG or WebP, max 2MB</Text>
      </Stack>

      <Divider mb="md" />

      <form onSubmit={form.onSubmit(handleSubmit)}>
        <Stack>
          <TextInput label="Company Name" required disabled={!isAdmin} {...form.getInputProps('name')} />
          <TextInput label="Email" required disabled={!isAdmin} {...form.getInputProps('email')} />
          <TextInput label="Phone" disabled={!isAdmin} {...form.getInputProps('phone')} />
          <TextInput label="Website" placeholder="https://example.com" disabled={!isAdmin} {...form.getInputProps('website')} />
          <Textarea label="Address" autosize minRows={2} disabled={!isAdmin} {...form.getInputProps('address')} />
          <TextInput label="KRA PIN / Tax ID" disabled={!isAdmin} {...form.getInputProps('tax_id')} />
          <Select label="Currency" required data={currencyOptions} searchable disabled={!isAdmin} {...form.getInputProps('currency')} />

          <Divider label="Bank Details" labelPosition="left" mt="sm" />

          <TextInput label="Bank Name" placeholder="e.g. Equity Bank" disabled={!isAdmin} {...form.getInputProps('bank_name')} />
          <TextInput label="Account Name" disabled={!isAdmin} {...form.getInputProps('bank_account_name')} />
          <TextInput label="Account Number" disabled={!isAdmin} {...form.getInputProps('bank_account_number')} />
          <TextInput label="Branch" disabled={!isAdmin} {...form.getInputProps('bank_branch')} />
          <Textarea
            label="Payment Instructions"
            placeholder="e.g. M-Pesa Paybill 123456, Account: Invoice Number"
            autosize
            minRows={2}
            disabled={!isAdmin}
            {...form.getInputProps('payment_instructions')}
          />

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
  const hasCustomSmtp = !!(settings?.smtp_host);

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

  const fieldsDisabled = !isAdmin;

  return (
    <Paper p="lg" withBorder maw={600}>
      <Alert icon={<IconAlertCircle size={16} />} color={hasCustomSmtp ? 'green' : 'blue'} mb="md" variant="light">
        {hasCustomSmtp
          ? 'Using your custom SMTP configuration for sending emails.'
          : 'Leave blank to use the platform default email. Configure your own SMTP to send emails from your domain.'}
      </Alert>

      {!isAdmin && (
        <Alert icon={<IconAlertCircle size={16} />} color="yellow" mb="md">
          Only admins can edit email settings.
        </Alert>
      )}

      <form onSubmit={form.onSubmit((values) => saveMutation.mutate(values))}>
        <fieldset disabled={fieldsDisabled} style={{ border: 'none', padding: 0, margin: 0, opacity: fieldsDisabled ? 0.6 : 1 }}>
          <Stack>
            <TextInput label="SMTP Host" placeholder="smtp.gmail.com" {...form.getInputProps('smtp_host')} />
            <NumberInput label="SMTP Port" placeholder="587" min={1} max={65535} {...form.getInputProps('smtp_port')} />
            <TextInput label="SMTP Username" placeholder="user@example.com" {...form.getInputProps('smtp_username')} />
            <PasswordInput
              label="SMTP Password"
              placeholder={settings?.has_password ? '••••••• (unchanged)' : 'Enter password'}
              {...form.getInputProps('smtp_password')}
            />
            <Select
              label="Encryption"
              data={[
                { value: 'tls', label: 'TLS' },
                { value: 'ssl', label: 'SSL' },
                { value: 'none', label: 'None' },
              ]}
              {...form.getInputProps('smtp_encryption')}
            />
            <TextInput label="From Email" placeholder="noreply@company.com" {...form.getInputProps('smtp_from_email')} />
            <TextInput label="From Name" placeholder="Company Name" {...form.getInputProps('smtp_from_name')} />

            {isAdmin && (
              <Group justify="flex-end">
                <Button
                  variant="outline"
                  loading={testMutation.isPending}
                  onClick={() => testMutation.mutate()}
                  disabled={!hasCustomSmtp}
                >
                  Send Test Email
                </Button>
                <Button type="submit" loading={saveMutation.isPending}>Save Settings</Button>
              </Group>
            )}
          </Stack>
        </fieldset>
      </form>
    </Paper>
  );
}

function RemindersTab({ isAdmin }: { isAdmin: boolean }) {
  const queryClient = useQueryClient();

  const { data, isLoading } = useQuery({
    queryKey: ['reminder-settings'],
    queryFn: getReminderSettings,
  });

  const settings: ReminderSettings | undefined = data?.data?.data;

  const form = useForm<ReminderSettings>({
    initialValues: { email_enabled: true, sms_enabled: false, reminder_sms_enabled: false, reminder_email_enabled: true, whatsapp_enabled: false, reminder_whatsapp_enabled: false },
  });

  const [initialized, setInitialized] = useState(false);
  if (settings && !initialized) {
    form.setValues({
      email_enabled: settings.email_enabled,
      sms_enabled: settings.sms_enabled,
      reminder_sms_enabled: settings.reminder_sms_enabled,
      reminder_email_enabled: settings.reminder_email_enabled,
      whatsapp_enabled: settings.whatsapp_enabled,
      reminder_whatsapp_enabled: settings.reminder_whatsapp_enabled,
    });
    setInitialized(true);
  }

  const saveMutation = useMutation({
    mutationFn: (values: ReminderSettings) => updateReminderSettings(values),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['reminder-settings'] });
      notifications.show({ title: 'Success', message: 'Reminder settings updated', color: 'green' });
    },
    onError: (err: any) => {
      notifications.show({
        title: 'Error',
        message: err.response?.data?.message || 'Failed to update reminder settings',
        color: 'red',
      });
    },
  });

  // --- Subscription auto-suspension settings ---
  const { data: subData, isLoading: subLoading } = useQuery({
    queryKey: ['subscription-settings'],
    queryFn: getSubscriptionSettings,
  });

  const subSettings: SubscriptionSettings | undefined = subData?.data?.data;
  const [graceDays, setGraceDays] = useState<number | string>(7);
  const [subInitialized, setSubInitialized] = useState(false);

  if (subSettings && !subInitialized) {
    setGraceDays(subSettings.subscription_grace_days);
    setSubInitialized(true);
  }

  const subSaveMutation = useMutation({
    mutationFn: (data: SubscriptionSettings) => updateSubscriptionSettings(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['subscription-settings'] });
      notifications.show({ title: 'Success', message: 'Subscription settings updated', color: 'green' });
    },
    onError: (err: any) => {
      notifications.show({
        title: 'Error',
        message: err.response?.data?.message || 'Failed to update subscription settings',
        color: 'red',
      });
    },
  });

  if (isLoading || subLoading) {
    return <Center py="xl"><Loader /></Center>;
  }

  return (
    <Paper p="lg" withBorder maw={600}>
      {!isAdmin && (
        <Alert icon={<IconAlertCircle size={16} />} color="yellow" mb="md">
          Only admins can edit reminder settings.
        </Alert>
      )}

      <form onSubmit={form.onSubmit((values) => saveMutation.mutate(values))}>
        <Stack>
          <Text fw={600} size="sm">System-wide Notifications</Text>
          <Text size="xs" c="dimmed">
            Master switches — when off, no emails or SMS are sent to customers at all (invoices, reminders, receipts, etc.)
          </Text>
          <Switch
            label="Email notifications enabled"
            description="Send emails to customers (invoices, reminders, receipts, warnings)"
            disabled={!isAdmin}
            checked={form.values.email_enabled}
            onChange={(e) => form.setFieldValue('email_enabled', e.currentTarget.checked)}
          />
          <Switch
            label="SMS notifications enabled"
            description="Send SMS to customers (invoices, reminders, warnings)"
            disabled={!isAdmin}
            checked={form.values.sms_enabled}
            onChange={(e) => form.setFieldValue('sms_enabled', e.currentTarget.checked)}
          />
          <Switch
            label="WhatsApp notifications enabled"
            description="Send WhatsApp messages to customers (reminders, payment alerts)"
            disabled={!isAdmin}
            checked={form.values.whatsapp_enabled}
            onChange={(e) => form.setFieldValue('whatsapp_enabled', e.currentTarget.checked)}
          />

          <Divider my="xs" label="Automatic Reminders" labelPosition="left" />

          <Switch
            label="Email reminders enabled"
            description="Send email reminders for upcoming and overdue bills"
            disabled={!isAdmin || !form.values.email_enabled}
            checked={form.values.reminder_email_enabled}
            onChange={(e) => form.setFieldValue('reminder_email_enabled', e.currentTarget.checked)}
          />
          <Switch
            label="SMS reminders enabled"
            description="Send SMS reminders for upcoming and overdue bills"
            disabled={!isAdmin || !form.values.sms_enabled}
            checked={form.values.reminder_sms_enabled}
            onChange={(e) => form.setFieldValue('reminder_sms_enabled', e.currentTarget.checked)}
          />
          <Switch
            label="WhatsApp reminders enabled"
            description="Send WhatsApp reminders for upcoming and overdue invoices"
            disabled={!isAdmin || !form.values.whatsapp_enabled}
            checked={form.values.reminder_whatsapp_enabled}
            onChange={(e) => form.setFieldValue('reminder_whatsapp_enabled', e.currentTarget.checked)}
          />

          <Alert variant="light" color="blue" icon={<IconAlertCircle size={16} />}>
            <Text size="sm">Edit message templates in the <strong>Templates</strong> tab.</Text>
          </Alert>

          {isAdmin && (
            <Group justify="flex-end">
              <Button type="submit" loading={saveMutation.isPending}>Save Settings</Button>
            </Group>
          )}
        </Stack>
      </form>

      <Divider my="lg" label="Subscription Auto-Suspension" labelPosition="left" />

      <Stack>
        <Text size="sm" c="dimmed">
          Automatically suspend client subscriptions when their invoice remains unpaid past the grace period.
          Subscriptions are reactivated automatically when the invoice is paid.
        </Text>

        <NumberInput
          label="Grace period (days)"
          description="Number of days after invoice due date before the subscription is suspended"
          min={1}
          max={90}
          value={graceDays}
          onChange={(val) => setGraceDays(val)}
          disabled={!isAdmin}
          maw={200}
        />

        {isAdmin && (
          <Group justify="flex-end">
            <Button
              loading={subSaveMutation.isPending}
              onClick={() => subSaveMutation.mutate({ subscription_grace_days: Number(graceDays) || 7 })}
            >
              Save Subscription Settings
            </Button>
          </Group>
        )}
      </Stack>
    </Paper>
  );
}

// --- Templates Tab ---

const DEFAULT_REMINDER_TEMPLATES = {
  reminder_email_subject: 'Reminder: {bill_name} due on {due_date}',
  reminder_email_body: '{bill_name} of {currency} {amount} is due on {due_date}. Please pay on time.',
  overdue_email_subject: 'OVERDUE: {bill_name} — {company_name}',
  overdue_email_body: '{bill_name} of {currency} {amount} was due on {due_date}. This bill is now overdue. Please pay immediately.',
  reminder_sms_body: '{bill_name} of {currency} {amount} is due on {due_date}. Please pay on time.',
  overdue_sms_body: 'OVERDUE: {bill_name} of {currency} {amount} was due {due_date}. Pay immediately.',
};

const DEFAULT_INVOICE_TEMPLATES = {
  invoice_email_subject: '{doc_type} {doc_number} — {company_name}',
  invoice_email_body: 'Hello {client_name},\n\nPlease find attached your {doc_type}.\n\nAmount: {currency} {amount}\nDue date: {due_date}\n\nThank you for your business.',
};

const DEFAULT_TEMPLATES: TemplateSettings = {
  ...DEFAULT_REMINDER_TEMPLATES,
  ...DEFAULT_INVOICE_TEMPLATES,
  email_footer_text: null,
};

function TemplatesTab({ isAdmin }: { isAdmin: boolean }) {
  const queryClient = useQueryClient();

  const { data, isLoading } = useQuery({
    queryKey: ['template-settings'],
    queryFn: getTemplates,
  });

  const settings: TemplateSettings | undefined = data?.data?.data;

  const form = useForm<TemplateSettings>({
    initialValues: { ...DEFAULT_TEMPLATES },
  });

  const [initialized, setInitialized] = useState(false);
  if (settings && !initialized) {
    form.setValues({
      invoice_email_subject: settings.invoice_email_subject ?? DEFAULT_TEMPLATES.invoice_email_subject,
      invoice_email_body: settings.invoice_email_body ?? DEFAULT_TEMPLATES.invoice_email_body,
      reminder_email_subject: settings.reminder_email_subject ?? DEFAULT_TEMPLATES.reminder_email_subject,
      reminder_email_body: settings.reminder_email_body ?? DEFAULT_TEMPLATES.reminder_email_body,
      overdue_email_subject: settings.overdue_email_subject ?? DEFAULT_TEMPLATES.overdue_email_subject,
      overdue_email_body: settings.overdue_email_body ?? DEFAULT_TEMPLATES.overdue_email_body,
      reminder_sms_body: settings.reminder_sms_body ?? DEFAULT_TEMPLATES.reminder_sms_body,
      overdue_sms_body: settings.overdue_sms_body ?? DEFAULT_TEMPLATES.overdue_sms_body,
      email_footer_text: settings.email_footer_text ?? DEFAULT_TEMPLATES.email_footer_text,
    });
    setInitialized(true);
  }

  const saveMutation = useMutation({
    mutationFn: (values: TemplateSettings) => updateTemplates(values),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['template-settings'] });
      notifications.show({ title: 'Success', message: 'Templates updated', color: 'green' });
    },
    onError: (err: any) => {
      notifications.show({
        title: 'Error',
        message: err.response?.data?.message || 'Failed to update templates',
        color: 'red',
      });
    },
  });

  const handleResetDefaults = () => {
    form.setValues({ ...DEFAULT_TEMPLATES });
  };

  if (isLoading) {
    return <Center py="xl"><Loader /></Center>;
  }

  return (
    <Paper p="lg" withBorder maw={700}>
      {!isAdmin && (
        <Alert icon={<IconAlertCircle size={16} />} color="yellow" mb="md">
          Only admins can edit templates.
        </Alert>
      )}

      <form onSubmit={form.onSubmit((values) => saveMutation.mutate(values))}>
        <Stack>
          {/* Section 0: Email Branding */}
          <Divider label="Email Branding" labelPosition="left" />

          <Alert variant="light" color="gray" icon={<IconAlertCircle size={16} />}>
            <Text size="sm">
              Your company logo and name appear in the email header automatically.
              Customize the footer text below, or leave blank for the default: "© {new Date().getFullYear()} Your Company. All rights reserved."
            </Text>
          </Alert>

          <Textarea
            label="Email Footer Text"
            placeholder="e.g. 123 Business St, Nairobi · +254 700 123456 · info@company.com"
            autosize
            minRows={2}
            maxLength={500}
            disabled={!isAdmin}
            {...form.getInputProps('email_footer_text')}
          />

          {/* Section 1: Invoice / Quote Email */}
          <Divider label="Invoice / Quote Email" labelPosition="left" mt="md" />

          <Alert variant="light" color="blue" icon={<IconAlertCircle size={16} />}>
            <Text size="sm">
              Placeholders: <Badge size="xs" variant="light">{'{doc_type}'}</Badge>{' '}
              <Badge size="xs" variant="light">{'{doc_number}'}</Badge>{' '}
              <Badge size="xs" variant="light">{'{client_name}'}</Badge>{' '}
              <Badge size="xs" variant="light">{'{amount}'}</Badge>{' '}
              <Badge size="xs" variant="light">{'{currency}'}</Badge>{' '}
              <Badge size="xs" variant="light">{'{due_date}'}</Badge>{' '}
              <Badge size="xs" variant="light">{'{company_name}'}</Badge>
            </Text>
          </Alert>

          <TextInput
            label="Subject"
            disabled={!isAdmin}
            {...form.getInputProps('invoice_email_subject')}
          />
          <Textarea
            label="Body"
            autosize
            minRows={4}
            disabled={!isAdmin}
            {...form.getInputProps('invoice_email_body')}
          />

          {/* Section 2: Bill Reminder Email & SMS */}
          <Divider label="Bill Reminder Email & SMS" labelPosition="left" mt="md" />

          <Alert variant="light" color="blue" icon={<IconAlertCircle size={16} />}>
            <Text size="sm">
              Placeholders: <Badge size="xs" variant="light">{'{bill_name}'}</Badge>{' '}
              <Badge size="xs" variant="light">{'{amount}'}</Badge>{' '}
              <Badge size="xs" variant="light">{'{currency}'}</Badge>{' '}
              <Badge size="xs" variant="light">{'{due_date}'}</Badge>{' '}
              <Badge size="xs" variant="light">{'{company_name}'}</Badge>
            </Text>
          </Alert>

          <TextInput
            label="Due Reminder — Subject"
            disabled={!isAdmin}
            {...form.getInputProps('reminder_email_subject')}
          />
          <Textarea
            label="Due Reminder — Body"
            autosize
            minRows={3}
            disabled={!isAdmin}
            {...form.getInputProps('reminder_email_body')}
          />
          <TextInput
            label="Overdue — Subject"
            disabled={!isAdmin}
            {...form.getInputProps('overdue_email_subject')}
          />
          <Textarea
            label="Overdue — Body"
            autosize
            minRows={3}
            disabled={!isAdmin}
            {...form.getInputProps('overdue_email_body')}
          />

          <Divider label="SMS Templates" labelPosition="left" />

          <Box>
            <Textarea
              label="Due Reminder SMS"
              autosize
              minRows={2}
              maxLength={160}
              disabled={!isAdmin}
              {...form.getInputProps('reminder_sms_body')}
            />
            <Text size="xs" c="dimmed" ta="right">
              {(form.values.reminder_sms_body || '').length}/160
            </Text>
          </Box>

          <Box>
            <Textarea
              label="Overdue SMS"
              autosize
              minRows={2}
              maxLength={160}
              disabled={!isAdmin}
              {...form.getInputProps('overdue_sms_body')}
            />
            <Text size="xs" c="dimmed" ta="right">
              {(form.values.overdue_sms_body || '').length}/160
            </Text>
          </Box>

          {isAdmin && (
            <Group justify="space-between">
              <Button variant="subtle" color="gray" onClick={handleResetDefaults}>
                Reset to Defaults
              </Button>
              <Button type="submit" loading={saveMutation.isPending}>Save Templates</Button>
            </Group>
          )}
        </Stack>
      </form>
    </Paper>
  );
}

// --- Payment Methods Tab ---

function PaymentMethodsTab({ isAdmin }: { isAdmin: boolean }) {
  const queryClient = useQueryClient();
  const [methods, setMethods] = useState<PaymentMethod[]>([]);
  const [initialized, setInitialized] = useState(false);

  const { data, isLoading } = useQuery({
    queryKey: ['payment-methods'],
    queryFn: getPaymentMethods,
  });

  if (data?.data?.data && !initialized) {
    setMethods(data.data.data);
    setInitialized(true);
  }

  const saveMutation = useMutation({
    mutationFn: () => updatePaymentMethods(methods),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['payment-methods'] });
      notifications.show({ title: 'Success', message: 'Payment methods updated', color: 'green' });
    },
    onError: (err: any) => {
      notifications.show({
        title: 'Error',
        message: err.response?.data?.message || 'Failed to update payment methods',
        color: 'red',
      });
    },
  });

  const addMethod = () => {
    setMethods([...methods, { value: '', label: '', details: [] }]);
  };

  const removeMethod = (index: number) => {
    setMethods(methods.filter((_, i) => i !== index));
  };

  const updateMethodField = (index: number, field: 'value' | 'label', val: string) => {
    const updated = [...methods];
    updated[index] = { ...updated[index], [field]: val };
    if (field === 'label') {
      const autoValue = val.toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '');
      const oldAuto = methods[index]?.label
        ? methods[index].label.toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '')
        : '';
      if (!methods[index]?.value || methods[index].value === oldAuto) {
        updated[index].value = autoValue;
      }
    }
    setMethods(updated);
  };

  // Details management
  const addDetail = (methodIndex: number) => {
    const updated = [...methods];
    const details = [...(updated[methodIndex].details || []), { key: '', value: '' }];
    updated[methodIndex] = { ...updated[methodIndex], details };
    setMethods(updated);
  };

  const removeDetail = (methodIndex: number, detailIndex: number) => {
    const updated = [...methods];
    const details = (updated[methodIndex].details || []).filter((_, i) => i !== detailIndex);
    updated[methodIndex] = { ...updated[methodIndex], details };
    setMethods(updated);
  };

  const updateDetail = (methodIndex: number, detailIndex: number, field: 'key' | 'value', val: string) => {
    const updated = [...methods];
    const details = [...(updated[methodIndex].details || [])];
    details[detailIndex] = { ...details[detailIndex], [field]: val };
    updated[methodIndex] = { ...updated[methodIndex], details };
    setMethods(updated);
  };

  const canSave = methods.length > 0 && methods.every((m) => m.value.trim() && m.label.trim());

  if (isLoading) {
    return <Center py="xl"><Loader /></Center>;
  }

  return (
    <Paper p="lg" withBorder maw={700}>
      {!isAdmin && (
        <Alert icon={<IconAlertCircle size={16} />} color="yellow" mb="md">
          Only admins can edit payment methods.
        </Alert>
      )}

      <Text size="sm" c="dimmed" mb="md">
        Configure payment methods and their details. Details (like bank account info or M-Pesa paybill) will appear on invoices.
      </Text>

      <Accordion variant="separated" multiple>
        {methods.map((method, mIdx) => (
          <Accordion.Item key={mIdx} value={String(mIdx)}>
            <Accordion.Control>
              <Group gap="sm">
                <ThemeIcon variant="light" color="blue" size="sm" radius="xl">
                  <IconCreditCard size={14} />
                </ThemeIcon>
                <Text fw={500} size="sm">
                  {method.label || 'New Method'}
                </Text>
                {(method.details?.filter((d) => d.value.trim()).length ?? 0) > 0 && (
                  <Badge size="xs" variant="light" color="green">
                    {method.details!.filter((d) => d.value.trim()).length} detail(s)
                  </Badge>
                )}
              </Group>
            </Accordion.Control>
            <Accordion.Panel>
              <Stack gap="sm">
                {/* Method name and value */}
                <Group gap="xs">
                  <TextInput
                    label="Display Name"
                    placeholder="e.g. M-Pesa"
                    value={method.label}
                    onChange={(e) => updateMethodField(mIdx, 'label', e.currentTarget.value)}
                    disabled={!isAdmin}
                    style={{ flex: 1 }}
                  />
                  <TextInput
                    label="Key"
                    placeholder="e.g. mpesa"
                    value={method.value}
                    onChange={(e) => updateMethodField(mIdx, 'value', e.currentTarget.value)}
                    disabled={!isAdmin}
                    style={{ flex: 1 }}
                  />
                  {isAdmin && (
                    <Tooltip label="Remove this method">
                      <ActionIcon
                        variant="subtle"
                        color="red"
                        onClick={() => removeMethod(mIdx)}
                        disabled={methods.length <= 1}
                        mt={24}
                      >
                        <IconTrash size={16} />
                      </ActionIcon>
                    </Tooltip>
                  )}
                </Group>

                {/* Method details */}
                <Divider label="Payment Details" labelPosition="left" />
                <Text size="xs" c="dimmed">
                  Add account numbers, paybill numbers, or other info clients need to pay you via this method.
                </Text>

                {(method.details || []).map((detail, dIdx) => (
                  <Group key={dIdx} gap="xs">
                    <TextInput
                      placeholder="Field name (e.g. Account Number)"
                      value={detail.key}
                      onChange={(e) => updateDetail(mIdx, dIdx, 'key', e.currentTarget.value)}
                      disabled={!isAdmin}
                      style={{ flex: 1 }}
                    />
                    <TextInput
                      placeholder="Value (e.g. 21208100521)"
                      value={detail.value}
                      onChange={(e) => updateDetail(mIdx, dIdx, 'value', e.currentTarget.value)}
                      disabled={!isAdmin}
                      style={{ flex: 1 }}
                    />
                    {isAdmin && (
                      <ActionIcon variant="subtle" color="red" onClick={() => removeDetail(mIdx, dIdx)}>
                        <IconTrash size={14} />
                      </ActionIcon>
                    )}
                  </Group>
                ))}

                {isAdmin && (
                  <Button
                    variant="subtle"
                    size="xs"
                    leftSection={<IconPlus size={14} />}
                    onClick={() => addDetail(mIdx)}
                    w="fit-content"
                  >
                    Add Detail
                  </Button>
                )}
              </Stack>
            </Accordion.Panel>
          </Accordion.Item>
        ))}
      </Accordion>

      {isAdmin && (
        <Group justify="space-between" mt="md">
          <Button variant="light" leftSection={<IconPlus size={16} />} onClick={addMethod} size="sm">
            Add Payment Method
          </Button>
          <Button onClick={() => saveMutation.mutate()} loading={saveMutation.isPending} disabled={!canSave}>
            Save Payment Methods
          </Button>
        </Group>
      )}
    </Paper>
  );
}

// --- WhatsApp Tab ---

function WhatsAppTab({ isAdmin }: { isAdmin: boolean }) {
  const queryClient = useQueryClient();

  const { data, isLoading } = useQuery({
    queryKey: ['whatsapp-settings'],
    queryFn: getWhatsAppSettings,
  });

  const settings: WhatsAppSettings | undefined = data?.data?.data;

  const [enabled, setEnabled] = useState(false);
  const [reminderEnabled, setReminderEnabled] = useState(false);
  const [phoneNumberId, setPhoneNumberId] = useState('');
  const [accessToken, setAccessToken] = useState('');
  const [businessAccountId, setBusinessAccountId] = useState('');
  const [initialized, setInitialized] = useState(false);

  if (settings && !initialized) {
    setEnabled(settings.whatsapp_enabled);
    setReminderEnabled(settings.reminder_whatsapp_enabled);
    setPhoneNumberId(settings.whatsapp_phone_number_id || '');
    setBusinessAccountId(settings.whatsapp_business_account_id || '');
    setInitialized(true);
  }

  const saveMutation = useMutation({
    mutationFn: () => updateWhatsAppSettings({
      whatsapp_enabled: enabled,
      reminder_whatsapp_enabled: reminderEnabled,
      whatsapp_phone_number_id: phoneNumberId || undefined,
      whatsapp_access_token: accessToken || undefined,
      whatsapp_business_account_id: businessAccountId || undefined,
    }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['whatsapp-settings'] });
      queryClient.invalidateQueries({ queryKey: ['reminder-settings'] });
      setAccessToken('');
      notifications.show({ title: 'Success', message: 'WhatsApp settings updated', color: 'green' });
    },
    onError: (err: any) => {
      notifications.show({
        title: 'Error',
        message: err.response?.data?.message || 'Failed to update WhatsApp settings',
        color: 'red',
      });
    },
  });

  if (isLoading) {
    return <Center py="xl"><Loader /></Center>;
  }

  return (
    <Paper p="lg" withBorder maw={600}>
      {!isAdmin && (
        <Alert icon={<IconAlertCircle size={16} />} color="yellow" mb="md">
          Only admins can edit WhatsApp settings.
        </Alert>
      )}

      <Stack>
        <Group gap="xs">
          <ThemeIcon variant="light" color="green" size="lg" radius="xl">
            <IconBrandWhatsapp size={20} />
          </ThemeIcon>
          <div>
            <Text fw={600}>WhatsApp Business API</Text>
            <Text size="xs" c="dimmed">Send automated reminders via WhatsApp</Text>
          </div>
        </Group>

        <Switch
          label="WhatsApp integration enabled"
          description="Enable WhatsApp Business API for sending messages"
          disabled={!isAdmin}
          checked={enabled}
          onChange={(e) => setEnabled(e.currentTarget.checked)}
        />

        <Switch
          label="Auto-send WhatsApp reminders"
          description="Automatically send invoice reminders via WhatsApp"
          disabled={!isAdmin || !enabled}
          checked={reminderEnabled}
          onChange={(e) => setReminderEnabled(e.currentTarget.checked)}
        />

        <Divider my="xs" label="API Credentials" labelPosition="left" />

        <TextInput
          label="Phone Number ID"
          description="From Meta Business Manager → WhatsApp → Phone numbers"
          placeholder="e.g. 123456789012345"
          disabled={!isAdmin}
          value={phoneNumberId}
          onChange={(e) => setPhoneNumberId(e.currentTarget.value)}
        />

        <PasswordInput
          label="Permanent Access Token"
          description="System user token from Meta Business Manager"
          placeholder={settings?.whatsapp_access_token_set ? '••••••••••••• (already set)' : 'Paste your access token'}
          disabled={!isAdmin}
          value={accessToken}
          onChange={(e) => setAccessToken(e.currentTarget.value)}
        />

        <TextInput
          label="Business Account ID"
          description="Your WhatsApp Business Account ID"
          placeholder="e.g. 123456789012345"
          disabled={!isAdmin}
          value={businessAccountId}
          onChange={(e) => setBusinessAccountId(e.currentTarget.value)}
        />

        {settings?.whatsapp_access_token_set && (
          <Badge color="green" variant="light">Access token configured</Badge>
        )}

        <Alert variant="light" color="blue" icon={<IconAlertCircle size={16} />}>
          <Text size="sm">
            To set up WhatsApp Business API, you need a <strong>Meta Business Manager</strong> account
            with a verified WhatsApp Business number. See the setup guide in the documentation.
          </Text>
        </Alert>

        {isAdmin && (
          <Group justify="flex-end">
            <Button onClick={() => saveMutation.mutate()} loading={saveMutation.isPending}>
              Save Settings
            </Button>
          </Group>
        )}
      </Stack>
    </Paper>
  );
}

// --- Pesapal Tab ---

function PesapalTab({ isAdmin }: { isAdmin: boolean }) {
  const queryClient = useQueryClient();

  const { data, isLoading } = useQuery({
    queryKey: ['pesapal-settings'],
    queryFn: getPesapalSettings,
  });

  const settings: PesapalSettings | undefined = data?.data?.data;

  const form = useForm({
    initialValues: {
      pesapal_enabled: false,
      pesapal_consumer_key: '',
      pesapal_consumer_secret: '',
      pesapal_sandbox: true,
    },
  });

  const [initialized, setInitialized] = useState(false);
  if (settings && !initialized) {
    form.setValues({
      pesapal_enabled: settings.pesapal_enabled,
      pesapal_consumer_key: settings.pesapal_consumer_key ?? '',
      pesapal_consumer_secret: '',
      pesapal_sandbox: settings.pesapal_sandbox,
    });
    setInitialized(true);
  }

  const saveMutation = useMutation({
    mutationFn: (values: typeof form.values) => {
      const payload: any = {
        pesapal_enabled: values.pesapal_enabled,
        pesapal_sandbox: values.pesapal_sandbox,
      };
      if (values.pesapal_consumer_key) payload.pesapal_consumer_key = values.pesapal_consumer_key;
      if (values.pesapal_consumer_secret) payload.pesapal_consumer_secret = values.pesapal_consumer_secret;
      return updatePesapalSettings(payload);
    },
    onSuccess: (res) => {
      queryClient.invalidateQueries({ queryKey: ['pesapal-settings'] });
      notifications.show({ title: 'Success', message: res.data.message || 'Pesapal settings updated', color: 'green' });
    },
    onError: (err: any) => {
      notifications.show({
        title: 'Error',
        message: err.response?.data?.message || 'Failed to update Pesapal settings',
        color: 'red',
      });
    },
  });

  if (isLoading) {
    return <Center py="xl"><Loader /></Center>;
  }

  return (
    <Paper p="lg" withBorder maw={600}>
      {!isAdmin && (
        <Alert icon={<IconAlertCircle size={16} />} color="yellow" mb="md">
          Only admins can edit Pesapal settings.
        </Alert>
      )}

      <Alert variant="light" color="blue" icon={<IconAlertCircle size={16} />} mb="md">
        <Text size="sm">
          Connect your Pesapal merchant account to allow clients to pay invoices online.
          When enabled, invoices will include a "Pay Now" link.
        </Text>
      </Alert>

      <form onSubmit={form.onSubmit((values) => saveMutation.mutate(values))}>
        <Stack>
          <Switch
            label="Enable Pesapal Payments"
            description="Allow clients to pay invoices online via Pesapal (card, mobile money, etc.)"
            disabled={!isAdmin}
            checked={form.values.pesapal_enabled}
            onChange={(e) => form.setFieldValue('pesapal_enabled', e.currentTarget.checked)}
          />

          <Divider label="API Credentials" labelPosition="left" />

          <TextInput
            label="Consumer Key"
            placeholder={settings?.pesapal_consumer_key_set ? '••••••• (already set)' : 'Enter your Pesapal consumer key'}
            disabled={!isAdmin}
            {...form.getInputProps('pesapal_consumer_key')}
          />
          <PasswordInput
            label="Consumer Secret"
            placeholder={settings?.pesapal_consumer_secret_set ? '••••••• (already set)' : 'Enter your Pesapal consumer secret'}
            disabled={!isAdmin}
            {...form.getInputProps('pesapal_consumer_secret')}
          />

          <Switch
            label="Sandbox Mode"
            description="Use Pesapal demo/test environment instead of live"
            disabled={!isAdmin}
            checked={form.values.pesapal_sandbox}
            onChange={(e) => form.setFieldValue('pesapal_sandbox', e.currentTarget.checked)}
          />

          {settings?.pesapal_ipn_id && (
            <Alert variant="light" color="green">
              <Text size="sm">IPN registered: <Text span fw={600}>{settings.pesapal_ipn_id}</Text></Text>
            </Alert>
          )}

          {isAdmin && (
            <Group justify="flex-end">
              <Button type="submit" loading={saveMutation.isPending}>Save Pesapal Settings</Button>
            </Group>
          )}
        </Stack>
      </form>
    </Paper>
  );
}
