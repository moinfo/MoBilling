import { TextInput, NumberInput, Select, Textarea, Button, Group, SegmentedControl, Switch, Stack, Divider, Text } from '@mantine/core';
import { useForm } from '@mantine/form';
import { useQuery } from '@tanstack/react-query';
import { ProductServiceFormData } from '../../api/productServices';
import { getServers } from '../../api/hosting';
import { usePermissions } from '../../hooks/usePermissions';

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

const billingCycleOptions = [
  { value: '', label: 'None' },
  { value: 'once', label: 'Once' },
  { value: 'monthly', label: 'Monthly' },
  { value: 'quarterly', label: 'Quarterly' },
  { value: 'half_yearly', label: 'Semi-Annual' },
  { value: 'yearly', label: 'Annually' },
];

export default function ProductServiceForm({ initialValues, onSubmit, loading }: Props) {
  const { can } = usePermissions();
  const canHosting = can('hosting.settings');

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
      billing_cycle: '',
      is_active: true,
      portal_visible: true,
      provisioning_type: 'none',
      server_id: null,
      cpanel_package: '',
      auto_provision: true,
    },
    validate: {
      name: (v) => (v.length > 0 ? null : 'Name is required'),
      price: (v) => (v >= 0 ? null : 'Price must be positive'),
    },
  });

  const unitOptions = form.values.type === 'product' ? productUnits : serviceUnits;

  const showProvisioning = canHosting && form.values.type === 'service';
  const { data: serversData } = useQuery({
    queryKey: ['servers'],
    queryFn: getServers,
    enabled: showProvisioning,
  });
  const serverOptions = (serversData?.data?.data ?? [])
    .filter((s) => s.is_active)
    .map((s) => ({ value: s.id, label: `${s.name} (${s.hostname})` }));

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
          <Select label="Unit" data={unitOptions} clearable {...form.getInputProps('unit')} />
          <TextInput label="Category" placeholder="e.g., Electronics, IT Services" {...form.getInputProps('category')} />
        </Group>
        <Select
          label="Billing Cycle"
          description="Optional — used to auto-fill when creating bills"
          data={billingCycleOptions}
          clearable
          {...form.getInputProps('billing_cycle')}
        />
        {showProvisioning && (
          <>
            <Divider label="Hosting Provisioning" labelPosition="left" />
            <Select
              label="Provisioning"
              description="Automatically manage a cPanel account for subscriptions of this service"
              data={[
                { value: 'none', label: 'None' },
                { value: 'whm_cpanel', label: 'WHM / cPanel' },
              ]}
              {...form.getInputProps('provisioning_type')}
            />
            {form.values.provisioning_type === 'whm_cpanel' && (
              <>
                <Group grow>
                  <Select
                    label="Server"
                    placeholder="Select WHM server"
                    data={serverOptions}
                    required
                    {...form.getInputProps('server_id')}
                  />
                  <TextInput
                    label="cPanel package"
                    placeholder="WHM package/plan name"
                    required
                    {...form.getInputProps('cpanel_package')}
                  />
                </Group>
                <Switch
                  label="Auto-provision on activation"
                  description="Create the cPanel account automatically when the subscription becomes active (first payment)"
                  {...form.getInputProps('auto_provision', { type: 'checkbox' })}
                />
                {serverOptions.length === 0 && (
                  <Text size="xs" c="orange">No active WHM servers — add one in Settings → Hosting Servers first.</Text>
                )}
              </>
            )}
          </>
        )}
        <Group>
          <Switch label="Active" {...form.getInputProps('is_active', { type: 'checkbox' })} />
          <Switch label="Show in portal catalog"
            description="Clients can order this from the portal Shopping Cart"
            {...form.getInputProps('portal_visible', { type: 'checkbox' })} />
        </Group>
        <Group justify="flex-end">
          <Button type="submit" loading={loading}>Save</Button>
        </Group>
      </Stack>
    </form>
  );
}
