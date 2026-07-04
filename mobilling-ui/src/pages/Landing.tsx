import {
  Container, Title, Text, Button, Group, SimpleGrid, Paper, Box, Image,
  ThemeIcon, ActionIcon, Badge, Stack, Divider, Card, List, Anchor,
  Loader, Center, Burger, Drawer, Accordion, Avatar, Progress,
  useMantineColorScheme, useComputedColorScheme, useMantineTheme,
} from '@mantine/core';
import { useDisclosure, useWindowScroll } from '@mantine/hooks';
import {
  IconFileInvoice, IconFileText, IconCalendarDue,
  IconCash, IconBuildingCommunity,
  IconSun, IconMoon, IconArrowRight,
  IconDeviceMobile, IconCheck,
  IconMail, IconPhone, IconMapPin, IconBrandWhatsapp,
  IconWorld, IconBrandWhatsappFilled, IconWalk, IconMessage2,
  IconRocket, IconTrendingUp, IconHeadset, IconStar,
  IconChevronUp, IconCurrencyDollar, IconQuote,
  IconServer, IconWorldWww, IconRepeat, IconTicket,
  IconLayoutDashboard, IconPalette, IconLock, IconRefresh,
} from '@tabler/icons-react';
import { Link, Navigate } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { motion, AnimatePresence } from 'framer-motion';
import { getPublicPlans, SubscriptionPlan } from '../api/subscription';
import { isBrandedHost } from '../branding';

// ── Data ─────────────────────────────────────────────────────────────────────

const features = [
  { icon: IconFileInvoice,         color: 'blue',   title: 'Invoicing & Recurring Billing', description: 'Professional invoices with automatic numbering, tax, recurring cycles, late fees and dunning — on autopilot.' },
  { icon: IconFileText,            color: 'violet', title: 'Quotations & Proformas', description: 'Win business with polished quotes and proforma invoices that convert to final invoices in one click.' },
  { icon: IconCalendarDue,         color: 'orange', title: 'Statutory Bills',        description: 'Never miss NHIF, NSSF, PAYE, or VAT deadlines with automated tracking and due-date reminders.' },
  { icon: IconCash,                color: 'green',  title: 'Payments & Wallet',      description: 'M-Pesa, Pesapal, bank, cash & cheque — plus a client credit wallet with top-ups and auto-pay.' },
  { icon: IconLayoutDashboard,     color: 'indigo', title: 'Client Portal',          description: 'Your clients log in to order services, pay invoices, open tickets and manage everything themselves.' },
  { icon: IconTicket,              color: 'red',    title: 'Support Helpdesk',       description: 'A full ticketing system — departments, priorities, email notifications — for you and your clients.' },
  { icon: IconBrandWhatsappFilled, color: 'teal',   title: 'WhatsApp Marketing',     description: 'Track leads from WhatsApp & social ads through a full pipeline. Log calls, schedule follow-ups, convert to clients.' },
  { icon: IconWalk,                color: 'cyan',   title: 'Field Marketing',        description: 'Manage door-to-door campaigns. Log visits, track conversion per officer, and measure ROI per session.' },
  { icon: IconMessage2,            color: 'pink',   title: 'SMS & Email Notifications', description: 'Automatic payment reminders, invoice and renewal notices sent to clients via SMS and email.' },
];

const hostingFeatures = [
  { icon: IconServer,   color: 'blue',   title: 'cPanel Hosting Automation', description: 'Connect your WHM server: accounts are created the moment an invoice is paid, suspended on non-payment, upgraded with prorated billing — hands-free.' },
  { icon: IconWorldWww, color: 'teal',   title: '.tz Domain Registrar',      description: 'Register, renew and transfer .tz domains directly at the TCRA/tzNIC registry over EPP. Live availability search, your own pricing per TLD.' },
  { icon: IconRefresh,  color: 'violet', title: 'Auto-Renewals from Wallet', description: 'Clients opt in to auto-renew — renewals invoice themselves and pay from the client\'s credit balance automatically.' },
  { icon: IconLock,     color: 'green',  title: 'SSL & DNS Management',      description: 'Nightly SSL monitoring on every domain, self-service nameserver changes, EPP transfer codes — all from the portal.' },
  { icon: IconLayoutDashboard, color: 'orange', title: 'One-Click cPanel Login', description: 'Clients jump into cPanel, webmail, file manager or phpMyAdmin from their portal — no passwords to share.' },
  { icon: IconRepeat,   color: 'grape',  title: 'Order → Pay → Provision',   description: 'A WHMCS-style shopping cart: clients choose a plan, pick a domain, pay online — and the service goes live automatically.' },
];

const resellerPoints = [
  { icon: IconPalette,          title: 'Your brand, your prices',    desc: 'Run the whole platform under your own business name and logo. Set your own hosting plans and per-TLD domain pricing — keep the margin.' },
  { icon: IconServer,           title: 'We run the machinery',       desc: 'Registry connections, cPanel automation, billing engine, portal, SSL monitoring — maintained for you. You focus on selling.' },
  { icon: IconBuildingCommunity,title: 'Isolated tenant workspace',  desc: 'Your clients, invoices and services live in your own isolated workspace. Your customers only ever see your brand.' },
];

const howItWorks = [
  { num: '01', color: 'blue',  step: 'Create your account',    desc: 'Sign up in seconds. Set up your business profile, logo, and invite your team members.' },
  { num: '02', color: 'teal',  step: 'Add services & pricing', desc: 'Import clients, define hosting plans, domain pricing and services — connect your WHM server if you host.' },
  { num: '03', color: 'green', step: 'Sell on autopilot',      desc: 'Clients order and pay in your portal; provisioning, renewals, reminders and dunning run themselves.' },
];

const socialProof = [
  { value: '500+',  label: 'Businesses onboarded'        },
  { value: '50K+',  label: 'Invoices generated'          },
  { value: '300+',  label: 'Domains & hosting automated' },
  { value: '99.9%', label: 'Uptime'                      },
];

const testimonials = [
  {
    name: 'Amina Hassan',
    company: 'Amina Traders, Dar es Salaam',
    avatar: 'AH',
    color: 'teal',
    text: 'MoBilling replaced our manual Excel tracking. Now I generate invoices and track M-Pesa payments in seconds. Statutory deadlines? I never miss them anymore.',
    stars: 5,
  },
  {
    name: 'David Ochieng',
    company: 'Ochieng IT Solutions, Nairobi',
    avatar: 'DO',
    color: 'blue',
    text: 'We moved our whole hosting business off WHMCS. Domains register themselves when clients pay, cPanel accounts provision automatically, and we stopped paying license fees. Unbelievable.',
    stars: 5,
  },
  {
    name: 'Fatuma Kombo',
    company: 'Kombo Supplies, Mombasa',
    avatar: 'FK',
    color: 'violet',
    text: 'Our field sales team now logs every door-to-door visit from their phones. Management sees real-time conversion stats. Best investment we made this year.',
    stars: 5,
  },
];

const faqs = [
  { q: 'Is MoBilling a WHMCS alternative?',         a: 'Yes. MoBilling does what WHMCS does — client portal, shopping cart, cPanel/WHM auto-provisioning, domain registration & renewals, tickets, recurring billing and dunning — with no separate license fee, and built for East African payments like M-Pesa and Pesapal.' },
  { q: 'Can I sell hosting and domains?',           a: 'Absolutely. Connect your own WHM/cPanel server and MoBilling provisions, suspends and upgrades accounts automatically. .tz domains register and renew directly at the TCRA/tzNIC registry, with your own retail pricing per TLD.' },
  { q: 'What is the white-label reseller program?', a: 'You run MoBilling under your own brand: your logo, your domain pricing, your hosting plans, your client portal. We operate the registry connections, automation and infrastructure behind the scenes — your customers only ever see your business.' },
  { q: 'Is there a free trial?',                    a: 'Yes! You can start completely free. No credit card required. When you\'re ready, choose a plan that fits your business.' },
  { q: 'Which payment methods are supported?',      a: 'M-Pesa, Pesapal, bank transfers, cash, cheques, and mobile money — plus a client credit wallet for prepaid balances and auto-renewals.' },
  { q: 'Is MoBilling compliant with TRA/KRA?',      a: 'Yes. MoBilling supports VAT, PAYE, NHIF, NSSF, and other statutory requirements for Tanzania and Kenya.' },
  { q: 'Can I use it on my phone?',                 a: 'Absolutely. MoBilling is fully responsive and works on any device — phone, tablet, or desktop.' },
  { q: 'Can I import my existing client data?',     a: 'Yes — including from WHMCS. We migrate clients, services, invoices, payments and domains; your clients even keep their old portal passwords.' },
  { q: 'Do you offer support in Swahili?',          a: 'Kabisa! Our support team speaks both Swahili and English. Reach us on WhatsApp, phone, or email any time.' },
];

const trustBadges = [
  { icon: IconWorldWww,     label: '.tz Registry Connected' },
  { icon: IconServer,       label: 'cPanel Automation'      },
  { icon: IconDeviceMobile, label: 'M-Pesa & Pesapal Ready' },
  { icon: IconHeadset,      label: 'Local Support Team'     },
];

const planColors = ['blue', 'teal', 'violet', 'orange'];

const NAV_LINKS = [
  { label: 'Features',          href: '#features'        },
  { label: 'Hosting & Domains', href: '#hosting-domains' },
  { label: 'Reseller',          href: '#reseller'        },
  { label: 'Pricing',           href: '#pricing'         },
  { label: 'Contact',           href: '#contact'         },
];

// ── Hero product mockup ───────────────────────────────────────────────────────

function ProductMockup({ dark }: { dark: boolean }) {
  const theme = useMantineTheme();
  const cardBg  = dark ? theme.colors.dark[6] : 'white';
  const rowBg   = dark ? theme.colors.dark[5] : theme.colors.gray[0];
  const border  = dark ? theme.colors.dark[4] : theme.colors.gray[2];

  return (
    <motion.div
      initial={{ opacity: 0, x: 40, rotate: 2 }}
      animate={{ opacity: 1, x: 0, rotate: 0 }}
      transition={{ duration: 0.8, delay: 0.2 }}
      style={{ perspective: 1000 }}
    >
      <Box
        style={{
          background: cardBg,
          borderRadius: 16,
          border: `1px solid ${border}`,
          boxShadow: dark ? '0 24px 80px rgba(0,0,0,0.5)' : '0 24px 80px rgba(0,60,180,0.12)',
          overflow: 'hidden',
          maxWidth: 480,
        }}
      >
        {/* App bar */}
        <Box px={20} py={12} style={{ borderBottom: `1px solid ${border}`, background: dark ? theme.colors.dark[7] : 'white' }}>
          <Group justify="space-between">
            <Group gap={6}>
              <Box w={10} h={10} style={{ borderRadius: '50%', background: '#ff5f57' }} />
              <Box w={10} h={10} style={{ borderRadius: '50%', background: '#ffbd2e' }} />
              <Box w={10} h={10} style={{ borderRadius: '50%', background: '#28c840' }} />
            </Group>
            <Text size="xs" c="dimmed" fw={500}>MoBilling — Dashboard</Text>
            <Box w={60} />
          </Group>
        </Box>

        {/* Stats row */}
        <Box px={20} py={14} style={{ background: rowBg, borderBottom: `1px solid ${border}` }}>
          <Group gap={12} grow>
            {[
              { label: 'Revenue', value: 'TZS 4.2M', color: 'blue' },
              { label: 'Hosting', value: '109', color: 'teal' },
              { label: 'Domains', value: '147', color: 'violet' },
            ].map(s => (
              <Box key={s.label} style={{ background: cardBg, borderRadius: 8, padding: '8px 10px', border: `1px solid ${border}` }}>
                <Text size="xs" c="dimmed">{s.label}</Text>
                <Text size="sm" fw={800} c={`${s.color}.5`}>{s.value}</Text>
              </Box>
            ))}
          </Group>
        </Box>

        {/* Invoice list */}
        <Box px={20} pt={14} pb={4}>
          <Text size="xs" fw={600} c="dimmed" mb={10} tt="uppercase" style={{ letterSpacing: '0.06em' }}>Recent Invoices</Text>
          {[
            { client: 'Amina Traders',   amount: 'TZS 450,000', status: 'Paid',    color: 'green'  },
            { client: 'Kibaha Hardware', amount: 'TZS 182,500', status: 'Pending', color: 'orange' },
            { client: 'TopNet Ltd',      amount: 'TZS 320,000', status: 'Paid',    color: 'green'  },
            { client: 'Salama Shops',    amount: 'TZS 95,000',  status: 'Overdue', color: 'red'    },
          ].map((row, i) => (
            <Box
              key={i}
              py={9}
              style={{ borderBottom: `1px solid ${border}`, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}
            >
              <Group gap={10}>
                <Avatar size={28} radius="xl" color="blue" variant="light">
                  {row.client[0]}
                </Avatar>
                <Text size="xs" fw={500}>{row.client}</Text>
              </Group>
              <Group gap={10}>
                <Text size="xs" fw={700}>{row.amount}</Text>
                <Badge size="xs" color={row.color} variant="light">{row.status}</Badge>
              </Group>
            </Box>
          ))}
        </Box>

        {/* Progress bar footer */}
        <Box px={20} py={14}>
          <Group justify="space-between" mb={6}>
            <Text size="xs" c="dimmed">Monthly target</Text>
            <Text size="xs" fw={700} c="blue">78%</Text>
          </Group>
          <Progress value={78} color="blue" radius="xl" size="sm" />
        </Box>
      </Box>

      {/* Floating notification card */}
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.6, delay: 1.1 }}
        style={{ position: 'absolute', bottom: -20, left: -40, zIndex: 10 }}
      >
        <Paper
          withBorder
          p="sm"
          radius="lg"
          shadow="lg"
          style={{ background: dark ? theme.colors.dark[6] : 'white', minWidth: 200 }}
        >
          <Group gap={10}>
            <ThemeIcon size={34} radius="xl" color="green" variant="light">
              <IconCurrencyDollar size={18} />
            </ThemeIcon>
            <div>
              <Text size="xs" fw={700}>Payment Received</Text>
              <Text size="xs" c="dimmed">TZS 450,000 via M-Pesa</Text>
            </div>
          </Group>
        </Paper>
      </motion.div>

      {/* Floating domain-registered card */}
      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.6, delay: 1.5 }}
        style={{ position: 'absolute', top: 52, right: -28, zIndex: 10 }}
      >
        <Paper
          withBorder
          p="sm"
          radius="lg"
          shadow="lg"
          style={{ background: dark ? theme.colors.dark[6] : 'white', minWidth: 210 }}
        >
          <Group gap={10}>
            <ThemeIcon size={34} radius="xl" color="teal" variant="light">
              <IconWorldWww size={18} />
            </ThemeIcon>
            <div>
              <Text size="xs" fw={700}>Domain Registered ✓</Text>
              <Text size="xs" c="dimmed">amina-traders.co.tz · auto</Text>
            </div>
          </Group>
        </Paper>
      </motion.div>
    </motion.div>
  );
}

// ── Main component ────────────────────────────────────────────────────────────

export default function Landing() {
  // White-label domains never show the MoBilling marketing site.
  // Checked before any hook so hook order stays stable (rules of hooks).
  if (isBrandedHost()) return <Navigate to="/portal/login" replace />;
  return <LandingContent />;
}

function LandingContent() {
  const { toggleColorScheme } = useMantineColorScheme();
  const computedColorScheme = useComputedColorScheme('light');
  const theme = useMantineTheme();
  const dark = computedColorScheme === 'dark';
  const [drawerOpened, { toggle: toggleDrawer, close: closeDrawer }] = useDisclosure(false);
  const [scroll] = useWindowScroll();

  const scrollTo = (href: string) => {
    const el = document.querySelector(href);
    if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
    closeDrawer();
  };

  const altBg = dark ? theme.colors.dark[7] : theme.colors.gray[0];

  return (
    <Box style={{ overflow: 'hidden' }}>

      {/* ── Sticky WhatsApp button ── */}
      <AnimatePresence>
        {scroll.y > 300 && (
          <motion.div
            initial={{ scale: 0, opacity: 0 }}
            animate={{ scale: 1, opacity: 1 }}
            exit={{ scale: 0, opacity: 0 }}
            style={{ position: 'fixed', bottom: 24, right: 24, zIndex: 999 }}
          >
            <ActionIcon
              size={56}
              radius="xl"
              color="teal"
              variant="gradient"
              gradient={{ from: 'teal', to: 'green' }}
              component="a"
              href="https://wa.me/255689011111"
              target="_blank"
              style={{ boxShadow: '0 8px 24px rgba(0,180,120,0.4)' }}
            >
              <IconBrandWhatsapp size={28} />
            </ActionIcon>
          </motion.div>
        )}
      </AnimatePresence>

      {/* ── Scroll to top ── */}
      <AnimatePresence>
        {scroll.y > 600 && (
          <motion.div
            initial={{ scale: 0, opacity: 0 }}
            animate={{ scale: 1, opacity: 1 }}
            exit={{ scale: 0, opacity: 0 }}
            style={{ position: 'fixed', bottom: 90, right: 24, zIndex: 999 }}
          >
            <ActionIcon
              size={40}
              radius="xl"
              variant="default"
              onClick={() => window.scrollTo({ top: 0, behavior: 'smooth' })}
              style={{ boxShadow: theme.shadows.md }}
            >
              <IconChevronUp size={18} />
            </ActionIcon>
          </motion.div>
        )}
      </AnimatePresence>

      {/* ── Top Contact Bar ── */}
      <Box py={6} bg={dark ? theme.colors.dark[8] : theme.colors.blue[7]} style={{ color: 'white' }} visibleFrom="sm">
        <Container size="lg">
          <Group justify="space-between">
            <Group gap="lg">
              <Anchor href="mailto:info@moinfo.co.tz" size="xs" c="white" underline="never">
                <Group gap={4}><IconMail size={13} /> info@moinfo.co.tz</Group>
              </Anchor>
              <Anchor href="tel:+255689011111" size="xs" c="white" underline="never">
                <Group gap={4}><IconPhone size={13} /> +255 689 011 111</Group>
              </Anchor>
            </Group>
            <Anchor href="https://wa.me/255689011111" target="_blank" size="xs" c="white" underline="never">
              <Group gap={4}><IconBrandWhatsapp size={13} /> Chat on WhatsApp</Group>
            </Anchor>
          </Group>
        </Container>
      </Box>

      {/* ── Header ── */}
      <Paper
        component="header"
        style={{
          position: 'sticky', top: 0, zIndex: 100,
          backdropFilter: 'blur(14px)',
          backgroundColor: dark ? 'rgba(26,27,30,0.92)' : 'rgba(255,255,255,0.92)',
          borderBottom: `1px solid ${dark ? theme.colors.dark[4] : theme.colors.gray[2]}`,
        }}
        shadow={undefined}
        p="sm"
      >
        <Container size="lg">
          <Group justify="space-between">
            <Group gap={8}>
              <Image src="/moinfotech-logo.png" h={32} w="auto" alt="MoBilling" />
              <Text size="lg" fw={800} variant="gradient" gradient={{ from: 'blue', to: 'cyan' }}>MoBilling</Text>
            </Group>

            <Group gap="xl" visibleFrom="md">
              {NAV_LINKS.map(n => (
                <Text
                  key={n.label}
                  size="sm"
                  fw={500}
                  c="dimmed"
                  style={{ cursor: 'pointer', transition: 'color 150ms' }}
                  onMouseEnter={e => (e.currentTarget.style.color = 'var(--mantine-color-blue-5)')}
                  onMouseLeave={e => (e.currentTarget.style.color = '')}
                  onClick={() => scrollTo(n.href)}
                >
                  {n.label}
                </Text>
              ))}
            </Group>

            <Group gap="xs" visibleFrom="sm">
              <ActionIcon variant="default" size="lg" onClick={toggleColorScheme} aria-label="Toggle theme">
                {dark ? <IconSun size={18} /> : <IconMoon size={18} />}
              </ActionIcon>
              <Button variant="subtle" component={Link} to="/login">Sign In</Button>
              <Button variant="gradient" gradient={{ from: 'blue', to: 'cyan' }} component={Link} to="/register" radius="xl">
                Get Started
              </Button>
            </Group>

            <Group gap="xs" hiddenFrom="sm">
              <ActionIcon variant="default" size="lg" onClick={toggleColorScheme}>
                {dark ? <IconSun size={18} /> : <IconMoon size={18} />}
              </ActionIcon>
              <Burger opened={drawerOpened} onClick={toggleDrawer} size="sm" />
            </Group>
          </Group>
        </Container>
      </Paper>

      {/* Mobile drawer */}
      <Drawer opened={drawerOpened} onClose={closeDrawer} size="xs" title="MoBilling" zIndex={200} padding="md">
        <Stack gap="sm">
          {NAV_LINKS.map(n => (
            <Text key={n.label} size="sm" fw={500} style={{ cursor: 'pointer' }} onClick={() => scrollTo(n.href)}>{n.label}</Text>
          ))}
          <Divider my="xs" />
          <Button fullWidth variant="subtle" component={Link} to="/login" onClick={closeDrawer}>Sign In</Button>
          <Button fullWidth variant="gradient" gradient={{ from: 'blue', to: 'cyan' }} component={Link} to="/register" onClick={closeDrawer}>
            Get Started
          </Button>
          <Divider my="xs" />
          <Group gap={6}><IconMail size={14} /><Anchor href="mailto:info@moinfo.co.tz" size="sm">info@moinfo.co.tz</Anchor></Group>
          <Group gap={6}><IconPhone size={14} /><Anchor href="tel:+255689011111" size="sm">+255 689 011 111</Anchor></Group>
          <Group gap={6}><IconBrandWhatsapp size={14} /><Anchor href="https://wa.me/255689011111" target="_blank" size="sm">WhatsApp</Anchor></Group>
        </Stack>
      </Drawer>

      {/* ── Hero (split layout) ── */}
      <Box
        py={{ base: 60, sm: 80, md: 100 }}
        style={{
          background: dark
            ? `radial-gradient(ellipse at 30% 0%, ${theme.colors.blue[9]}44 0%, ${theme.colors.violet[9]}22 50%, transparent 75%)`
            : `radial-gradient(ellipse at 30% 0%, ${theme.colors.blue[1]} 0%, ${theme.colors.cyan[0]} 50%, white 75%)`,
          position: 'relative',
          overflow: 'hidden',
        }}
      >
        {/* Background decoration circles */}
        <Box style={{ position: 'absolute', top: -120, right: -120, width: 480, height: 480, borderRadius: '50%', background: dark ? `${theme.colors.blue[9]}18` : `${theme.colors.blue[1]}cc`, pointerEvents: 'none' }} />
        <Box style={{ position: 'absolute', bottom: -80, left: -80, width: 320, height: 320, borderRadius: '50%', background: dark ? `${theme.colors.cyan[9]}12` : `${theme.colors.cyan[1]}aa`, pointerEvents: 'none' }} />

        <Container size="xl">
          <Group gap={60} align="center" wrap="wrap" justify="center">
            {/* Left: Text */}
            <Box style={{ flex: '1 1 380px', maxWidth: 540 }}>
              <motion.div
                initial={{ opacity: 0, y: 32 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ duration: 0.65 }}
              >
                <Badge size="xl" variant="gradient" gradient={{ from: 'blue', to: 'cyan' }} mb="lg" px="lg" radius="xl">
                  The WHMCS-style platform built for East Africa
                </Badge>

                <Title order={1} fw={900} style={{ fontSize: 'clamp(2.2rem, 4.5vw, 3.6rem)', lineHeight: 1.1 }}>
                  Billing,{' '}
                  <Text component="span" inherit variant="gradient" gradient={{ from: 'blue', to: 'cyan', deg: 90 }}>
                    Hosting & Domains
                  </Text>
                  {' '}on{' '}
                  <Text component="span" inherit style={{ fontStyle: 'italic' }}>Autopilot</Text>
                </Title>

                <Text size="lg" c="dimmed" mt="lg" lh={1.8}>
                  Invoices, statutory bills, a client portal, cPanel hosting automation and a
                  direct .tz domain registrar — everything WHMCS does plus East African billing,
                  in one platform. White-label it and sell under your own brand.
                </Text>

                <Group mt={{ base: 28, sm: 36 }} gap="md" wrap="wrap">
                  <Button
                    size="xl"
                    variant="gradient"
                    gradient={{ from: 'blue', to: 'cyan' }}
                    rightSection={<IconArrowRight size={20} />}
                    component={Link}
                    to="/register"
                    radius="xl"
                  >
                    Start Free Today
                  </Button>
                  <Button
                    size="xl"
                    variant="default"
                    leftSection={<IconBrandWhatsapp size={20} />}
                    component="a"
                    href="https://wa.me/255689011111"
                    target="_blank"
                    radius="xl"
                  >
                    WhatsApp Us
                  </Button>
                </Group>

                <Group mt={36} gap="xl" wrap="wrap">
                  {trustBadges.map((s) => (
                    <Group key={s.label} gap={8}>
                      <ThemeIcon size={26} radius="xl" variant="light" color="blue">
                        <s.icon size={14} />
                      </ThemeIcon>
                      <Text size="sm" fw={500} c="dimmed">{s.label}</Text>
                    </Group>
                  ))}
                </Group>
              </motion.div>
            </Box>

            {/* Right: Product mockup */}
            <Box style={{ flex: '1 1 340px', maxWidth: 480, position: 'relative' }} visibleFrom="md">
              <ProductMockup dark={dark} />
            </Box>
          </Group>
        </Container>
      </Box>

      {/* ── Social proof stats ── */}
      <Box py={48} bg={altBg}>
        <Container size="lg">
          <SimpleGrid cols={{ base: 2, sm: 4 }} spacing="xl">
            {socialProof.map((s, i) => (
              <motion.div
                key={s.label}
                initial={{ opacity: 0, y: 16 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true }}
                transition={{ duration: 0.4, delay: i * 0.08 }}
              >
                <Stack align="center" gap={4}>
                  <Text
                    style={{ fontSize: 'clamp(1.8rem, 3.5vw, 2.6rem)' }}
                    fw={900}
                    variant="gradient"
                    gradient={{ from: 'blue', to: 'cyan' }}
                  >
                    {s.value}
                  </Text>
                  <Text size="sm" c="dimmed" ta="center">{s.label}</Text>
                </Stack>
              </motion.div>
            ))}
          </SimpleGrid>
        </Container>
      </Box>

      {/* ── How it works ── */}
      <Box id="how-it-works" py={{ base: 64, sm: 96 }}>
        <Container size="lg">
          <motion.div initial={{ opacity: 0, y: 20 }} whileInView={{ opacity: 1, y: 0 }} viewport={{ once: true }} transition={{ duration: 0.5 }}>
            <Stack align="center" mb={64}>
              <Badge variant="light" size="lg" color="teal" radius="xl">How it Works</Badge>
              <Title order={2} ta="center" style={{ fontSize: 'clamp(1.5rem, 3vw, 2.2rem)' }}>
                Up and running in minutes
              </Title>
              <Text c="dimmed" ta="center" maw={460}>
                No complicated setup. No training needed. Just sign up and start billing.
              </Text>
            </Stack>
          </motion.div>

          <Box style={{ position: 'relative' }}>
            {/* Connector line (desktop) */}
            <Box
              visibleFrom="sm"
              style={{
                position: 'absolute',
                top: 50,
                left: '16.5%',
                right: '16.5%',
                height: 2,
                background: `linear-gradient(90deg, ${theme.colors.blue[5]}, ${theme.colors.teal[5]}, ${theme.colors.green[5]})`,
                opacity: 0.3,
              }}
            />

            <SimpleGrid cols={{ base: 1, sm: 3 }} spacing={48}>
              {howItWorks.map((step, i) => (
                <motion.div
                  key={step.step}
                  initial={{ opacity: 0, y: 24 }}
                  whileInView={{ opacity: 1, y: 0 }}
                  viewport={{ once: true, margin: '-40px' }}
                  transition={{ duration: 0.4, delay: i * 0.15 }}
                >
                  <Stack align="center" ta="center" gap="md">
                    <Box
                      style={{
                        width: 80,
                        height: 80,
                        borderRadius: '50%',
                        background: `linear-gradient(135deg, var(--mantine-color-${step.color}-6), var(--mantine-color-${step.color}-4))`,
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        boxShadow: `0 8px 24px var(--mantine-color-${step.color}-3)`,
                        position: 'relative',
                        zIndex: 1,
                      }}
                    >
                      <Text size="xl" fw={900} c="white">{step.num}</Text>
                    </Box>
                    <Text fw={700} size="lg">{step.step}</Text>
                    <Text c="dimmed" size="sm" lh={1.7} maw={280}>{step.desc}</Text>
                  </Stack>
                </motion.div>
              ))}
            </SimpleGrid>
          </Box>
        </Container>
      </Box>

      {/* ── Features ── */}
      <Box id="features" py={{ base: 64, sm: 96 }} bg={altBg}>
        <Container size="lg">
          <motion.div initial={{ opacity: 0, y: 20 }} whileInView={{ opacity: 1, y: 0 }} viewport={{ once: true }} transition={{ duration: 0.5 }}>
            <Stack align="center" mb={64}>
              <Badge variant="light" size="lg" radius="xl">Features</Badge>
              <Title order={2} ta="center" style={{ fontSize: 'clamp(1.5rem, 3vw, 2.2rem)' }}>
                Everything you need to run your business
              </Title>
              <Text c="dimmed" ta="center" maw={520}>
                From generating invoices to running WhatsApp marketing campaigns — MoBilling handles it all.
              </Text>
            </Stack>
          </motion.div>

          <SimpleGrid cols={{ base: 1, sm: 2, md: 3 }} spacing="xl">
            {features.map((f, i) => (
              <motion.div
                key={f.title}
                initial={{ opacity: 0, y: 24 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true, margin: '-40px' }}
                transition={{ duration: 0.4, delay: i * 0.07 }}
              >
                <Paper
                  withBorder
                  p="xl"
                  radius="xl"
                  h="100%"
                  style={{ transition: 'transform 160ms ease, box-shadow 160ms ease, border-color 160ms ease', cursor: 'default' }}
                  onMouseEnter={(e) => {
                    e.currentTarget.style.transform = 'translateY(-6px)';
                    e.currentTarget.style.boxShadow = theme.shadows.xl;
                    e.currentTarget.style.borderColor = `var(--mantine-color-${f.color}-5)`;
                  }}
                  onMouseLeave={(e) => {
                    e.currentTarget.style.transform = 'translateY(0)';
                    e.currentTarget.style.boxShadow = '';
                    e.currentTarget.style.borderColor = '';
                  }}
                >
                  <ThemeIcon
                    size={56}
                    radius="xl"
                    variant="gradient"
                    gradient={{ from: f.color, to: 'cyan', deg: 135 }}
                  >
                    <f.icon size={30} />
                  </ThemeIcon>
                  <Text size="lg" fw={700} mt="md">{f.title}</Text>
                  <Text size="sm" c="dimmed" mt={6} lh={1.7}>{f.description}</Text>
                </Paper>
              </motion.div>
            ))}
          </SimpleGrid>
        </Container>
      </Box>

      {/* ── Hosting & Domains (WHMCS parity) ── */}
      <Box id="hosting-domains" py={{ base: 64, sm: 96 }}>
        <Container size="lg">
          <motion.div initial={{ opacity: 0, y: 20 }} whileInView={{ opacity: 1, y: 0 }} viewport={{ once: true }} transition={{ duration: 0.5 }}>
            <Stack align="center" mb={64}>
              <Badge variant="light" size="lg" color="teal" radius="xl">Hosting & Domains</Badge>
              <Title order={2} ta="center" style={{ fontSize: 'clamp(1.5rem, 3vw, 2.2rem)' }}>
                Everything WHMCS does — built in
              </Title>
              <Text c="dimmed" ta="center" maw={560}>
                Sell cPanel hosting and .tz domains with end-to-end automation: order, pay,
                provision, renew, suspend — no license fees, no plugins, no cron babysitting.
              </Text>
            </Stack>
          </motion.div>

          <SimpleGrid cols={{ base: 1, sm: 2, md: 3 }} spacing="xl">
            {hostingFeatures.map((f, i) => (
              <motion.div
                key={f.title}
                initial={{ opacity: 0, y: 24 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true, margin: '-40px' }}
                transition={{ duration: 0.4, delay: i * 0.07 }}
              >
                <Paper
                  withBorder
                  p="xl"
                  radius="xl"
                  h="100%"
                  style={{ transition: 'transform 160ms ease, box-shadow 160ms ease, border-color 160ms ease', cursor: 'default' }}
                  onMouseEnter={(e) => {
                    e.currentTarget.style.transform = 'translateY(-6px)';
                    e.currentTarget.style.boxShadow = theme.shadows.xl;
                    e.currentTarget.style.borderColor = `var(--mantine-color-${f.color}-5)`;
                  }}
                  onMouseLeave={(e) => {
                    e.currentTarget.style.transform = 'translateY(0)';
                    e.currentTarget.style.boxShadow = '';
                    e.currentTarget.style.borderColor = '';
                  }}
                >
                  <ThemeIcon size={56} radius="xl" variant="gradient" gradient={{ from: f.color, to: 'cyan', deg: 135 }}>
                    <f.icon size={30} />
                  </ThemeIcon>
                  <Text size="lg" fw={700} mt="md">{f.title}</Text>
                  <Text size="sm" c="dimmed" mt={6} lh={1.7}>{f.description}</Text>
                </Paper>
              </motion.div>
            ))}
          </SimpleGrid>

          {/* Migration strip */}
          <motion.div initial={{ opacity: 0, y: 20 }} whileInView={{ opacity: 1, y: 0 }} viewport={{ once: true }} transition={{ duration: 0.5, delay: 0.15 }}>
            <Paper withBorder radius="xl" p="xl" mt={48}>
              <Group justify="space-between" wrap="wrap" gap="lg">
                <Group gap="md" style={{ flex: '1 1 420px' }}>
                  <ThemeIcon size={52} radius="xl" variant="gradient" gradient={{ from: 'orange', to: 'red', deg: 135 }}>
                    <IconRocket size={28} />
                  </ThemeIcon>
                  <div style={{ flex: 1 }}>
                    <Text fw={700} size="lg">Migrating from WHMCS?</Text>
                    <Text size="sm" c="dimmed" lh={1.7}>
                      We import your clients, services, invoices, payments and domains — your
                      clients even keep their existing portal passwords. Zero-downtime cutover.
                    </Text>
                  </div>
                </Group>
                <Button
                  size="md"
                  radius="xl"
                  variant="gradient"
                  gradient={{ from: 'orange', to: 'red' }}
                  component="a"
                  href="https://wa.me/255689011111?text=I%20want%20to%20migrate%20from%20WHMCS"
                  target="_blank"
                  leftSection={<IconBrandWhatsapp size={18} />}
                >
                  Ask About Migration
                </Button>
              </Group>
            </Paper>
          </motion.div>
        </Container>
      </Box>

      {/* ── Why MoBilling strip ── */}
      <Box
        py={{ base: 56, sm: 80 }}
        style={{
          background: dark
            ? `linear-gradient(135deg, ${theme.colors.blue[9]}55 0%, ${theme.colors.violet[9]}44 100%)`
            : `linear-gradient(135deg, ${theme.colors.blue[6]} 0%, ${theme.colors.cyan[5]} 100%)`,
        }}
      >
        <Container size="lg">
          <SimpleGrid cols={{ base: 1, sm: 3 }} spacing="xl">
            {[
              { icon: IconRocket,     title: 'Launch in minutes',     desc: 'No setup fees, no complex onboarding. Sign up and generate your first invoice immediately.' },
              { icon: IconTrendingUp, title: 'Grow with confidence',  desc: 'From solo operators to 50-person firms. MoBilling scales as your business grows.' },
              { icon: IconHeadset,    title: 'Local support team',    desc: 'Based in Tanzania. We speak Swahili and English — we understand your business context.' },
            ].map((item, i) => (
              <motion.div
                key={item.title}
                initial={{ opacity: 0, y: 20 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true }}
                transition={{ duration: 0.4, delay: i * 0.1 }}
              >
                <Group gap="md" align="flex-start">
                  <ThemeIcon size={52} radius="xl" color="white" variant="white" style={{ color: theme.colors.blue[6], flexShrink: 0 }}>
                    <item.icon size={28} />
                  </ThemeIcon>
                  <div>
                    <Text fw={700} size="lg" c="white">{item.title}</Text>
                    <Text size="sm" mt={4} style={{ color: 'rgba(255,255,255,0.78)', lineHeight: 1.7 }}>{item.desc}</Text>
                  </div>
                </Group>
              </motion.div>
            ))}
          </SimpleGrid>
        </Container>
      </Box>

      {/* ── Testimonials ── */}
      <Box py={{ base: 64, sm: 96 }}>
        <Container size="lg">
          <motion.div initial={{ opacity: 0, y: 20 }} whileInView={{ opacity: 1, y: 0 }} viewport={{ once: true }} transition={{ duration: 0.5 }}>
            <Stack align="center" mb={64}>
              <Badge variant="light" size="lg" radius="xl" color="orange">Testimonials</Badge>
              <Title order={2} ta="center" style={{ fontSize: 'clamp(1.5rem, 3vw, 2.2rem)' }}>
                Loved by businesses across East Africa
              </Title>
              <Text c="dimmed" ta="center" maw={460}>
                Real feedback from real customers who use MoBilling every day.
              </Text>
            </Stack>
          </motion.div>

          <SimpleGrid cols={{ base: 1, sm: 3 }} spacing="xl">
            {testimonials.map((t, i) => (
              <motion.div
                key={t.name}
                initial={{ opacity: 0, y: 24 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true, margin: '-40px' }}
                transition={{ duration: 0.4, delay: i * 0.1 }}
              >
                <Paper withBorder p="xl" radius="xl" h="100%" style={{ position: 'relative' }}>
                  <ThemeIcon size={36} radius="xl" color={t.color} variant="light" style={{ position: 'absolute', top: 20, right: 20 }}>
                    <IconQuote size={18} />
                  </ThemeIcon>

                  <Group gap={4} mb="md">
                    {Array.from({ length: t.stars }).map((_, si) => (
                      <IconStar key={si} size={14} fill={theme.colors.yellow[5]} color={theme.colors.yellow[5]} />
                    ))}
                  </Group>

                  <Text size="sm" lh={1.8} c="dimmed" mb="lg" style={{ fontStyle: 'italic' }}>
                    "{t.text}"
                  </Text>

                  <Group gap={10}>
                    <Avatar size={38} radius="xl" color={t.color} variant="gradient" gradient={{ from: t.color, to: 'cyan' }}>
                      {t.avatar}
                    </Avatar>
                    <div>
                      <Text size="sm" fw={700}>{t.name}</Text>
                      <Text size="xs" c="dimmed">{t.company}</Text>
                    </div>
                  </Group>
                </Paper>
              </motion.div>
            ))}
          </SimpleGrid>
        </Container>
      </Box>

      {/* ── White-label reseller ── */}
      <Box
        id="reseller"
        py={{ base: 64, sm: 96 }}
        style={{
          background: dark
            ? `linear-gradient(135deg, ${theme.colors.violet[9]}55 0%, ${theme.colors.blue[9]}44 100%)`
            : `linear-gradient(135deg, ${theme.colors.violet[6]} 0%, ${theme.colors.blue[6]} 100%)`,
        }}
      >
        <Container size="lg">
          <motion.div initial={{ opacity: 0, y: 20 }} whileInView={{ opacity: 1, y: 0 }} viewport={{ once: true }} transition={{ duration: 0.5 }}>
            <Stack align="center" mb={56}>
              <Badge size="lg" radius="xl" variant="white" c="violet">White-Label Reseller</Badge>
              <Title order={2} ta="center" c="white" style={{ fontSize: 'clamp(1.5rem, 3vw, 2.2rem)' }}>
                Your brand. Our engine.
              </Title>
              <Text ta="center" maw={560} style={{ color: 'rgba(255,255,255,0.8)' }}>
                Start your own hosting & domains business without building any infrastructure.
                Resell under your name — MoBilling runs the registry, servers and billing behind the scenes.
              </Text>
            </Stack>
          </motion.div>

          <SimpleGrid cols={{ base: 1, sm: 3 }} spacing="xl">
            {resellerPoints.map((p, i) => (
              <motion.div
                key={p.title}
                initial={{ opacity: 0, y: 24 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true, margin: '-40px' }}
                transition={{ duration: 0.4, delay: i * 0.1 }}
              >
                <Paper
                  p="xl"
                  radius="xl"
                  h="100%"
                  style={{
                    background: 'rgba(255,255,255,0.10)',
                    border: '1px solid rgba(255,255,255,0.22)',
                    backdropFilter: 'blur(8px)',
                  }}
                >
                  <ThemeIcon size={52} radius="xl" variant="white" style={{ color: theme.colors.violet[6] }}>
                    <p.icon size={28} />
                  </ThemeIcon>
                  <Text fw={700} size="lg" mt="md" c="white">{p.title}</Text>
                  <Text size="sm" mt={6} lh={1.7} style={{ color: 'rgba(255,255,255,0.78)' }}>{p.desc}</Text>
                </Paper>
              </motion.div>
            ))}
          </SimpleGrid>

          <Group justify="center" mt={48} gap="md" wrap="wrap">
            <Button
              size="lg"
              radius="xl"
              variant="white"
              c="violet"
              rightSection={<IconArrowRight size={18} />}
              component={Link}
              to="/register"
            >
              Become a Reseller
            </Button>
            <Button
              size="lg"
              radius="xl"
              variant="outline"
              color="white"
              styles={{ root: { borderColor: 'rgba(255,255,255,0.55)', color: 'white' } }}
              leftSection={<IconBrandWhatsapp size={18} />}
              component="a"
              href="https://wa.me/255689011111?text=I%20want%20to%20know%20about%20the%20white-label%20reseller%20program"
              target="_blank"
            >
              Talk to Sales
            </Button>
          </Group>
        </Container>
      </Box>

      {/* ── Pricing ── */}
      <Box id="pricing" bg={altBg}>
        <PricingSection />
      </Box>

      {/* ── FAQ ── */}
      <Box py={{ base: 64, sm: 96 }}>
        <Container size="md">
          <motion.div initial={{ opacity: 0, y: 20 }} whileInView={{ opacity: 1, y: 0 }} viewport={{ once: true }} transition={{ duration: 0.5 }}>
            <Stack align="center" mb={56}>
              <Badge variant="light" size="lg" radius="xl" color="violet">FAQ</Badge>
              <Title order={2} ta="center" style={{ fontSize: 'clamp(1.5rem, 3vw, 2.2rem)' }}>
                Frequently asked questions
              </Title>
              <Text c="dimmed" ta="center" maw={440}>
                Still have questions? Reach us on WhatsApp any time.
              </Text>
            </Stack>
          </motion.div>

          <motion.div
            initial={{ opacity: 0, y: 20 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true }}
            transition={{ duration: 0.5, delay: 0.1 }}
          >
            <Accordion variant="separated" radius="lg">
              {faqs.map((faq, i) => (
                <Accordion.Item key={i} value={String(i)}>
                  <Accordion.Control>
                    <Text fw={600} size="sm">{faq.q}</Text>
                  </Accordion.Control>
                  <Accordion.Panel>
                    <Text size="sm" c="dimmed" lh={1.7}>{faq.a}</Text>
                  </Accordion.Panel>
                </Accordion.Item>
              ))}
            </Accordion>
          </motion.div>
        </Container>
      </Box>

      {/* ── CTA ── */}
      <Box
        py={{ base: 64, sm: 100 }}
        style={{
          background: dark
            ? `linear-gradient(135deg, ${theme.colors.blue[9]}55 0%, ${theme.colors.cyan[9]}33 100%)`
            : `linear-gradient(135deg, ${theme.colors.blue[0]} 0%, ${theme.colors.cyan[1]} 100%)`,
        }}
      >
        <Container size="sm" ta="center">
          <motion.div initial={{ opacity: 0, y: 20 }} whileInView={{ opacity: 1, y: 0 }} viewport={{ once: true }} transition={{ duration: 0.5 }}>
            <Badge size="xl" variant="gradient" gradient={{ from: 'blue', to: 'cyan' }} mb="lg" radius="xl">
              Free to start
            </Badge>
            <Title order={2} style={{ fontSize: 'clamp(1.6rem, 3.5vw, 2.4rem)' }}>
              Ready to simplify your billing?
            </Title>
            <Text c="dimmed" mt="sm" size="lg" maw={440} mx="auto" lh={1.7}>
              Join hundreds of East African businesses already using MoBilling to stay compliant and grow faster.
            </Text>
            <Group justify="center" mt="xl" gap="md" wrap="wrap">
              <Button
                size="xl"
                variant="gradient"
                gradient={{ from: 'blue', to: 'cyan' }}
                rightSection={<IconArrowRight size={20} />}
                component={Link}
                to="/register"
                radius="xl"
              >
                Create Free Account
              </Button>
              <Button
                size="xl"
                variant="default"
                leftSection={<IconBrandWhatsapp size={20} />}
                component="a"
                href="https://wa.me/255689011111"
                target="_blank"
                radius="xl"
              >
                Chat with Us
              </Button>
            </Group>
          </motion.div>
        </Container>
      </Box>

      {/* ── Contact ── */}
      <Box id="contact" py={{ base: 64, sm: 96 }} bg={altBg}>
        <Container size="lg">
          <motion.div initial={{ opacity: 0, y: 20 }} whileInView={{ opacity: 1, y: 0 }} viewport={{ once: true }} transition={{ duration: 0.5 }}>
            <Stack align="center" mb={56}>
              <Badge variant="light" size="lg" radius="xl">Contact</Badge>
              <Title order={2} ta="center" style={{ fontSize: 'clamp(1.5rem, 3vw, 2.2rem)' }}>Get in touch</Title>
              <Text c="dimmed" ta="center" maw={480}>
                Have questions or need help? Our local team is ready to assist you in Swahili or English.
              </Text>
            </Stack>
          </motion.div>

          <SimpleGrid cols={{ base: 1, sm: 2, md: 4 }} spacing="xl">
            {[
              { icon: IconMail,          color: 'blue',   title: 'Email',    value: 'info@moinfo.co.tz',       href: 'mailto:info@moinfo.co.tz' },
              { icon: IconPhone,         color: 'green',  title: 'Phone',    value: '+255 689 011 111',         href: 'tel:+255689011111' },
              { icon: IconBrandWhatsapp, color: 'teal',   title: 'WhatsApp', value: '+255 689 011 111',         href: 'https://wa.me/255689011111' },
              { icon: IconMapPin,        color: 'orange', title: 'Location', value: 'Njuweni Hotel, 1st Floor, Room 134, Kibaha, Tanzania', href: undefined },
            ].map((c, i) => (
              <motion.div
                key={c.title}
                initial={{ opacity: 0, y: 20 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true }}
                transition={{ duration: 0.4, delay: i * 0.08 }}
              >
                <Paper
                  withBorder
                  p="xl"
                  radius="xl"
                  ta="center"
                  h="100%"
                  style={{ transition: 'transform 160ms ease, box-shadow 160ms ease' }}
                  onMouseEnter={e => { e.currentTarget.style.transform = 'translateY(-5px)'; e.currentTarget.style.boxShadow = theme.shadows.lg; }}
                  onMouseLeave={e => { e.currentTarget.style.transform = ''; e.currentTarget.style.boxShadow = ''; }}
                >
                  <ThemeIcon size={56} radius="xl" variant="gradient" gradient={{ from: c.color, to: 'cyan', deg: 135 }} mx="auto">
                    <c.icon size={28} />
                  </ThemeIcon>
                  <Text fw={700} mt="md" size="md">{c.title}</Text>
                  {c.href ? (
                    <Anchor href={c.href} target={c.href.startsWith('http') ? '_blank' : undefined} size="sm" mt={6} display="block">
                      {c.value}
                    </Anchor>
                  ) : (
                    <Text size="sm" c="dimmed" mt={6}>{c.value}</Text>
                  )}
                </Paper>
              </motion.div>
            ))}
          </SimpleGrid>
        </Container>
      </Box>

      {/* ── Footer ── */}
      <Divider />
      <Box py="xl" bg={dark ? theme.colors.dark[8] : theme.colors.gray[1]}>
        <Container size="lg">
          <SimpleGrid cols={{ base: 1, sm: 3 }} spacing="xl">
            <Stack gap={8}>
              <Group gap={8}>
                <Image src="/moinfotech-logo.png" h={28} w="auto" alt="MoBilling" />
                <Text fw={800} variant="gradient" gradient={{ from: 'blue', to: 'cyan' }}>MoBilling</Text>
              </Group>
              <Text size="sm" c="dimmed" maw={260} lh={1.6}>
                Billing, hosting automation & .tz domain registrar — the WHMCS-style
                platform built for East African businesses. White-label ready.
              </Text>
              <Group gap={8} mt={4}>
                <ActionIcon variant="light" color="teal" size="lg" radius="xl" component="a" href="https://wa.me/255689011111" target="_blank">
                  <IconBrandWhatsapp size={18} />
                </ActionIcon>
                <ActionIcon variant="light" color="blue" size="lg" radius="xl" component="a" href="mailto:info@moinfo.co.tz">
                  <IconMail size={18} />
                </ActionIcon>
                <ActionIcon variant="light" color="green" size="lg" radius="xl" component="a" href="tel:+255689011111">
                  <IconPhone size={18} />
                </ActionIcon>
              </Group>
            </Stack>

            <Stack gap={6}>
              <Text size="sm" fw={700} mb={4} tt="uppercase" c="dimmed" style={{ letterSpacing: '0.06em' }}>Navigation</Text>
              {NAV_LINKS.map(n => (
                <Text key={n.label} size="sm" c="dimmed" style={{ cursor: 'pointer' }} onClick={() => scrollTo(n.href)}>
                  {n.label}
                </Text>
              ))}
              <Anchor component={Link} to="/login" size="sm" c="dimmed">Sign In</Anchor>
              <Anchor component={Link} to="/register" size="sm" c="dimmed">Create Account</Anchor>
            </Stack>

            <Stack gap={6}>
              <Text size="sm" fw={700} mb={4} tt="uppercase" c="dimmed" style={{ letterSpacing: '0.06em' }}>Contact Us</Text>
              <Group gap={8}><IconMail size={14} color="var(--mantine-color-dimmed)" /><Anchor href="mailto:info@moinfo.co.tz" size="sm" c="dimmed">info@moinfo.co.tz</Anchor></Group>
              <Group gap={8}><IconPhone size={14} color="var(--mantine-color-dimmed)" /><Anchor href="tel:+255689011111" size="sm" c="dimmed">+255 689 011 111</Anchor></Group>
              <Group gap={8}><IconMapPin size={14} color="var(--mantine-color-dimmed)" /><Text size="sm" c="dimmed">Kibaha, Tanzania</Text></Group>
            </Stack>
          </SimpleGrid>

          <Divider my="lg" />

          <Group justify="space-between" wrap="wrap" gap="xs">
            <Text size="xs" c="dimmed">&copy; {new Date().getFullYear()} MoBilling. All rights reserved.</Text>
            <Group gap={6}>
              <Text size="xs" c="dimmed">Powered by</Text>
              <Anchor href="https://moinfotech.co.tz" target="_blank" size="xs" fw={700}>
                <Group gap={4}><IconWorld size={14} /> Moinfotech</Group>
              </Anchor>
            </Group>
          </Group>
        </Container>
      </Box>
    </Box>
  );
}

// ── Pricing section ───────────────────────────────────────────────────────────

function PricingSection() {
  const { data, isLoading } = useQuery({ queryKey: ['public-plans'], queryFn: getPublicPlans });
  const plans: SubscriptionPlan[] = data?.data?.data || [];

  if (isLoading) return (
    <Box py={{ base: 64, sm: 96 }}>
      <Center><Loader /></Center>
    </Box>
  );

  if (plans.length === 0) return null;

  const recommended = Math.floor(plans.length / 2);

  return (
    <Box py={{ base: 64, sm: 96 }}>
      <Container size="lg">
        <motion.div initial={{ opacity: 0, y: 20 }} whileInView={{ opacity: 1, y: 0 }} viewport={{ once: true }} transition={{ duration: 0.5 }}>
          <Stack align="center" mb={64}>
            <Badge variant="light" size="lg" radius="xl">Pricing</Badge>
            <Title order={2} ta="center" style={{ fontSize: 'clamp(1.5rem, 3vw, 2.2rem)' }}>Simple, transparent pricing</Title>
            <Text c="dimmed" ta="center" maw={480}>
              Start with a free trial. Choose a plan that fits your business when you're ready.
            </Text>
          </Stack>
        </motion.div>

        <SimpleGrid cols={{ base: 1, sm: 2, md: plans.length >= 4 ? 4 : plans.length }} spacing="lg" style={{ alignItems: 'start' }}>
          {plans.map((plan, i) => {
            const color = planColors[i % planColors.length];
            const isRecommended = i === recommended;
            return (
              <motion.div
                key={plan.id}
                initial={{ opacity: 0, y: 24 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true, margin: '-40px' }}
                transition={{ duration: 0.4, delay: i * 0.1 }}
              >
                <Card
                  withBorder
                  padding="xl"
                  radius="xl"
                  h="100%"
                  style={{
                    borderTop: `4px solid var(--mantine-color-${color}-6)`,
                    transform: isRecommended ? 'scale(1.04)' : undefined,
                    boxShadow: isRecommended ? `0 16px 48px var(--mantine-color-${color}-3)` : undefined,
                    position: 'relative',
                  }}
                >
                  {isRecommended && (
                    <Badge
                      variant="gradient"
                      gradient={{ from: color, to: 'cyan' }}
                      size="sm"
                      radius="xl"
                      style={{ position: 'absolute', top: -14, left: '50%', transform: 'translateX(-50%)', whiteSpace: 'nowrap' }}
                    >
                      ⭐ Most Popular
                    </Badge>
                  )}

                  <Stack gap="md" justify="space-between" h="100%">
                    <div>
                      <Text fw={800} size="xl">{plan.name}</Text>
                      {plan.description && <Text size="sm" c="dimmed" mt={4}>{plan.description}</Text>}

                      <Group gap={4} align="baseline" mt="md">
                        <Text style={{ fontSize: 'clamp(1.6rem, 4vw, 2.2rem)' }} fw={900} lh={1}>
                          TZS {Number(plan.price).toLocaleString()}
                        </Text>
                      </Group>
                      <Text size="xs" c="dimmed" mt={2}>per {plan.billing_cycle_days} days</Text>

                      {plan.features && plan.features.length > 0 && (
                        <List
                          spacing={8}
                          size="sm"
                          mt="lg"
                          icon={<ThemeIcon size={20} radius="xl" color={color} variant="light"><IconCheck size={12} /></ThemeIcon>}
                        >
                          {plan.features.map((f, fi) => <List.Item key={fi}>{f}</List.Item>)}
                        </List>
                      )}
                    </div>

                    <Button
                      fullWidth
                      size="md"
                      variant={isRecommended ? 'gradient' : 'light'}
                      gradient={isRecommended ? { from: color, to: 'cyan' } : undefined}
                      color={color}
                      component={Link}
                      to="/register"
                      rightSection={<IconArrowRight size={16} />}
                      radius="xl"
                      mt="md"
                    >
                      Get Started
                    </Button>
                  </Stack>
                </Card>
              </motion.div>
            );
          })}
        </SimpleGrid>
      </Container>
    </Box>
  );
}
