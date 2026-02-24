import { TextInput, Textarea, Button, Group, Stack, Select, PasswordInput } from '@mantine/core';
import { useForm } from '@mantine/form';
import { useQuery } from '@tanstack/react-query';
import { TenantFormData, CreateTenantData, getActiveCurrencies } from '../../api/admin';

interface Props {
  initialValues?: TenantFormData;
  onSubmit: (values: TenantFormData | CreateTenantData) => void;
  loading?: boolean;
  isEdit?: boolean;
}

export default function TenantForm({ initialValues, onSubmit, loading, isEdit }: Props) {
  const { data: currencyData } = useQuery({
    queryKey: ['active-currencies'],
    queryFn: getActiveCurrencies,
  });

  const currencyOptions = (currencyData?.data?.data || []).map((c) => ({
    value: c.code,
    label: `${c.code} — ${c.name}`,
  }));

  const form = useForm({
    initialValues: initialValues
      ? { ...initialValues, admin_name: '', admin_email: '', admin_password: '' }
      : {
          name: '',
          email: '',
          phone: '',
          address: '',
          tax_id: '',
          currency: 'TZS',
          admin_name: '',
          admin_email: '',
          admin_password: '',
        },
    validate: {
      name: (v) => (v.length > 0 ? null : 'Company name is required'),
      email: (v) => (/^\S+@\S+$/.test(v) ? null : 'Valid email is required'),
      admin_name: (v) => (!isEdit && !v ? 'Admin name is required' : null),
      admin_email: (v) => (!isEdit && !/^\S+@\S+$/.test(v) ? 'Valid admin email is required' : null),
      admin_password: (v) => (!isEdit && v.length < 8 ? 'Password must be at least 8 characters' : null),
    },
  });

  const handleSubmit = (values: typeof form.values) => {
    if (isEdit) {
      const { admin_name, admin_email, admin_password, ...tenantData } = values;
      onSubmit(tenantData);
    } else {
      onSubmit(values as CreateTenantData);
    }
  };

  return (
    <form onSubmit={form.onSubmit(handleSubmit)}>
      <Stack>
        <TextInput label="Company Name" placeholder="Acme Ltd" required {...form.getInputProps('name')} />
        <TextInput label="Company Email" placeholder="info@acme.com" required {...form.getInputProps('email')} />
        <TextInput label="Phone" placeholder="+255 7xx xxx xxx" {...form.getInputProps('phone')} />
        <Textarea label="Address" placeholder="Company address" {...form.getInputProps('address')} />
        <TextInput label="Tax ID / TIN" placeholder="e.g., 123-456-789" {...form.getInputProps('tax_id')} />
        <Select
          label="Currency"
          data={currencyOptions}
          searchable
          {...form.getInputProps('currency')}
        />

        {!isEdit && (
          <>
            <TextInput label="Admin Name" placeholder="John Doe" required {...form.getInputProps('admin_name')} />
            <TextInput label="Admin Email" placeholder="admin@acme.com" required {...form.getInputProps('admin_email')} />
            <PasswordInput label="Admin Password" placeholder="Min. 8 characters" required {...form.getInputProps('admin_password')} />
          </>
        )}

        <Group justify="flex-end">
          <Button type="submit" loading={loading}>
            {isEdit ? 'Update Tenant' : 'Create Tenant'}
          </Button>
        </Group>
      </Stack>
    </form>
  );
}
