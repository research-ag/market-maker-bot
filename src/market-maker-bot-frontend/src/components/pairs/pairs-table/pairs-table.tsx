import { Box, Button, Table } from '@mui/joy';

import { useGetPairsList, useRemovePairByIndex } from '../../../integration';
import InfoItem from '../../root/info-item';
import { displayWithDecimals } from '../../../utils';

export const PairsTable = () => {
  const { data: pairsList, isFetching } = useGetPairsList();
  const { mutate: removePair, isLoading: isRemoveLoading } = useRemovePairByIndex();
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
        {!(isFetching || isRemoveLoading) && (pairsList ?? []).map((pair: any, i: number) => {
          return (
            <tr key={i}>
              <td>
                <InfoItem content={pair.base_asset.asset.symbol} withCopy={true} />
                <InfoItem content={pair.base_asset.principal.toText()} withCopy={true} />
                <InfoItem content={`Decimals ${pair.base_asset.decimals}`} />
                <InfoItem content={`Credits ${displayWithDecimals(pair.base_credits, pair.base_asset.decimals)}`} />
              </td>
              <td>
                <InfoItem content={pair.quote_asset.asset.symbol} withCopy={true} />
                <InfoItem content={pair.quote_asset.principal.toText()} withCopy={true} />
                <InfoItem content={`Decimals ${pair.quote_asset.decimals}`} />
                <InfoItem content={`Credits ${displayWithDecimals(pair.quote_credits, pair.quote_asset.decimals)}`} />
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
