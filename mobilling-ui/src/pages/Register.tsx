import { TextInput, PasswordInput, Button, Paper, Title, Text, Container, Anchor, Stack } from '@mantine/core';
import { useForm } from '@mantine/form';
import { notifications } from '@mantine/notifications';
import { useAuth } from '../context/AuthContext';
import { useNavigate, Link } from 'react-router-dom';

export default function Register() {
  const { register } = useAuth();
  const navigate = useNavigate();

  const form = useForm({
    initialValues: {
      company_name: '',
      name: '',
      email: '',
      phone: '',
      password: '',
      password_confirmation: '',
    },
    validate: {
      company_name: (v) => (v.length > 0 ? null : 'Company name is required'),
      name: (v) => (v.length > 0 ? null : 'Name is required'),
      email: (v) => (/^\S+@\S+$/.test(v) ? null : 'Invalid email'),
      password: (v) => (v.length >= 8 ? null : 'Password must be at least 8 characters'),
      password_confirmation: (v, values) =>
        v === values.password ? null : 'Passwords do not match',
    },
  });

  const handleSubmit = async (values: typeof form.values) => {
    try {
      await register(values);
      navigate('/');
    } catch (err: any) {
      const errors = err.response?.data?.errors;
      if (errors) {
        Object.entries(errors).forEach(([key, messages]) => {
          form.setFieldError(key, (messages as string[])[0]);
        });
      } else {
        notifications.show({
          title: 'Registration failed',
          message: err.response?.data?.message || 'Something went wrong',
          color: 'red',
        });
      }
    }
  };

  return (
    <Container size={480} my={40}>
      <Title ta="center">MoBilling</Title>
      <Text c="dimmed" size="sm" ta="center" mt={5}>
        Create your account
      </Text>

      <Paper withBorder shadow="md" p={30} mt={30} radius="md">
        <form onSubmit={form.onSubmit(handleSubmit)}>
          <Stack>
            <TextInput label="Company Name" placeholder="Your company" required {...form.getInputProps('company_name')} />
            <TextInput label="Your Name" placeholder="John Doe" required {...form.getInputProps('name')} />
            <TextInput label="Email" placeholder="you@email.com" required {...form.getInputProps('email')} />
            <TextInput label="Phone" placeholder="+254 7xx xxx xxx" {...form.getInputProps('phone')} />
            <PasswordInput label="Password" placeholder="Min 8 characters" required {...form.getInputProps('password')} />
            <PasswordInput label="Confirm Password" placeholder="Repeat password" required {...form.getInputProps('password_confirmation')} />
            <Button fullWidth type="submit">Create Account</Button>
          </Stack>
        </form>
        <Text c="dimmed" size="sm" ta="center" mt="md">
          Already have an account?{' '}
          <Anchor component={Link} to="/login" size="sm">Sign in</Anchor>
        </Text>
      </Paper>
    </Container>
  );
}
