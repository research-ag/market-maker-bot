import {useState} from 'react';
import {Box, Tab, TabList, Tabs} from '@mui/joy';

import {canisterId, useGetBotState, useGetQuoteInfo, useGetQuoteReserve} from '../../integration';

import {ToggleBotButton} from '../toggle-bot-button';
import {ThemeButton} from '../theme-button';
import {Pairs} from '../pairs';
import {OrdersHistory} from '../orders-history';

import InfoItem from './info-item';

const Root = () => {
  const { data: botState, isFetching } = useGetBotState();
  const [tabValue, setTabValue] = useState(0);
  let {data: quoteReserve} = useGetQuoteReserve();
  const {data: quoteInfo} = useGetQuoteInfo();

  return (
    <Box sx={{ width: '100%', maxWidth: '1200px', p: 4, mx: 'auto' }}>
      <Tabs
        sx={{ backgroundColor: 'transparent' }}
        value={tabValue}
        onChange={(_, value) => setTabValue(value as number)}>
        <Box sx={{ display: 'flex', justifyContent: 'flex-end' }}>
          <Box sx={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 0.5, marginBottom: 1 }}>
            <InfoItem label="Bot principal" content={canisterId} withCopy />
            <InfoItem label="Initialized" content={botState?.initializing ? 'in progress' : (botState?.initialized ? 'true' : 'false')} />
            <InfoItem label="Timer interval" content={botState?.timer_interval ? `${botState?.timer_interval.toString()} seconds` :  '0 seconds'} />
            <InfoItem label="Quote symbol" content={quoteInfo?.symbol || '-'} withCopy={true}/>
            <InfoItem label="Quote principal" content={quoteInfo?.principal.toText() || '-'} withCopy={true}/>
            <InfoItem label="Quote decimals" content={'' + (quoteInfo?.decimals || '-')}/>
            <InfoItem label="Quote reserve"
                      content={'' + (Number(quoteReserve) / Math.pow(10, quoteInfo?.decimals || 0))}/>
            <ToggleBotButton isRunning = {!!botState?.running} isFetching = {isFetching} currentTimer = {botState?.timer_interval ?? 0n}/>
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
