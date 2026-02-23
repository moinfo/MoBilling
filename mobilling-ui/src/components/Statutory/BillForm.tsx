import { TextInput, NumberInput, Select, Textarea, Button, Group, Switch, Stack } from '@mantine/core';
import { DateInput } from '@mantine/dates';
import { useForm } from '@mantine/form';
import dayjs from 'dayjs';

interface Props {
  initialValues?: any;
  onSubmit: (values: any) => void;
  loading?: boolean;
}

export default function BillForm({ initialValues, onSubmit, loading }: Props) {
  const form = useForm({
    initialValues: initialValues || {
      name: '',
      category: 'other',
      amount: 0,
      cycle: 'monthly',
      due_date: new Date(),
      remind_days_before: 3,
      is_active: true,
      notes: '',
    },
    validate: {
      name: (v: string) => (v.length > 0 ? null : 'Name is required'),
      amount: (v: number) => (v > 0 ? null : 'Amount must be positive'),
    },
  });

  const handleSubmit = (values: any) => {
    onSubmit({
      ...values,
      due_date: dayjs(values.due_date).format('YYYY-MM-DD'),
    });
  };

  return (
    <form onSubmit={form.onSubmit(handleSubmit)}>
      <Stack>
        <TextInput label="Bill Name" placeholder="e.g., Electricity" required {...form.getInputProps('name')} />
        <Group grow>
          <Select label="Category" data={[
            { value: 'utility', label: 'Utility' },
            { value: 'rent', label: 'Rent' },
            { value: 'subscription', label: 'Subscription' },
            { value: 'loan', label: 'Loan' },
            { value: 'insurance', label: 'Insurance' },
            { value: 'other', label: 'Other' },
          ]} {...form.getInputProps('category')} />
          <NumberInput label="Amount" min={0} decimalScale={2} required {...form.getInputProps('amount')} />
        </Group>
        <Group grow>
          <Select label="Billing Cycle" data={[
            { value: 'monthly', label: 'Monthly' },
            { value: 'quarterly', label: 'Quarterly' },
            { value: 'half_yearly', label: 'Half Yearly' },
            { value: 'yearly', label: 'Yearly' },
          ]} {...form.getInputProps('cycle')} />
          <DateInput label="Next Due Date" required {...form.getInputProps('due_date')} />
        </Group>
        <Group grow>
          <NumberInput label="Remind Days Before" min={1} max={30} {...form.getInputProps('remind_days_before')} />
          <Switch label="Active" mt="xl" {...form.getInputProps('is_active', { type: 'checkbox' })} />
        </Group>
        <Textarea label="Notes" {...form.getInputProps('notes')} />
        <Group justify="flex-end">
          <Button type="submit" loading={loading}>Save Bill</Button>
        </Group>
      </Stack>
    </form>
  );
}
