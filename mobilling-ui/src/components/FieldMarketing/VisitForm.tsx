import { useState } from 'react';
import { TextInput, Textarea, Button, Stack, MultiSelect, Select, Group, Text, Anchor } from '@mantine/core';
import { useForm } from '@mantine/form';
import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { VISIT_STATUSES, type FieldVisit, type VisitStatus } from '../../api/fieldMarketing';
import { getServices } from '../../api/marketingServices';

interface Props {
  visit?: FieldVisit | null;
  onSubmit: (values: {
    business_name: string;
    location: string;
    phone?: string;
    services: string[];
    feedback?: string;
    status: VisitStatus;
  }) => void;
  loading?: boolean;
}

export default function VisitForm({ visit, onSubmit, loading }: Props) {
  const { data: servicesData } = useQuery({
    queryKey: ['marketing-services'],
    queryFn: getServices,
  });

  const apiServices = (servicesData?.data ?? []).map(s => s.name);
  const [extraOptions, setExtraOptions] = useState<string[]>([]);
  const serviceOptions = [...apiServices, ...extraOptions.filter(e => !apiServices.includes(e))];

  const form = useForm({
    initialValues: {
      business_name: visit?.business_name ?? '',
      location:      visit?.location ?? '',
      phone:         visit?.phone ?? '',
      services:      visit?.services ?? [] as string[],
      feedback:      visit?.feedback ?? '',
      status:        (visit?.status ?? 'interested') as VisitStatus,
    },
    validate: {
      business_name: v => !v.trim() ? 'Business name is required' : null,
      location:      v => !v.trim() ? 'Location is required' : null,
      services:      v => v.length === 0 ? 'Select at least one service' : null,
    },
  });

  return (
    <form onSubmit={form.onSubmit(v => onSubmit({
      ...v,
      phone:    v.phone || undefined,
      feedback: v.feedback || undefined,
    }))}>
      <Stack>
        <TextInput label="Business Name" placeholder="e.g. Amiry Traders" required {...form.getInputProps('business_name')} />
        <TextInput label="Location" placeholder="e.g. Kariakoo, Stall 12" required {...form.getInputProps('location')} />
        <TextInput label="Phone" placeholder="+255..." {...form.getInputProps('phone')} />
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
          required
          nothingFoundMessage="Press Enter to add a custom service"
          onKeyDown={(e) => {
            if (e.key === 'Enter') {
              const input = (e.target as HTMLInputElement).value.trim();
              if (input && !serviceOptions.includes(input)) {
                setExtraOptions(prev => [...prev, input]);
                const current = form.values.services ?? [];
                if (!current.includes(input)) {
                  form.setFieldValue('services', [...current, input]);
                }
              }
            }
          }}
          {...form.getInputProps('services')}
        />
        <Select
          label="Status"
          data={VISIT_STATUSES.map(s => ({ value: s.value, label: s.label }))}
          required
          {...form.getInputProps('status')}
        />
        <Textarea label="Feedback / Notes" placeholder="What did the prospect say?" minRows={2} {...form.getInputProps('feedback')} />
        <Group justify="flex-end">
          <Button type="submit" loading={loading}>{visit ? 'Update Visit' : 'Log Visit'}</Button>
        </Group>
      </Stack>
    </form>
  );
}
