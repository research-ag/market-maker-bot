import { Box, Button, Table } from '@mui/joy';

import { useListPairs, useRemovePair } from '../../../integration';
import InfoItem from '../../root/info-item';
import { displayWithDecimals } from '../../../utils';

export const PairsTable = () => {
  const { data: pairs, isFetching } = useListPairs();
  const { mutate: removePair, isLoading: isRemoveLoading } = useRemovePair();
  return (
    <Box sx={{ width: '100%', overflow: 'auto' }}>
      <Table>
        <colgroup>
          <col style={{ width: '200px' }} />
          <col style={{ width: '200px' }} />
          <col style={{ width: '110px' }} />
          <col style={{ width: '80px' }} />
        </colgroup>
        <thead>
        <tr>
          <th>Base Token</th>
          <th>Quote Token</th>
          <th>Spread</th>
          <th></th>
        </tr>
        </thead>
        <tbody>
        {(isFetching || isRemoveLoading) && (
          <tr>
            <td colSpan={4}>
              Loading...
            </td>
            </tr>
        )}
        {!(isFetching || isRemoveLoading) && (pairs ?? []).map((pair: any, i: number) => {
          return (
            <tr key={i}>
              <td>
                <InfoItem content={pair.base.symbol} withCopy={true} />
                <InfoItem content={pair.base.principal.toText()} withCopy={true} />
                <InfoItem content={`Decimals ${pair.base.decimals}`} />
                <InfoItem content={`Credits ${displayWithDecimals(pair.base.credits, pair.base.decimals)}`} />
              </td>
              <td>
                <InfoItem content={pair.quote.symbol} withCopy={true} />
                <InfoItem content={pair.quote.principal.toText()} withCopy={true} />
                <InfoItem content={`Decimals ${pair.quote.decimals}`} />
                <InfoItem content={`Credits ${displayWithDecimals(pair.quote.credits, pair.quote.decimals)}`} />
              </td>
              <td>{pair.spread_value}</td>
              <td>
                <Button onClick={() => removePair(i)} color="danger" size="sm">
                  Remove
                </Button>
              </td>
            </tr>
          );
        })}
        </tbody>
      </Table>
    </Box>
  );
};
