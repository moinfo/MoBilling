import {
  AppShell, Group, Text, Avatar, Menu, UnstyledButton, Burger,
  ActionIcon, Image, useMantineColorScheme, useComputedColorScheme, ScrollArea,
} from '@mantine/core';
import { useDisclosure } from '@mantine/hooks';
import { useQuery } from '@tanstack/react-query';
import { getPortalDashboard } from '../../api/portal';
import classes from './PortalShell.module.css';
import { useCallback } from 'react';
import {
  IconDashboard, IconFileInvoice, IconFileText, IconCash, IconReceipt,
  IconCalendarRepeat, IconWorld, IconWorldWww, IconMessageCircle, IconNews, IconBook, IconUser, IconUsers, IconLogout, IconSun, IconMoon,
  IconLock, IconPackage, IconShoppingCart,
} from '@tabler/icons-react';
import { Outlet, useNavigate, useLocation } from 'react-router-dom';
import { useAuth } from '../../context/AuthContext';
import { useBranding } from '../../branding';

export default function PortalShell() {
  const [opened, { toggle, close }] = useDisclosure();
  const { user, logout, permissions } = useAuth();
  const branding = useBranding();
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
      label: 'Overview',
      items: [
        { icon: IconDashboard, label: 'Dashboard', path: '/portal/dashboard' },
        { icon: IconNews, label: 'News', path: '/portal/announcements' },
      ],
    },
    {
      label: 'Services',
      items: [
        { icon: IconWorld, label: 'My Hosting', path: '/portal/hosting', count: counts?.services_count },
        { icon: IconWorldWww, label: 'My Domains', path: '/portal/domains', count: counts?.domains_count },
        { icon: IconPackage, label: 'Products & Services', path: '/portal/products-services' },
        { icon: IconCalendarRepeat, label: 'Subscriptions', path: '/portal/subscriptions' },
        { icon: IconShoppingCart, label: 'Order Services', path: '/order' },
      ],
    },
    {
      label: 'Billing',
      items: [
        {
          icon: IconFileInvoice,
          label: 'Invoices',
          path: '/portal/invoices',
          count: counts?.unpaid_invoices_count,
          alert: (counts?.overdue_count ?? 0) > 0,
        },
        { icon: IconCash, label: 'Payments', path: '/portal/payments' },
        { icon: IconFileText, label: 'Quotations', path: '/portal/quotations' },
        { icon: IconReceipt, label: 'Credit Notes', path: '/portal/credit-notes' },
        { icon: IconReceipt, label: 'Statement', path: '/portal/statement' },
      ],
    },
    {
      label: 'Support',
      items: [
        { icon: IconMessageCircle, label: 'Support Tickets', path: '/portal/tickets', count: counts?.tickets_count },
        { icon: IconBook, label: 'Knowledgebase', path: '/portal/knowledgebase' },
      ],
    },
    {
      label: 'Account',
      items: [
        { icon: IconUser, label: 'Profile', path: '/portal/profile' },
        { icon: IconUsers, label: 'Portal Users', path: '/portal/users', permission: 'portal.users' },
      ],
    },
  ];

  return (
    <AppShell
      header={{ height: 60 }}
      navbar={{ width: 244, breakpoint: 'sm', collapsed: { mobile: !opened } }}
      padding="md"
    >
      <AppShell.Header>
        <Group h="100%" px="md" justify="space-between">
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
            ALL SYSTEMS OPERATIONAL
          </div>
          <button type="button" className={classes.item} onClick={handleLogout}>
            <IconLogout size={16} />
            <span className={classes.itemLabel}>Sign out</span>
          </button>
        </AppShell.Section>
      </AppShell.Navbar>

      <AppShell.Main>
        <Outlet />
      </AppShell.Main>
    </AppShell>
  );
}
