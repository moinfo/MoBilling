import { Modal, Group, Text } from '@mantine/core';
import { IconPhoneCall } from '@tabler/icons-react';
import { FollowupEntry } from '../../api/followups';
import LogCallForm from './LogCallForm';

interface Props {
  followup: FollowupEntry | null;
  onClose: () => void;
  onLogged?: () => void;
}

/** Thin Modal wrapper around LogCallForm — kept so existing callers (Followups.tsx) don't change. */
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
        <LogCallForm
          followup={followup}
          onCancel={onClose}
          onDone={() => { onLogged?.(); onClose(); }}
        />
      )}
    </Modal>
  );
}
