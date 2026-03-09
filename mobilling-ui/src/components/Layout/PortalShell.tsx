import {
  AppShell, NavLink, Group, Text, Avatar, Menu, UnstyledButton, Burger,
  ActionIcon, Image, useMantineColorScheme, useComputedColorScheme, ScrollArea,
} from '@mantine/core';
import { useDisclosure } from '@mantine/hooks';
import { useCallback } from 'react';
import {
  IconDashboard, IconFileInvoice, IconFileText, IconCash, IconReceipt,
  IconCalendarRepeat, IconUser, IconUsers, IconLogout, IconSun, IconMoon,
  IconLock,
} from '@tabler/icons-react';
import { Outlet, useNavigate, useLocation } from 'react-router-dom';
import { useAuth } from '../../context/AuthContext';

export default function PortalShell() {
  const [opened, { toggle, close }] = useDisclosure();
  const { user, logout, permissions } = useAuth();
  const { toggleColorScheme } = useMantineColorScheme();
  const computedColorScheme = useComputedColorScheme('light');
  const navigate = useNavigate();
  const location = useLocation();

  const isActive = (path: string) => location.pathname === path;

  const navigateAndClose = useCallback((path: string) => {
    navigate(path);
    close();
  }, [navigate, close]);

  const handleLogout = async () => {
    await logout();
    navigate('/login');
  };

  const canManageUsers = permissions.includes('portal.users');

  const navItems = [
    { icon: IconDashboard, label: 'Dashboard', path: '/portal/dashboard' },
    { icon: IconFileInvoice, label: 'Invoices', path: '/portal/invoices' },
    { icon: IconFileText, label: 'Quotations', path: '/portal/quotations' },
    { icon: IconCash, label: 'Payments', path: '/portal/payments' },
    { icon: IconReceipt, label: 'Statement', path: '/portal/statement' },
    { icon: IconCalendarRepeat, label: 'Subscriptions', path: '/portal/subscriptions' },
    { icon: IconUser, label: 'Profile', path: '/portal/profile' },
  ];

  return (
    <AppShell
      header={{ height: 60 }}
      navbar={{ width: 260, breakpoint: 'sm', collapsed: { mobile: !opened } }}
      padding="md"
    >
      <AppShell.Header>
        <Group h="100%" px="md" justify="space-between">
          <Group gap="sm">
            <Burger opened={opened} onClick={toggle} hiddenFrom="sm" size="sm" />
            <Image src="/moinfotech-logo.png" h={32} w="auto" alt="MoBilling" />
            <Text fw={700} size="lg" visibleFrom="sm">Client Portal</Text>
          </Group>
          <Group gap="xs">
            <ActionIcon variant="default" size="lg" onClick={toggleColorScheme}>
              {computedColorScheme === 'dark' ? <IconSun size={18} /> : <IconMoon size={18} />}
            </ActionIcon>
            <Menu shadow="md" width={200}>
              <Menu.Target>
                <UnstyledButton>
                  <Group gap="xs">
                    <Avatar radius="xl" size="sm" color="blue">
                      {user?.name?.charAt(0)?.toUpperCase()}
                    </Avatar>
                    <Text size="sm" fw={500} visibleFrom="sm">{user?.name}</Text>
                  </Group>
                </UnstyledButton>
              </Menu.Target>
              <Menu.Dropdown>
                <Menu.Item leftSection={<IconUser size={14} />} onClick={() => navigate('/portal/profile')}>
                  Profile
                </Menu.Item>
                <Menu.Item leftSection={<IconLock size={14} />} onClick={() => navigate('/portal/profile')}>
                  Change Password
                </Menu.Item>
                <Menu.Divider />
                <Menu.Item color="red" leftSection={<IconLogout size={14} />} onClick={handleLogout}>
                  Logout
                </Menu.Item>
              </Menu.Dropdown>
            </Menu>
          </Group>
        </Group>
      </AppShell.Header>

      <AppShell.Navbar p="xs">
        <AppShell.Section grow component={ScrollArea}>
          {user?.client?.name && (
            <Text size="xs" fw={600} c="dimmed" tt="uppercase" px="sm" py="xs">
              {user.client.name}
            </Text>
          )}
          {navItems.map((item) => (
            <NavLink
              key={item.path}
              label={item.label}
              leftSection={<item.icon size={18} />}
              active={isActive(item.path)}
              onClick={() => navigateAndClose(item.path)}
            />
          ))}
          {canManageUsers && (
            <NavLink
              label="Portal Users"
              leftSection={<IconUsers size={18} />}
              active={isActive('/portal/users')}
              onClick={() => navigateAndClose('/portal/users')}
            />
          )}
        </AppShell.Section>
      </AppShell.Navbar>

      <AppShell.Main>
        <Outlet />
      </AppShell.Main>
    </AppShell>
  );
}
