import { TextInput, Select, Button, Group, Stack, PasswordInput } from '@mantine/core';
import { useForm } from '@mantine/form';
import { UserFormData } from '../../api/users';

interface Props {
  initialValues?: UserFormData;
  onSubmit: (values: UserFormData) => void;
  loading?: boolean;
}

export default function UserForm({ initialValues, onSubmit, loading }: Props) {
  const isEditing = !!initialValues;

  const form = useForm<UserFormData>({
    initialValues: initialValues || {
      name: '',
      email: '',
      password: '',
      phone: '',
      role: 'user',
    },
    validate: {
      name: (v) => (v.length > 0 ? null : 'Name is required'),
      email: (v) => (/^\S+@\S+$/.test(v) ? null : 'Valid email is required'),
      password: (v) => {
        if (!isEditing && (!v || v.length < 8)) return 'Password must be at least 8 characters';
        if (isEditing && v && v.length > 0 && v.length < 8) return 'Password must be at least 8 characters';
        return null;
      },
    },
  });

  return (
    <form onSubmit={form.onSubmit(onSubmit)}>
      <Stack>
        <TextInput label="Name" placeholder="Full name" required {...form.getInputProps('name')} />
        <TextInput label="Email" placeholder="user@email.com" required {...form.getInputProps('email')} />
        <PasswordInput
          label="Password"
          placeholder={isEditing ? 'Leave blank to keep current' : 'Min 8 characters'}
          required={!isEditing}
          {...form.getInputProps('password')}
        />
        <TextInput label="Phone" placeholder="+254 7xx xxx xxx" {...form.getInputProps('phone')} />
        <Select
          label="Role"
          data={[
            { value: 'admin', label: 'Admin' },
            { value: 'user', label: 'User' },
          ]}
          required
          {...form.getInputProps('role')}
        />
        <Group justify="flex-end">
          <Button type="submit" loading={loading}>
            {isEditing ? 'Update User' : 'Create User'}
          </Button>
        </Group>
      </Stack>
    </form>
  );
}
