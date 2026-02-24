import { TextInput, NumberInput, Select, Textarea, Button, Group, Switch, Stack } from '@mantine/core';
import { DateInput } from '@mantine/dates';
import { useForm } from '@mantine/form';
import { useQuery } from '@tanstack/react-query';
import dayjs from 'dayjs';
import { getProductServices, ProductService } from '../../api/productServices';

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

  const { data: psData } = useQuery({
    queryKey: ['product-services', { active_only: true }],
    queryFn: () => getProductServices({ active_only: true }),
  });

  const productServices: ProductService[] = psData?.data?.data || [];

  const psOptions = [
    { value: '', label: '— Manual entry —' },
    ...productServices.map((ps) => ({
      value: ps.id,
      label: `${ps.name}${ps.billing_cycle ? ` (${cycleOptions.find(c => c.value === ps.billing_cycle)?.label || ps.billing_cycle})` : ''}`,
    })),
  ];

  const handleProductSelect = (value: string | null) => {
    if (!value) return;
    const ps = productServices.find((p) => p.id === value);
    if (!ps) return;
    form.setValues({
      name: ps.name,
      amount: parseFloat(ps.price),
      category: ps.category || 'other',
      ...(ps.billing_cycle ? { cycle: ps.billing_cycle } : {}),
    });
  };

  const handleSubmit = (values: any) => {
    onSubmit({
      ...values,
      due_date: dayjs(values.due_date).format('YYYY-MM-DD'),
    });
  };

  return (
    <form onSubmit={form.onSubmit(handleSubmit)}>
      <Stack>
        {!initialValues && (
          <Select
            label="From Product / Service"
            description="Select to auto-fill name, amount, and cycle"
            data={psOptions}
            searchable
            clearable
            onChange={handleProductSelect}
          />
        )}
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
          <Select label="Billing Cycle" data={cycleOptions} {...form.getInputProps('cycle')} />
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
