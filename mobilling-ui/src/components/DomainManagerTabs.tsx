import { useEffect, useState } from 'react';
import {
  Tabs, Stack, Group, Text, Title, Button, Alert, Loader, Table, ActionIcon, Modal, TextInput, Textarea, Select,
  SegmentedControl, SimpleGrid, Badge, Paper, Divider,
} from '@mantine/core';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { IconListDetails, IconAddressBook, IconArrowsSplit, IconServer, IconShieldLock, IconPlus, IconEdit, IconTrash, IconAlertTriangle } from '@tabler/icons-react';
import { DnsSections, DnsRecordModal, DnsRec, DnsPayload, dnsErrMsg } from './DnsSections';
import {
  dmGetDns, dmAddRecord, dmEditRecord, dmDeleteRecord, dmUseOurDns, dmGetContacts, dmSaveContacts, dmGetForwarding,
  dmAddUrl, dmEditUrl, dmDeleteUrl, dmAddEmail, dmEditEmail, dmDeleteEmail, dmGetHosts, dmAddHost, dmEditHost,
  DmContact, DmRole, DmUrlForward, DmEmailForward, DmHost,
} from '../api/domainManager';

const DNS_TYPES = ['MX', 'A', 'CNAME', 'ANAME', 'TXT', 'SRV'];

const Loading = ({ label }: { label: string }) => <Group gap="xs"><Loader size="xs" /><Text size="sm" c="dimmed">{label}</Text></Group>;
const LoadError = ({ e }: { e: any }) => <Alert color="orange" variant="light">{e?.response?.data?.message ?? 'Could not load this right now - please try again shortly.'}</Alert>;
const ok = (message: string) => notifications.show({ message, color: 'green', autoClose: 7000 });
const bad = (e: any) => notifications.show({ title: 'Not saved', message: dnsErrMsg(e), color: 'red' });

// ───────────────────────── DNS records ─────────────────────────

function DnsPanel({ domainId, domainName, canEdit }: { domainId: string; domainName: string; canEdit: boolean }) {
  const qc = useQueryClient();
  const key = ['dm-dns', domainId];
  const { data, isLoading, isError, error } = useQuery({ queryKey: key, queryFn: () => dmGetDns(domainId), retry: false });
  const [editing, setEditing] = useState<{ type: string; record: DnsRec | null } | null>(null);
  const info = data?.data?.data;

  const switchDns = useMutation({
    mutationFn: () => dmUseOurDns(domainId),
    onSuccess: (r: any) => { qc.invalidateQueries({ queryKey: key }); qc.invalidateQueries({ queryKey: ['portal-domain-ns', domainId] }); ok(r.data.message); },
    onError: bad,
  });
  const del = useMutation({
    mutationFn: (r: DnsRec) => dmDeleteRecord(domainId, r.id),
    onSuccess: () => { qc.invalidateQueries({ queryKey: key }); ok('DNS record removed.'); },
    onError: bad,
  });

  const askSwitch = () => modals.openConfirmModal({
    title: 'Use our DNS servers?', centered: true,
    children: <Text size="sm">Your domain's nameservers will be changed to our DNS servers so the records below take effect. Make sure the records are complete first - your website and email follow them. Changes can take a few hours to spread.</Text>,
    labels: { confirm: 'Yes, use our DNS servers', cancel: 'Cancel' }, confirmProps: { color: 'green' }, onConfirm: () => switchDns.mutate(),
  });
  const askDelete = (r: DnsRec) => modals.openConfirmModal({
    title: 'Remove this DNS record?', centered: true,
    children: <Text size="sm">{r.type} record <b>{r.name ? `${r.name}.${domainName}` : domainName}</b> will be removed. Anything relying on it may stop working.</Text>,
    labels: { confirm: 'Remove record', cancel: 'Keep it' }, confirmProps: { color: 'red' }, onConfirm: () => del.mutate(r),
  });

  if (isLoading) return <Loading label="Loading DNS records..." />;
  if (isError || !info) return <LoadError e={error} />;

  return (
    <Stack gap="md">
      {!info.in_use && (
        <Alert color="orange" variant="light" icon={<IconAlertTriangle size={18} />} title="Your nameservers point elsewhere, so records here are not in use">
          <Text size="sm">You can prepare records now, but they only take effect when this domain uses our DNS servers.</Text>
          {canEdit && <Button mt="sm" size="xs" color="orange" loading={switchDns.isPending} onClick={askSwitch}>Use our DNS servers</Button>}
        </Alert>
      )}
      <Text size="sm" c="dimmed">Records tell the internet where your website and email live. {info.records.length} of {info.max_records} records used. Changes usually apply within minutes.</Text>
      <DnsSections domain={domainName} rows={info.records} canManage={canEdit} types={DNS_TYPES}
        onAdd={(t) => setEditing({ type: t, record: null })} onEdit={(r) => setEditing({ type: r.type, record: r })} onDelete={askDelete} />
      {editing && (
        <DnsRecordModal type={editing.type} record={editing.record} domain={domainName} ttls={info.ttls} defaultTtl={3600}
          submit={(p: DnsPayload, rec) => (rec ? dmEditRecord(domainId, rec.id, p) : dmAddRecord(domainId, p))}
          onClose={() => setEditing(null)} onSaved={() => qc.invalidateQueries({ queryKey: key })} />
      )}
    </Stack>
  );
}

// ───────────────────────── Contacts ─────────────────────────

const ROLE_LABEL: Record<DmRole, string> = { registrant: 'Owner (registrant)', admin: 'Administrative', tech: 'Technical', billing: 'Billing' };
const FIELDS: { k: keyof Omit<DmContact, 'verified'>; label: string; req?: boolean; ph?: string }[] = [
  { k: 'first_name', label: 'First name', req: true }, { k: 'last_name', label: 'Last name', req: true },
  { k: 'company', label: 'Organization (leave empty for an individual)' },
  { k: 'address1', label: 'Address line 1', req: true }, { k: 'address2', label: 'Address line 2' },
  { k: 'city', label: 'City', req: true }, { k: 'state', label: 'State / region', req: true }, { k: 'zip', label: 'Postal code', req: true },
  { k: 'country', label: 'Country (2-letter code)', req: true, ph: 'TZ' },
  { k: 'email', label: 'Email', req: true }, { k: 'phone', label: 'Phone (international format)', req: true, ph: '+255712345678' }, { k: 'fax', label: 'Fax (optional)' },
];

function ContactsPanel({ domainId, canEdit }: { domainId: string; canEdit: boolean }) {
  const qc = useQueryClient();
  const key = ['dm-contacts', domainId];
  const { data, isLoading, isError, error } = useQuery({ queryKey: key, queryFn: () => dmGetContacts(domainId), retry: false });
  const [role, setRole] = useState<DmRole>('registrant');
  const [form, setForm] = useState<Omit<DmContact, 'verified'> | null>(null);
  const info = data?.data?.data;
  const current = info?.contacts?.[role];

  useEffect(() => {
    if (current) { const { verified: _v, ...rest } = current; setForm(rest); }
  }, [current, role]);

  const save = useMutation({
    mutationFn: () => dmSaveContacts(domainId, { [role]: form! }),
    onSuccess: (r) => { qc.invalidateQueries({ queryKey: key }); ok(r.data.data.changed.length ? r.data.message : 'No changes to save.'); },
    onError: bad,
  });

  const dirty = !!(form && current && FIELDS.some((f) => (form[f.k] ?? '') !== (current[f.k] ?? '')));
  const missing = form ? FIELDS.filter((f) => f.req && !String(form[f.k] ?? '').trim()).length : 0;

  const confirm = () => modals.openConfirmModal({
    title: `Save ${ROLE_LABEL[role].toLowerCase()} contact?`, centered: true,
    children: (
      <Stack gap={6}>
        <Text size="sm">These details are published in the domain's registration record.</Text>
        {role === 'registrant' && <Alert color="orange" variant="light" p="xs">Changing the owner (registrant) details can lock the domain against transfers to another provider for 60 days, and a verification email may be sent to the new email address - please verify it promptly.</Alert>}
      </Stack>
    ),
    labels: { confirm: 'Yes, save', cancel: 'Cancel' }, confirmProps: { color: 'green' }, onConfirm: () => save.mutate(),
  });

  if (isLoading) return <Loading label="Loading contact details..." />;
  if (isError || !info || !form) return isError || !info ? <LoadError e={error} /> : <Loading label="Loading contact details..." />;

  return (
    <Stack gap="md">
      <Text size="sm" c="dimmed">The contact details registered for this domain. Keep them correct - you may be asked to verify the email address.</Text>
      {info.transfer_lock_until && <Alert color="blue" variant="light">This domain is protected against transfers to another provider until {info.transfer_lock_until}.</Alert>}
      <SegmentedControl fullWidth value={role} onChange={(v) => setRole(v as DmRole)} data={(Object.keys(ROLE_LABEL) as DmRole[]).map((r) => ({ value: r, label: ROLE_LABEL[r] }))} styles={{ label: { fontSize: 12, padding: '6px 4px' } }} />
      {current?.verified === false && <Badge color="orange" variant="light" w="fit-content">Email not verified yet</Badge>}
      <SimpleGrid cols={{ base: 1, sm: 2 }}>
        {FIELDS.map((f) => (
          <TextInput key={f.k} label={f.label} placeholder={f.ph} required={f.req} disabled={!canEdit}
            value={form[f.k] ?? ''} onChange={(e) => setForm({ ...form, [f.k]: f.k === 'country' ? e.currentTarget.value.toUpperCase() : e.currentTarget.value })}
            maxLength={f.k === 'country' ? 2 : 200} />
        ))}
      </SimpleGrid>
      {canEdit ? (
        <Group justify="flex-end"><Button disabled={!dirty || missing > 0} loading={save.isPending} onClick={confirm}>Save {ROLE_LABEL[role].toLowerCase()} contact</Button></Group>
      ) : <Text size="xs" c="dimmed">Only portal administrators can change contact details.</Text>}
    </Stack>
  );
}

// ───────────────────────── Forwarding ─────────────────────────

const FWD_TYPES = [{ value: 'permanent', label: 'Redirect (permanent)' }, { value: 'temporary', label: 'Redirect (temporary)' }, { value: 'masked', label: 'Masked (keeps your address in the browser)' }];

function UrlModal({ domainId, domainName, item, onClose, onSaved }: { domainId: string; domainName: string; item: DmUrlForward | null; onClose: () => void; onSaved: () => void }) {
  const [host, setHost] = useState(item?.host ?? 'www');
  const [target, setTarget] = useState(item?.target ?? 'https://');
  const [type, setType] = useState<string>(item?.type ?? 'permanent');
  const [title, setTitle] = useState(item?.title ?? '');
  const [err, setErr] = useState<string | null>(null);
  const m = useMutation({
    mutationFn: () => (item ? dmEditUrl(domainId, item.id, { host, target, type, ...(type === 'masked' ? { title } : {}) }) : dmAddUrl(domainId, { host, target, type, ...(type === 'masked' ? { title } : {}) })),
    onSuccess: (r: any) => { ok(r.data.message); onSaved(); onClose(); }, onError: (e) => setErr(dnsErrMsg(e)),
  });
  return (
    <Modal opened onClose={onClose} title={item ? 'Edit website forwarding' : 'Add website forwarding'} zIndex={500}>
      <Stack>
        {err && <Alert color="red">{err}</Alert>}
        <TextInput label="Forward this address" description="Leave empty for the main domain." value={host} onChange={(e) => setHost(e.currentTarget.value)}
          rightSection={<Text size="xs" c="dimmed" pr={4}>.{domainName}</Text>} rightSectionWidth={Math.min(220, 24 + domainName.length * 7)} />
        <TextInput label="To this web address" placeholder="https://example.org/page" value={target} onChange={(e) => setTarget(e.currentTarget.value)} required />
        <Select label="Type" data={FWD_TYPES} value={type} onChange={(v) => setType(v ?? 'permanent')} allowDeselect={false} />
        {type === 'masked' && <TextInput label="Page title" value={title} onChange={(e) => setTitle(e.currentTarget.value)} maxLength={100} />}
        <Text size="xs" c="dimmed">Only public http(s) addresses are allowed. It can take up to 24 hours to take effect.</Text>
        <Button loading={m.isPending} disabled={!target.trim()} onClick={() => { setErr(null); m.mutate(); }}>Save</Button>
      </Stack>
    </Modal>
  );
}

function EmailModal({ domainId, domainName, item, onClose, onSaved }: { domainId: string; domainName: string; item: DmEmailForward | null; onClose: () => void; onSaved: () => void }) {
  const [box, setBox] = useState(item?.box ?? '');
  const [to, setTo] = useState(item?.to ?? '');
  const [err, setErr] = useState<string | null>(null);
  const m = useMutation({
    mutationFn: () => (item ? dmEditEmail(domainId, item.box, to) : dmAddEmail(domainId, { box, to })),
    onSuccess: (r: any) => { ok(r.data.message); onSaved(); onClose(); }, onError: (e) => setErr(dnsErrMsg(e)),
  });
  return (
    <Modal opened onClose={onClose} title={item ? 'Edit email forwarding' : 'Add email forwarding'} zIndex={500}>
      <Stack>
        {err && <Alert color="red">{err}</Alert>}
        <TextInput label="Address to forward" placeholder="info" value={box} onChange={(e) => setBox(e.currentTarget.value)} disabled={!!item} required
          rightSection={<Text size="xs" c="dimmed" pr={4}>@{domainName}</Text>} rightSectionWidth={Math.min(240, 30 + domainName.length * 7)} />
        <TextInput label="Send it to" placeholder="you@gmail.com" value={to} onChange={(e) => setTo(e.currentTarget.value)} required />
        <Text size="xs" c="dimmed">One destination address, outside this domain. Catch-all (*) is not supported.</Text>
        <Button loading={m.isPending} disabled={!to.trim() || !box.trim()} onClick={() => { setErr(null); m.mutate(); }}>Save</Button>
      </Stack>
    </Modal>
  );
}

function ForwardingPanel({ domainId, domainName, canEdit }: { domainId: string; domainName: string; canEdit: boolean }) {
  const qc = useQueryClient();
  const key = ['dm-fwd', domainId];
  const { data, isLoading, isError, error } = useQuery({ queryKey: key, queryFn: () => dmGetForwarding(domainId), retry: false });
  const dns = useQuery({ queryKey: ['dm-dns', domainId], queryFn: () => dmGetDns(domainId), retry: false });
  const [urlEdit, setUrlEdit] = useState<{ item: DmUrlForward | null } | null>(null);
  const [mailEdit, setMailEdit] = useState<{ item: DmEmailForward | null } | null>(null);
  const refresh = () => qc.invalidateQueries({ queryKey: key });
  const delUrl = useMutation({ mutationFn: (f: DmUrlForward) => dmDeleteUrl(domainId, f.id), onSuccess: () => { refresh(); ok('Website forwarding removed.'); }, onError: bad });
  const delMail = useMutation({ mutationFn: (f: DmEmailForward) => dmDeleteEmail(domainId, f.box), onSuccess: () => { refresh(); ok('Email forwarding removed.'); }, onError: bad });

  const askDel = (what: string, name: string, run: () => void) => modals.openConfirmModal({
    title: `Remove ${what}?`, centered: true, children: <Text size="sm"><b>{name}</b> will stop being forwarded.</Text>,
    labels: { confirm: 'Remove', cancel: 'Keep it' }, confirmProps: { color: 'red' }, onConfirm: run,
  });

  if (isLoading) return <Loading label="Loading forwarding..." />;
  if (isError || !data?.data?.data) return <LoadError e={error} />;
  const f = data.data.data;
  const inUse = dns.data?.data?.data?.in_use;

  return (
    <Stack gap="lg">
      {inUse === false && <Alert color="orange" variant="light" icon={<IconAlertTriangle size={18} />}>Your nameservers point elsewhere, so forwarding set up here may not be in use. Open the DNS records tab to switch to our DNS servers.</Alert>}

      <Stack gap="xs">
        <Group justify="space-between">
          <Title order={5}>Website forwarding</Title>
          {canEdit && <Button size="compact-xs" variant="light" leftSection={<IconPlus size={14} />} disabled={f.url.length >= f.max} onClick={() => setUrlEdit({ item: null })}>Add website forwarding</Button>}
        </Group>
        <Text size="xs" c="dimmed">Send visitors of your domain (or a subdomain) to another web address. {f.url.length} of {f.max} used.</Text>
        <Table.ScrollContainer minWidth={480}>
          <Table verticalSpacing="xs">
            <Table.Thead><Table.Tr><Table.Th>Address</Table.Th><Table.Th>Forwards to</Table.Th><Table.Th>Type</Table.Th><Table.Th /></Table.Tr></Table.Thead>
            <Table.Tbody>
              {f.url.length === 0 ? <Table.Tr><Table.Td colSpan={4}><Text size="sm" c="dimmed">No items to display.</Text></Table.Td></Table.Tr> : f.url.map((u) => (
                <Table.Tr key={u.id}>
                  <Table.Td style={{ wordBreak: 'break-all' }}>{u.host ? `${u.host}.${domainName}` : domainName}</Table.Td>
                  <Table.Td style={{ wordBreak: 'break-all' }}>{u.target}</Table.Td>
                  <Table.Td>{FWD_TYPES.find((t) => t.value === u.type)?.label.split(' (')[0] ?? u.type}</Table.Td>
                  <Table.Td>{canEdit && <Group gap={4} wrap="nowrap">
                    <ActionIcon variant="light" aria-label="Edit" onClick={() => setUrlEdit({ item: u })}><IconEdit size={14} /></ActionIcon>
                    <ActionIcon variant="light" color="red" aria-label="Remove" onClick={() => askDel('website forwarding', u.host ? `${u.host}.${domainName}` : domainName, () => delUrl.mutate(u))}><IconTrash size={14} /></ActionIcon>
                  </Group>}</Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      </Stack>

      <Divider />

      <Stack gap="xs">
        <Group justify="space-between">
          <Title order={5}>Email forwarding</Title>
          {canEdit && <Button size="compact-xs" variant="light" leftSection={<IconPlus size={14} />} disabled={f.email.length >= f.max} onClick={() => setMailEdit({ item: null })}>Add email forwarding</Button>}
        </Group>
        <Text size="xs" c="dimmed">Receive mail sent to an address on your domain in another inbox. {f.email.length} of {f.max} used.</Text>
        {canEdit && f.email.length === 0 && <Alert color="yellow" variant="light" p="xs">Adding your first forwarding may update this domain's mail (MX) records. If you already receive email through another service, it could stop working - check first.</Alert>}
        <Table.ScrollContainer minWidth={420}>
          <Table verticalSpacing="xs">
            <Table.Thead><Table.Tr><Table.Th>Address</Table.Th><Table.Th>Forwards to</Table.Th><Table.Th /></Table.Tr></Table.Thead>
            <Table.Tbody>
              {f.email.length === 0 ? <Table.Tr><Table.Td colSpan={3}><Text size="sm" c="dimmed">No items to display.</Text></Table.Td></Table.Tr> : f.email.map((m) => (
                <Table.Tr key={m.box}>
                  <Table.Td style={{ wordBreak: 'break-all' }}>{m.address}</Table.Td>
                  <Table.Td style={{ wordBreak: 'break-all' }}>{m.to}</Table.Td>
                  <Table.Td>{canEdit && <Group gap={4} wrap="nowrap">
                    <ActionIcon variant="light" aria-label="Edit" onClick={() => setMailEdit({ item: m })}><IconEdit size={14} /></ActionIcon>
                    <ActionIcon variant="light" color="red" aria-label="Remove" onClick={() => askDel('email forwarding', m.address, () => delMail.mutate(m))}><IconTrash size={14} /></ActionIcon>
                  </Group>}</Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      </Stack>
      {!canEdit && <Text size="xs" c="dimmed">Only portal administrators can change forwarding.</Text>}
      {urlEdit && <UrlModal domainId={domainId} domainName={domainName} item={urlEdit.item} onClose={() => setUrlEdit(null)} onSaved={refresh} />}
      {mailEdit && <EmailModal domainId={domainId} domainName={domainName} item={mailEdit.item} onClose={() => setMailEdit(null)} onSaved={refresh} />}
    </Stack>
  );
}

// ───────────────────────── Custom nameserver hosts ─────────────────────────

function HostModal({ domainId, domainName, item, onClose, onSaved }: { domainId: string; domainName: string; item: DmHost | null; onClose: () => void; onSaved: () => void }) {
  const [host, setHost] = useState(item ? item.hostname.replace(`.${domainName}`, '') : 'ns1');
  const [ips, setIps] = useState((item?.ips ?? []).join('\n'));
  const [err, setErr] = useState<string | null>(null);
  const list = ips.split(/[\s,;]+/).map((x) => x.trim()).filter(Boolean);
  const m = useMutation({
    mutationFn: () => (item ? dmEditHost(domainId, item.hostname, list) : dmAddHost(domainId, host, list)),
    onSuccess: (r: any) => { ok(r.data.message); onSaved(); onClose(); }, onError: (e) => setErr(dnsErrMsg(e)),
  });
  return (
    <Modal opened onClose={onClose} title={item ? 'Edit custom nameserver host' : 'Add custom nameserver host'} zIndex={500}>
      <Stack>
        {err && <Alert color="red">{err}</Alert>}
        <TextInput label="Host name" value={host} onChange={(e) => setHost(e.currentTarget.value.toLowerCase())} disabled={!!item} required
          rightSection={<Text size="xs" c="dimmed" pr={4}>.{domainName}</Text>} rightSectionWidth={Math.min(220, 24 + domainName.length * 7)} />
        <Textarea label="IP addresses" description="One per line (public IPv4 or IPv6, up to 4)." autosize minRows={2} value={ips} onChange={(e) => setIps(e.currentTarget.value)} required />
        <Button loading={m.isPending} disabled={!host.trim() || list.length === 0} onClick={() => { setErr(null); m.mutate(); }}>Save</Button>
      </Stack>
    </Modal>
  );
}

function HostsPanel({ domainId, domainName, canEdit }: { domainId: string; domainName: string; canEdit: boolean }) {
  const qc = useQueryClient();
  const key = ['dm-hosts', domainId];
  const { data, isLoading, isError, error } = useQuery({ queryKey: key, queryFn: () => dmGetHosts(domainId), retry: false });
  const [edit, setEdit] = useState<{ item: DmHost | null } | null>(null);
  if (isLoading) return <Loading label="Loading custom hosts..." />;
  if (isError || !data?.data?.data) return <LoadError e={error} />;
  const h = data.data.data;
  return (
    <Stack gap="xs">
      <Group justify="space-between">
        <Title order={5}>Custom nameserver hosts</Title>
        {canEdit && <Button size="compact-xs" variant="light" leftSection={<IconPlus size={14} />} disabled={h.hosts.length >= h.max} onClick={() => setEdit({ item: null })}>Add host</Button>}
      </Group>
      <Text size="xs" c="dimmed">Register your own nameserver names (like ns1.{domainName}) with their IP addresses, so you can use them as your domain's nameservers. {h.hosts.length} of {h.max} used.</Text>
      <Table.ScrollContainer minWidth={420}>
        <Table verticalSpacing="xs">
          <Table.Thead><Table.Tr><Table.Th>Host</Table.Th><Table.Th>IP addresses</Table.Th><Table.Th /></Table.Tr></Table.Thead>
          <Table.Tbody>
            {h.hosts.length === 0 ? <Table.Tr><Table.Td colSpan={3}><Text size="sm" c="dimmed">No items to display.</Text></Table.Td></Table.Tr> : h.hosts.map((x) => (
              <Table.Tr key={x.hostname}>
                <Table.Td style={{ wordBreak: 'break-all' }}>{x.hostname}</Table.Td>
                <Table.Td style={{ wordBreak: 'break-all' }}>{x.ips.join(', ')}</Table.Td>
                <Table.Td>{canEdit && <ActionIcon variant="light" aria-label="Edit" onClick={() => setEdit({ item: x })}><IconEdit size={14} /></ActionIcon>}</Table.Td>
              </Table.Tr>
            ))}
          </Table.Tbody>
        </Table>
      </Table.ScrollContainer>
      {edit && <HostModal domainId={domainId} domainName={domainName} item={edit.item} onClose={() => setEdit(null)} onSaved={() => qc.invalidateQueries({ queryKey: key })} />}
    </Stack>
  );
}

// ───────────────────────── Tabs ─────────────────────────

/**
 * Client "Domain Manager". Neutral wording only. `nameservers` and `security` are slots so the page can
 * reuse its existing nameserver editor and the transfer lock / code card without duplicating them here.
 */
export default function DomainManagerTabs({ domainId, domainName, isAdmin, active, nameservers, security }: {
  domainId: string; domainName: string; isAdmin: boolean; active: boolean;
  nameservers?: React.ReactNode; security?: React.ReactNode;
}) {
  const canEdit = isAdmin && active;
  return (
    <Stack gap="md">
      <Title order={4}>Domain Manager</Title>
      {!active && <Alert color="gray" variant="light">This domain is not active yet, so changes are disabled.</Alert>}
      <Tabs defaultValue="dns" keepMounted={false}>
        <Tabs.List style={{ flexWrap: 'wrap' }}>
          <Tabs.Tab value="dns" leftSection={<IconListDetails size={15} />}>DNS records</Tabs.Tab>
          <Tabs.Tab value="contacts" leftSection={<IconAddressBook size={15} />}>Contact details</Tabs.Tab>
          <Tabs.Tab value="forwarding" leftSection={<IconArrowsSplit size={15} />}>Forwarding</Tabs.Tab>
          <Tabs.Tab value="nameservers" leftSection={<IconServer size={15} />}>Nameservers</Tabs.Tab>
          {security && <Tabs.Tab value="security" leftSection={<IconShieldLock size={15} />}>Security & transfer</Tabs.Tab>}
        </Tabs.List>
        <Tabs.Panel value="dns" pt="md"><DnsPanel domainId={domainId} domainName={domainName} canEdit={canEdit} /></Tabs.Panel>
        <Tabs.Panel value="contacts" pt="md"><ContactsPanel domainId={domainId} canEdit={canEdit} /></Tabs.Panel>
        <Tabs.Panel value="forwarding" pt="md"><ForwardingPanel domainId={domainId} domainName={domainName} canEdit={canEdit} /></Tabs.Panel>
        <Tabs.Panel value="nameservers" pt="md">
          <Stack gap="xl">
            {nameservers}
            <Paper withBorder radius="md" p="md"><HostsPanel domainId={domainId} domainName={domainName} canEdit={canEdit} /></Paper>
          </Stack>
        </Tabs.Panel>
        {security && <Tabs.Panel value="security" pt="md">{security}</Tabs.Panel>}
      </Tabs>
    </Stack>
  );
}
