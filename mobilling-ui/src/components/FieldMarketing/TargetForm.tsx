import { Select, NumberInput, Button, Stack, Group } from '@mantine/core';
import { useForm } from '@mantine/form';
import { useQuery } from '@tanstack/react-query';
import { getUsers } from '../../api/users';

interface Props {
  month: number;
  year: number;
  onSubmit: (values: { officer_id: string; month: number; year: number; target_clients: number }) => void;
  loading?: boolean;
}

export default function TargetForm({ month, year, onSubmit, loading }: Props) {
  const { data: usersData } = useQuery({ queryKey: ['users'], queryFn: () => getUsers({ per_page: 100 }) });
  const users: { id: string; name: string }[] = usersData?.data?.data ?? [];

  const form = useForm({
    initialValues: {
      officer_id:     '',
      target_clients: 5,
    },
    validate: {
      officer_id:     v => !v ? 'Officer is required' : null,
      target_clients: v => v < 1 ? 'Must be at least 1' : null,
    },
  });

  const officerOptions = users.map(u => ({ value: u.id, label: u.name }));

  return (
    <form onSubmit={form.onSubmit(v => onSubmit({ ...v, month, year }))}>
      <Stack>
        <Select
          label="Officer"
          placeholder="Select officer"
          data={officerOptions}
          searchable
          required
          {...form.getInputProps('officer_id')}
        />
        <NumberInput
          label="Target: Clients to Win"
          description="Number of prospects to convert to MoBilling clients this month"
          min={1}
          required
          {...form.getInputProps('target_clients')}
        />
        <Group justify="flex-end">
          <Button type="submit" loading={loading}>Set Target</Button>
        </Group>
      </Stack>
    </form>
  );
}
