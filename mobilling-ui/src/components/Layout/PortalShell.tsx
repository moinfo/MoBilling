import {
  AppShell, Group, Text, Avatar, Menu, UnstyledButton, Burger,
  ActionIcon, Image, useMantineColorScheme, useComputedColorScheme, ScrollArea, Button,
} from '@mantine/core';
import { useDisclosure } from '@mantine/hooks';
import { useQuery } from '@tanstack/react-query';
import { getPortalDashboard } from '../../api/portal';
import classes from './PortalShell.module.css';
import { useCallback } from 'react';
import {
  IconDashboard, IconFileInvoice, IconFileText, IconCash, IconReceipt,
  IconCalendarRepeat, IconWorld, IconWorldWww, IconMessageCircle, IconNews, IconBook, IconUser, IconUsers, IconLogout, IconSun, IconMoon,
  IconLock, IconPackage, IconShoppingCart, IconArrowBack,
} from '@tabler/icons-react';
import { Outlet, useNavigate, useLocation } from 'react-router-dom';
import { useAuth } from '../../context/AuthContext';
import { useBranding } from '../../branding';
import { useLanguage } from '../../i18n/LanguageContext';

export default function PortalShell() {
  const [opened, { toggle, close }] = useDisclosure();
  const { user, logout, permissions, isImpersonatingClient, exitClientImpersonation } = useAuth();
  const branding = useBranding();
  const { t } = useLanguage();
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

  // Live counts so the badges mean something — a stale "5" is worse than none.
  const { data: dash } = useQuery({
    queryKey: ['portal-dashboard'],
    queryFn: getPortalDashboard,
    staleTime: 60_000,
  });
  const counts = dash?.data as Record<string, number> | undefined;

  /**
   * Five labelled groups, per the design. The original 17 flat items were
   * unscannable — grouping is the whole point of this sidebar.
   * `alert` renders the badge amber: it marks something needing action.
   */
  const navGroups: {
    label: string;
    items: {
      icon: typeof IconDashboard;
      label: string;
      path: string;
      count?: number;
      alert?: boolean;
      permission?: string;
    }[];
  }[] = [
    {
      label: t('nav.overview'),
      items: [
        { icon: IconDashboard, label: t('nav.dashboard'), path: '/portal/dashboard' },
        { icon: IconNews, label: t('nav.news'), path: '/portal/announcements' },
      ],
    },
    {
      label: t('nav.services'),
      items: [
        { icon: IconWorld, label: t('nav.myHosting'), path: '/portal/hosting', count: counts?.services_count },
        { icon: IconWorldWww, label: t('nav.myDomains'), path: '/portal/domains', count: counts?.domains_count },
        { icon: IconPackage, label: t('nav.productsServices'), path: '/portal/products-services' },
        { icon: IconCalendarRepeat, label: t('nav.subscriptions'), path: '/portal/subscriptions' },
        { icon: IconShoppingCart, label: t('nav.orderServices'), path: '/order' },
      ],
    },
    {
      label: t('nav.billing'),
      items: [
        {
          icon: IconFileInvoice,
          label: t('nav.invoices'),
          path: '/portal/invoices',
          count: counts?.unpaid_invoices_count,
          alert: (counts?.overdue_count ?? 0) > 0,
        },
        { icon: IconCash, label: t('nav.payments'), path: '/portal/payments' },
        { icon: IconFileText, label: t('nav.quotations'), path: '/portal/quotations' },
        { icon: IconReceipt, label: t('nav.creditNotes'), path: '/portal/credit-notes' },
        { icon: IconReceipt, label: t('nav.statement'), path: '/portal/statement' },
      ],
    },
    {
      label: t('nav.support'),
      items: [
        { icon: IconMessageCircle, label: t('nav.tickets'), path: '/portal/tickets', count: counts?.tickets_count },
        { icon: IconBook, label: t('nav.knowledgebase'), path: '/portal/knowledgebase' },
      ],
    },
    {
      label: t('nav.account'),
      items: [
        { icon: IconUser, label: t('nav.profile'), path: '/portal/profile' },
        { icon: IconUsers, label: t('nav.portalUsers'), path: '/portal/users', permission: 'portal.users' },
      ],
    },
  ];

  return (
    <AppShell
      header={{ height: isImpersonatingClient ? 96 : 60 }}
      navbar={{ width: 244, breakpoint: 'sm', collapsed: { mobile: !opened } }}
      padding="md"
    >
      <AppShell.Header>
        {isImpersonatingClient && (
          <Group h={36} px="md" justify="space-between" bg="orange.6" style={{ color: 'white' }} wrap="nowrap">
            <Text size="xs" fw={600} truncate>
              Staff view — logged in as {user?.name} ({user?.client?.name})
            </Text>
            <Button
              size="compact-xs" variant="white" color="orange"
              leftSection={<IconArrowBack size={14} />}
              onClick={exitClientImpersonation}
              style={{ flexShrink: 0 }}
            >
              Back to Admin
            </Button>
          </Group>
        )}
        <Group h={60} px="md" justify="space-between">
          <Group gap="sm">
            <Burger opened={opened} onClick={toggle} hiddenFrom="sm" size="sm" />
            {(branding.branded ? branding.logo_url : '/moinfotech-logo.png') && (
              <Image src={branding.branded ? branding.logo_url! : '/moinfotech-logo.png'} h={32} w="auto"
                alt={branding.branded ? branding.name : 'MoBilling'} />
            )}
            <Text fw={700} size="lg" visibleFrom="sm">
              {branding.branded ? `${branding.name} — Client Portal` : 'Client Portal'}
            </Text>
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
                {isImpersonatingClient && (
                  <Menu.Item leftSection={<IconArrowBack size={14} />} onClick={exitClientImpersonation}>
                    Back to Admin
                  </Menu.Item>
                )}
                <Menu.Divider />
                <Menu.Item color="red" leftSection={<IconLogout size={14} />} onClick={handleLogout}>
                  Logout
                </Menu.Item>
              </Menu.Dropdown>
            </Menu>
          </Group>
        </Group>
      </AppShell.Header>

      <AppShell.Navbar p={0} className={classes.sidebar}>
        <AppShell.Section grow component={ScrollArea}>
          {user?.client?.name && (
            <div className={classes.groupLabel}>{user.client.name}</div>
          )}

          {navGroups.map((group) => {
            const items = group.items.filter(
              (i) => !i.permission || permissions.includes(i.permission),
            );
            if (!items.length) return null;
            return (
              <div key={group.label}>
                <div className={classes.groupLabel}>{group.label}</div>
                {items.map((item) => (
                  <button
                    key={item.path}
                    type="button"
                    className={`${classes.item} ${isActive(item.path) ? classes.itemActive : ''}`}
                    onClick={() => navigateAndClose(item.path)}
                    aria-current={isActive(item.path) ? 'page' : undefined}
                  >
                    <span className={classes.marker} aria-hidden="true">▸</span>
                    <item.icon size={16} />
                    <span className={classes.itemLabel}>{item.label}</span>
                    {item.count !== undefined && item.count > 0 && (
                      <span className={`${classes.badge} ${item.alert ? classes.badgeAlert : ''}`}>
                        {item.count}
                      </span>
                    )}
                  </button>
                ))}
              </div>
            );
          })}
        </AppShell.Section>

        <AppShell.Section className={classes.footer}>
          <div className={classes.status}>
            <span className={classes.statusDot} aria-hidden="true" />
            {t('nav.operational')}
          </div>
          <button type="button" className={classes.item} onClick={handleLogout}>
            <IconLogout size={16} />
            <span className={classes.itemLabel}>{t('nav.signOut')}</span>
          </button>
        </AppShell.Section>
      </AppShell.Navbar>

      <AppShell.Main>
        <Outlet />
      </AppShell.Main>
    </AppShell>
  );
}
