import { AppShell, NavLink, Group, Text, Avatar, Menu, UnstyledButton, Burger, ActionIcon, Image, useMantineColorScheme, useComputedColorScheme, Button, Badge, Tooltip, Box, ScrollArea } from '@mantine/core';
import { useDisclosure } from '@mantine/hooks';
import { useState, useCallback } from 'react';
import {
  IconDashboard, IconUsers, IconUsersGroup, IconPackages,
  IconFileText, IconFileInvoice, IconReceipt, IconFileDescription, IconFileCheck,
  IconCalendarDue, IconSettings, IconLogout, IconCalendarRepeat,
  IconSun, IconMoon, IconMessage, IconArrowBack, IconCreditCard, IconLink,
  IconClipboardList, IconCalendarEvent, IconCategory, IconFileSpreadsheet,
  IconWallet, IconCategory2, IconReceipt2, IconRobot, IconTargetArrow, IconPhoneCall,
  IconReportAnalytics, IconCash, IconClock, IconFileAnalytics, IconCreditCard as IconCreditCardReport,
  IconWallet as IconWalletReport, IconScale, IconShieldCheck, IconLink as IconLinkReport,
  IconChartBar, IconMail, IconSpeakerphone,
} from '@tabler/icons-react';
import { Outlet, useNavigate, useLocation } from 'react-router-dom';
import { useAuth } from '../../context/AuthContext';
import NotificationBell from './NotificationBell';

export default function AppLayout() {
  const [opened, { toggle, close }] = useDisclosure();
  const { user, logout, isImpersonating, exitImpersonation, subscriptionStatus, daysRemaining } = useAuth();
  const { toggleColorScheme } = useMantineColorScheme();
  const computedColorScheme = useComputedColorScheme('light');
  const navigate = useNavigate();
  const location = useLocation();

  const isActive = (path: string) => location.pathname === path;

  // Determine which section the current route belongs to
  const billingPaths = ['/clients', '/product-services', '/quotations', '/proformas', '/invoices', '/payments-in', '/client-subscriptions', '/next-bills'];
  const statutoryPaths = ['/statutories', '/statutory-schedule', '/bills', '/bill-categories', '/payments-out'];
  const expensePaths = ['/expense-categories', '/expenses'];
  const reportPaths = ['/reports/revenue', '/reports/aging', '/reports/client-statement', '/reports/payment-collection', '/reports/expenses', '/reports/profit-loss', '/reports/statutory', '/reports/subscriptions', '/reports/collection-effectiveness', '/reports/communication-log'];

  const getActiveSection = () => {
    if (billingPaths.some((p) => location.pathname === p)) return 'billing';
    if (statutoryPaths.some((p) => location.pathname === p)) return 'statutory';
    if (expensePaths.some((p) => location.pathname === p)) return 'expenses';
    if (reportPaths.some((p) => location.pathname === p)) return 'reports';
    return null;
  };

  const [openSection, setOpenSection] = useState<string | null>(getActiveSection);

  const toggleSection = useCallback((section: string) => {
    setOpenSection((prev) => (prev === section ? null : section));
  }, []);

  const navigateAndClose = useCallback((path: string) => {
    navigate(path);
    close(); // close mobile drawer
  }, [navigate, close]);

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
          <Group h={36} px="md" justify="space-between" bg="yellow.6" style={{ color: 'white', cursor: 'pointer' }} wrap="nowrap" onClick={() => navigate('/subscription')}>
            <Text size="xs" fw={600} truncate>
              {daysRemaining > 0
                ? `Trial ends in ${daysRemaining}d — Subscribe now`
                : 'Trial expired — Subscribe now'}
            </Text>
            <Button size="compact-xs" variant="white" color="yellow" style={{ flexShrink: 0 }}>
              Plans
            </Button>
          </Group>
        )}
        {isImpersonating && (
          <Group h={36} px="md" justify="space-between" bg="orange.6" style={{ color: 'white' }} wrap="nowrap">
            <Text size="xs" fw={600} truncate>Viewing: {user?.tenant?.name}</Text>
            <Button
              size="compact-xs"
              variant="white"
              color="orange"
              leftSection={<IconArrowBack size={14} />}
              onClick={handleExitImpersonation}
              style={{ flexShrink: 0 }}
            >
              Exit
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
              visibleFrom="sm"
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
        <AppShell.Section grow component={ScrollArea} type="scroll">
          <NavLink label="Dashboard" leftSection={<IconDashboard size={18} />}
            active={isActive('/dashboard')} onClick={() => navigateAndClose('/dashboard')} />

          <NavLink label="Collection" leftSection={<IconTargetArrow size={18} />}
            active={isActive('/collection')} onClick={() => navigateAndClose('/collection')} />

          <NavLink label="Follow-ups" leftSection={<IconPhoneCall size={18} />}
            active={isActive('/followups')} onClick={() => navigateAndClose('/followups')} />

          <NavLink label="Billing" leftSection={<IconFileText size={18} />}
            opened={openSection === 'billing'} onChange={() => toggleSection('billing')}>
            <NavLink label="Clients" leftSection={<IconUsers size={16} />}
              active={isActive('/clients')} onClick={() => navigateAndClose('/clients')} />
            <NavLink label="Products & Services" leftSection={<IconPackages size={16} />}
              active={isActive('/product-services')} onClick={() => navigateAndClose('/product-services')} />
            <NavLink label="Quotations" leftSection={<IconFileDescription size={16} />}
              active={isActive('/quotations')} onClick={() => navigateAndClose('/quotations')} />
            <NavLink label="Proforma Invoices" leftSection={<IconFileCheck size={16} />}
              active={isActive('/proformas')} onClick={() => navigateAndClose('/proformas')} />
            <NavLink label="Invoices" leftSection={<IconFileInvoice size={16} />}
              active={isActive('/invoices')} onClick={() => navigateAndClose('/invoices')} />
            <NavLink label="Payments" leftSection={<IconReceipt size={16} />}
              active={isActive('/payments-in')} onClick={() => navigateAndClose('/payments-in')} />
            <NavLink label="Subscriptions" leftSection={<IconLink size={16} />}
              active={isActive('/client-subscriptions')} onClick={() => navigateAndClose('/client-subscriptions')} />
            <NavLink label="Next Bills" leftSection={<IconCalendarRepeat size={16} />}
              active={isActive('/next-bills')} onClick={() => navigateAndClose('/next-bills')} />
          </NavLink>

          <NavLink label="Statutory" leftSection={<IconCalendarDue size={18} />}
            opened={openSection === 'statutory'} onChange={() => toggleSection('statutory')}>
            <NavLink label="Obligations" leftSection={<IconClipboardList size={16} />}
              active={isActive('/statutories')} onClick={() => navigateAndClose('/statutories')} />
            <NavLink label="Schedule" leftSection={<IconCalendarEvent size={16} />}
              active={isActive('/statutory-schedule')} onClick={() => navigateAndClose('/statutory-schedule')} />
            <NavLink label="Bills" leftSection={<IconFileSpreadsheet size={16} />}
              active={isActive('/bills')} onClick={() => navigateAndClose('/bills')} />
            <NavLink label="Categories" leftSection={<IconCategory size={16} />}
              active={isActive('/bill-categories')} onClick={() => navigateAndClose('/bill-categories')} />
            <NavLink label="Payment History" leftSection={<IconReceipt size={16} />}
              active={isActive('/payments-out')} onClick={() => navigateAndClose('/payments-out')} />
          </NavLink>

          <NavLink label="Expenses" leftSection={<IconWallet size={18} />}
            opened={openSection === 'expenses'} onChange={() => toggleSection('expenses')}>
            <NavLink label="Categories" leftSection={<IconCategory2 size={16} />}
              active={isActive('/expense-categories')} onClick={() => navigateAndClose('/expense-categories')} />
            <NavLink label="Expenses" leftSection={<IconReceipt2 size={16} />}
              active={isActive('/expenses')} onClick={() => navigateAndClose('/expenses')} />
          </NavLink>

          <NavLink label="Reports" leftSection={<IconReportAnalytics size={18} />}
            opened={openSection === 'reports'} onChange={() => toggleSection('reports')}>
            <NavLink label="Revenue Summary" leftSection={<IconCash size={16} />}
              active={isActive('/reports/revenue')} onClick={() => navigateAndClose('/reports/revenue')} />
            <NavLink label="Outstanding & Aging" leftSection={<IconClock size={16} />}
              active={isActive('/reports/aging')} onClick={() => navigateAndClose('/reports/aging')} />
            <NavLink label="Client Statement" leftSection={<IconFileAnalytics size={16} />}
              active={isActive('/reports/client-statement')} onClick={() => navigateAndClose('/reports/client-statement')} />
            <NavLink label="Payment Collection" leftSection={<IconCreditCardReport size={16} />}
              active={isActive('/reports/payment-collection')} onClick={() => navigateAndClose('/reports/payment-collection')} />
            <NavLink label="Expense Report" leftSection={<IconWalletReport size={16} />}
              active={isActive('/reports/expenses')} onClick={() => navigateAndClose('/reports/expenses')} />
            <NavLink label="Profit & Loss" leftSection={<IconScale size={16} />}
              active={isActive('/reports/profit-loss')} onClick={() => navigateAndClose('/reports/profit-loss')} />
            <NavLink label="Statutory Compliance" leftSection={<IconShieldCheck size={16} />}
              active={isActive('/reports/statutory')} onClick={() => navigateAndClose('/reports/statutory')} />
            <NavLink label="Subscriptions" leftSection={<IconLinkReport size={16} />}
              active={isActive('/reports/subscriptions')} onClick={() => navigateAndClose('/reports/subscriptions')} />
            <NavLink label="Collection Effectiveness" leftSection={<IconChartBar size={16} />}
              active={isActive('/reports/collection-effectiveness')} onClick={() => navigateAndClose('/reports/collection-effectiveness')} />
            <NavLink label="Communication Log" leftSection={<IconMail size={16} />}
              active={isActive('/reports/communication-log')} onClick={() => navigateAndClose('/reports/communication-log')} />
          </NavLink>

          <NavLink label="SMS" leftSection={<IconMessage size={18} />}
            active={isActive('/sms')} onClick={() => navigateAndClose('/sms')} />

          <NavLink label="Broadcast" leftSection={<IconSpeakerphone size={18} />}
            active={isActive('/broadcast')} onClick={() => navigateAndClose('/broadcast')} />

          <NavLink label="Subscription" leftSection={<IconCreditCard size={18} />}
            active={isActive('/subscription')} onClick={() => navigateAndClose('/subscription')} />

          <NavLink label="Automation" leftSection={<IconRobot size={18} />}
            active={isActive('/automation')} onClick={() => navigateAndClose('/automation')} />

          <NavLink label="Team" leftSection={<IconUsersGroup size={18} />}
            active={isActive('/users')} onClick={() => navigateAndClose('/users')} />

          <NavLink label="Settings" leftSection={<IconSettings size={18} />}
            active={isActive('/settings')} onClick={() => navigateAndClose('/settings')} />
        </AppShell.Section>
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
  visibleFrom,
}: {
  status: string | null;
  daysRemaining: number;
  onClick: () => void;
  visibleFrom?: string;
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
    <Box visibleFrom={visibleFrom as any}>
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
    </Box>
  );
}
