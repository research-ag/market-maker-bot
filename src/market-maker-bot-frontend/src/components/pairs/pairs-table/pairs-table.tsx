import {Box, Table} from '@mui/joy';

import {useGetPairsList, useGetQuoteInfo} from '../../../integration';
import InfoItem from '../../root/info-item';
import {useState} from "react";
import SettingsModal from "../../settings-modal";
import {MarketPairShared} from "../../../declarations/market-maker-bot-backend/market-maker-bot-backend.did";
import QuoteBalanceModal from "../../quote-balance-modal";

export const PairsTable = () => {
  const {data: quoteInfo, isFetching: isQuoteInfoFetching} = useGetQuoteInfo();
  const { data: pairsList, isFetching } = useGetPairsList();

  const [isSettingsModalOpen, setIsSettingsModalOpen] = useState(false);
  const [isQuoteBalanceModalOpen, setIsQuoteBalanceModalOpen] = useState(false);

  const [selectedItem, setSelectedItem] = useState<MarketPairShared>({ base: { symbol: '-'}, spread_value: 0.05 } as any);

  return (
    <Box sx={{ width: '100%', overflow: 'auto' }}>
      <SettingsModal pair={selectedItem} isOpen={isSettingsModalOpen} onClose={() => setIsSettingsModalOpen(false)}/>
      <QuoteBalanceModal pair={selectedItem} isOpen={isQuoteBalanceModalOpen}
                         onClose={() => setIsQuoteBalanceModalOpen(false)}/>
      <Table>
        <colgroup>
          <col style={{width: '200px'}}/>
          <col style={{width: '110px'}}/>
          <col style={{width: '110px'}}/>
          <col style={{width: '110px'}}/>
        </colgroup>
        <thead>
        <tr>
          <th>Base Token</th>
          <th>Spread</th>
          <th>Quote balance</th>
          <th>Base balance</th>
        </tr>
        </thead>
        <tbody>
        {(isFetching || isQuoteInfoFetching) && (
          <tr>
            <td colSpan={3}>
              Loading...
            </td>
            </tr>
        )}
        {!(isFetching || isQuoteInfoFetching) && (pairsList ?? []).map((pair, i) => {
          return (
              <tr key={i}>
                <td>
                  <InfoItem content={pair.base.symbol} withCopy={true}/>
                  <InfoItem content={pair.base.principal.toText()} withCopy={true}/>
                  <InfoItem content={`Decimals ${pair.base.decimals}`}/>
                </td>
                <td>
                  <InfoItem content={'Value: ' + pair.spread[0] + '; bias: ' + pair.spread[1]} withEdit={true} onEdit={() => {
                    setSelectedItem(pair);
                    setTimeout(() => setIsSettingsModalOpen(true), 50);
                  }}/>
                </td>
                <td>
                  <InfoItem content={'' + (Number(pair.quote_credits) / Math.pow(10, quoteInfo?.decimals || 0))}
                            withEdit={true} onEdit={() => {
                    setSelectedItem(pair);
                    setTimeout(() => setIsQuoteBalanceModalOpen(true), 50);
                  }}/>
                </td>
                <td>
                  <InfoItem content={'' + (Number(pair.base_credits) / Math.pow(10, pair.base.decimals))}/>
                </td>
              </tr>
          );
        })}
        </tbody>
      </Table>
    </Box>
  );
};
