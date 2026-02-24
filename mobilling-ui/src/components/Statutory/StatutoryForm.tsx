import { TextInput, NumberInput, Select, Textarea, Button, Group, Switch, Stack, Text } from '@mantine/core';
import { DateInput } from '@mantine/dates';
import { useForm } from '@mantine/form';
import { useQuery } from '@tanstack/react-query';
import dayjs from 'dayjs';
import { getBillCategories, BillCategory } from '../../api/billCategories';

interface Props {
  initialValues?: any;
  onSubmit: (values: any) => void;
  loading?: boolean;
}

const cycleOptions = [
  { value: 'once', label: 'Once' },
  { value: 'monthly', label: 'Monthly' },
  { value: 'quarterly', label: 'Quarterly' },
  { value: 'half_yearly', label: 'Semi-Annual' },
  { value: 'yearly', label: 'Annually' },
];

function computeDueDate(issueDate: Date | null, cycle: string): string | null {
  if (!issueDate) return null;
  const d = dayjs(issueDate);
  const due = cycle === 'monthly' ? d.add(1, 'month')
    : cycle === 'quarterly' ? d.add(3, 'month')
    : cycle === 'half_yearly' ? d.add(6, 'month')
    : cycle === 'yearly' ? d.add(1, 'year')
    : d; // 'once' — due date = issue date
  return due.format('DD MMM YYYY');
}

export default function StatutoryForm({ initialValues, onSubmit, loading }: Props) {
  const form = useForm({
    initialValues: initialValues || {
      name: '',
      bill_category_id: null as string | null,
      amount: 0,
      cycle: 'monthly',
      issue_date: new Date(),
      remind_days_before: 3,
      is_active: true,
      notes: '',
    },
    validate: {
      name: (v: string) => (v.length > 0 ? null : 'Name is required'),
      amount: (v: number) => (v > 0 ? null : 'Amount must be positive'),
    },
  });

  const dueDatePreview = computeDueDate(form.values.issue_date, form.values.cycle);

  // Fetch bill categories for grouped dropdown
  const { data: catData } = useQuery({
    queryKey: ['bill-categories'],
    queryFn: getBillCategories,
  });

  const categories: BillCategory[] = catData?.data?.data || [];

  const subcategoryOptions = categories
    .filter((cat) => cat.children?.some((sub) => sub.is_active))
    .map((cat) => ({
      group: cat.name,
      items: (cat.children || [])
        .filter((sub) => sub.is_active)
        .map((sub) => ({ value: sub.id, label: sub.name })),
    }));

  const handleSubmit = (values: any) => {
    onSubmit({
      ...values,
      issue_date: dayjs(values.issue_date).format('YYYY-MM-DD'),
    });
  };

  return (
    <form onSubmit={form.onSubmit(handleSubmit)}>
      <Stack>
        <TextInput label="Obligation Name" placeholder="e.g., Electricity" required {...form.getInputProps('name')} />
        <Group grow>
          <Select
            label="Sub Category"
            placeholder="Select subcategory"
            data={subcategoryOptions}
            searchable
            clearable
            {...form.getInputProps('bill_category_id')}
          />
          <NumberInput label="Amount" min={0.01} decimalScale={2} required {...form.getInputProps('amount')} />
        </Group>
        <Group grow>
          <Select label="Billing Cycle" data={cycleOptions} {...form.getInputProps('cycle')} />
          <DateInput label="Issue Date" required {...form.getInputProps('issue_date')} />
        </Group>
        {dueDatePreview && (
          <Text size="sm" c="dimmed">
            Due Date: <Text span fw={600} c="blue">{dueDatePreview}</Text>
          </Text>
        )}
        <Group grow>
          <NumberInput label="Remind Days Before" min={1} max={30} {...form.getInputProps('remind_days_before')} />
          <Switch label="Active" mt="xl" {...form.getInputProps('is_active', { type: 'checkbox' })} />
        </Group>
        <Textarea label="Notes" {...form.getInputProps('notes')} />
        <Group justify="flex-end">
          <Button type="submit" loading={loading}>
            {initialValues ? 'Update Obligation' : 'Register Obligation'}
          </Button>
        </Group>
      </Stack>
    </form>
  );
}
