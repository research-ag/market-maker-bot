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
          <col style={{ width: '200px' }} />
          <col style={{ width: '200px' }} />
        </colgroup>
        <thead>
        <tr>
          <th>Base Token</th>
          <th>Quote Token</th>
          <th>Spread</th>
          <th>BID</th>
          <th>ASK</th>
        </tr>
        </thead>
        <tbody>
        {isFetching && (
          <tr>
            <td colSpan={6}>
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
                    {item?.bidOrder?.amount?.toString()} as {item?.bidOrder?.price}
                  </td>
                  <td>
                    {item?.askOrder?.amount?.toString()} as {item?.askOrder?.price}
                  </td>
                </>
              ) : (
                <>
                  <td colSpan={2}>
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
