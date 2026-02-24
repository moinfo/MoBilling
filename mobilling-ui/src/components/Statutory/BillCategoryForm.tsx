import { TextInput, Select, Switch, Button, Group, Stack } from '@mantine/core';
import { useForm } from '@mantine/form';

interface Props {
  initialValues?: {
    name: string;
    billing_cycle?: string | null;
    is_active?: boolean;
  };
  isSubcategory: boolean;
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

export default function BillCategoryForm({ initialValues, isSubcategory, onSubmit, loading }: Props) {
  const form = useForm({
    initialValues: initialValues || {
      name: '',
      billing_cycle: null as string | null,
      is_active: true,
    },
    validate: {
      name: (v: string) => (v.trim().length > 0 ? null : 'Name is required'),
    },
  });

  return (
    <form onSubmit={form.onSubmit(onSubmit)}>
      <Stack>
        <TextInput
          label={isSubcategory ? 'Subcategory Name' : 'Category Name'}
          placeholder={isSubcategory ? 'e.g., Electricity' : 'e.g., Utilities'}
          required
          {...form.getInputProps('name')}
        />
        {isSubcategory && (
          <Select
            label="Default Billing Cycle"
            description="Auto-fills when this subcategory is selected on a bill"
            data={cycleOptions}
            clearable
            {...form.getInputProps('billing_cycle')}
          />
        )}
        <Switch
          label="Active"
          {...form.getInputProps('is_active', { type: 'checkbox' })}
        />
        <Group justify="flex-end">
          <Button type="submit" loading={loading}>
            Save
          </Button>
        </Group>
      </Stack>
    </form>
  );
}
