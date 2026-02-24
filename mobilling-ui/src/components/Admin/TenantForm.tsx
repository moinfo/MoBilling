import { TextInput, Textarea, Button, Group, Stack, Select, PasswordInput } from '@mantine/core';
import { useForm } from '@mantine/form';
import { TenantFormData, CreateTenantData } from '../../api/admin';

interface Props {
  initialValues?: TenantFormData;
  onSubmit: (values: TenantFormData | CreateTenantData) => void;
  loading?: boolean;
  isEdit?: boolean;
}

const CURRENCIES = [
  { value: 'KES', label: 'KES — Kenyan Shilling' },
  { value: 'USD', label: 'USD — US Dollar' },
  { value: 'EUR', label: 'EUR — Euro' },
  { value: 'GBP', label: 'GBP — British Pound' },
  { value: 'TZS', label: 'TZS — Tanzanian Shilling' },
  { value: 'UGX', label: 'UGX — Ugandan Shilling' },
];

export default function TenantForm({ initialValues, onSubmit, loading, isEdit }: Props) {
  const form = useForm({
    initialValues: initialValues
      ? { ...initialValues, admin_name: '', admin_email: '', admin_password: '' }
      : {
          name: '',
          email: '',
          phone: '',
          address: '',
          tax_id: '',
          currency: 'KES',
          admin_name: '',
          admin_email: '',
          admin_password: '',
        },
    validate: {
      name: (v) => (v.length > 0 ? null : 'Company name is required'),
      email: (v) => (/^\S+@\S+$/.test(v) ? null : 'Valid email is required'),
      admin_name: (v, values) => (!isEdit && !v ? 'Admin name is required' : null),
      admin_email: (v, values) => (!isEdit && !/^\S+@\S+$/.test(v) ? 'Valid admin email is required' : null),
      admin_password: (v, values) => (!isEdit && v.length < 8 ? 'Password must be at least 8 characters' : null),
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
        <TextInput label="Phone" placeholder="+254 7xx xxx xxx" {...form.getInputProps('phone')} />
        <Textarea label="Address" placeholder="Company address" {...form.getInputProps('address')} />
        <TextInput label="Tax ID / KRA PIN" placeholder="e.g., A123456789B" {...form.getInputProps('tax_id')} />
        <Select
          label="Currency"
          data={CURRENCIES}
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
