import { useState } from 'react';
import {
  Paper, Text, Group, Button, Stack, TextInput, PinInput, Badge, Modal,
  PasswordInput, CopyButton, ActionIcon, Tooltip, Alert, List, ThemeIcon,
} from '@mantine/core';
import { QRCodeSVG } from 'qrcode.react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import {
  IconShieldLock, IconShieldCheck, IconCopy, IconCheck, IconAlertTriangle,
} from '@tabler/icons-react';
import {
  getTwoFactorStatus, enableTwoFactor, confirmTwoFactor, disableTwoFactor,
  regenerateTwoFactorRecoveryCodes,
} from '../api/twoFactor';

/**
 * Self-service TOTP 2FA management — shared by staff Settings (Profile tab)
 * and the portal Profile page, since both User and ClientUser go through
 * the exact same backend endpoints (see TwoFactorAuthController).
 */
export default function TwoFactorSetup() {
  const qc = useQueryClient();
  const [setupOpen, setSetupOpen] = useState(false);
  const [setupData, setSetupData] = useState<{ secret: string; otpauth_url: string } | null>(null);
  const [code, setCode] = useState('');
  const [recoveryCodes, setRecoveryCodes] = useState<string[] | null>(null);
  const [disableOpen, setDisableOpen] = useState(false);
  const [disablePassword, setDisablePassword] = useState('');
  const [regenOpen, setRegenOpen] = useState(false);
  const [regenPassword, setRegenPassword] = useState('');
  const [regenCodes, setRegenCodes] = useState<string[] | null>(null);

  const { data, isLoading } = useQuery({ queryKey: ['2fa-status'], queryFn: getTwoFactorStatus });
  const status = data?.data;

  const enableMut = useMutation({
    mutationFn: enableTwoFactor,
    onSuccess: (res) => {
      setSetupData(res.data.data);
      setCode('');
      setSetupOpen(true);
    },
    onError: (e: any) => notifications.show({ message: e.response?.data?.message ?? 'Could not start setup.', color: 'red' }),
  });

  const confirmMut = useMutation({
    mutationFn: () => confirmTwoFactor(code),
    onSuccess: (res) => {
      setRecoveryCodes(res.data.recovery_codes);
      qc.invalidateQueries({ queryKey: ['2fa-status'] });
    },
    onError: (e: any) => notifications.show({ message: e.response?.data?.message ?? 'That code was not correct.', color: 'red' }),
  });

  const disableMut = useMutation({
    mutationFn: () => disableTwoFactor(disablePassword),
    onSuccess: () => {
      notifications.show({ title: 'Disabled', message: 'Two-factor authentication has been turned off.', color: 'gray' });
      setDisableOpen(false);
      setDisablePassword('');
      qc.invalidateQueries({ queryKey: ['2fa-status'] });
    },
    onError: (e: any) => notifications.show({ message: e.response?.data?.message ?? 'Incorrect password.', color: 'red' }),
  });

  const regenMut = useMutation({
    mutationFn: () => regenerateTwoFactorRecoveryCodes(regenPassword),
    onSuccess: (res) => setRegenCodes(res.data.recovery_codes),
    onError: (e: any) => notifications.show({ message: e.response?.data?.message ?? 'Incorrect password.', color: 'red' }),
  });

  const closeSetup = () => {
    setSetupOpen(false);
    setSetupData(null);
    setRecoveryCodes(null);
    setCode('');
  };

  const closeRegen = () => {
    setRegenOpen(false);
    setRegenPassword('');
    setRegenCodes(null);
  };

  return (
    <Paper withBorder p="md">
      <Group justify="space-between" mb="sm">
        <Group gap="xs">
          <IconShieldLock size={18} />
          <Text fw={600}>Two-Factor Authentication</Text>
        </Group>
        {!isLoading && (
          status?.enabled
            ? <Badge color="green" variant="light" leftSection={<IconShieldCheck size={12} />}>Enabled</Badge>
            : <Badge color="gray" variant="light">Not enabled</Badge>
        )}
      </Group>

      {status?.enabled ? (
        <Stack gap="sm">
          <Text size="sm" c="dimmed">
            Your account is protected with an authenticator app.
            {status.recovery_codes_remaining !== null && (
              <> You have <b>{status.recovery_codes_remaining}</b> unused recovery codes.</>
            )}
          </Text>
          <Group gap="xs">
            <Button size="xs" variant="light" onClick={() => setRegenOpen(true)}>
              Regenerate Recovery Codes
            </Button>
            <Button size="xs" variant="light" color="red" onClick={() => setDisableOpen(true)}>
              Disable
            </Button>
          </Group>
        </Stack>
      ) : (
        <Stack gap="sm">
          <Text size="sm" c="dimmed">
            Add an extra layer of security — after entering your password, you'll also need a code from an
            authenticator app (Google Authenticator, Authy, etc.) to sign in.
          </Text>
          <Button size="xs" onClick={() => enableMut.mutate()} loading={enableMut.isPending}>
            Enable Two-Factor Authentication
          </Button>
        </Stack>
      )}

      {/* Setup flow: QR -> confirm code -> recovery codes (shown once) */}
      <Modal opened={setupOpen} onClose={closeSetup} title="Set Up Two-Factor Authentication" centered size="md"
        closeOnClickOutside={!recoveryCodes} closeOnEscape={!recoveryCodes} withCloseButton={!recoveryCodes}>
        {!recoveryCodes ? (
          <Stack gap="md" align="center">
            <Text size="sm" c="dimmed" ta="center">
              Scan this QR code with your authenticator app, then enter the 6-digit code it shows.
            </Text>
            {setupData && (
              <>
                <QRCodeSVG value={setupData.otpauth_url} size={200} />
                <TextInput
                  label="Can't scan? Enter this key manually" readOnly value={setupData.secret}
                  w="100%"
                  rightSection={
                    <CopyButton value={setupData.secret}>
                      {({ copied, copy }) => (
                        <Tooltip label={copied ? 'Copied' : 'Copy'}>
                          <ActionIcon variant="subtle" onClick={copy}>
                            {copied ? <IconCheck size={14} /> : <IconCopy size={14} />}
                          </ActionIcon>
                        </Tooltip>
                      )}
                    </CopyButton>
                  }
                />
              </>
            )}
            <PinInput length={6} type="number" value={code} onChange={setCode} oneTimeCode
              onComplete={() => confirmMut.mutate()} />
            <Button fullWidth disabled={code.length !== 6} loading={confirmMut.isPending}
              onClick={() => confirmMut.mutate()}>
              Confirm & Enable
            </Button>
          </Stack>
        ) : (
          <RecoveryCodesView codes={recoveryCodes} onDone={closeSetup} />
        )}
      </Modal>

      {/* Disable */}
      <Modal opened={disableOpen} onClose={() => { setDisableOpen(false); setDisablePassword(''); }}
        title="Disable Two-Factor Authentication" centered>
        <Stack gap="sm">
          <Text size="sm" c="dimmed">Enter your password to confirm.</Text>
          <PasswordInput label="Password" value={disablePassword}
            onChange={(e) => setDisablePassword(e.currentTarget.value)} autoFocus />
          <Group justify="flex-end">
            <Button variant="default" onClick={() => { setDisableOpen(false); setDisablePassword(''); }}>Cancel</Button>
            <Button color="red" disabled={!disablePassword} loading={disableMut.isPending}
              onClick={() => disableMut.mutate()}>
              Disable
            </Button>
          </Group>
        </Stack>
      </Modal>

      {/* Regenerate recovery codes */}
      <Modal opened={regenOpen} onClose={closeRegen} title="Regenerate Recovery Codes" centered
        closeOnClickOutside={!regenCodes} closeOnEscape={!regenCodes} withCloseButton={!regenCodes}>
        {!regenCodes ? (
          <Stack gap="sm">
            <Alert color="orange" variant="light" icon={<IconAlertTriangle size={16} />}>
              Your existing recovery codes will stop working.
            </Alert>
            <PasswordInput label="Password" value={regenPassword}
              onChange={(e) => setRegenPassword(e.currentTarget.value)} autoFocus />
            <Group justify="flex-end">
              <Button variant="default" onClick={closeRegen}>Cancel</Button>
              <Button disabled={!regenPassword} loading={regenMut.isPending} onClick={() => regenMut.mutate()}>
                Regenerate
              </Button>
            </Group>
          </Stack>
        ) : (
          <RecoveryCodesView codes={regenCodes} onDone={closeRegen} />
        )}
      </Modal>
    </Paper>
  );
}

function RecoveryCodesView({ codes, onDone }: { codes: string[]; onDone: () => void }) {
  const allCodes = codes.join('\n');
  return (
    <Stack gap="md">
      <Alert color="orange" variant="light" icon={<IconAlertTriangle size={16} />}>
        Save these recovery codes somewhere safe. Each one can be used once to sign in if you lose access to
        your authenticator app — they won't be shown again.
      </Alert>
      <List spacing={4} center>
        {codes.map((c) => (
          <List.Item key={c} icon={<ThemeIcon size={18} variant="light" color="gray"><IconShieldLock size={11} /></ThemeIcon>}>
            <Text ff="monospace" size="sm">{c}</Text>
          </List.Item>
        ))}
      </List>
      <Group grow>
        <CopyButton value={allCodes}>
          {({ copied, copy }) => (
            <Button variant="light" leftSection={copied ? <IconCheck size={14} /> : <IconCopy size={14} />} onClick={copy}>
              {copied ? 'Copied' : 'Copy All'}
            </Button>
          )}
        </CopyButton>
        <Button onClick={onDone}>I've Saved These Codes</Button>
      </Group>
    </Stack>
  );
}
