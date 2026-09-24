import { Paper, Group, Title, Text, Badge, Stack, Button, Code, Loader, Alert, List, Anchor, Divider } from '@mantine/core';
import { IconWorldWww, IconExternalLink, IconCloudDownload, IconCheck, IconX } from '@tabler/icons-react';
import dayjs from 'dayjs';
import { DomainRegistrarInfo } from '../api/domains';

const yesNo = (v: boolean | null | undefined, on = 'Yes', off = 'No') =>
  v === null || v === undefined ? <Text span c="dimmed">Unknown</Text> : <Badge size="sm" variant="light" color={v ? 'green' : 'gray'}>{v ? on : off}</Badge>;
const fmt = (d?: string | null) => (d ? dayjs(d).format('D MMM YYYY') : '—');

function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <Group justify="space-between" wrap="nowrap" gap="md">
      <Text size="sm" c="dimmed">{label}</Text>
      <Text size="sm" component="div" ta="right">{children}</Text>
    </Group>
  );
}

/**
 * Staff-only card for Name.com domains: live read-only facts, what can be done from MoBilling
 * and what must be done on Name.com's own website. No FRED/registry fields here.
 */
export default function NameComRegistrarCard({
  info, loading, onSync, syncing, canSync, syncedAt, children,
}: {
  info: DomainRegistrarInfo | undefined;
  loading: boolean;
  onSync: () => void;
  syncing: boolean;
  canSync: boolean;
  syncedAt?: string | null;
  children?: React.ReactNode; // extra manage-at-registrar controls (e.g. transfer lock / auth code)
}) {
  const f = info?.facts;
  return (
    <Paper withBorder radius="md" p="lg">
      <Group justify="space-between" mb="md" wrap="wrap">
        <Group gap="xs"><IconWorldWww size={18} /><Title order={5}>Registrar: Name.com</Title></Group>
        {info?.label && <Badge variant="light" color="grape">Account: {info.label}</Badge>}
      </Group>

      {loading ? (
        <Group gap="xs"><Loader size="xs" /><Text size="sm" c="dimmed">Reading live from Name.com…</Text></Group>
      ) : info?.error ? (
        <Alert color="orange" variant="light" p="xs" mb="sm">{info.error}</Alert>
      ) : f ? (
        <Stack gap={6}>
          <Row label="Expiry date (Name.com)">{fmt(f.expires_at)}</Row>
          <Row label="Created (Name.com)">{fmt(f.created_at)}</Row>
          <Row label="Transfer lock">{yesNo(f.locked, 'Locked', 'Unlocked')}</Row>
          <Row label="Auto-renew at Name.com">{yesNo(f.autorenew, 'On', 'Off')}</Row>
          <Row label="WHOIS privacy">{yesNo(f.privacy, 'Enabled', 'Disabled')}</Row>
          {f.transfer_lock_expires_at && <Row label="Policy transfer lock until">{fmt(f.transfer_lock_expires_at)}</Row>}
        </Stack>
      ) : null}
      {syncedAt && <Text size="xs" c="dimmed" mt="sm">Last synced from Name.com: {dayjs(syncedAt).format('D MMM YYYY HH:mm')}</Text>}

      <Divider my="md" label="Manage at registrar" labelPosition="left" />
      <Group gap="xs" mb="sm">
        {canSync && (
          <Button size="xs" variant="light" color="grape" leftSection={<IconCloudDownload size={14} />} loading={syncing} onClick={onSync}>
            Sync from Name.com
          </Button>
        )}
        <Button size="xs" variant="default" component="a" href="https://www.name.com/account/login" target="_blank" rel="noopener noreferrer"
          leftSection={<IconExternalLink size={14} />}>
          Open Name.com website
        </Button>
      </Group>
      {children}

      <Text size="sm" fw={600} mt="md" mb={4}>What you can do here</Text>
      <List size="xs" spacing={2} icon={<IconCheck size={12} color="var(--mantine-color-teal-6)" />}>
        <List.Item>Change nameservers (Nameservers card below) and see them live from Name.com</List.Item>
        <List.Item>View / sync expiry, status, lock, auto-renew and privacy (read-only)</List.Item>
        <List.Item>Renewals: create the renewal invoice here; once paid it enters the manual renewal queue for staff to renew on Name.com</List.Item>
        <List.Item>New registrations and transfers: through the staff-confirmed queue</List.Item>
      </List>
      <Text size="sm" fw={600} mt="sm" mb={4}>Only on Name.com's website</Text>
      <List size="xs" spacing={2} icon={<IconX size={12} color="var(--mantine-color-gray-6)" />}>
        <List.Item>Paying for the actual renewal, turning auto-renew or WHOIS privacy on/off, contacts, DNS records, deleting or transferring out</List.Item>
      </List>
      <Text size="xs" c="dimmed" mt="sm">
        The registry <Code fz="xs">.tz</Code> tools (Registrant / NSset) do not apply to this domain.
        {' '}<Anchor size="xs" href="https://www.name.com/support" target="_blank" rel="noopener noreferrer">Name.com support</Anchor>
      </Text>
    </Paper>
  );
}
