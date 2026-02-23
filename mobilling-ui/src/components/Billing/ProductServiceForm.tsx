import { TextInput, NumberInput, Select, Textarea, Button, Group, SegmentedControl, Switch, Stack } from '@mantine/core';
import { useForm } from '@mantine/form';
import { ProductServiceFormData } from '../../api/productServices';

interface Props {
  initialValues?: ProductServiceFormData;
  onSubmit: (values: ProductServiceFormData) => void;
  loading?: boolean;
}

const productUnits = [
  { value: 'pcs', label: 'Pieces' },
  { value: 'kg', label: 'Kilograms' },
  { value: 'box', label: 'Box' },
  { value: 'ltr', label: 'Litres' },
  { value: 'mtr', label: 'Metres' },
  { value: 'set', label: 'Set' },
  { value: 'pack', label: 'Pack' },
];

const serviceUnits = [
  { value: 'hrs', label: 'Hours' },
  { value: 'days', label: 'Days' },
  { value: 'months', label: 'Months' },
  { value: 'project', label: 'Project' },
  { value: 'visit', label: 'Visit' },
  { value: 'session', label: 'Session' },
];

export default function ProductServiceForm({ initialValues, onSubmit, loading }: Props) {
  const form = useForm<ProductServiceFormData>({
    initialValues: initialValues || {
      type: 'product',
      name: '',
      code: '',
      description: '',
      price: 0,
      tax_percent: 0,
      unit: 'pcs',
      category: '',
      is_active: true,
    },
    validate: {
      name: (v) => (v.length > 0 ? null : 'Name is required'),
      price: (v) => (v >= 0 ? null : 'Price must be positive'),
    },
  });

  const unitOptions = form.values.type === 'product' ? productUnits : serviceUnits;

  return (
    <form onSubmit={form.onSubmit(onSubmit)}>
      <Stack>
        <SegmentedControl
          fullWidth
          data={[
            { value: 'product', label: 'Product' },
            { value: 'service', label: 'Service' },
          ]}
          {...form.getInputProps('type')}
        />
        <TextInput label="Name" placeholder="e.g., Laptop / Consulting" required {...form.getInputProps('name')} />
        <TextInput label="Code" placeholder="e.g., SKU-001 / SRV-001" {...form.getInputProps('code')} />
        <Textarea label="Description" {...form.getInputProps('description')} />
        <Group grow>
          <NumberInput label="Price / Rate" min={0} decimalScale={2} required {...form.getInputProps('price')} />
          <NumberInput label="Tax %" min={0} max={100} decimalScale={2} {...form.getInputProps('tax_percent')} />
        </Group>
        <Group grow>
          <Select label="Unit" data={unitOptions} {...form.getInputProps('unit')} />
          <TextInput label="Category" placeholder="e.g., Electronics, IT Services" {...form.getInputProps('category')} />
        </Group>
        <Switch label="Active" {...form.getInputProps('is_active', { type: 'checkbox' })} />
        <Group justify="flex-end">
          <Button type="submit" loading={loading}>Save</Button>
        </Group>
      </Stack>
    </form>
  );
}
