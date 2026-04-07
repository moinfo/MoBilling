import { TextInput, Textarea, Button, Stack, MultiSelect, Select, Group } from '@mantine/core';
import { useForm } from '@mantine/form';
import { SERVICES, VISIT_STATUSES, type FieldVisit, type VisitStatus } from '../../api/fieldMarketing';

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
          label="Services Interested In"
          placeholder="Select services"
          data={SERVICES as unknown as string[]}
          required
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
