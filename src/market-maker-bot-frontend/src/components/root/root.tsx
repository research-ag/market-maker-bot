import { useState } from 'react';
import { Box, Tab, TabList, Tabs } from '@mui/joy';

import { canisterId } from '../../integration';

import { ToggleBotButton } from '../toggle-bot-button';
import { ThemeButton } from '../theme-button';
import { Pairs } from '../pairs';
import { OrdersHistory } from '../orders-history';

import InfoItem from './info-item';

const Root = () => {
  const [tabValue, setTabValue] = useState(0);

  return (
    <Box sx={{ width: '100%', maxWidth: '1200px', p: 4, mx: 'auto' }}>
      <Tabs
        sx={{ backgroundColor: 'transparent' }}
        value={tabValue}
        onChange={(_, value) => setTabValue(value as number)}>
        <Box sx={{ display: 'flex', justifyContent: 'flex-end' }}>
          <Box sx={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 0.5, marginBottom: 1 }}>
            <InfoItem label="Bot principal" content={canisterId} withCopy />
            <ToggleBotButton />
          </Box>
        </Box>
        <Box sx={{ display: 'flex', alignItems: 'center', marginBottom: 2 }}>
          <TabList sx={{ marginRight: 1, flexGrow: 1 }} variant="plain">
            <Tab color="neutral">Pairs</Tab>
            <Tab color="neutral">Order history</Tab>
          </TabList>
          <ThemeButton sx={{ marginLeft: 1 }} />
        </Box>
        {tabValue === 0 && <Pairs />}
        {tabValue === 1 && <OrdersHistory />}
      </Tabs>
    </Box>
  );
};

export default Root;
