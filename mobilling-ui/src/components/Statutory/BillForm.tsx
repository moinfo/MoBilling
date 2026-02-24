import { TextInput, NumberInput, Select, Textarea, Button, Group, Switch, Stack } from '@mantine/core';
import { DateInput } from '@mantine/dates';
import { useForm } from '@mantine/form';
import { useQuery } from '@tanstack/react-query';
import dayjs from 'dayjs';
import { getProductServices, ProductService } from '../../api/productServices';
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

export default function BillForm({ initialValues, onSubmit, loading }: Props) {
  const form = useForm({
    initialValues: initialValues || {
      name: '',
      bill_category_id: null as string | null,
      issue_date: new Date(),
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

  // Fetch product/services for auto-fill
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
      ...(ps.billing_cycle ? { cycle: ps.billing_cycle } : {}),
    });
  };

  // Fetch bill categories for grouped dropdown
  const { data: catData } = useQuery({
    queryKey: ['bill-categories'],
    queryFn: getBillCategories,
  });

  const categories: BillCategory[] = catData?.data?.data || [];

  // Build grouped select data in Mantine v8 nested format: { group, items[] }
  const subcategoryMap = new Map<string, BillCategory>();
  const subcategoryOptions = categories
    .filter((cat) => cat.children?.some((sub) => sub.is_active))
    .map((cat) => {
      const items = (cat.children || [])
        .filter((sub) => sub.is_active)
        .map((sub) => {
          subcategoryMap.set(sub.id, sub);
          return { value: sub.id, label: sub.name };
        });
      return { group: cat.name, items };
    });

  // Compute due date from issue date + billing cycle
  const computeDueDate = (issueDate: Date | null, cycle: string) => {
    if (!issueDate) return;
    const d = dayjs(issueDate);
    const dueDate = cycle === 'monthly' ? d.add(1, 'month')
      : cycle === 'quarterly' ? d.add(3, 'month')
      : cycle === 'half_yearly' ? d.add(6, 'month')
      : cycle === 'yearly' ? d.add(1, 'year')
      : d; // 'once' — due date = issue date
    form.setFieldValue('due_date', dueDate.toDate());
  };

  const handleIssueDateChange = (value: Date | null) => {
    form.setFieldValue('issue_date', value);
    computeDueDate(value, form.values.cycle);
  };

  const handleCycleChange = (value: string | null) => {
    if (!value) return;
    form.setFieldValue('cycle', value);
    computeDueDate(form.values.issue_date, value);
  };

  const handleSubcategoryChange = (value: string | null) => {
    form.setFieldValue('bill_category_id', value);
    if (value) {
      const sub = subcategoryMap.get(value);
      if (sub?.billing_cycle) {
        form.setFieldValue('cycle', sub.billing_cycle);
        computeDueDate(form.values.issue_date, sub.billing_cycle);
      }
    }
  };

  const handleSubmit = (values: any) => {
    onSubmit({
      ...values,
      issue_date: values.issue_date ? dayjs(values.issue_date).format('YYYY-MM-DD') : null,
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
        <Group grow>
          <DateInput label="Issue Date" value={form.values.issue_date as any} onChange={handleIssueDateChange as any} />
          <TextInput label="Bill Name" placeholder="e.g., Electricity" required {...form.getInputProps('name')} />
        </Group>
        <Group grow>
          <Select
            label="Sub Category"
            placeholder="Select subcategory"
            data={subcategoryOptions}
            searchable
            clearable
            value={form.values.bill_category_id}
            onChange={handleSubcategoryChange}
          />
          <NumberInput label="Amount" min={0} decimalScale={2} required {...form.getInputProps('amount')} />
        </Group>
        <Group grow>
          <Select label="Billing Cycle" data={cycleOptions} value={form.values.cycle} onChange={handleCycleChange} />
          <DateInput label="Due Date" required {...form.getInputProps('due_date')} />
        </Group>
        <Group grow>
          <NumberInput label="Remind Days Before" min={1} max={30} {...form.getInputProps('remind_days_before')} />
          <Switch label="Active" mt="xl" {...form.getInputProps('is_active', { type: 'checkbox' })} />
        </Group>
        <Textarea label="Description" {...form.getInputProps('notes')} />
        <Group justify="flex-end">
          <Button type="submit" loading={loading}>Save Bill</Button>
        </Group>
      </Stack>
    </form>
  );
}
