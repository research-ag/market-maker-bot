import {Box, Table} from '@mui/joy';

import {useGetPairsList, useGetQuoteInfo} from '../../../integration';
import InfoItem from '../../root/info-item';
import {useState} from "react";
import SettingsModal from "../../settings-modal";
import {MarketPairShared} from "../../../declarations/market-maker-bot-backend/market-maker-bot-backend.did";

export const PairsTable = () => {
  const {data: quoteInfo, isFetching: isQuoteInfoFetching} = useGetQuoteInfo();
  const { data: pairsList, isFetching } = useGetPairsList();

  const [isSettingsModalOpen, setIsSettingsModalOpen] = useState(false);
  const openSettingsModal = () => setIsSettingsModalOpen(true);
  const closeSettingsModal = () => setIsSettingsModalOpen(false);

  const [selectedItem, setSelectedItem] = useState<MarketPairShared>({ base: { symbol: '-'}, spread_value: 0.05 } as any);

  return (
    <Box sx={{ width: '100%', overflow: 'auto' }}>
      <SettingsModal pair={selectedItem} isOpen={isSettingsModalOpen} onClose={closeSettingsModal}/>
      <Table>
        <colgroup>
          <col style={{ width: '200px' }} />
          <col style={{ width: '200px' }} />
          <col style={{ width: '110px' }} />
        </colgroup>
        <thead>
        <tr>
          <th>Base Token</th>
          <th>Quote Token</th>
          <th>Spread</th>
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
                <InfoItem content={quoteInfo?.symbol || '-'} withCopy={true}/>
                <InfoItem content={quoteInfo?.principal.toText() || '-'} withCopy={true}/>
                <InfoItem content={`Decimals ${quoteInfo?.decimals || '-'}`}/>
              </td>
              <td>
                <InfoItem content={'' + pair.spread_value} withEdit={true} onEdit={() => {
                  setSelectedItem(pair);
                  setTimeout(() => openSettingsModal());
                }}/>
              </td>
            </tr>
          );
        })}
        </tbody>
      </Table>
    </Box>
  );
};
