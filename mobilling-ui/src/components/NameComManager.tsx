import { useState } from 'react';
import { Modal, Tabs } from '@mantine/core';
import { useMediaQuery } from '@mantine/hooks';
import { IconPlugConnected, IconDownload, IconTags } from '@tabler/icons-react';
import NameComPricingPanel from './NameComPricingPanel';
import NameComAccountsPanel from './NameComAccountsPanel';
import NameComImport from './NameComImport';
import { usePermissions } from '../hooks/usePermissions';

/** Shared by the Domains-page modal and Settings > Domains (one implementation). */
export function NameComTabs({ initialTab }: { initialTab?: string }) {
  const { can } = usePermissions();
  const [tab, setTab] = useState<string | null>(initialTab ?? (can('domains.settings') ? 'connection' : 'import'));
  return (
    <Tabs value={tab} onChange={setTab} keepMounted={false}>
      <Tabs.List>
        {can('domains.settings') && <Tabs.Tab value="connection" leftSection={<IconPlugConnected size={14} />}>Connection</Tabs.Tab>}
        {can('domains.settings') && <Tabs.Tab value="pricing" leftSection={<IconTags size={14} />}>TLDs &amp; pricing</Tabs.Tab>}
        {can('domains.create') && <Tabs.Tab value="import" leftSection={<IconDownload size={14} />}>Import from Name.com</Tabs.Tab>}
      </Tabs.List>
      {can('domains.settings') && <Tabs.Panel value="connection" pt="md"><NameComAccountsPanel /></Tabs.Panel>}
      {can('domains.settings') && <Tabs.Panel value="pricing" pt="md"><NameComPricingPanel /></Tabs.Panel>}
      {can('domains.create') && <Tabs.Panel value="import" pt="md"><NameComImport /></Tabs.Panel>}
    </Tabs>
  );
}

export default function NameComManager({ opened, onClose, initialTab }: { opened: boolean; onClose: () => void; initialTab?: string }) {
  const mobile = useMediaQuery('(max-width: 48em)');
  return (
    <Modal opened={opened} onClose={onClose} title="Name.com" size="xl" fullScreen={!!mobile}>
      <NameComTabs initialTab={initialTab} />
    </Modal>
  );
}
