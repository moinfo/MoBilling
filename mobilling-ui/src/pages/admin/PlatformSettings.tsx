import { useEffect, useState } from 'react';
import {
  Title, Text, Paper, Stack, TextInput, Textarea, Button, Group, Loader, Center,
  Divider, Badge, Alert, Tabs,
} from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconBuildingBank, IconDeviceFloppy, IconTemplate, IconAlertCircle } from '@tabler/icons-react';
import { getPlatformSettings, updatePlatformSettings, PlatformSettings as PlatformSettingsType } from '../../api/admin';

export default function PlatformSettings() {
  const queryClient = useQueryClient();

  const { data, isLoading } = useQuery({
    queryKey: ['platform-settings'],
    queryFn: getPlatformSettings,
  });

  const settings: PlatformSettingsType | undefined = data?.data?.data as PlatformSettingsType | undefined;

  const [bankForm, setBankForm] = useState({
    platform_bank_name: '',
    platform_bank_account_name: '',
    platform_bank_account_number: '',
    platform_bank_branch: '',
    platform_payment_instructions: '',
  });

  const [templateForm, setTemplateForm] = useState({
    welcome_email_subject: '',
    welcome_email_body: '',
    reset_password_email_subject: '',
    reset_password_email_body: '',
    new_tenant_email_subject: '',
    new_tenant_email_body: '',
    sms_activation_email_subject: '',
    sms_activation_email_body: '',
  });

  useEffect(() => {
    if (settings) {
      setBankForm({
        platform_bank_name: settings.platform_bank_name || '',
        platform_bank_account_name: settings.platform_bank_account_name || '',
        platform_bank_account_number: settings.platform_bank_account_number || '',
        platform_bank_branch: settings.platform_bank_branch || '',
        platform_payment_instructions: settings.platform_payment_instructions || '',
      });
      setTemplateForm({
        welcome_email_subject: settings.welcome_email_subject || '',
        welcome_email_body: settings.welcome_email_body || '',
        reset_password_email_subject: settings.reset_password_email_subject || '',
        reset_password_email_body: settings.reset_password_email_body || '',
        new_tenant_email_subject: settings.new_tenant_email_subject || '',
        new_tenant_email_body: settings.new_tenant_email_body || '',
        sms_activation_email_subject: settings.sms_activation_email_subject || '',
        sms_activation_email_body: settings.sms_activation_email_body || '',
      });
    }
  }, [settings]);

  const saveBankMutation = useMutation({
    mutationFn: () => updatePlatformSettings(bankForm),
    onSuccess: (res) => {
      queryClient.invalidateQueries({ queryKey: ['platform-settings'] });
      notifications.show({ title: 'Saved', message: res.data.message, color: 'green' });
    },
    onError: (err: any) => {
      notifications.show({
        title: 'Error',
        message: err.response?.data?.message || 'Failed to save settings',
        color: 'red',
      });
    },
  });

  const saveTemplateMutation = useMutation({
    mutationFn: () => updatePlatformSettings(templateForm),
    onSuccess: (res) => {
      queryClient.invalidateQueries({ queryKey: ['platform-settings'] });
      notifications.show({ title: 'Saved', message: res.data.message, color: 'green' });
    },
    onError: (err: any) => {
      notifications.show({
        title: 'Error',
        message: err.response?.data?.message || 'Failed to save templates',
        color: 'red',
      });
    },
  });

  const handleClearTemplates = () => {
    setTemplateForm({
      welcome_email_subject: '',
      welcome_email_body: '',
      reset_password_email_subject: '',
      reset_password_email_body: '',
      new_tenant_email_subject: '',
      new_tenant_email_body: '',
      sms_activation_email_subject: '',
      sms_activation_email_body: '',
    });
  };

  if (isLoading) {
    return <Center py="xl"><Loader /></Center>;
  }

  return (
    <Stack gap="lg">
      <div>
        <Title order={2} mb={4}>Platform Settings</Title>
        <Text c="dimmed">Configure platform-wide settings including bank details and email templates.</Text>
      </div>

      <Tabs defaultValue="bank">
        <Tabs.List mb="md">
          <Tabs.Tab value="bank" leftSection={<IconBuildingBank size={16} />}>
            Bank Details
          </Tabs.Tab>
          <Tabs.Tab value="templates" leftSection={<IconTemplate size={16} />}>
            Email Templates
          </Tabs.Tab>
        </Tabs.List>

        <Tabs.Panel value="bank">
          <Paper withBorder p="lg" radius="md" maw={600}>
            <Text size="sm" c="dimmed" mb="md">
              These bank details will appear on subscription invoices for bank transfer payments.
            </Text>

            <Stack gap="md">
              <TextInput
                label="Bank Name"
                placeholder="e.g. CRDB Bank"
                value={bankForm.platform_bank_name}
                onChange={(e) => setBankForm({ ...bankForm, platform_bank_name: e.currentTarget.value })}
              />
              <TextInput
                label="Account Name"
                placeholder="e.g. Moinfotech Company Ltd"
                value={bankForm.platform_bank_account_name}
                onChange={(e) => setBankForm({ ...bankForm, platform_bank_account_name: e.currentTarget.value })}
              />
              <TextInput
                label="Account Number"
                placeholder="e.g. 0152XXXXXXXX"
                value={bankForm.platform_bank_account_number}
                onChange={(e) => setBankForm({ ...bankForm, platform_bank_account_number: e.currentTarget.value })}
              />
              <TextInput
                label="Branch"
                placeholder="e.g. Dar es Salaam"
                value={bankForm.platform_bank_branch}
                onChange={(e) => setBankForm({ ...bankForm, platform_bank_branch: e.currentTarget.value })}
              />
              <Textarea
                label="Payment Instructions"
                placeholder="Instructions that appear on subscription invoices..."
                minRows={3}
                value={bankForm.platform_payment_instructions}
                onChange={(e) => setBankForm({ ...bankForm, platform_payment_instructions: e.currentTarget.value })}
              />

              <Group justify="flex-end">
                <Button
                  leftSection={<IconDeviceFloppy size={16} />}
                  loading={saveBankMutation.isPending}
                  onClick={() => saveBankMutation.mutate()}
                >
                  Save Bank Details
                </Button>
              </Group>
            </Stack>
          </Paper>
        </Tabs.Panel>

        <Tabs.Panel value="templates">
          <Paper withBorder p="lg" radius="md" maw={700}>
            <Alert variant="light" color="blue" icon={<IconAlertCircle size={16} />} mb="md">
              <Text size="sm">
                Customize platform-level email templates. Leave fields blank to use the built-in defaults.
                Both subject and body must be filled for a custom template to take effect.
              </Text>
            </Alert>

            <Stack gap="md">
              {/* Welcome Email */}
              <Divider label="Welcome Email (New Registration)" labelPosition="left" />
              <Alert variant="light" color="gray" icon={<IconAlertCircle size={16} />} py="xs">
                <Text size="xs">
                  Placeholders: <Badge size="xs" variant="light">{'{user_name}'}</Badge>{' '}
                  <Badge size="xs" variant="light">{'{company_name}'}</Badge>{' '}
                  <Badge size="xs" variant="light">{'{login_url}'}</Badge>
                </Text>
              </Alert>
              <TextInput
                label="Subject"
                placeholder="e.g. Welcome to MoBilling, {user_name}!"
                value={templateForm.welcome_email_subject}
                onChange={(e) => setTemplateForm({ ...templateForm, welcome_email_subject: e.currentTarget.value })}
              />
              <Textarea
                label="Body"
                placeholder="e.g. Hello {user_name},&#10;&#10;Welcome! Your account for {company_name} is ready..."
                autosize
                minRows={3}
                value={templateForm.welcome_email_body}
                onChange={(e) => setTemplateForm({ ...templateForm, welcome_email_body: e.currentTarget.value })}
              />

              {/* Reset Password Email */}
              <Divider label="Reset Password Email" labelPosition="left" mt="sm" />
              <Alert variant="light" color="gray" icon={<IconAlertCircle size={16} />} py="xs">
                <Text size="xs">
                  Placeholders: <Badge size="xs" variant="light">{'{user_name}'}</Badge>{' '}
                  <Badge size="xs" variant="light">{'{reset_url}'}</Badge>
                </Text>
              </Alert>
              <TextInput
                label="Subject"
                placeholder="e.g. Reset Your Password — MoBilling"
                value={templateForm.reset_password_email_subject}
                onChange={(e) => setTemplateForm({ ...templateForm, reset_password_email_subject: e.currentTarget.value })}
              />
              <Textarea
                label="Body"
                placeholder="e.g. Hello {user_name},&#10;&#10;We received a request to reset your password..."
                autosize
                minRows={3}
                value={templateForm.reset_password_email_body}
                onChange={(e) => setTemplateForm({ ...templateForm, reset_password_email_body: e.currentTarget.value })}
              />

              {/* New Tenant Email */}
              <Divider label="New Tenant Alert (Admin)" labelPosition="left" mt="sm" />
              <Alert variant="light" color="gray" icon={<IconAlertCircle size={16} />} py="xs">
                <Text size="xs">
                  Placeholders: <Badge size="xs" variant="light">{'{tenant_name}'}</Badge>{' '}
                  <Badge size="xs" variant="light">{'{tenant_email}'}</Badge>{' '}
                  <Badge size="xs" variant="light">{'{admin_url}'}</Badge>
                </Text>
              </Alert>
              <TextInput
                label="Subject"
                placeholder="e.g. New Tenant: {tenant_name}"
                value={templateForm.new_tenant_email_subject}
                onChange={(e) => setTemplateForm({ ...templateForm, new_tenant_email_subject: e.currentTarget.value })}
              />
              <Textarea
                label="Body"
                placeholder="e.g. Hello Admin,&#10;&#10;A new tenant has registered: {tenant_name} ({tenant_email})."
                autosize
                minRows={3}
                value={templateForm.new_tenant_email_body}
                onChange={(e) => setTemplateForm({ ...templateForm, new_tenant_email_body: e.currentTarget.value })}
              />

              {/* SMS Activation Request */}
              <Divider label="SMS Activation Request (Admin)" labelPosition="left" mt="sm" />
              <Alert variant="light" color="gray" icon={<IconAlertCircle size={16} />} py="xs">
                <Text size="xs">
                  Placeholders: <Badge size="xs" variant="light">{'{tenant_name}'}</Badge>{' '}
                  <Badge size="xs" variant="light">{'{tenant_email}'}</Badge>{' '}
                  <Badge size="xs" variant="light">{'{configure_url}'}</Badge>
                </Text>
              </Alert>
              <TextInput
                label="Subject"
                placeholder="e.g. SMS Activation Request — {tenant_name}"
                value={templateForm.sms_activation_email_subject}
                onChange={(e) => setTemplateForm({ ...templateForm, sms_activation_email_subject: e.currentTarget.value })}
              />
              <Textarea
                label="Body"
                placeholder="e.g. Hello Admin,&#10;&#10;{tenant_name} ({tenant_email}) has requested SMS activation."
                autosize
                minRows={3}
                value={templateForm.sms_activation_email_body}
                onChange={(e) => setTemplateForm({ ...templateForm, sms_activation_email_body: e.currentTarget.value })}
              />

              <Group justify="space-between">
                <Button variant="subtle" color="gray" onClick={handleClearTemplates}>
                  Reset to Defaults
                </Button>
                <Button
                  leftSection={<IconDeviceFloppy size={16} />}
                  loading={saveTemplateMutation.isPending}
                  onClick={() => saveTemplateMutation.mutate()}
                >
                  Save Templates
                </Button>
              </Group>
            </Stack>
          </Paper>
        </Tabs.Panel>
      </Tabs>
    </Stack>
  );
}
