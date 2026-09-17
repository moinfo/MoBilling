import { TextInput, Select, Button, Group, Stack, PasswordInput } from '@mantine/core';
import { useForm } from '@mantine/form';
import { useQuery } from '@tanstack/react-query';
import { UserFormData } from '../../api/users';
import { getRoles, Role } from '../../api/roles';
import { getWorkLocations, WorkLocation } from '../../api/workLocations';
import { usePermissions } from '../../hooks/usePermissions';

interface Props {
  initialValues?: UserFormData;
  onSubmit: (values: UserFormData) => void;
  loading?: boolean;
}

export default function UserForm({ initialValues, onSubmit, loading }: Props) {
  const isEditing = !!initialValues;
  const { can } = usePermissions();
  const showWorkLocation = isEditing && can('menu.work_locations');

  const { data: rolesData } = useQuery({
    queryKey: ['roles'],
    queryFn: () => getRoles(),
  });

  const { data: locationsData } = useQuery({
    queryKey: ['work-locations', 'picker'],
    queryFn: () => getWorkLocations({ per_page: 200 }),
    enabled: showWorkLocation,
  });

  const roles: Role[] = rolesData?.data?.data || [];
  const roleOptions = roles.map((r) => ({ value: r.id, label: r.label }));

  const locations: WorkLocation[] = locationsData?.data?.data || [];
  const locationOptions = locations.map((l) => ({ value: l.id, label: l.name }));

  const form = useForm<UserFormData>({
    initialValues: initialValues || {
      name: '',
      email: '',
      password: '',
      phone: '',
      role_id: '',
      work_location_id: null,
    },
    validate: {
      name: (v) => (v.length > 0 ? null : 'Name is required'),
      email: (v) => (/^\S+@\S+$/.test(v) ? null : 'Valid email is required'),
      role_id: (v) => (v ? null : 'Role is required'),
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
          data={roleOptions}
          required
          placeholder="Select a role"
          {...form.getInputProps('role_id')}
        />
        {showWorkLocation && (
          <Select
            label="Work Location"
            description="Where this staff member checks in from (mobile app self-check-in)"
            data={locationOptions}
            placeholder="No location assigned"
            clearable
            {...form.getInputProps('work_location_id')}
          />
        )}
        <Group justify="flex-end">
          <Button type="submit" loading={loading}>
            {isEditing ? 'Update User' : 'Create User'}
          </Button>
        </Group>
      </Stack>
    </form>
  );
}
