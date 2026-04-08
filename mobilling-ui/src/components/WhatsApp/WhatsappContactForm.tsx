import { useEffect } from 'react';
import { useForm } from '@mantine/form';
import {
  TextInput, Textarea, Select, Switch, Stack, Button, Group, Modal, MultiSelect, ScrollArea, Text, Anchor,
} from '@mantine/core';

const { Autosize: ScrollAreaAutosize } = ScrollArea;
import { DatePickerInput } from '@mantine/dates';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import {
  WhatsappContact, WaLabel, WaSource,
  createContact, updateContact, LABEL_META, LABEL_ORDER, SOURCE_META,
} from '../../api/whatsappContacts';
import { Alert } from '@mantine/core';
import { IconAlertCircle } from '@tabler/icons-react';
import { useState } from 'react';
import { getCampaigns } from '../../api/whatsappCampaigns';
import { getUsers } from '../../api/users';
import { getServices } from '../../api/marketingServices';
import { Link } from 'react-router-dom';
import { notifications } from '@mantine/notifications';

interface Props {
  opened: boolean;
  onClose: () => void;
  contact?: WhatsappContact | null;
}

const LABEL_OPTIONS = LABEL_ORDER.map((v) => ({ value: v, label: LABEL_META[v].label }));
const SOURCE_OPTIONS = (Object.keys(SOURCE_META) as WaSource[]).map((v) => ({ value: v, label: SOURCE_META[v] }));

export default function WhatsappContactForm({ opened, onClose, contact }: Props) {
  const qc = useQueryClient();
  const [existingClient, setExistingClient] = useState<{ name: string; phone: string | null } | null>(null);
  const [extraServiceOptions, setExtraServiceOptions] = useState<string[]>([]);

  const { data: servicesData } = useQuery({
    queryKey: ['marketing-services'],
    queryFn: getServices,
  });
  const apiServices = (servicesData?.data ?? []).map(s => s.name);
  const serviceOptions = [...apiServices, ...extraServiceOptions.filter(e => !apiServices.includes(e))];

  const { data: usersData } = useQuery({
    queryKey: ['users-simple'],
    queryFn: () => getUsers({ per_page: 100 }),
  });

  const { data: campaignsData } = useQuery({
    queryKey: ['whatsapp-campaigns'],
    queryFn: getCampaigns,
  });

  const userOptions = (usersData?.data?.data ?? []).map((u: any) => ({ value: u.id, label: u.name }));
  const campaignOptions = (campaignsData?.data ?? []).map((c) => ({ value: c.id, label: c.name }));

  const form = useForm({
    initialValues: {
      name: '',
      phone: '',
      label: 'lead' as WaLabel,
      is_important: false,
      source: 'whatsapp_ad' as WaSource,
      campaign_id: null as string | null,
      notes: '',
      services: [] as string[],
      next_followup_date: null as Date | null,
      assigned_to: null as string | null,
    },
  });

  useEffect(() => {
    if (contact) {
      form.setValues({
        name: contact.name,
        phone: contact.phone,
        label: contact.label,
        is_important: contact.is_important,
        source: contact.source,
        campaign_id: contact.campaign_id ?? null,
        notes: contact.notes ?? '',
        services: contact.services ?? [],
        next_followup_date: contact.next_followup_date ? new Date(contact.next_followup_date) : null,
        assigned_to: contact.assigned_to ?? null,
      });
    } else {
      form.reset();
    }
    setExistingClient(null);
  }, [contact, opened]);

  const toDateStr = (val: any): string | null => {
    if (!val) return null;
    const d = val instanceof Date ? val : new Date(val);
    return isNaN(d.getTime()) ? null : d.toISOString().split('T')[0];
  };

  const mutation = useMutation({
    mutationFn: (values: any) => {
      const payload = {
        ...values,
        next_followup_date: toDateStr(values.next_followup_date),
        notes: values.notes || null,
      };
      return contact ? updateContact(contact.id, payload) : createContact(payload);
    },
    onSuccess: (res) => {
      qc.invalidateQueries({ queryKey: ['whatsapp-contacts'] });
      qc.invalidateQueries({ queryKey: ['whatsapp-stats'] });
      // Check if phone matched an existing client
      const matched = (res.data as any)?.existing_client;
      if (matched) {
        setExistingClient(matched);
        notifications.show({
          message: `Contact added. Phone matches existing client: ${matched.name}`,
          color: 'yellow',
          autoClose: 8000,
        });
      } else {
        notifications.show({ message: contact ? 'Contact updated' : 'Contact added', color: 'green' });
        onClose();
      }
    },
    onError: (err: any) => {
      const msg = err?.response?.data?.errors
        ? Object.values(err.response.data.errors).flat().join(' ')
        : 'Failed to save contact';
      notifications.show({ message: msg as string, color: 'red' });
    },
  });

  return (
    <Modal opened={opened} onClose={onClose} title={contact ? 'Edit Contact' : 'Add WhatsApp Contact'} size="md" scrollAreaComponent={ScrollAreaAutosize}>
      <form onSubmit={form.onSubmit((v) => mutation.mutate(v))}>
        <Stack gap="sm">
          {existingClient && (
            <Alert icon={<IconAlertCircle size={16} />} color="yellow" title="Phone matches existing client">
              This phone number belongs to client <strong>{existingClient.name}</strong>.
              Consider linking instead of creating a duplicate.
            </Alert>
          )}
          <TextInput label="Name" required {...form.getInputProps('name')} />
          <TextInput label="Phone" required placeholder="+255..." {...form.getInputProps('phone')} />

          <Group grow>
            <Select label="Stage" data={LABEL_OPTIONS} required {...form.getInputProps('label')} />
            <Select label="Source" data={SOURCE_OPTIONS} required {...form.getInputProps('source')} />
          </Group>

          <Select
            label="Ad Campaign"
            placeholder="Select campaign..."
            data={campaignOptions}
            clearable
            searchable
            {...form.getInputProps('campaign_id')}
          />

          <MultiSelect
            label={
              <Group gap={4} justify="space-between">
                <Text size="sm" fw={500}>Services Interested In</Text>
                <Anchor component={Link} to="/field-marketing?tab=services" size="xs" c="dimmed">
                  + Manage services
                </Anchor>
              </Group>
            }
            placeholder="Select or type to add..."
            data={serviceOptions}
            searchable
            clearable
            nothingFoundMessage={(search) =>
              search ? `Press Enter to add "${search}"` : 'No services found'
            }
            onKeyDown={(e) => {
              if (e.key === 'Enter') {
                const input = (e.target as HTMLInputElement).value.trim();
                if (input && !serviceOptions.includes(input)) {
                  setExtraServiceOptions(prev => [...prev, input]);
                  const current = form.values.services ?? [];
                  if (!current.includes(input)) {
                    form.setFieldValue('services', [...current, input]);
                  }
                }
              }
            }}
            {...form.getInputProps('services')}
          />

          <DatePickerInput label="Next Follow-up Date" clearable {...form.getInputProps('next_followup_date')} />

          <Select label="Assigned To" data={userOptions} clearable searchable {...form.getInputProps('assigned_to')} />

          <Textarea label="Notes" rows={3} {...form.getInputProps('notes')} />

          <Switch label="Mark as Important" {...form.getInputProps('is_important', { type: 'checkbox' })} />

          <Group justify="flex-end" mt="sm">
            <Button variant="default" onClick={onClose}>{existingClient ? 'Close' : 'Cancel'}</Button>
            {!existingClient && (
              <Button type="submit" loading={mutation.isPending} color="green">
                {contact ? 'Save Changes' : 'Add Contact'}
              </Button>
            )}
          </Group>
        </Stack>
      </form>
    </Modal>
  );
}
