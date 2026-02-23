import { TextInput, Textarea, Button, Group, Stack } from '@mantine/core';
import { useForm } from '@mantine/form';
import { ClientFormData } from '../../api/clients';

interface Props {
  initialValues?: ClientFormData;
  onSubmit: (values: ClientFormData) => void;
  loading?: boolean;
}

export default function ClientForm({ initialValues, onSubmit, loading }: Props) {
  const form = useForm<ClientFormData>({
    initialValues: initialValues || {
      name: '',
      email: '',
      phone: '',
      address: '',
      tax_id: '',
    },
    validate: {
      name: (v) => (v.length > 0 ? null : 'Name is required'),
      email: (v) => (v && !/^\S+@\S+$/.test(v) ? 'Invalid email' : null),
    },
  });

  return (
    <form onSubmit={form.onSubmit(onSubmit)}>
      <Stack>
        <TextInput label="Name" placeholder="Client name" required {...form.getInputProps('name')} />
        <TextInput label="Email" placeholder="client@email.com" {...form.getInputProps('email')} />
        <TextInput label="Phone" placeholder="+254 7xx xxx xxx" {...form.getInputProps('phone')} />
        <Textarea label="Address" placeholder="Client address" {...form.getInputProps('address')} />
        <TextInput label="Tax ID / KRA PIN" placeholder="e.g., A123456789B" {...form.getInputProps('tax_id')} />
        <Group justify="flex-end">
          <Button type="submit" loading={loading}>Save Client</Button>
        </Group>
      </Stack>
    </form>
  );
}
