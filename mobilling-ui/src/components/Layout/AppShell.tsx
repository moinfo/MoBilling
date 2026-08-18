import { AppShell, NavLink, Group, Text, Avatar, Menu, UnstyledButton, Burger, ActionIcon, Image, useMantineColorScheme, useComputedColorScheme, Button, Badge, Tooltip, Box, ScrollArea } from '@mantine/core';
import { useDisclosure } from '@mantine/hooks';
import { useState, useCallback } from 'react';
import {
  IconDashboard, IconUsers, IconUsersGroup, IconPackages,
  IconFileText, IconFileInvoice, IconReceipt, IconFileDescription, IconFileCheck,
  IconCalendarDue, IconSettings, IconLogout, IconCalendarRepeat,
  IconSun, IconMoon, IconMessage, IconArrowBack, IconCreditCard, IconLink,
  IconClipboardList, IconClipboardCheck, IconCalendarEvent, IconCategory, IconFileSpreadsheet,
  IconWallet, IconCategory2, IconReceipt2, IconRobot, IconTargetArrow, IconPhoneCall, IconWorld, IconWorldWww, IconMessageCircle, IconMessageDots, IconNews, IconBook,
  IconReportAnalytics, IconCash, IconClock, IconFileAnalytics, IconCreditCard as IconCreditCardReport,
  IconWallet as IconWalletReport, IconScale, IconShieldCheck, IconLink as IconLinkReport,
  IconChartBar, IconMail, IconSpeakerphone, IconShieldLock,
  IconHeartHandshake, IconBrandWhatsapp, IconMapPin, IconBrandInstagram, IconUserCheck,
  IconDatabase, IconShoppingCart, IconDeviceLaptop,
  IconCalendarTime, IconMoneybag, IconUserCog,
} from '@tabler/icons-react';
import { Outlet, useNavigate, useLocation } from 'react-router-dom';
import { useAuth } from '../../context/AuthContext';
import { usePermissions } from '../../hooks/usePermissions';
import NotificationBell from './NotificationBell';

export default function AppLayout() {
  const [opened, { toggle, close }] = useDisclosure();
  const { user, logout, isImpersonating, exitImpersonation, subscriptionStatus, daysRemaining } = useAuth();
  const { can, canAny } = usePermissions();
  const { toggleColorScheme } = useMantineColorScheme();
  const computedColorScheme = useComputedColorScheme('light');
  const navigate = useNavigate();
  const location = useLocation();

  const isActive = (path: string) => location.pathname === path;

  // Determine which section the current route belongs to
  const billingPaths = ['/collection', '/followups', '/clients', '/product-services', '/product-addons', '/config-options', '/coupons', '/quotations', '/proformas', '/invoices', '/credit-notes', '/payments-in', '/client-subscriptions', '/next-bills'];
  const statutoryPaths = ['/statutories', '/statutory-schedule', '/bills', '/bill-categories', '/payments-out'];
  const expensePaths = ['/expense-categories', '/expenses', '/petty-cash'];
  const reportPaths = ['/reports/revenue', '/reports/aging', '/reports/client-statement', '/reports/payment-collection', '/reports/expenses', '/reports/system-records', '/reports/system-verifications', '/reports/profit-loss', '/reports/statutory', '/reports/subscriptions', '/reports/collection-effectiveness', '/reports/satisfaction-calls', '/reports/communication-log'];
  const hrPaths = ['/staff-reports', '/attendance', '/staff-targets', '/leave', '/payroll'];
  const webServicesPaths = ['/hosting', '/hosting/services', '/hosting/discover', '/domains'];
  const supportPaths = ['/tickets', '/canned-replies', '/knowledgebase'];
  const engagementPaths = ['/satisfaction-calls', '/appointments', '/whatsapp-contacts', '/field-marketing', '/social-media', '/served-customers'];
  const recordsPaths = ['/system-records', '/my-verifications'];
  const commsPaths = ['/sms', '/broadcast', '/announcements'];
  const accountPaths = ['/subscription', '/users', '/roles', '/sessions', '/settings'];

  const getActiveSection = () => {
    if (billingPaths.some((p) => location.pathname === p)) return 'billing';
    if (statutoryPaths.some((p) => location.pathname === p)) return 'statutory';
    if (expensePaths.some((p) => location.pathname === p)) return 'expenses';
    if (reportPaths.some((p) => location.pathname === p)) return 'reports';
    if (hrPaths.some((p) => location.pathname === p)) return 'hr';
    if (webServicesPaths.some((p) => location.pathname === p) || location.pathname.startsWith('/hosting')) return 'webservices';
    if (supportPaths.some((p) => location.pathname === p)) return 'support';
    if (engagementPaths.some((p) => location.pathname === p)) return 'engagement';
    if (recordsPaths.some((p) => location.pathname === p)) return 'records';
    if (commsPaths.some((p) => location.pathname === p)) return 'comms';
    if (accountPaths.some((p) => location.pathname === p)) return 'account';
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

  // Check if any billing sub-items are visible
  const showBilling = canAny(['menu.collection', 'menu.followups', 'menu.clients', 'menu.products', 'menu.quotations', 'menu.proformas', 'menu.invoices', 'menu.payments_in', 'menu.client_subscriptions', 'menu.next_bills']);
  const showStatutory = canAny(['menu.statutories', 'menu.statutory_bills', 'menu.bill_categories', 'menu.payments_out']);
  const showExpenses = canAny(['menu.expense_categories', 'menu.expenses', 'menu.petty_cash']);
  // The three reference CRUDs (Systems / Bank Accounts / System Properties)
  // are accessed via the Settings page tabs, not the sidebar. Only the
  // top-level data-entry CRUD (System Records) appears here.
  const showSystemRecords = can('menu.system_records');
  const showReports = can('menu.reports');
  const showHr = canAny(['menu.staff_reports', 'attendance.manage', 'menu.staff_targets', 'menu.leave', 'menu.payroll']);
  // Grouped nav parents (Dec 2026 reorg) — each is purely a visual container;
  // every leaf item below still gates on the exact same permission it always did.
  const showWebServices = canAny(['menu.hosting', 'menu.domains']);
  const showSupport = canAny(['menu.tickets', 'menu.announcements']);
  const showEngagement = canAny(['menu.satisfaction_calls', 'menu.whatsapp', 'menu.field_marketing', 'menu.social_media', 'menu.served_customers']);
  const showRecords = canAny(['menu.system_records', 'menu.my_verifications']);
  const showComms = canAny(['menu.sms', 'menu.broadcast', 'menu.announcements']);
  const showAccount = canAny(['menu.subscription', 'menu.users', 'menu.roles', 'settings.users', 'menu.settings']);

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
          {can('menu.dashboard') && (
            <NavLink label="Dashboard" leftSection={<IconDashboard size={18} />}
              active={isActive('/dashboard')} onClick={() => navigateAndClose('/dashboard')} />
          )}

          {showWebServices && (
            <NavLink label="Web Services" leftSection={<IconWorld size={18} />}
              opened={openSection === 'webservices'} onChange={() => toggleSection('webservices')}>
              {can('menu.hosting') && (
                <NavLink label="Hosting" leftSection={<IconWorld size={16} />}
                  defaultOpened={isActive('/hosting')}>
                  <NavLink label="Accounts" active={location.pathname === '/hosting'}
                    onClick={() => navigateAndClose('/hosting')} />
                  <NavLink label="Manage Services" active={location.pathname.startsWith('/hosting/services')}
                    onClick={() => navigateAndClose('/hosting/services')} />
                  <NavLink label="Discover Accounts" active={location.pathname === '/hosting/discover'}
                    onClick={() => navigateAndClose('/hosting/discover')} />
                </NavLink>
              )}
              {can('menu.domains') && (
                <NavLink label="Domains" leftSection={<IconWorldWww size={16} />}
                  active={isActive('/domains')} onClick={() => navigateAndClose('/domains')} />
              )}
            </NavLink>
          )}

          {showSupport && (
            <NavLink label="Support" leftSection={<IconMessageCircle size={18} />}
              opened={openSection === 'support'} onChange={() => toggleSection('support')}>
              {can('menu.tickets') && (
                <NavLink label="Support Tickets" leftSection={<IconMessageCircle size={16} />}
                  active={isActive('/tickets')} onClick={() => navigateAndClose('/tickets')} />
              )}
              {can('menu.tickets') && (
                <NavLink label="Canned Replies" leftSection={<IconMessageDots size={16} />}
                  active={isActive('/canned-replies')} onClick={() => navigateAndClose('/canned-replies')} />
              )}
              {can('menu.announcements') && (
                <NavLink label="Knowledgebase" leftSection={<IconBook size={16} />}
                  active={isActive('/knowledgebase')} onClick={() => navigateAndClose('/knowledgebase')} />
              )}
            </NavLink>
          )}

          {showEngagement && (
            <NavLink label="Engagement" leftSection={<IconHeartHandshake size={18} />}
              opened={openSection === 'engagement'} onChange={() => toggleSection('engagement')}>
              {can('menu.satisfaction_calls') && (
                <NavLink label="Satisfaction Calls" leftSection={<IconHeartHandshake size={16} />}
                  active={isActive('/satisfaction-calls')} onClick={() => navigateAndClose('/satisfaction-calls')} />
              )}
              {can('menu.satisfaction_calls') && (
                <NavLink label="Appointments" leftSection={<IconCalendarEvent size={16} />}
                  active={isActive('/appointments')} onClick={() => navigateAndClose('/appointments')} />
              )}
              {can('menu.whatsapp') && (
                <NavLink label="WhatsApp" leftSection={<IconBrandWhatsapp size={16} color="#25D366" />}
                  active={isActive('/whatsapp-contacts')} onClick={() => navigateAndClose('/whatsapp-contacts')} />
              )}
              {can('menu.field_marketing') && (
                <NavLink label="Field Marketing" leftSection={<IconMapPin size={16} />}
                  active={isActive('/field-marketing')} onClick={() => navigateAndClose('/field-marketing')} />
              )}
              {can('menu.social_media') && (
                <NavLink label="Social Media" leftSection={<IconBrandInstagram size={16} />}
                  active={isActive('/social-media')} onClick={() => navigateAndClose('/social-media')} />
              )}
              {can('menu.served_customers') && (
                <NavLink label="Served Customers" leftSection={<IconUserCheck size={16} />}
                  active={isActive('/served-customers')} onClick={() => navigateAndClose('/served-customers')} />
              )}
            </NavLink>
          )}

          {showBilling && (
            <NavLink label="Billing" leftSection={<IconFileText size={18} />}
              opened={openSection === 'billing'} onChange={() => toggleSection('billing')}>
              {can('menu.collection') && (
                <NavLink label="Collection" leftSection={<IconTargetArrow size={16} />}
                  active={isActive('/collection')} onClick={() => navigateAndClose('/collection')} />
              )}
              {can('menu.followups') && (
                <NavLink label="Follow-ups" leftSection={<IconPhoneCall size={16} />}
                  active={isActive('/followups')} onClick={() => navigateAndClose('/followups')} />
              )}
              {can('menu.clients') && (
                <NavLink label="Clients" leftSection={<IconUsers size={16} />}
                  active={isActive('/clients')} onClick={() => navigateAndClose('/clients')} />
              )}
              {can('menu.portal_users') && (
                <NavLink label="Portal Users" leftSection={<IconShieldLock size={16} />}
                  active={isActive('/portal-users')} onClick={() => navigateAndClose('/portal-users')} />
              )}
              {can('orders.create') && (
                <NavLink label="Add Order" leftSection={<IconShoppingCart size={16} />}
                  active={isActive('/orders')} onClick={() => navigateAndClose('/orders')} />
              )}
              {can('menu.products') && (
                <NavLink label="Products & Services" leftSection={<IconPackages size={16} />}
                  active={isActive('/product-services')} onClick={() => navigateAndClose('/product-services')} />
              )}
              {can('menu.product_addons') && (
                <NavLink label="Product Add-ons" leftSection={<IconPackages size={16} />}
                  active={isActive('/product-addons')} onClick={() => navigateAndClose('/product-addons')} />
              )}
              {can('menu.config_options') && (
                <NavLink label="Configurable Options" leftSection={<IconPackages size={16} />}
                  active={isActive('/config-options')} onClick={() => navigateAndClose('/config-options')} />
              )}
              {can('menu.coupons') && (
                <NavLink label="Promotions / Coupons" leftSection={<IconPackages size={16} />}
                  active={isActive('/coupons')} onClick={() => navigateAndClose('/coupons')} />
              )}
              {can('menu.quotations') && (
                <NavLink label="Quotations" leftSection={<IconFileDescription size={16} />}
                  active={isActive('/quotations')} onClick={() => navigateAndClose('/quotations')} />
              )}
              {can('menu.proformas') && (
                <NavLink label="Proforma Invoices" leftSection={<IconFileCheck size={16} />}
                  active={isActive('/proformas')} onClick={() => navigateAndClose('/proformas')} />
              )}
              {can('menu.invoices') && (
                <NavLink label="Invoices" leftSection={<IconFileInvoice size={16} />}
                  active={isActive('/invoices')} onClick={() => navigateAndClose('/invoices')} />
              )}
              {can('menu.invoices') && (
                <NavLink label="Unpaid Invoices" leftSection={<IconClock size={16} />}
                  onClick={() => navigateAndClose('/invoices?status=unpaid&range=all')} />
              )}
              {can('menu.invoices') && (
                <NavLink label="Credit Notes" leftSection={<IconFileInvoice size={16} />}
                  active={isActive('/credit-notes')} onClick={() => navigateAndClose('/credit-notes')} />
              )}
              {can('menu.payments_in') && (
                <NavLink label="Payments" leftSection={<IconReceipt size={16} />}
                  active={isActive('/payments-in')} onClick={() => navigateAndClose('/payments-in')} />
              )}
              {can('menu.client_subscriptions') && (
                <NavLink label="Subscriptions" leftSection={<IconLink size={16} />}
                  active={isActive('/client-subscriptions')} onClick={() => navigateAndClose('/client-subscriptions')} />
              )}
              {can('menu.next_bills') && (
                <NavLink label="Next Bills" leftSection={<IconCalendarRepeat size={16} />}
                  active={isActive('/next-bills')} onClick={() => navigateAndClose('/next-bills')} />
              )}
            </NavLink>
          )}

          {showStatutory && (
            <NavLink label="Statutory" leftSection={<IconCalendarDue size={18} />}
              opened={openSection === 'statutory'} onChange={() => toggleSection('statutory')}>
              {can('menu.statutories') && (
                <NavLink label="Obligations" leftSection={<IconClipboardList size={16} />}
                  active={isActive('/statutories')} onClick={() => navigateAndClose('/statutories')} />
              )}
              {can('menu.statutories') && (
                <NavLink label="Schedule" leftSection={<IconCalendarEvent size={16} />}
                  active={isActive('/statutory-schedule')} onClick={() => navigateAndClose('/statutory-schedule')} />
              )}
              {can('menu.statutory_bills') && (
                <NavLink label="Bills" leftSection={<IconFileSpreadsheet size={16} />}
                  active={isActive('/bills')} onClick={() => navigateAndClose('/bills')} />
              )}
              {can('menu.bill_categories') && (
                <NavLink label="Categories" leftSection={<IconCategory size={16} />}
                  active={isActive('/bill-categories')} onClick={() => navigateAndClose('/bill-categories')} />
              )}
              {can('menu.payments_out') && (
                <NavLink label="Payment History" leftSection={<IconReceipt size={16} />}
                  active={isActive('/payments-out')} onClick={() => navigateAndClose('/payments-out')} />
              )}
            </NavLink>
          )}

          {showExpenses && (
            <NavLink label="Expenses" leftSection={<IconWallet size={18} />}
              opened={openSection === 'expenses'} onChange={() => toggleSection('expenses')}>
              {can('menu.expense_categories') && (
                <NavLink label="Categories" leftSection={<IconCategory2 size={16} />}
                  active={isActive('/expense-categories')} onClick={() => navigateAndClose('/expense-categories')} />
              )}
              {can('menu.expenses') && (
                <NavLink label="Expenses" leftSection={<IconReceipt2 size={16} />}
                  active={isActive('/expenses')} onClick={() => navigateAndClose('/expenses')} />
              )}
              {can('menu.petty_cash') && (
                <NavLink label="Petty Cash" leftSection={<IconCash size={16} />}
                  active={isActive('/petty-cash')} onClick={() => navigateAndClose('/petty-cash')} />
              )}
            </NavLink>
          )}

          {showRecords && (
            <NavLink label="Records & Verification" leftSection={<IconDatabase size={18} />}
              opened={openSection === 'records'} onChange={() => toggleSection('records')}>
              {showSystemRecords && (
                <NavLink label="System Records" leftSection={<IconDatabase size={16} />}
                  active={isActive('/system-records')} onClick={() => navigateAndClose('/system-records')} />
              )}
              {can('menu.my_verifications') && (
                <NavLink label="My Verifications" leftSection={<IconShieldCheck size={16} />}
                  active={isActive('/my-verifications')} onClick={() => navigateAndClose('/my-verifications')} />
              )}
              {/* System Verifications (admin CRUD) lives inside Settings → tab.
                  See pages/Settings.tsx — it's gated by menu.system_verifications
                  which is admin-only after 2026_06_10_100003. */}
            </NavLink>
          )}

          {showReports && (
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
              {can('menu.report_system_records') && (
                <NavLink label="System Records Report" leftSection={<IconDatabase size={16} />}
                  active={isActive('/reports/system-records')} onClick={() => navigateAndClose('/reports/system-records')} />
              )}
              {can('menu.report_system_verifications') && (
                <NavLink label="System Verifications Report" leftSection={<IconShieldCheck size={16} />}
                  active={isActive('/reports/system-verifications')} onClick={() => navigateAndClose('/reports/system-verifications')} />
              )}
              <NavLink label="Profit & Loss" leftSection={<IconScale size={16} />}
                active={isActive('/reports/profit-loss')} onClick={() => navigateAndClose('/reports/profit-loss')} />
              <NavLink label="Statutory Compliance" leftSection={<IconShieldCheck size={16} />}
                active={isActive('/reports/statutory')} onClick={() => navigateAndClose('/reports/statutory')} />
              <NavLink label="Subscriptions" leftSection={<IconLinkReport size={16} />}
                active={isActive('/reports/subscriptions')} onClick={() => navigateAndClose('/reports/subscriptions')} />
              <NavLink label="Collection Effectiveness" leftSection={<IconChartBar size={16} />}
                active={isActive('/reports/collection-effectiveness')} onClick={() => navigateAndClose('/reports/collection-effectiveness')} />
              <NavLink label="Satisfaction Calls" leftSection={<IconHeartHandshake size={16} />}
                active={isActive('/reports/satisfaction-calls')} onClick={() => navigateAndClose('/reports/satisfaction-calls')} />
              <NavLink label="Communication Log" leftSection={<IconMail size={16} />}
                active={isActive('/reports/communication-log')} onClick={() => navigateAndClose('/reports/communication-log')} />
            </NavLink>
          )}

          {showComms && (
            <NavLink label="Communications" leftSection={<IconMessage size={18} />}
              opened={openSection === 'comms'} onChange={() => toggleSection('comms')}>
              {can('menu.sms') && (
                <NavLink label="SMS" leftSection={<IconMessage size={16} />}
                  active={isActive('/sms')} onClick={() => navigateAndClose('/sms')} />
              )}
              {can('menu.broadcast') && (
                <NavLink label="Broadcast" leftSection={<IconSpeakerphone size={16} />}
                  active={isActive('/broadcast')} onClick={() => navigateAndClose('/broadcast')} />
              )}
              {can('menu.announcements') && (
                <NavLink label="Announcements" leftSection={<IconNews size={16} />}
                  active={isActive('/announcements')} onClick={() => navigateAndClose('/announcements')} />
              )}
            </NavLink>
          )}

          {showHr && (
            <NavLink label="HR" leftSection={<IconUserCog size={18} />}
              opened={openSection === 'hr'} onChange={() => toggleSection('hr')}>
              {can('menu.staff_reports') && (
                <NavLink label="Staff Reports" leftSection={<IconClipboardList size={16} />}
                  active={isActive('/staff-reports')} onClick={() => navigateAndClose('/staff-reports')} />
              )}
              {can('attendance.manage') && (
                <NavLink label="Attendance" leftSection={<IconClipboardCheck size={16} />}
                  active={isActive('/attendance')} onClick={() => navigateAndClose('/attendance')} />
              )}
              {can('menu.staff_targets') && (
                <NavLink label="Staff Targets" leftSection={<IconTargetArrow size={16} />}
                  active={isActive('/staff-targets')} onClick={() => navigateAndClose('/staff-targets')} />
              )}
              {can('menu.leave') && (
                <NavLink label="Leave" leftSection={<IconCalendarTime size={16} />}
                  active={isActive('/leave')} onClick={() => navigateAndClose('/leave')} />
              )}
              {can('menu.payroll') && (
                <NavLink label="Payroll" leftSection={<IconMoneybag size={16} />}
                  active={isActive('/payroll')} onClick={() => navigateAndClose('/payroll')} />
              )}
            </NavLink>
          )}

          {can('menu.automation') && (
            <NavLink label="Automation" leftSection={<IconRobot size={18} />}
              active={isActive('/automation')} onClick={() => navigateAndClose('/automation')} />
          )}

          {showAccount && (
            <NavLink label="Account" leftSection={<IconSettings size={18} />}
              opened={openSection === 'account'} onChange={() => toggleSection('account')}>
              {can('menu.subscription') && (
                <NavLink label="Subscription" leftSection={<IconCreditCard size={16} />}
                  active={isActive('/subscription')} onClick={() => navigateAndClose('/subscription')} />
              )}
              {/* Team & Roles pages both require settings.users — only show the nav
                  when the user can actually use the page (was: menu.* only → 403). */}
              {can('menu.users') && can('settings.users') && (
                <NavLink label="Team" leftSection={<IconUsersGroup size={16} />}
                  active={isActive('/users')} onClick={() => navigateAndClose('/users')} />
              )}
              {can('menu.roles') && can('settings.users') && (
                <NavLink label="Roles" leftSection={<IconShieldLock size={16} />}
                  active={isActive('/roles')} onClick={() => navigateAndClose('/roles')} />
              )}
              {can('settings.users') && (
                <NavLink label="Active Sessions" leftSection={<IconDeviceLaptop size={16} />}
                  active={isActive('/sessions')} onClick={() => navigateAndClose('/sessions')} />
              )}
              {can('menu.settings') && (
                <NavLink label="Settings" leftSection={<IconSettings size={16} />}
                  active={isActive('/settings')} onClick={() => navigateAndClose('/settings')} />
              )}
            </NavLink>
          )}
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
