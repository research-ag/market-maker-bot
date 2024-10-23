import { Box, Table } from '@mui/joy';

import { useGetHistory, useGetQuoteInfo } from '../../integration';
import { HistoryItemType } from '../../declarations/market-maker-bot-backend/market-maker-bot-backend.did';
import { displayWithDecimals } from '../../utils';
{/* <InfoItem content={`Credits ${displayWithDecimals(pair.base_credits, pair.base_decimals)}`} /> */}

const transformHistoryItem = (quoteDecimals : number, item: HistoryItemType) => {
  const timestamp = new Date(Number(item.timestamp / 1000000n));
  const bidOrder = item.bidOrder && item.bidOrder.length ? item.bidOrder[0] : null;
  const askOrder = item.askOrder && item.askOrder.length ? item.askOrder[0] : null;
  const spread = item.pair.spread_value;
  const baseToken = item.pair.base.symbol;
  const baseDecimals = item.pair.base.decimals;
  const normalize_factor = quoteDecimals - baseDecimals;
  const bidVolume = bidOrder?.amount ? displayWithDecimals(bidOrder?.amount, baseDecimals) : 'N/A';
  const askVolume = askOrder?.amount ? displayWithDecimals(askOrder?.amount, baseDecimals) : 'N/A';
  const bidPrice = bidOrder?.price ? (bidOrder?.price / 10**normalize_factor).toPrecision(5) : 'N/A';
  const askPrice = askOrder?.price ? (askOrder?.price / 10**normalize_factor).toPrecision(5) : 'N/A';

  return {
    timestamp,
    baseToken,
    spread,
    bidVolume,
    bidPrice,
    askVolume,
    askPrice,
    rate: item.rate ? item.rate[0]?.toPrecision(5) : 'N/A',
    message: item.message,
  };
}

export const OrdersHistory = () => {
  const { data: history, isFetching: fetchingHistory } = useGetHistory();
  const { data: quoteInfo, isFetching: fetchingQuoteInfo } = useGetQuoteInfo();
  return (
    <Box sx={{ width: '100%', overflow: 'auto' }}>
      <Table>
        <colgroup>
          <col style={{ width: '150px' }} />
          <col style={{ width: '50px' }} />
          <col style={{ width: '50px' }} />
          <col style={{ width: '100px' }} />
          <col style={{ width: '100px' }} />
          <col style={{ width: '100px' }} />
          <col style={{ width: '100px' }} />
          <col style={{ width: '100px' }} />
        </colgroup>
        <thead>
        <tr>
          <th>Timestamp</th>
          <th>Token</th>
          <th>Spread</th>
          <th>Rate</th>
          <th>BID Volume</th>
          <th>BID Price</th>
          <th>ASK Volume</th>
          <th>ASK Price</th>
        </tr>
        </thead>
        <tbody>
        {(fetchingHistory || fetchingQuoteInfo) && (
          <tr>
            <td colSpan={8}>
              Loading...
            </td>
          </tr>
        )}
        {!fetchingHistory && !fetchingQuoteInfo && (history ?? []).map((item: any, i: number) => {
          const {
            timestamp,
            baseToken,
            spread,
            bidVolume,
            bidPrice,
            askVolume,
            askPrice,
            rate,
            message,
          } = transformHistoryItem(quoteInfo!.decimals, item);
          return (
            <tr key={i}>
              <td>{timestamp.toLocaleString()}</td>
              <td>{baseToken}</td>
              <td>{spread}</td>
              {item.message === 'OK' ? (
                <>
                  <td>{rate}</td>
                  <td>{bidVolume}</td>
                  <td>{bidPrice}</td>
                  <td>{askVolume}</td>
                  <td>{askPrice}</td>
                </>
              ) : (
                <>
                  <td colSpan={5}>{message}</td>
                </>
              )}
            </tr>
          );
        })}
        </tbody>
      </Table>
    </Box>
  );
};
