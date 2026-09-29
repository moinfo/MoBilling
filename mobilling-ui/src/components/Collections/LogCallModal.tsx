import { Modal, Group, Text, Stack, Alert } from '@mantine/core';
import { IconPhoneCall, IconNotes } from '@tabler/icons-react';
import { FollowupEntry } from '../../api/followups';
import LogCallForm from './LogCallForm';
import ClientFollowupHistory from './ClientFollowupHistory';

interface Props {
  followup: FollowupEntry | null;
  onClose: () => void;
  onLogged?: () => void;
}

/**
 * Modal wrapper around LogCallForm — used by Followups.tsx and MyCollections.tsx. Also shows the
 * client's prior follow-up history and any assignment note (Followup.notes on the active row) up front,
 * so staff calling from "My Collections" have the same client context an admin already has before they
 * dial, without an extra click.
 */
export default function LogCallModal({ followup, onClose, onLogged }: Props) {
  return (
    <Modal
      opened={!!followup}
      onClose={onClose}
      title={
        <Group gap="sm">
          <IconPhoneCall size={20} />
          <Text fw={600}>Log Call</Text>
        </Group>
      }
      size="lg"
    >
      {followup && (
        <Stack gap="md">
          <ClientFollowupHistory clientId={followup.client_id} currentDocumentNumber={followup.document_number} />
          {followup.notes && (
            <Alert color="blue" variant="light" title="Assignment note" icon={<IconNotes size={16} />}>
              <Text size="sm">{followup.notes}</Text>
            </Alert>
          )}
          <LogCallForm
            followup={followup}
            onCancel={onClose}
            onDone={() => { onLogged?.(); onClose(); }}
          />
        </Stack>
      )}
    </Modal>
  );
}
