import { AppShell, NavLink, Group, Text, Avatar, Menu, UnstyledButton, Burger, ActionIcon, Image, useMantineColorScheme, useComputedColorScheme, Button, Badge, Tooltip } from '@mantine/core';
import { useDisclosure } from '@mantine/hooks';
import {
  IconDashboard, IconUsers, IconUsersGroup, IconPackages,
  IconFileText, IconFileInvoice, IconReceipt,
  IconCalendarDue, IconSettings, IconLogout, IconCalendarRepeat,
  IconSun, IconMoon, IconMessage, IconArrowBack, IconCreditCard, IconLink,
} from '@tabler/icons-react';
import { Outlet, useNavigate, useLocation } from 'react-router-dom';
import { useAuth } from '../../context/AuthContext';
import NotificationBell from './NotificationBell';

export default function AppLayout() {
  const [opened, { toggle }] = useDisclosure();
  const { user, logout, isImpersonating, exitImpersonation, subscriptionStatus, daysRemaining } = useAuth();
  const { toggleColorScheme } = useMantineColorScheme();
  const computedColorScheme = useComputedColorScheme('light');
  const navigate = useNavigate();
  const location = useLocation();

  const isActive = (path: string) => location.pathname === path;

  const handleLogout = async () => {
    await logout();
    navigate('/login');
  };

  const handleExitImpersonation = () => {
    exitImpersonation();
    navigate('/admin/tenants');
  };

  const showSubscriptionBanner = !isImpersonating && subscriptionStatus === 'trial' && daysRemaining <= 5;
  const headerHeight = (isImpersonating ? 96 : 60) + (showSubscriptionBanner ? 36 : 0);

  return (
    <AppShell
      navbar={{ width: 250, breakpoint: 'sm', collapsed: { mobile: !opened } }}
      header={{ height: headerHeight }}
      padding="md"
    >
      <AppShell.Header>
        {showSubscriptionBanner && (
          <Group h={36} px="md" justify="space-between" bg="yellow.6" style={{ color: 'white', cursor: 'pointer' }} onClick={() => navigate('/subscription')}>
            <Text size="sm" fw={600}>
              {daysRemaining > 0
                ? `Free trial ends in ${daysRemaining} day(s) — Subscribe now to keep access`
                : 'Your free trial has expired — Subscribe now'}
            </Text>
            <Button size="compact-sm" variant="white" color="yellow">
              View Plans
            </Button>
          </Group>
        )}
        {isImpersonating && (
          <Group h={36} px="md" justify="space-between" bg="orange.6" style={{ color: 'white' }}>
            <Text size="sm" fw={600}>Viewing as: {user?.tenant?.name}</Text>
            <Button
              size="compact-sm"
              variant="white"
              color="orange"
              leftSection={<IconArrowBack size={14} />}
              onClick={handleExitImpersonation}
            >
              Back to Admin
            </Button>
          </Group>
        )}
        <Group h={60} px="md" justify="space-between">
          <Group>
            <Burger opened={opened} onClick={toggle} hiddenFrom="sm" size="sm" />
            <Image src="/moinfotech-logo.png" h={32} w="auto" alt="MoBilling" />
            <Text size="lg" fw={700}>MoBilling</Text>
          </Group>
          <Group gap="sm">
            <SubscriptionBadge
              status={subscriptionStatus}
              daysRemaining={daysRemaining}
              onClick={() => navigate('/subscription')}
            />
            <NotificationBell />
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
              {isImpersonating && (
                <Menu.Item leftSection={<IconArrowBack size={14} />} onClick={handleExitImpersonation}>
                  Back to Admin
                </Menu.Item>
              )}
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
          <NavLink label="Payments" leftSection={<IconReceipt size={16} />}
            active={isActive('/payments-in')} onClick={() => navigate('/payments-in')} />
          <NavLink label="Subscriptions" leftSection={<IconLink size={16} />}
            active={isActive('/client-subscriptions')} onClick={() => navigate('/client-subscriptions')} />
          <NavLink label="Next Bills" leftSection={<IconCalendarRepeat size={16} />}
            active={isActive('/next-bills')} onClick={() => navigate('/next-bills')} />
        </NavLink>

        <NavLink label="Statutory" leftSection={<IconCalendarDue size={18} />} defaultOpened>
          <NavLink label="Bills"
            active={isActive('/bills')} onClick={() => navigate('/bills')} />
          <NavLink label="Payment History" leftSection={<IconReceipt size={16} />}
            active={isActive('/payments-out')} onClick={() => navigate('/payments-out')} />
        </NavLink>

        <NavLink label="SMS" leftSection={<IconMessage size={18} />}
          active={isActive('/sms')} onClick={() => navigate('/sms')} />

        <NavLink label="Subscription" leftSection={<IconCreditCard size={18} />}
          active={isActive('/subscription')} onClick={() => navigate('/subscription')} />

        <NavLink label="Team" leftSection={<IconUsersGroup size={18} />}
          active={isActive('/users')} onClick={() => navigate('/users')} />

        <NavLink label="Settings" leftSection={<IconSettings size={18} />}
          active={isActive('/settings')} onClick={() => navigate('/settings')} />
      </AppShell.Navbar>

      <AppShell.Main>
        <Outlet />
      </AppShell.Main>
    </AppShell>
  );
}

function SubscriptionBadge({
  status,
  daysRemaining,
  onClick,
}: {
  status: string | null;
  daysRemaining: number;
  onClick: () => void;
}) {
  if (!status) return null;

  const color = daysRemaining <= 0 ? 'red' : daysRemaining <= 7 ? 'orange'
    : status === 'trial' ? 'blue' : status === 'subscribed' ? 'green'
    : status === 'expired' ? 'red' : 'gray';

  let label: string;
  if (status === 'expired' || status === 'deactivated') {
    label = status === 'expired' ? 'Expired' : 'Deactivated';
  } else {
    const prefix = status === 'trial' ? 'Trial' : 'Plan';
    label = `${prefix} \u00B7 ${daysRemaining}d left`;
  }

  return (
    <Tooltip label="Manage subscription">
      <Badge
        color={color}
        variant="light"
        size="lg"
        style={{ cursor: 'pointer' }}
        onClick={onClick}
      >
        {label}
      </Badge>
    </Tooltip>
  );
}
