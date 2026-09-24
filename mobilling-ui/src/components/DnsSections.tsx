import { useState } from 'react';
import { Stack, Table, Group, Text, Title, Button, ActionIcon, Modal, Select, TextInput, Textarea, NumberInput, Alert, Tooltip } from '@mantine/core';
import { IconPlus, IconEdit, IconTrash } from '@tabler/icons-react';
import { RECORD_TTLS } from '../api/linode';

/** Sectioned DNS view mirroring Linode Cloud Manager's domain detail page (shared by the client portal and staff). */
export interface DnsRec {
  id: number; type: string; name: string; target: string; ttl_sec: number;
  priority?: number | null; weight?: number | null; port?: number | null; service?: string | null; protocol?: string | null; tag?: string | null; locked?: boolean;
}
export interface DnsSoa { soa_email: string | null; ttl_sec: number; refresh_sec: number; retry_sec: number; expire_sec: number }
export type DnsPayload = { type: string; name: string; target: string; ttl_sec: number; priority?: number; weight?: number; port?: number; tag?: string; service?: string; protocol?: string };

export const dnsErrMsg = (e: any): string =>
  e?.response?.data?.message || (e?.response?.data?.errors ? Object.values(e.response.data.errors).flat().join(' ') : null) || e?.message || 'Something went wrong';

export const ttlText = (s: number | null | undefined) => {
  const n = Number(s ?? 0);
  if (n === 0) return 'Default';
  if (n >= 86400) return `${n / 86400} ${n === 86400 ? 'day' : 'days'}`;
  if (n >= 3600) return `${n / 3600} ${n === 3600 ? 'hour' : 'hours'}`;
  return `${n / 60} minutes`;
};
export const ttlSelectData = (list: number[]) => list.map((t) => ({ value: String(t), label: ttlText(t) }));

type Col = { label: string; render: (r: DnsRec) => React.ReactNode };
const host = (r: DnsRec, domain: string) => (r.name ? `${r.name}.${domain}` : domain);

function LongText({ v, max = 60 }: { v: string; max?: number }) {
  if (v.length <= max) return <span style={{ wordBreak: 'break-all' }}>{v}</span>;
  return <Tooltip label={<div style={{ maxWidth: 420, wordBreak: 'break-all', whiteSpace: 'normal' }}>{v}</div>} multiline withArrow events={{ hover: true, focus: true, touch: true }}><span style={{ wordBreak: 'break-all', cursor: 'help' }}>{v.slice(0, max)}...</span></Tooltip>;
}

const sections = (domain: string): { title: string; type: string; types: string[]; cols: Col[]; add: boolean }[] => [
  { title: 'NS Record', type: 'NS', types: ['NS'], add: false, cols: [
    { label: 'Name Server', render: (r) => r.target }, { label: 'Subdomain', render: (r) => r.name }, { label: 'TTL', render: (r) => ttlText(r.ttl_sec) }] },
  { title: 'MX Record', type: 'MX', types: ['MX'], add: true, cols: [
    { label: 'Mail Server', render: (r) => r.target }, { label: 'Preference', render: (r) => r.priority ?? '' }, { label: 'Subdomain', render: (r) => r.name }, { label: 'TTL', render: (r) => ttlText(r.ttl_sec) }] },
  { title: 'A/AAAA Record', type: 'A', types: ['A', 'AAAA'], add: true, cols: [
    { label: 'Hostname', render: (r) => host(r, domain) }, { label: 'IP Address', render: (r) => r.target }, { label: 'TTL', render: (r) => ttlText(r.ttl_sec) }] },
  { title: 'CNAME Record', type: 'CNAME', types: ['CNAME'], add: true, cols: [
    { label: 'Hostname', render: (r) => host(r, domain) }, { label: 'Aliases to', render: (r) => r.target }, { label: 'TTL', render: (r) => ttlText(r.ttl_sec) }] },
  { title: 'ANAME Record', type: 'ANAME', types: ['ANAME'], add: true, cols: [
    { label: 'Hostname', render: (r) => host(r, domain) }, { label: 'Aliases to', render: (r) => r.target }, { label: 'TTL', render: (r) => ttlText(r.ttl_sec) }] },
  { title: 'TXT Record', type: 'TXT', types: ['TXT'], add: true, cols: [
    { label: 'Hostname', render: (r) => host(r, domain) }, { label: 'Value', render: (r) => <LongText v={r.target} /> }, { label: 'TTL', render: (r) => ttlText(r.ttl_sec) }] },
  { title: 'SRV Record', type: 'SRV', types: ['SRV'], add: true, cols: [
    { label: 'Service/Protocol', render: (r) => [r.service ? `_${r.service.replace(/^_/, '')}` : '', r.protocol ? `_${r.protocol.replace(/^_/, '')}` : ''].filter(Boolean).join('.') },
    { label: 'Name', render: (r) => r.name }, { label: 'Priority', render: (r) => r.priority ?? '' }, { label: 'Weight', render: (r) => r.weight ?? '' },
    { label: 'Port', render: (r) => r.port ?? '' }, { label: 'Target', render: (r) => r.target }, { label: 'TTL', render: (r) => ttlText(r.ttl_sec) }] },
  { title: 'CAA Record', type: 'CAA', types: ['CAA'], add: true, cols: [
    { label: 'Name', render: (r) => r.name }, { label: 'Tag', render: (r) => r.tag ?? '' }, { label: 'Value', render: (r) => <LongText v={r.target} /> }, { label: 'TTL', render: (r) => ttlText(r.ttl_sec) }] },
];

/** Section types shown when the caller does not pass `types` (unchanged for Linode / staff). */
export const DEFAULT_DNS_TYPES = ['NS', 'MX', 'A', 'CNAME', 'TXT', 'SRV', 'CAA'];

export function DnsSections({ domain, rows, soa, canManage, sw = false, onAdd, onEdit, onEditSoa, onDelete, types = DEFAULT_DNS_TYPES }: {
  domain: string; rows: DnsRec[]; soa?: DnsSoa | null; canManage: boolean; sw?: boolean;
  onAdd: (type: string) => void; onEdit: (r: DnsRec) => void; onEditSoa?: () => void;
  /** When given, each editable row also gets a delete button. */
  onDelete?: (r: DnsRec) => void;
  /** Which record sections to show (e.g. no CAA, plus ANAME). */
  types?: string[];
}) {
  const empty = 'No items to display.';
  return (
    <Stack gap="lg">
      {soa !== undefined && (
        <Stack gap={6}>
          <Group justify="space-between"><Title order={5}>SOA Record</Title></Group>
          <Table.ScrollContainer minWidth={560}>
            <Table verticalSpacing="xs">
              <Table.Thead><Table.Tr>
                {['Primary Domain', 'Email', 'Default TTL', 'Refresh Rate', 'Retry Rate', 'Expire Time'].map((h) => <Table.Th key={h}>{h}</Table.Th>)}<Table.Th />
              </Table.Tr></Table.Thead>
              <Table.Tbody>
                {soa ? (
                  <Table.Tr>
                    <Table.Td>{domain}</Table.Td><Table.Td style={{ wordBreak: 'break-all' }}>{soa.soa_email ?? ''}</Table.Td>
                    <Table.Td>{ttlText(soa.ttl_sec)}</Table.Td><Table.Td>{ttlText(soa.refresh_sec)}</Table.Td><Table.Td>{ttlText(soa.retry_sec)}</Table.Td><Table.Td>{ttlText(soa.expire_sec)}</Table.Td>
                    <Table.Td>{canManage && onEditSoa && <ActionIcon variant="light" aria-label={sw ? 'Hariri SOA' : 'Edit SOA'} onClick={onEditSoa}><IconEdit size={14} /></ActionIcon>}</Table.Td>
                  </Table.Tr>
                ) : <Table.Tr><Table.Td colSpan={7}><Text size="sm" c="dimmed">{empty}</Text></Table.Td></Table.Tr>}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        </Stack>
      )}
      {sections(domain).filter((s) => types.includes(s.type)).map((s) => {
        const list = rows.filter((r) => s.types.includes(r.type));
        const editable = s.add;
        return (
          <Stack gap={6} key={s.title}>
            <Group justify="space-between">
              <Title order={5}>{s.title}</Title>
              {canManage && s.add && <Button size="compact-xs" variant="light" leftSection={<IconPlus size={14} />} onClick={() => onAdd(s.type)}>{sw ? `Ongeza ${s.type === 'A' ? 'A/AAAA' : s.type} record` : `Add ${s.type === 'A' ? 'an A/AAAA' : s.type === 'MX' ? 'an MX' : s.type === 'ANAME' ? 'an ANAME' : s.type === 'SRV' ? 'an SRV' : 'a ' + s.type} record`}</Button>}
            </Group>
            <Table.ScrollContainer minWidth={480}>
              <Table verticalSpacing="xs">
                <Table.Thead><Table.Tr>{s.cols.map((c) => <Table.Th key={c.label}>{c.label}</Table.Th>)}<Table.Th /></Table.Tr></Table.Thead>
                <Table.Tbody>
                  {list.length === 0 ? <Table.Tr><Table.Td colSpan={s.cols.length + 1}><Text size="sm" c="dimmed">{empty}</Text></Table.Td></Table.Tr> : list.map((r) => (
                    <Table.Tr key={r.id}>
                      {s.cols.map((c) => <Table.Td key={c.label}>{c.render(r)}</Table.Td>)}
                      <Table.Td>{canManage && editable && !r.locked && (
                        <Group gap={4} wrap="nowrap">
                          <ActionIcon variant="light" aria-label={sw ? 'Hariri' : 'Edit'} onClick={() => onEdit(r)}><IconEdit size={14} /></ActionIcon>
                          {onDelete && <ActionIcon variant="light" color="red" aria-label={sw ? 'Futa' : 'Delete'} onClick={() => onDelete(r)}><IconTrash size={14} /></ActionIcon>}
                        </Group>
                      )}</Table.Td>
                    </Table.Tr>
                  ))}
                </Table.Tbody>
              </Table>
            </Table.ScrollContainer>
          </Stack>
        );
      })}
    </Stack>
  );
}

/** Add/Edit modal showing only the fields relevant to the record type, with Linode-like labels. `submit` performs the API call. */
export function DnsRecordModal({ type: initialType, record, domain, sw = false, submit, onClose, onSaved, ttls = RECORD_TTLS, defaultTtl = 0 }: {
  type: string; record: DnsRec | null; domain: string; sw?: boolean; submit: (p: DnsPayload, record: DnsRec | null) => Promise<any>; onClose: () => void; onSaved: () => void;
  /** Allowed TTL choices and the default for new records (Linode: 0 = Default; other providers may have a minimum). */
  ttls?: number[]; defaultTtl?: number;
}) {
  const [type, setType] = useState<string>(record?.type ?? initialType);
  const [name, setName] = useState(record?.name ?? '');
  const [target, setTarget] = useState(record?.target ?? '');
  const [ttl, setTtl] = useState<string>(String(record?.ttl_sec ?? defaultTtl));
  const [priority, setPriority] = useState<number | string>(record?.priority ?? 10);
  const [weight, setWeight] = useState<number | string>(record?.weight ?? 5);
  const [port, setPort] = useState<number | string>(record?.port ?? 80);
  const [tag, setTag] = useState<string>(record?.tag ?? 'issue');
  const [service, setService] = useState(record?.service ?? '');
  const [protocol, setProtocol] = useState(record?.protocol ?? 'tcp');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const save = async () => {
    setError(null); setBusy(true);
    const p: DnsPayload = { type, name: name.trim(), target: target.trim(), ttl_sec: Number(ttl),
      ...(type === 'MX' || type === 'SRV' ? { priority: Number(priority) } : {}),
      ...(type === 'SRV' ? { weight: Number(weight), port: Number(port), service: service.trim(), protocol: protocol.trim() } : {}),
      ...(type === 'CAA' ? { tag } : {}) };
    try { await submit(p, record); onSaved(); onClose(); } catch (e) { setError(dnsErrMsg(e)); } finally { setBusy(false); }
  };

  const hostDesc = sw ? `Acha wazi kwa ${domain} yenyewe.` : `Leave empty for ${domain} itself.`;
  const nameField = (label: string, desc?: string, req = false) => <TextInput label={label} description={desc} placeholder="www" value={name} onChange={(e) => setName(e.currentTarget.value)} required={req} rightSection={<Text size="xs" c="dimmed" pr={4}>.{domain}</Text>} rightSectionWidth={Math.min(220, 24 + domain.length * 7)} />;
  const title = (record ? (sw ? 'Hariri ' : 'Edit ') : (sw ? 'Ongeza ' : 'Add ')) + (type === 'A' || type === 'AAAA' ? 'A/AAAA' : type) + ' record';

  return (
    <Modal opened onClose={onClose} title={title} zIndex={500}>
      <Stack>
        {error && <Alert color="red">{error}</Alert>}
        {(type === 'A' || type === 'AAAA') && <Select label="Type" data={['A', 'AAAA']} value={type} onChange={(v) => setType(v ?? 'A')} allowDeselect={false} disabled={!!record} />}
        {(type === 'A' || type === 'AAAA') && (<>{nameField('Hostname', hostDesc)}<TextInput label="IP Address" placeholder={type === 'A' ? '1.2.3.4' : '2001:db8::1'} value={target} onChange={(e) => setTarget(e.currentTarget.value)} required /></>)}
        {type === 'CNAME' && (<>{nameField('Hostname', sw ? 'Lazima iwe na jina (si domain kuu).' : 'Required (cannot be the root domain).', true)}<TextInput label="Aliases to" placeholder="host.example.com" value={target} onChange={(e) => setTarget(e.currentTarget.value)} required /></>)}
        {type === 'ANAME' && (<>{nameField('Hostname', hostDesc)}<TextInput label="Aliases to" placeholder="host.example.com" value={target} onChange={(e) => setTarget(e.currentTarget.value)} required /></>)}
        {type === 'TXT' && (<>{nameField('Hostname', hostDesc)}<Textarea label="Value" autosize minRows={2} maxRows={8} value={target} onChange={(e) => setTarget(e.currentTarget.value)} required /></>)}
        {type === 'MX' && (<>
          <TextInput label="Mail Server" placeholder="mail.example.com" value={target} onChange={(e) => setTarget(e.currentTarget.value)} required />
          <NumberInput label="Preference" min={0} max={255} value={priority} onChange={setPriority} />
          {nameField('Subdomain', hostDesc)}
        </>)}
        {type === 'SRV' && (<>
          <TextInput label="Service" placeholder="sip" value={service} onChange={(e) => setService(e.currentTarget.value)} />
          <TextInput label="Protocol" placeholder="tcp" value={protocol} onChange={(e) => setProtocol(e.currentTarget.value)} />
          {nameField('Name', undefined, true)}
          <Group grow><NumberInput label="Priority" min={0} max={255} value={priority} onChange={setPriority} /><NumberInput label="Weight" min={0} max={65535} value={weight} onChange={setWeight} /><NumberInput label="Port" min={0} max={65535} value={port} onChange={setPort} /></Group>
          <TextInput label="Target" placeholder="sip.example.com" value={target} onChange={(e) => setTarget(e.currentTarget.value)} required />
        </>)}
        {type === 'CAA' && (<>
          {nameField('Name', hostDesc)}
          <Select label="Tag" data={['issue', 'issuewild', 'iodef']} value={tag} onChange={(v) => setTag(v ?? 'issue')} allowDeselect={false} />
          <TextInput label="Value" placeholder="letsencrypt.org" value={target} onChange={(e) => setTarget(e.currentTarget.value)} required />
        </>)}
        <Select label="TTL" data={ttlSelectData(ttls)} value={ttl} onChange={(v) => setTtl(v ?? String(defaultTtl))} allowDeselect={false} />
        <Button loading={busy} disabled={!target.trim()} onClick={save}>{sw ? 'Hifadhi' : 'Save'}</Button>
      </Stack>
    </Modal>
  );
}
