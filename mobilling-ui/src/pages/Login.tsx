import { TextInput, PasswordInput, Button, Paper, Title, Text, Container, Anchor, Stack } from '@mantine/core';
import { useForm } from '@mantine/form';
import { notifications } from '@mantine/notifications';
import { useAuth } from '../context/AuthContext';
import { useNavigate, Link } from 'react-router-dom';

export default function Login() {
  const { login } = useAuth();
  const navigate = useNavigate();

  const form = useForm({
    initialValues: { email: '', password: '' },
    validate: {
      email: (v) => (/^\S+@\S+$/.test(v) ? null : 'Invalid email'),
      password: (v) => (v.length > 0 ? null : 'Password is required'),
    },
  });

  const handleSubmit = async (values: typeof form.values) => {
    try {
      await login(values);
      navigate('/');
    } catch (err: any) {
      notifications.show({
        title: 'Login failed',
        message: err.response?.data?.message || 'Invalid credentials',
        color: 'red',
      });
    }
  };

  return (
    <Container size={420} my={40}>
      <Title ta="center">MoBilling</Title>
      <Text c="dimmed" size="sm" ta="center" mt={5}>
        Sign in to your account
      </Text>

      <Paper withBorder shadow="md" p={30} mt={30} radius="md">
        <form onSubmit={form.onSubmit(handleSubmit)}>
          <Stack>
            <TextInput label="Email" placeholder="you@email.com" required {...form.getInputProps('email')} />
            <PasswordInput label="Password" placeholder="Your password" required {...form.getInputProps('password')} />
            <Button fullWidth type="submit">Sign in</Button>
          </Stack>
        </form>
        <Text c="dimmed" size="sm" ta="center" mt="md">
          Don&apos;t have an account?{' '}
          <Anchor component={Link} to="/register" size="sm">Register</Anchor>
        </Text>
      </Paper>
    </Container>
  );
}
