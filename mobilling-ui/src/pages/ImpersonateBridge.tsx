import { useEffect, useState } from 'react';
import { Center, Loader, Stack, Text, Alert } from '@mantine/core';
import { IconAlertCircle } from '@tabler/icons-react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';

/**
 * Cross-domain "Login As" handoff. A tenant's own custom_domain serves this
 * exact same build (see e.g. luchamcloud.co.tz's nginx config — identical
 * root/backend, just a different Host header), but localStorage is
 * origin-scoped, so a token set on mobilling.co.tz doesn't exist here. The
 * superadmin's /admin/tenants "Login As" redirects here with a one-time
 * impersonation token in the query string; this page plants it in THIS
 * origin's localStorage, hydrates the session via the normal refreshUser()
 * path, then drops into /dashboard — so the admin actually lands on the
 * tenant's own domain, logged in as the user they picked.
 */
export default function ImpersonateBridge() {
  const { refreshUser } = useAuth();
  const navigate = useNavigate();
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const token = new URLSearchParams(window.location.search).get('token');
    // Scrub the token out of the address bar/history immediately, whether
    // or not sign-in below succeeds — it's a bearer credential.
    window.history.replaceState(null, '', '/impersonate-bridge');

    if (!token) {
      setError('This link is missing its sign-in token.');
      return;
    }

    localStorage.setItem('token', token);
    localStorage.setItem('user_type', 'tenant');

    refreshUser()
      .then(() => navigate('/dashboard', { replace: true }))
      .catch(() => setError('This link has expired or is no longer valid — go back and try "Login As" again.'));
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  return (
    <Center style={{ minHeight: '100vh' }}>
      <Stack align="center" gap="sm" maw={420} px="md">
        {error ? (
          <Alert color="red" icon={<IconAlertCircle size={18} />} title="Sign-in failed">
            {error}
          </Alert>
        ) : (
          <>
            <Loader />
            <Text c="dimmed" size="sm">Signing you in…</Text>
          </>
        )}
      </Stack>
    </Center>
  );
}
