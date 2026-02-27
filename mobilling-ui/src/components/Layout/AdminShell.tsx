import { AppShell, NavLink, Group, Text, Avatar, Menu, UnstyledButton, Burger, ActionIcon, Image, useMantineColorScheme, useComputedColorScheme, ScrollArea } from '@mantine/core';
import { useDisclosure } from '@mantine/hooks';
import { IconDashboard, IconBuilding, IconLogout, IconSun, IconMoon, IconMail, IconTemplate, IconMessage, IconPackage, IconReceipt, IconCreditCard, IconCoin, IconBuildingBank, IconShieldLock, IconShieldCheck } from '@tabler/icons-react';
import { Outlet, useNavigate, useLocation } from 'react-router-dom';
import { useAuth } from '../../context/AuthContext';
import NotificationBell from './NotificationBell';

export default function AdminShell() {
  const [opened, { toggle, close }] = useDisclosure();
  const { user, logout } = useAuth();
  const { toggleColorScheme } = useMantineColorScheme();
  const computedColorScheme = useComputedColorScheme('light');
  const navigate = useNavigate();
  const location = useLocation();

  const handleLogout = async () => {
    await logout();
    navigate('/login');
  };

  const navigateAndClose = (path: string) => {
    navigate(path);
    close();
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
            <Text size="lg" fw={700} visibleFrom="xs">MoBilling</Text>
          </Group>
          <Group gap="xs">
            <NotificationBell />
            <ActionIcon variant="default" size="lg" onClick={toggleColorScheme} aria-label="Toggle color scheme">
              {computedColorScheme === 'dark' ? <IconSun size={18} /> : <IconMoon size={18} />}
            </ActionIcon>
            <Menu shadow="md" width={200}>
              <Menu.Target>
                <UnstyledButton>
                  <Group gap="xs">
                    <Avatar radius="xl" size="sm" color="violet">{user?.name?.[0]}</Avatar>
                    <Text size="sm" visibleFrom="sm">{user?.name}</Text>
                  </Group>
                </UnstyledButton>
              </Menu.Target>
              <Menu.Dropdown>
                <Menu.Label>Super Admin</Menu.Label>
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
        <AppShell.Section grow component={ScrollArea} type="scroll">
          <NavLink
            label="Dashboard"
            leftSection={<IconDashboard size={18} />}
            active={location.pathname === '/admin/dashboard'}
            onClick={() => navigateAndClose('/admin/dashboard')}
          />
          <NavLink
            label="Tenants"
            leftSection={<IconBuilding size={18} />}
            active={location.pathname === '/admin/tenants'}
            onClick={() => navigateAndClose('/admin/tenants')}
          />
          <NavLink
            label="Permissions"
            leftSection={<IconShieldLock size={18} />}
            active={location.pathname === '/admin/permissions'}
            onClick={() => navigateAndClose('/admin/permissions')}
          />
          <NavLink
            label="Roles"
            leftSection={<IconShieldCheck size={18} />}
            active={location.pathname === '/admin/roles'}
            onClick={() => navigateAndClose('/admin/roles')}
          />
          <NavLink
            label="Email Settings"
            leftSection={<IconMail size={18} />}
            active={location.pathname === '/admin/email-settings'}
            onClick={() => navigateAndClose('/admin/email-settings')}
          />
          <NavLink
            label="Email Templates"
            leftSection={<IconTemplate size={18} />}
            active={location.pathname === '/admin/email-templates'}
            onClick={() => navigateAndClose('/admin/email-templates')}
          />
          <NavLink
            label="SMS Settings"
            leftSection={<IconMessage size={18} />}
            active={location.pathname === '/admin/sms-settings'}
            onClick={() => navigateAndClose('/admin/sms-settings')}
          />
          <NavLink
            label="SMS Packages"
            leftSection={<IconPackage size={18} />}
            active={location.pathname === '/admin/sms-packages'}
            onClick={() => navigateAndClose('/admin/sms-packages')}
          />
          <NavLink
            label="SMS Purchases"
            leftSection={<IconReceipt size={18} />}
            active={location.pathname === '/admin/sms-purchases'}
            onClick={() => navigateAndClose('/admin/sms-purchases')}
          />
          <NavLink
            label="Subscription Plans"
            leftSection={<IconCreditCard size={18} />}
            active={location.pathname === '/admin/subscription-plans'}
            onClick={() => navigateAndClose('/admin/subscription-plans')}
          />
          <NavLink
            label="Currencies"
            leftSection={<IconCoin size={18} />}
            active={location.pathname === '/admin/currencies'}
            onClick={() => navigateAndClose('/admin/currencies')}
          />
          <NavLink
            label="Platform Settings"
            leftSection={<IconBuildingBank size={18} />}
            active={location.pathname === '/admin/platform-settings'}
            onClick={() => navigateAndClose('/admin/platform-settings')}
          />
        </AppShell.Section>
      </AppShell.Navbar>

      <AppShell.Main>
        <Outlet />
      </AppShell.Main>
    </AppShell>
  );
}
