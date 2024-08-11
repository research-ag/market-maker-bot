import { Box, Table } from '@mui/joy';

import { useOrdersHistory } from '../../integration';

export const OrdersHistory = () => {
  const { data: history, isFetching } = useOrdersHistory();
  return (
    <Box sx={{ width: '100%', overflow: 'auto' }}>
      <Table>
        <tbody>
        {isFetching && (
          <tr>
            <td>
              Loading...
            </td>
          </tr>
        )}
        {isFetching && (history ?? []).map((item: any, i: number) => {
          return (
            <tr key={i}>
              <td>
                {item}
              </td>
            </tr>
          );
        })}
        </tbody>
      </Table>
    </Box>
  );
};
