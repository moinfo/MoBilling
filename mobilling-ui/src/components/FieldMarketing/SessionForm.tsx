import { useEffect } from 'react';
import { TextInput, Textarea, Button, Stack, Select, Group, Text } from '@mantine/core';
import { DatePickerInput } from '@mantine/dates';
import { useForm } from '@mantine/form';
import { useQuery } from '@tanstack/react-query';
import { useAuth } from '../../context/AuthContext';
import { usePermissions } from '../../hooks/usePermissions';
import { getUsers } from '../../api/users';
import type { FieldSession } from '../../api/fieldMarketing';

interface Props {
  session?: FieldSession | null;
  onSubmit: (values: {
    officer_id: string;
    visit_date: string;
    area: string;
    summary?: string;
    challenges?: string;
    recommendations?: string;
  }) => void;
  loading?: boolean;
}

const toDateStr = (val: unknown): string => {
  if (!val) return '';
  if (val instanceof Date) return val.toISOString().slice(0, 10);
  const d = new Date(val as string);
  return isNaN(d.getTime()) ? '' : d.toISOString().slice(0, 10);
};

export default function SessionForm({ session, onSubmit, loading }: Props) {
  const { user } = useAuth();
  const { can } = usePermissions();
  const canPickOfficer = can('settings.users');

  const { data: usersData } = useQuery({
    queryKey: ['users'],
    queryFn: () => getUsers({ per_page: 100 }),
    enabled: canPickOfficer,
  });
  const users: { id: string; name: string }[] = usersData?.data?.data ?? [];

  const form = useForm({
    initialValues: {
      officer_id:      session?.officer?.id ?? user?.id ?? '',
      visit_date:      session ? new Date(session.visit_date) : new Date() as Date | null,
      area:            session?.area ?? '',
      summary:         session?.summary ?? '',
      challenges:      session?.challenges ?? '',
      recommendations: session?.recommendations ?? '',
    },
    validate: {
      officer_id: v => !v ? 'Officer is required' : null,
      visit_date: v => !v ? 'Date is required' : null,
      area:       v => !v.trim() ? 'Area is required' : null,
    },
  });

  // Pre-fill officer when user loads (in case it wasn't available on mount)
  useEffect(() => {
    if (!form.values.officer_id && user?.id) {
      form.setFieldValue('officer_id', user.id);
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user?.id]);

  useEffect(() => {
    if (session) {
      form.setValues({
        officer_id:      session.officer?.id ?? '',
        visit_date:      new Date(session.visit_date),
        area:            session.area,
        summary:         session.summary ?? '',
        challenges:      session.challenges ?? '',
        recommendations: session.recommendations ?? '',
      });
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [session?.id]);

  const officerOptions = users.map(u => ({ value: u.id, label: u.name }));

  return (
    <form onSubmit={form.onSubmit(v => onSubmit({
      ...v,
      visit_date: toDateStr(v.visit_date),
    }))}>
      <Stack>
        {canPickOfficer ? (
          <Select
            label="Officer"
            placeholder="Select officer"
            data={officerOptions}
            searchable
            required
            {...form.getInputProps('officer_id')}
          />
        ) : (
          <div>
            <Text size="sm" fw={500} mb={4}>Officer</Text>
            <TextInput value={user?.name ?? ''} readOnly disabled />
          </div>
        )}
        <DatePickerInput
          label="Visit Date"
          placeholder="Pick date"
          maxDate={new Date()}
          required
          {...form.getInputProps('visit_date')}
          onChange={(val) => form.setFieldValue('visit_date', val as Date | null)}
        />
        <TextInput label="Area Covered" placeholder="e.g. Kariakoo, Ilala" required {...form.getInputProps('area')} />
        <Textarea label="Summary" placeholder="What was discussed?" minRows={2} {...form.getInputProps('summary')} />
        <Textarea label="Challenges" placeholder="Any challenges faced?" minRows={2} {...form.getInputProps('challenges')} />
        <Textarea label="Recommendations" placeholder="Suggestions?" minRows={2} {...form.getInputProps('recommendations')} />
        <Group justify="flex-end">
          <Button type="submit" loading={loading}>{session ? 'Update Session' : 'Create Session'}</Button>
        </Group>
      </Stack>
    </form>
  );
}
