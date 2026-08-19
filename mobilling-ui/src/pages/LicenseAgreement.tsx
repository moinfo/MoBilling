import { useEffect, useState } from 'react';
import { Container, Paper, Title, Text, Stack, Center, Loader, Image, Button } from '@mantine/core';
import { Link } from 'react-router-dom';
import { getLicenseAgreement, LicenseAgreement as LicenseAgreementData } from '../api/install';

export default function LicenseAgreement() {
  const [data, setData] = useState<LicenseAgreementData | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    getLicenseAgreement()
      .then((res) => setData(res.data.data))
      .finally(() => setLoading(false));
  }, []);

  return (
    <Container size="sm" py={{ base: 32, sm: 64 }}>
      <Stack align="center" mb="xl">
        <Image src="/moinfotech-logo.png" h={40} w="auto" alt="MoBilling" />
        <Title order={2} ta="center">License Agreement</Title>
        {data && <Text c="dimmed" size="sm">Version {data.version} — effective {data.effective_date}</Text>}
      </Stack>

      <Paper withBorder p={{ base: 'md', sm: 'xl' }} radius="md">
        {loading ? (
          <Center py="xl"><Loader /></Center>
        ) : data ? (
          <Text size="sm" style={{ whiteSpace: 'pre-wrap' }}>{data.content}</Text>
        ) : (
          <Text c="dimmed" ta="center">Could not load the license agreement.</Text>
        )}
      </Paper>

      <Center mt="lg">
        <Button component={Link} to="/" variant="subtle">Back to MoBilling</Button>
      </Center>
    </Container>
  );
}
