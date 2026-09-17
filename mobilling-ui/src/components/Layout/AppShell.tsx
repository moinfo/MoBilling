import { AppShell, NavLink, Group, Text, Avatar, Menu, UnstyledButton, Burger, ActionIcon, Image, useMantineColorScheme, useComputedColorScheme, Button, Badge, Tooltip, Box, ScrollArea, Modal, TextInput, Stack, Kbd } from '@mantine/core';
import { useDisclosure, useHotkeys } from '@mantine/hooks';
import { useState, useCallback, useMemo, useEffect } from 'react';
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
  IconDatabase, IconShoppingCart, IconDeviceLaptop, IconBuildingBank, IconWifi, IconRouter, IconTicket,
  IconCalendarTime, IconMoneybag, IconUserCog, IconSearch,
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
  const showRecords = canAny(['menu.system_records', 'menu.my_verifications', 'menu.report_balance_statement']);
  const showWifi = can('menu.wifi_hotspot');
  const showComms = canAny(['menu.sms', 'menu.broadcast', 'menu.announcements']);
  const showAccount = canAny(['menu.subscription', 'menu.users', 'menu.roles', 'settings.users', 'menu.settings']);

  // Flat, searchable mirror of the sidebar tree below — kept as plain data
  // (not derived from the JSX) so search doesn't need to walk/parse the
  // render tree. Reuses the exact same can()/show* checks already computed
  // above, so visibility never drifts from what's actually in the sidebar.
  // NOTE: when adding a new sidebar item below, add its search entry here too.
  const navSearchItems = useMemo(() => [
    { label: 'Dashboard', path: '/dashboard', group: '', visible: can('menu.dashboard') },
    { label: 'Hosting — Accounts', path: '/hosting', group: 'Web Services', visible: can('menu.hosting') },
    { label: 'Hosting — Manage Services', path: '/hosting/services', group: 'Web Services', visible: can('menu.hosting') },
    { label: 'Hosting — Discover Accounts', path: '/hosting/discover', group: 'Web Services', visible: can('menu.hosting') },
    { label: 'Domains', path: '/domains', group: 'Web Services', visible: can('menu.domains') },
    { label: 'Support Tickets', path: '/tickets', group: 'Support', visible: can('menu.tickets') },
    { label: 'Canned Replies', path: '/canned-replies', group: 'Support', visible: can('menu.tickets') },
    { label: 'Knowledgebase', path: '/knowledgebase', group: 'Support', visible: can('menu.announcements') },
    { label: 'Satisfaction Calls', path: '/satisfaction-calls', group: 'Engagement', visible: can('menu.satisfaction_calls') },
    { label: 'Appointments', path: '/appointments', group: 'Engagement', visible: can('menu.satisfaction_calls') },
    { label: 'WhatsApp', path: '/whatsapp-contacts', group: 'Engagement', visible: can('menu.whatsapp') },
    { label: 'Field Marketing', path: '/field-marketing', group: 'Engagement', visible: can('menu.field_marketing') },
    { label: 'Social Media', path: '/social-media', group: 'Engagement', visible: can('menu.social_media') },
    { label: 'Served Customers', path: '/served-customers', group: 'Engagement', visible: can('menu.served_customers') },
    { label: 'Collection', path: '/collection', group: 'Billing', visible: can('menu.collection') },
    { label: 'Follow-ups', path: '/followups', group: 'Billing', visible: can('menu.followups') },
    { label: 'Clients', path: '/clients', group: 'Billing', visible: can('menu.clients') },
    { label: 'Portal Users', path: '/portal-users', group: 'Billing', visible: can('menu.portal_users') },
    { label: 'Add Order', path: '/orders', group: 'Billing', visible: can('orders.create') },
    { label: 'Products & Services', path: '/product-services', group: 'Billing', visible: can('menu.products') },
    { label: 'Product Add-ons', path: '/product-addons', group: 'Billing', visible: can('menu.product_addons') },
    { label: 'Configurable Options', path: '/config-options', group: 'Billing', visible: can('menu.config_options') },
    { label: 'Promotions / Coupons', path: '/coupons', group: 'Billing', visible: can('menu.coupons') },
    { label: 'Quotations', path: '/quotations', group: 'Billing', visible: can('menu.quotations') },
    { label: 'Proforma Invoices', path: '/proformas', group: 'Billing', visible: can('menu.proformas') },
    { label: 'Invoices', path: '/invoices', group: 'Billing', visible: can('menu.invoices') },
    { label: 'Unpaid Invoices', path: '/invoices?status=unpaid&range=all', group: 'Billing', visible: can('menu.invoices') },
    { label: 'Credit Notes', path: '/credit-notes', group: 'Billing', visible: can('menu.invoices') },
    { label: 'Payments', path: '/payments-in', group: 'Billing', visible: can('menu.payments_in') },
    { label: 'Subscriptions', path: '/client-subscriptions', group: 'Billing', visible: can('menu.client_subscriptions') },
    { label: 'Next Bills', path: '/next-bills', group: 'Billing', visible: can('menu.next_bills') },
    { label: 'Obligations', path: '/statutories', group: 'Statutory', visible: can('menu.statutories') },
    { label: 'Schedule', path: '/statutory-schedule', group: 'Statutory', visible: can('menu.statutories') },
    { label: 'Bills', path: '/bills', group: 'Statutory', visible: can('menu.statutory_bills') },
    { label: 'Categories', path: '/bill-categories', group: 'Statutory', visible: can('menu.bill_categories') },
    { label: 'Payment History', path: '/payments-out', group: 'Statutory', visible: can('menu.payments_out') },
    { label: 'Expense Categories', path: '/expense-categories', group: 'Expenses', visible: can('menu.expense_categories') },
    { label: 'Expenses', path: '/expenses', group: 'Expenses', visible: can('menu.expenses') },
    { label: 'Petty Cash', path: '/petty-cash', group: 'Expenses', visible: can('menu.petty_cash') },
    { label: 'System Records', path: '/system-records', group: 'Records & Verification', visible: showSystemRecords },
    { label: 'Bank Balance Statement', path: '/reports/bank-balance-statement', group: 'Records & Verification', visible: can('menu.report_balance_statement') },
    { label: 'My Verifications', path: '/my-verifications', group: 'Records & Verification', visible: can('menu.my_verifications') },
    { label: 'WiFi Routers', path: '/wifi-routers', group: 'WiFi Hotspot', visible: can('wifi_routers.read') },
    { label: 'WiFi Plans', path: '/wifi-plans', group: 'WiFi Hotspot', visible: can('wifi_plans.read') },
    { label: 'WiFi Voucher Sales', path: '/wifi-voucher-purchases', group: 'WiFi Hotspot', visible: can('wifi_purchases.read') },
    { label: 'WiFi My Earnings', path: '/wifi-earnings', group: 'WiFi Hotspot', visible: can('wifi_purchases.read') },
    { label: 'Revenue Summary', path: '/reports/revenue', group: 'Reports', visible: showReports },
    { label: 'Outstanding & Aging', path: '/reports/aging', group: 'Reports', visible: showReports },
    { label: 'Client Statement', path: '/reports/client-statement', group: 'Reports', visible: showReports },
    { label: 'Payment Collection', path: '/reports/payment-collection', group: 'Reports', visible: showReports },
    { label: 'Expense Report', path: '/reports/expenses', group: 'Reports', visible: showReports },
    { label: 'System Records Report', path: '/reports/system-records', group: 'Reports', visible: can('menu.report_system_records') },
    { label: 'System Verifications Report', path: '/reports/system-verifications', group: 'Reports', visible: can('menu.report_system_verifications') },
    { label: 'Profit & Loss', path: '/reports/profit-loss', group: 'Reports', visible: showReports },
    { label: 'Statutory Compliance', path: '/reports/statutory', group: 'Reports', visible: showReports },
    { label: 'Subscriptions Report', path: '/reports/subscriptions', group: 'Reports', visible: showReports },
    { label: 'Collection Effectiveness', path: '/reports/collection-effectiveness', group: 'Reports', visible: showReports },
    { label: 'Satisfaction Calls Report', path: '/reports/satisfaction-calls', group: 'Reports', visible: showReports },
    { label: 'Communication Log', path: '/reports/communication-log', group: 'Reports', visible: showReports },
    { label: 'SMS', path: '/sms', group: 'Communications', visible: can('menu.sms') },
    { label: 'Broadcast', path: '/broadcast', group: 'Communications', visible: can('menu.broadcast') },
    { label: 'Announcements', path: '/announcements', group: 'Communications', visible: can('menu.announcements') },
    { label: 'Staff Reports', path: '/staff-reports', group: 'HR', visible: can('menu.staff_reports') },
    { label: 'Attendance', path: '/attendance', group: 'HR', visible: can('attendance.manage') },
    { label: 'Staff Targets', path: '/staff-targets', group: 'HR', visible: can('menu.staff_targets') },
    { label: 'Leave', path: '/leave', group: 'HR', visible: can('menu.leave') },
    { label: 'Payroll', path: '/payroll', group: 'HR', visible: can('menu.payroll') },
    { label: 'Automation', path: '/automation', group: '', visible: can('menu.automation') },
    { label: 'Subscription', path: '/subscription', group: 'Account', visible: can('menu.subscription') && !user?.tenant?.is_self_hosted },
    { label: 'Team', path: '/users', group: 'Account', visible: can('menu.users') && can('settings.users') },
    { label: 'Roles', path: '/roles', group: 'Account', visible: can('menu.roles') && can('settings.users') },
    { label: 'Active Sessions', path: '/sessions', group: 'Account', visible: can('settings.users') },
    { label: 'Settings', path: '/settings', group: 'Account', visible: can('menu.settings') },
    // eslint-disable-next-line react-hooks/exhaustive-deps
  ].filter((i) => i.visible), [can, showSystemRecords, showReports, user?.tenant?.is_self_hosted]);

  const [searchOpen, setSearchOpen] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  useHotkeys([['mod+K', () => setSearchOpen(true)]]);
  useEffect(() => { if (!searchOpen) setSearchQuery(''); }, [searchOpen]);

  const searchResults = useMemo(() => {
    const q = searchQuery.trim().toLowerCase();
    if (!q) return navSearchItems;
    return navSearchItems.filter((i) => i.label.toLowerCase().includes(q) || i.group.toLowerCase().includes(q));
  }, [navSearchItems, searchQuery]);

  const goToSearchResult = (path: string) => {
    navigate(path);
    setSearchOpen(false);
    close();
  };

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
            <Tooltip label="Search menu (Ctrl+K)" visibleFrom="sm">
              <ActionIcon variant="default" size="lg" onClick={() => setSearchOpen(true)} aria-label="Search menu">
                <IconSearch size={18} />
              </ActionIcon>
            </Tooltip>
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
              {can('menu.report_balance_statement') && (
                <NavLink label="Bank Balance Statement" leftSection={<IconBuildingBank size={16} />}
                  active={isActive('/reports/bank-balance-statement')} onClick={() => navigateAndClose('/reports/bank-balance-statement')} />
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

          {showWifi && (
            <NavLink label="WiFi Hotspot" leftSection={<IconWifi size={18} />}
              opened={openSection === 'wifi'} onChange={() => toggleSection('wifi')}>
              {can('wifi_routers.read') && (
                <NavLink label="Routers" leftSection={<IconRouter size={16} />}
                  active={isActive('/wifi-routers')} onClick={() => navigateAndClose('/wifi-routers')} />
              )}
              {can('wifi_plans.read') && (
                <NavLink label="Plans" leftSection={<IconWifi size={16} />}
                  active={isActive('/wifi-plans')} onClick={() => navigateAndClose('/wifi-plans')} />
              )}
              {can('wifi_purchases.read') && (
                <NavLink label="Voucher Sales" leftSection={<IconTicket size={16} />}
                  active={isActive('/wifi-voucher-purchases')} onClick={() => navigateAndClose('/wifi-voucher-purchases')} />
              )}
              {can('wifi_purchases.read') && (
                <NavLink label="My Earnings" leftSection={<IconBuildingBank size={16} />}
                  active={isActive('/wifi-earnings')} onClick={() => navigateAndClose('/wifi-earnings')} />
              )}
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
              {can('menu.report_balance_statement') && (
                <NavLink label="Bank Balance Statement" leftSection={<IconBuildingBank size={16} />}
                  active={isActive('/reports/bank-balance-statement')} onClick={() => navigateAndClose('/reports/bank-balance-statement')} />
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
              {can('menu.subscription') && !user?.tenant?.is_self_hosted && (
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

      <Modal opened={searchOpen} onClose={() => setSearchOpen(false)} title="Search Menu" size="md">
        <Stack gap="xs">
          <TextInput
            placeholder="Type to search menus…"
            leftSection={<IconSearch size={16} />}
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.currentTarget.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter' && searchResults.length > 0) {
                goToSearchResult(searchResults[0].path);
              }
            }}
            autoFocus
            data-autofocus
          />
          <ScrollArea.Autosize mah={400}>
            <Stack gap={2}>
              {searchResults.length === 0 ? (
                <Text size="sm" c="dimmed" ta="center" py="md">No matching menu found</Text>
              ) : (
                searchResults.map((item) => (
                  <NavLink
                    key={item.path + item.label}
                    label={item.label}
                    description={item.group || undefined}
                    onClick={() => goToSearchResult(item.path)}
                    style={{ borderRadius: 6 }}
                  />
                ))
              )}
            </Stack>
          </ScrollArea.Autosize>
          <Group justify="flex-end" gap={4}>
            <Text size="xs" c="dimmed">Tip: <Kbd size="xs">Ctrl</Kbd> + <Kbd size="xs">K</Kbd> to open this anytime</Text>
          </Group>
        </Stack>
      </Modal>
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
