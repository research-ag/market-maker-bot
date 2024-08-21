import { Box, Table } from '@mui/joy';

import { useGetHistory } from '../../integration';

export const OrdersHistory = () => {
  const { data: history, isFetching } = useGetHistory();
  return (
    <Box sx={{ width: '100%', overflow: 'auto' }}>
      <Table>
        <colgroup>
          <col style={{ width: '50px' }} />
          <col style={{ width: '50px' }} />
          <col style={{ width: '50px' }} />
          <col style={{ width: '100px' }} />
          <col style={{ width: '100px' }} />
          <col style={{ width: '100px' }} />
          <col style={{ width: '100px' }} />
        </colgroup>
        <thead>
        <tr>
          <th>Base Token</th>
          <th>Quote Token</th>
          <th>Spread</th>
          <th>BID Volume</th>
          <th>BID Price</th>
          <th>ASK Volume</th>
          <th>ASK Price</th>
        </tr>
        </thead>
        <tbody>
        {isFetching && (
          <tr>
            <td colSpan={7}>
              Loading...
            </td>
          </tr>
        )}
        {!isFetching && (history ?? []).map((item: any, i: number) => {
          return (
            <tr key={i}>
              <td>
                {item?.pair?.base?.symbol}
              </td>
              <td>
                {item?.pair?.quote?.symbol}
              </td>
              <td>
                {item?.pair?.spread_value}
              </td>
              {item.message === 'OK' ? (
                <>
                  <td>
                    {item?.bidOrder?.amount?.toString()}
                  </td>
                  <td>
                    {item?.bidOrder?.price}
                  </td>
                  <td>
                    {item?.askOrder?.amount?.toString()}
                  </td>
                  <td>
                    {item?.askOrder?.price}
                  </td>
                </>
              ) : (
                <>
                  <td colSpan={4}>
                    {item?.message}
                  </td>
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
