import { TextInput, Textarea, Button, Group, Stack, Accordion, SimpleGrid } from '@mantine/core';
import { useForm } from '@mantine/form';
import { ClientFormData } from '../../api/clients';

interface Props {
  initialValues?: ClientFormData;
  onSubmit: (values: ClientFormData) => void;
  loading?: boolean;
}

const EMPTY: ClientFormData = {
  name: '', email: '', phone: '', address: '', tax_id: '',
  first_name: '', last_name: '', company_name: '',
  address_1: '', address_2: '', city: '', state: '', postcode: '', country: '',
};

export default function ClientForm({ initialValues, onSubmit, loading }: Props) {
  const form = useForm<ClientFormData>({
    initialValues: initialValues ? { ...EMPTY, ...initialValues } : EMPTY,
    validate: {
      name: (v) => (v.length > 0 ? null : 'Name is required'),
      email: (v) => (v && !/^\S+@\S+$/.test(v) ? 'Invalid email' : null),
      country: (v) => (v && v.length !== 2 ? '2-letter code, e.g. TZ' : null),
    },
  });

  const hasDetailedAddress = !!(
    form.values.first_name || form.values.last_name || form.values.company_name
    || form.values.address_1 || form.values.city || form.values.country
  );

  return (
    <form onSubmit={form.onSubmit(onSubmit)}>
      <Stack>
        <TextInput label="Name" placeholder="Client name" required {...form.getInputProps('name')} />
        <TextInput label="Email" placeholder="client@email.com" {...form.getInputProps('email')} />
        <TextInput label="Phone" placeholder="+254 7xx xxx xxx" {...form.getInputProps('phone')} />
        <Textarea label="Address" placeholder="Client address" {...form.getInputProps('address')} />
        <TextInput label="Tax ID / KRA PIN" placeholder="e.g., A123456789B" {...form.getInputProps('tax_id')} />

        <Accordion variant="contained" defaultValue={hasDetailedAddress ? 'detailed' : null}>
          <Accordion.Item value="detailed">
            <Accordion.Control>Detailed name / address (optional, WHMCS-style)</Accordion.Control>
            <Accordion.Panel>
              <Stack gap="sm">
                <SimpleGrid cols={2}>
                  <TextInput label="First Name" {...form.getInputProps('first_name')} />
                  <TextInput label="Last Name" {...form.getInputProps('last_name')} />
                </SimpleGrid>
                <TextInput label="Company Name" {...form.getInputProps('company_name')} />
                <TextInput label="Address 1" {...form.getInputProps('address_1')} />
                <TextInput label="Address 2" {...form.getInputProps('address_2')} />
                <SimpleGrid cols={2}>
                  <TextInput label="City" {...form.getInputProps('city')} />
                  <TextInput label="State / Region" {...form.getInputProps('state')} />
                </SimpleGrid>
                <SimpleGrid cols={2}>
                  <TextInput label="Postcode" {...form.getInputProps('postcode')} />
                  <TextInput label="Country" placeholder="TZ" maxLength={2}
                    {...form.getInputProps('country')}
                    onChange={(e) => form.setFieldValue('country', e.currentTarget.value.toUpperCase())} />
                </SimpleGrid>
              </Stack>
            </Accordion.Panel>
          </Accordion.Item>
        </Accordion>

        <Group justify="flex-end">
          <Button type="submit" loading={loading}>Save Client</Button>
        </Group>
      </Stack>
    </form>
  );
}
