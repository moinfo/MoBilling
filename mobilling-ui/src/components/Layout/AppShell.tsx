import { AppShell, NavLink, Group, Text, Avatar, Menu, UnstyledButton, Burger, ActionIcon, Image, useMantineColorScheme, useComputedColorScheme } from '@mantine/core';
import { useDisclosure } from '@mantine/hooks';
import {
  IconDashboard, IconUsers, IconPackages,
  IconFileText, IconFileInvoice, IconReceipt,
  IconCalendarDue, IconSettings, IconLogout,
  IconSun, IconMoon,
} from '@tabler/icons-react';
import { Outlet, useNavigate, useLocation } from 'react-router-dom';
import { useAuth } from '../../context/AuthContext';

export default function AppLayout() {
  const [opened, { toggle }] = useDisclosure();
  const { user, logout } = useAuth();
  const { toggleColorScheme } = useMantineColorScheme();
  const computedColorScheme = useComputedColorScheme('light');
  const navigate = useNavigate();
  const location = useLocation();

  const isActive = (path: string) => location.pathname === path;

  const handleLogout = async () => {
    await logout();
    navigate('/login');
  };

  return (
    <AppShell
      navbar={{ width: 250, breakpoint: 'sm', collapsed: { mobile: !opened } }}
      header={{ height: 60 }}
      padding="md"
    >
      <AppShell.Header>
        <Group h="100%" px="md" justify="space-between">
          <Group>
            <Burger opened={opened} onClick={toggle} hiddenFrom="sm" size="sm" />
            <Image src="/moinfotech-logo.png" h={32} w="auto" alt="MoBilling" />
            <Text size="lg" fw={700}>MoBilling</Text>
          </Group>
          <Group gap="xs">
            <ActionIcon variant="default" size="lg" onClick={toggleColorScheme} aria-label="Toggle color scheme">
              {computedColorScheme === 'dark' ? <IconSun size={18} /> : <IconMoon size={18} />}
            </ActionIcon>
          <Menu shadow="md" width={200}>
            <Menu.Target>
              <UnstyledButton>
                <Group gap="xs">
                  <Avatar radius="xl" size="sm" color="blue">{user?.name?.[0]}</Avatar>
                  <Text size="sm" visibleFrom="sm">{user?.name}</Text>
                </Group>
              </UnstyledButton>
            </Menu.Target>
            <Menu.Dropdown>
              <Menu.Label>{user?.tenant?.name}</Menu.Label>
              <Menu.Item leftSection={<IconSettings size={14} />} onClick={() => navigate('/settings')}>
                Settings
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
        <NavLink label="Dashboard" leftSection={<IconDashboard size={18} />}
          active={isActive('/dashboard')} onClick={() => navigate('/dashboard')} />

        <NavLink label="Billing" leftSection={<IconFileText size={18} />} defaultOpened>
          <NavLink label="Clients" leftSection={<IconUsers size={16} />}
            active={isActive('/clients')} onClick={() => navigate('/clients')} />
          <NavLink label="Products & Services" leftSection={<IconPackages size={16} />}
            active={isActive('/product-services')} onClick={() => navigate('/product-services')} />
          <NavLink label="Quotations"
            active={isActive('/quotations')} onClick={() => navigate('/quotations')} />
          <NavLink label="Proforma Invoices"
            active={isActive('/proformas')} onClick={() => navigate('/proformas')} />
          <NavLink label="Invoices" leftSection={<IconFileInvoice size={16} />}
            active={isActive('/invoices')} onClick={() => navigate('/invoices')} />
        </NavLink>

        <NavLink label="Statutory" leftSection={<IconCalendarDue size={18} />} defaultOpened>
          <NavLink label="Bills"
            active={isActive('/bills')} onClick={() => navigate('/bills')} />
          <NavLink label="Payment History" leftSection={<IconReceipt size={16} />}
            active={isActive('/payments-out')} onClick={() => navigate('/payments-out')} />
        </NavLink>

        <NavLink label="Settings" leftSection={<IconSettings size={18} />}
          active={isActive('/settings')} onClick={() => navigate('/settings')} />
      </AppShell.Navbar>

      <AppShell.Main>
        <Outlet />
      </AppShell.Main>
    </AppShell>
  );
}
