import { Box, Button, Table } from '@mui/joy';

import { useGetPairsList } from '../../../integration';
import InfoItem from '../../root/info-item';
import { displayWithDecimals } from '../../../utils';

export const PairsTable = () => {
  const { data: pairsList, isFetching } = useGetPairsList();
  return (
    <Box sx={{ width: '100%', overflow: 'auto' }}>
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
        {(isFetching) && (
          <tr>
            <td colSpan={3}>
              Loading...
            </td>
            </tr>
        )}
        {!(isFetching) && (pairsList ?? []).map((pair: any, i: number) => {
          return (
            <tr key={i}>
              <td>
                <InfoItem content={pair.base_symbol} withCopy={true} />
                <InfoItem content={pair.base_principal.toText()} withCopy={true} />
                <InfoItem content={`Decimals ${pair.base_decimals}`} />
                <InfoItem content={`Credits ${displayWithDecimals(pair.base_credits, pair.base_decimals)}`} />
              </td>
              <td>
                <InfoItem content={pair.quote_symbol} withCopy={true} />
                <InfoItem content={pair.quote_principal.toText()} withCopy={true} />
                <InfoItem content={`Decimals ${pair.quote_decimals}`} />
                <InfoItem content={`Credits ${displayWithDecimals(pair.quote_credits, pair.quote_decimals)}`} />
              </td>
              <td>{pair.spread_value}</td>
            </tr>
          );
        })}
        </tbody>
      </Table>
    </Box>
  );
};
