import { Modal, Accordion, Text, List, Code, Stack, Alert } from '@mantine/core';
import { IconInfoCircle } from '@tabler/icons-react';

export default function WifiRouterSetupGuide({ opened, onClose }: { opened: boolean; onClose: () => void }) {
  return (
    <Modal opened={opened} onClose={onClose} title="Router Setup Guide" size="lg">
      <Stack gap="md">
        <Text size="sm" c="dimmed">
          How to connect a MikroTik router to WiFi Hotspot Voucher Billing. Requires RouterOS v7.18+
          and a dedicated WiFi interface for the hotspot (don't reuse your management interface).
        </Text>

        <Accordion variant="separated" defaultValue="enable">
          <Accordion.Item value="enable">
            <Accordion.Control>1. Enable the Hotspot</Accordion.Control>
            <Accordion.Panel>
              <Text size="sm" mb={6}>
                RouterOS v7 disables risky features by default. In the router's Terminal, run:
              </Text>
              <Code block>{`/system device-mode update hotspot=yes`}</Code>
              <Text size="sm" mt={6}>
                This requires a <b>physical confirmation within ~5 minutes</b> — unplug/replug the
                router, or briefly press its reset button (don't hold it). Then confirm with{' '}
                <Code>/system device-mode print</Code> — <Code>hotspot</Code> should read{' '}
                <Code>yes</Code>.
              </Text>
            </Accordion.Panel>
          </Accordion.Item>

          <Accordion.Item value="wifi">
            <Accordion.Control>2. Set up the hotspot WiFi</Accordion.Control>
            <Accordion.Panel>
              <List size="sm" type="ordered" spacing={6}>
                <List.Item>
                  If the interface was auto-added to a bridge, remove it first (a DHCP server can't
                  run on a bridge-slave interface):
                  <Code block mt={4}>{`/interface bridge port remove [find interface=wlan1]`}</Code>
                </List.Item>
                <List.Item>
                  Run the Hotspot setup wizard on that interface — WebFig: <b>IP → Hotspot → Hotspot
                  Setup</b>, select your WiFi interface, accept the defaults. This creates the DHCP
                  server and the hotspot's own local IP (e.g. <Code>10.5.50.1/24</Code>) — write
                  this down, you'll need it later for "Local Hotspot IP" below.
                </List.Item>
                <List.Item>
                  Make the WiFi <b>open, no password</b> — access is controlled entirely by the
                  hotspot login page, not WiFi encryption:
                  <Code block mt={4}>{`/interface wireless security-profiles add name=open mode=none\n/interface wireless set wlan1 security-profile=open`}</Code>
                </List.Item>
              </List>
            </Accordion.Panel>
          </Accordion.Item>

          <Accordion.Item value="reach">
            <Accordion.Control>3. Let MoBilling reach your router</Accordion.Control>
            <Accordion.Panel>
              <Text size="sm" mb={6}>
                MoBilling needs to reach your router's API (port 8728) over the internet to create
                voucher logins automatically. Your router's default firewall blocks this — add a
                rule allowing it, placed <b>before</b> the existing drop rule:
              </Text>
              <Code block>{`/ip firewall filter print   ; find the drop rule's position/comment\n/ip firewall filter add chain=input action=accept protocol=tcp dst-port=8728 \\\n    src-address=<MOBILLING_SERVER_IP> place-before=[find comment="<drop rule comment>"]`}</Code>
              <Alert icon={<IconInfoCircle size={16} />} color="blue" mt={8} variant="light">
                Some mobile/4G data plans block inbound connections even with a real public IP. If
                "Test Connection" keeps timing out despite a correct firewall rule and a real public
                IP, your router likely needs a VPN tunnel (e.g. WireGuard) to MoBilling's server
                instead — contact support and we'll set it up together.
              </Alert>
            </Accordion.Panel>
          </Accordion.Item>

          <Accordion.Item value="apiuser">
            <Accordion.Control>4. Create an API user</Accordion.Control>
            <Accordion.Panel>
              <Text size="sm" mb={6}>Don't reuse your admin login — create a dedicated one:</Text>
              <Code block>{`/user group add name=mobilling-api policy=api,read,write,test\n/user add name=mobilling-api password=<STRONG_PASSWORD> group=mobilling-api`}</Code>
              <Text size="sm" mt={6}>
                Then click <b>Add Router</b> on this page and fill in: <b>Host</b> (your router's
                public IP or DDNS), <b>API Port</b> <Code>8728</Code>, <b>Username</b>/
                <b>Password</b> = the API user above, and <b>Local Hotspot IP</b> = the address from
                step 2 (this is what lets customers auto-connect after paying, without typing a
                code). Click <b>Test Connection</b> to confirm before creating any plans.
              </Text>
            </Accordion.Panel>
          </Accordion.Item>

          <Accordion.Item value="walledgarden">
            <Accordion.Control>5. Allow checkout before payment (important!)</Accordion.Control>
            <Accordion.Panel>
              <Text size="sm" mb={6}>
                Before a customer logs in, the hotspot blocks <i>all</i> traffic except the login
                page itself — including the link to buy a voucher, since that's an external site.
                Without this step, customers can never reach checkout:
              </Text>
              <Code block>{`/ip hotspot walled-garden add dst-host=mobilling.co.tz action=allow\n/ip hotspot walled-garden add dst-host=*.mobilling.co.tz action=allow\n/ip hotspot walled-garden add dst-host=pay.pesapal.com action=allow\n/ip hotspot walled-garden add dst-host=*.pesapal.com action=allow`}</Code>
            </Accordion.Panel>
          </Accordion.Item>

          <Accordion.Item value="sharing">
            <Accordion.Control>6. Stop one voucher being shared across many devices</Accordion.Control>
            <Accordion.Panel>
              <Text size="sm" mb={6}>
                Check the hotspot user profile your plans use (RouterOS's <Code>default</Code>{' '}
                profile normally ships with this already set):
              </Text>
              <Code block>{`/ip hotspot user profile print\n/ip hotspot user profile set [find name="default"] shared-users=1`}</Code>
              <Text size="sm" mt={6}>
                <Code>shared-users=1</Code> limits a voucher code to one active device at a time.
              </Text>
            </Accordion.Panel>
          </Accordion.Item>

          <Accordion.Item value="brand">
            <Accordion.Control>7. Optional: brand the login page</Accordion.Control>
            <Accordion.Panel>
              <Text size="sm">
                You can replace the router's default login page with your own logo and a "buy a
                voucher" link. Upload files with <Code>scp</Code> rather than pasting into WebFig's
                file editor — pasting long HTML there is known to silently corrupt it. Contact
                support if you'd like help customizing this.
              </Text>
            </Accordion.Panel>
          </Accordion.Item>

          <Accordion.Item value="troubleshoot">
            <Accordion.Control>Troubleshooting</Accordion.Control>
            <Accordion.Panel>
              <List size="sm" spacing={8}>
                <List.Item><b>"not allowed by device-mode"</b> in <Code>/ip hotspot print detail</Code> — redo step 1.</List.Item>
                <List.Item><b>"DHCP server cannot run on slave interface!"</b> — the interface is still a bridge slave, see step 2.</List.Item>
                <List.Item><b>Test Connection times out</b> — check the firewall rule (step 3); if the IP is correct and it still fails, you may be behind carrier-level NAT — contact support about a VPN tunnel.</List.Item>
                <List.Item><b>Customers can't reach the "buy a voucher" link</b> — walled garden not configured (step 5).</List.Item>
                <List.Item><b>Voucher shared across many devices at once</b> — <Code>shared-users</Code> not set on the profile actually in use (step 6).</List.Item>
              </List>
            </Accordion.Panel>
          </Accordion.Item>
        </Accordion>
      </Stack>
    </Modal>
  );
}
